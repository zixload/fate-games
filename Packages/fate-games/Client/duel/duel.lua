-- Duel cote client : le HUD, les touches, le choix de l'arme et le tir en
-- premiere personne. Presentation seule (R1) : le client dit ce qu'il vise,
-- le serveur tranche (games/duel/adapter.lua).

return function(SharedConfig)
    SharedConfig = SharedConfig or {}
    Package.Require("duel/contour.lua")(SharedConfig.duel_contour)
    local Catalogue = Package.Require("Shared/catalogue.lua")
    local vm = SharedConfig.duel_arme or {}

    local page = WebUI("duel", "file://duel/hud.html", WidgetVisibility.VisibleNotHitTestable, true, true)
    -- Mode capture (F1, Client/photo.lua) : la page disparait le temps des captures.
    Events.Subscribe("zix:photo", function(cache)
        page:SetVisibility(cache and WidgetVisibility.Hidden or WidgetVisibility.VisibleNotHitTestable)
    end)

    local pret_page = false
    local attente = {}
    local etat = nil
    local chat_ouvert = false
    local dernier_tir = 0
    local balles = 6
    local pv_affiches = nil
    local regarde = false
    local mes_armes, arme_choisie = {}, nil

    local PALIERS_REPLI = { 0, 50, 100, 250 }
    local CADENCE_MS = 330           -- un peu sous celle du serveur (350), qui fait foi
    local PORTEE = 6000

    local function appeler(nom, ...)
        if pret_page then page:CallEvent("duel:" .. nom, ...) else attente[#attente + 1] = { nom, { ... } } end
    end

    local function marquer_pret()
        if pret_page then return end
        pret_page = true
        page:BringToFront()
        for _, a in ipairs(attente) do page:CallEvent("duel:" .. a[1], (table.unpack or unpack)(a[2])) end
        attente = {}
    end
    page:Subscribe("Ready", marquer_pret)
    page:Subscribe("pret", marquer_pret)

    Chat.Subscribe("Open", function() chat_ouvert = true end)
    Chat.Subscribe("Close", function() chat_ouvert = false end)

    local function moi()
        local p = Client.GetLocalPlayer()
        return p and p:GetID()
    end

    local function mon_perso()
        local p = Client.GetLocalPlayer()
        return p and p:GetControlledCharacter()
    end

    local function mon_joueur()
        if not etat then return nil end
        for _, j in ipairs(etat.joueurs) do
            if j.id == moi() then return j end
        end
        return nil
    end

    local function en_combat()
        local j = mon_joueur()
        return etat and etat.phase == "combat" and j and j.vivant and not j.parti
    end

    local function son(position)
        pcall(function()
            Sound(position, "package://fate-games/Client/Sounds/gunshot.ogg", false, true, SoundType.SFX, 0.7, 1.0, 180, 2500)
        end)
    end

    ------------------------------------------------------------ effets du tir

    -- Trainee de balle : un court trait fin et translucide, pres du canon, qui
    -- s'efface aussitot ; un petit eclat a l'impact. Sans ombre (SetCastShadow).
    local tr = SharedConfig.duel_trainee or {}
    local function morceau(position, rot, echelle, opacite, duree)
        local m = StaticMesh(position, rot, "nanos-world::SM_Cube", CollisionType.NoCollision)
        m:SetScale(echelle)
        m:SetCastShadow(false)
        m:SetMaterial("nanos-world::M_Default_Translucent_Unlit")
        m:SetMaterialColorParameter("Tint", Color(1.0, 0.88, 0.55))
        m:SetMaterialScalarParameter("Opacity", opacite)
        Timer.SetTimeout(function() if m:IsValid() then m:Destroy() end end, duree)
    end

    -- Chaque trainee avance comme une balle, du canon au point touche, a
    -- `vitesse` cm/s ; l'eclat apparait a l'arrivee. Deplacees a chaque image.
    local balles_en_vol = {}

    local function trainee(depart, fin)
        if not (depart and fin) then return end
        pcall(function()
            local dx, dy, dz = fin.X - depart.X, fin.Y - depart.Y, fin.Z - depart.Z
            local n = math.sqrt(dx * dx + dy * dy + dz * dz)
            if n < 1 then return end
            local longueur = math.min(n, tr.longueur or 140)
            local rot = Vector(dx, dy, dz):ToOrientationRotator()
            local m = StaticMesh(depart, rot, "nanos-world::SM_Cube", CollisionType.NoCollision)
            m:SetScale(Vector(longueur / 100, tr.epaisseur or 0.006, tr.epaisseur or 0.006))
            m:SetCastShadow(false)
            m:SetMaterial("nanos-world::M_Default_Translucent_Unlit")
            m:SetMaterialColorParameter("Tint", Color(1.0, 0.88, 0.55))
            m:SetMaterialScalarParameter("Opacity", tr.opacite or 0.45)
            balles_en_vol[#balles_en_vol + 1] = { m = m, depart = depart, u = Vector(dx / n, dy / n, dz / n),
                distance = n, longueur = longueur, parcouru = tr.ecart or 60, fin = fin, rot = rot }
        end)
    end

    Client.Subscribe("Tick", function(delta)
        for i = #balles_en_vol, 1, -1 do
            local b = balles_en_vol[i]
            b.parcouru = b.parcouru + (tr.vitesse or 30000) * delta
            if b.parcouru >= b.distance or not b.m:IsValid() then
                if b.m:IsValid() then b.m:Destroy() end
                pcall(morceau, b.fin, b.rot, Vector(0.04, 0.04, 0.04), 0.7, 90)
                table.remove(balles_en_vol, i)
            else
                -- La queue du trait ne recule jamais derriere le canon.
                local tete = b.parcouru
                local centre = math.max(b.longueur / 2, tete - b.longueur / 2)
                b.m:SetLocation(b.depart + b.u * centre)
            end
        end
    end)

    ------------------------------------------------------------ arme en premiere personne

    -- Le personnage n'a pas de pose de visee : sa main pend. Le tireur voit
    -- donc un modele de son arme pose devant sa camera ; les autres voient
    -- celle que le serveur met dans la main (et on cache celle-la chez soi).
    local vue_arme, vue_id, recul = nil, nil, 0
    -- Position de la camera dans le repere du personnage (mesuree a l'arret),
    -- et balancement lisse qui suit la vitesse.
    local camera_locale, stable, balance = nil, 0, Vector(0, 0, 0)
    -- Petite inclinaison quand on leve ou baisse les yeux, bornee et lissee.
    local tangage_avant, bascule = nil, 0

    local function retirer_vue_arme()
        if vue_arme and vue_arme:IsValid() then vue_arme:Destroy() end
        vue_arme, vue_id = nil, nil
        camera_locale, stable, balance = nil, 0, Vector(0, 0, 0)
        tangage_avant, bascule = nil, 0
    end

    local function angle(a) return (a + 180) % 360 - 180 end

    local function poser_vue_arme(id)
        if vue_id == id and vue_arme and vue_arme:IsValid() then return end
        retirer_vue_arme()
        local article = Catalogue.article("armes", id)
        if not (article and Catalogue.en_3d(id)) then return end
        pcall(function()
            vue_arme = StaticMesh(Vector(0, 0, -100000), Rotator(0, 0, 0), article.mesh, CollisionType.NoCollision)
            local s = (article.taille or 30) / 100
            vue_arme:SetScale(Vector(s, s, s))
            vue_id = id
        end)
    end

    local function bout_du_canon()
        local p = Client.GetLocalPlayer()
        local loc, rot = p:GetCameraLocation(), p:GetCameraRotation()
        return loc + rot:GetForwardVector() * ((vm.avant or 38) + 20) + rot:GetRightVector() * (vm.droite or 16)
            - rot:GetUpVector() * ((vm.bas or 15) - 3)
    end

    -- Tete cachee chez soi en premiere personne, et l'arme en main (vue des
    -- autres) aussi.
    local function masquer_soi(oui)
        local perso = mon_perso()
        if not (perso and perso:IsValid()) then return end
        pcall(function()
            if oui then perso:HideBone("Head"); perso:HideBone("Neck")
            else perso:UnHideBone("Head"); perso:UnHideBone("Neck") end
        end)
        for _, m in pairs(StaticMesh.GetPairs()) do
            if m:IsValid() and m:GetValue("duel_proprio", nil) == moi() then m:SetVisibility(not oui) end
        end
    end

    Client.Subscribe("Tick", function(delta)
        local perso = mon_perso()
        -- La valeur "duel" est posee par le serveur a chaque manche et retiree a
        -- la fin du duel, exactement comme la camera premiere personne : l'arme
        -- a l'ecran et la tete cachee la suivent, entre les manches comprises.
        local d = perso and perso:IsValid() and perso:GetValue("duel", nil)
        local combat = type(d) == "table" and d.combat == true
        if not combat then
            if vue_arme then retirer_vue_arme(); masquer_soi(false) end
        else
            if not vue_arme or vue_id ~= d.arme then
                poser_vue_arme(d.arme); masquer_soi(true)
                -- Accrochee au personnage : elle bouge dans la meme image que lui.
                -- Placee d'apres la camera, elle avait une image de retard et
                -- saccadait en marchant.
                if vue_arme and vue_arme:IsValid() then
                    -- KeepWorld : elle garde sa taille reelle (le personnage est a 0,8).
                    pcall(function() vue_arme:AttachTo(perso, AttachmentRule.KeepWorld, "", -1, false) end)
                end
            end
            if vue_arme and vue_arme:IsValid() then
                local p = Client.GetLocalPlayer()
                local loc, rot = p:GetCameraLocation(), p:GetCameraRotation()
                local prot = perso:GetRotation()
                local vitesse = prot:UnrotateVector(perso:GetVelocity())
                -- Un seul ancrage : les yeux. En premiere personne la camera ne bouge
                -- pas par rapport au personnage (bras nul) ; on la mesure dans son
                -- repere, mais seulement si elle est bien au-dessus de lui. Au debut
                -- d'une manche elle peut encore etre derriere (troisieme personne) :
                -- une telle mesure ancrait l'arme a 2,50 m, qui tournait alors
                -- autour du joueur quand il se retournait.
                local mesure = prot:UnrotateVector(loc - perso:GetLocation())
                local a_plat = math.sqrt(mesure.X * mesure.X + mesure.Y * mesure.Y)
                local valide = a_plat < (vm.ancrage_max or 60) and mesure.Z > 0
                local vx, vy = vitesse.X, vitesse.Y
                if vx * vx + vy * vy < 25 then stable = stable + 1 else stable = 0 end
                if valide and (not camera_locale or stable >= 4) then
                    camera_locale = camera_locale and (camera_locale + (mesure - camera_locale) * 0.3) or mesure
                end
                recul = math.max(0, recul - delta * 1000 / (vm.retour_ms or 90) * (vm.recul or 6))
                local k = math.min(1, delta * (vm.lissage or 8))
                local voulu = Vector(-vitesse.X, -vitesse.Y, -vitesse.Z) * (vm.balancement or 0.006)
                balance = balance + (voulu - balance) * k
                local visee = Rotator(rot.Pitch, angle(rot.Yaw - prot.Yaw), 0)
                local decalage = visee:RotateVector(Vector((vm.avant or 38) - recul, vm.droite or 16, -(vm.bas or 15)))
                local r = vm.rotation or { p = 0, y = 180, r = 0 }
                -- L'arme suit le regard ; en plus, quand le regard monte ou descend,
                -- elle s'incline a peine (au plus `inclinaison_max` degres) puis
                -- revient.
                local vitesse_tangage = tangage_avant and angle(rot.Pitch - tangage_avant) / math.max(delta, 0.001) or 0
                tangage_avant = rot.Pitch
                local borne = vm.inclinaison_max or 3
                local voulue = math.max(-borne, math.min(borne, -vitesse_tangage * (vm.inclinaison or 0.02)))
                bascule = bascule + (voulue - bascule) * k
                -- Le modele est exporte canon vers -X et retourne d'un demi-tour
                -- (r.y = 180) : dans ce repere, le tangage s'applique a l'envers.
                local tangage = visee.Pitch + bascule
                if math.abs(angle(r.y)) > 90 then tangage = -tangage end
                -- Le decalage relatif est dans le repere du personnage, donc a son echelle.
                local s = perso:GetScale().X
                if not s or s == 0 then s = 1 end
                -- Pas encore d'ancrage valable : l'arme reste hors de vue plutot que
                -- n'importe ou.
                if not camera_locale then
                    vue_arme:SetRelativeLocation(Vector(0, 0, -5000))
                else
                    vue_arme:SetRelativeLocation((camera_locale + decalage + balance) * (1 / s))
                end
                vue_arme:SetRelativeRotation(Rotator(tangage + r.p, visee.Yaw + r.y, r.r))
            end
        end

        -- La barre de vie suit la sante du personnage, lue chez soi ; une baisse
        -- assombrit l'ecran un instant.
        local j = mon_joueur()
        if j and etat and etat.phase ~= "attente" and perso and perso:IsValid() then
            local pv = perso:GetHealth()
            if pv ~= pv_affiches then
                if pv_affiches and pv < pv_affiches then appeler("blesse") end
                pv_affiches = pv
                appeler("vie", pv, perso:GetMaxHealth())
            end
        end
    end)

    ------------------------------------------------------------ ligne de vue des bots

    -- Le serveur ne sait pas tracer de rayon : c'est le client du joueur vise
    -- qui dit s'il voit le bot (et donc si le bot le voit). Sans cela, un bot
    -- tirait a travers les murs. Envoye seulement quand ca change.
    local vus = {}
    Timer.SetInterval(function()
        if not en_combat() then vus = {} return end
        local player, perso = Client.GetLocalPlayer(), mon_perso()
        local ok, err = pcall(function()
            local origine = player:GetCameraLocation()
            for _, c in pairs(CharacterSimple.GetPairs()) do
                local bot = c:IsValid() and c:GetValue("duel_bot", nil)
                if bot then
                    local cible = c:GetLocation() + Vector(0, 0, 50)
                    local hit = Trace.LineSingle(origine, cible,
                        CollisionChannel.WorldStatic | CollisionChannel.WorldDynamic | CollisionChannel.Pawn,
                        TraceMode.ReturnEntity | TraceMode.TraceComplex, { perso })
                    local visible = not (hit and hit.Success) or (hit.Entity ~= nil and hit.Entity:GetID() == c:GetID())
                    if vus[bot] ~= visible then
                        vus[bot] = visible
                        Events.CallRemote("duel:vue", Reliability.Reliable, bot, visible)
                    end
                end
            end
        end)
        if not ok then Console.Error("[duel] ligne de vue : " .. tostring(err)) end
    end, 200)

    ------------------------------------------------------------ evenements

    Events.SubscribeRemote("duel:etat", function(e)
        etat = e
        appeler("etat", e, moi())
    end)
    Events.SubscribeRemote("duel:mes_armes", function(liste, choisie)
        mes_armes, arme_choisie = liste or {}, choisie
        appeler("armes", mes_armes, choisie)
    end)
    Events.SubscribeRemote("duel:decompte", function(ms) appeler("decompte", ms) end)
    Events.SubscribeRemote("duel:manche", function(n) appeler("manche", n); pv_affiches = nil end)
    Events.SubscribeRemote("duel:manche_gagnee", function(camp) appeler("mancheGagnee", camp) end)
    Events.SubscribeRemote("duel:fin", function(camp, cagnotte)
        local j = mon_joueur()
        appeler("fin", camp, cagnotte, j ~= nil and j.camp == camp)
        if regarde then regarde = false; appeler("regarde", false) end
    end)
    Events.SubscribeRemote("duel:refus", function(_, noms) appeler("refus", noms or {}) end)
    Events.SubscribeRemote("duel:munitions", function(n)
        balles = n
        appeler("munitions", n, 6)
    end)
    Events.SubscribeRemote("duel:recharge", function(ms) appeler("recharge", ms) end)
    Events.SubscribeRemote("duel:touche", function() appeler("touche") end)
    Events.SubscribeRemote("duel:coup", function(depart, fin)
        son(depart)
        trainee(depart, fin)
    end)

    ------------------------------------------------------------ touches

    local function index_de(liste, valeur)
        for i, v in ipairs(liste) do if v == valeur then return i end end
        return 1
    end

    Input.Subscribe("KeyPress", function(touche)
        if chat_ouvert or not etat then return end
        local j = mon_joueur()
        if etat.phase == "attente" and j then
            if touche == "R" then
                Events.CallRemote("duel:pret", Reliability.Reliable, not j.pret)
            elseif etat.createur == moi() and (touche == "Right" or touche == "Left") then
                local paliers = etat.paliers or PALIERS_REPLI
                local i = index_de(paliers, etat.mise) + (touche == "Right" and 1 or -1)
                i = math.max(1, math.min(#paliers, i))
                Events.CallRemote("duel:mise", Reliability.Reliable, paliers[i])
            end
        elseif en_combat() and touche == "R" then
            Events.CallRemote("duel:recharger", Reliability.Reliable)
        elseif not j and (etat.phase == "combat" or etat.phase == "entre_manches" or etat.phase == "decompte") then
            if touche == "F" then
                regarde = true
                Events.CallRemote("duel:regarder", Reliability.Reliable, 1)
                appeler("regarde", true)
            elseif touche == "G" and regarde then
                regarde = false
                Events.CallRemote("duel:regarder", Reliability.Reliable, 0)
                appeler("regarde", false)
            end
        end
    end)

    -- Molette : l'arme suivante ou precedente, dans l'arene et hors combat.
    Input.Subscribe("MouseScroll", function(_, _, sens)
        local j = mon_joueur()
        if chat_ouvert or not (etat and j) or etat.phase == "combat" or #mes_armes < 2 then return end
        local i = 1
        for k, a in ipairs(mes_armes) do if a.id == arme_choisie then i = k end end
        i = (i - 1 + (sens > 0 and -1 or 1)) % #mes_armes + 1
        arme_choisie = mes_armes[i].id
        appeler("armes", mes_armes, arme_choisie)
        Events.CallRemote("duel:arme", Reliability.Reliable, arme_choisie)
    end)

    ------------------------------------------------------------ tir

    -- Le client vise (Trace n'existe que chez lui, doc Trace), le serveur
    -- verifie cadence, balles, portee et camps avant tout degat.
    Input.Subscribe("MouseDown", function(touche)
        if touche ~= "LeftMouseButton" or chat_ouvert or not en_combat() then return end
        local t = Client.GetTime()
        if t - dernier_tir < CADENCE_MS or balles <= 0 then return end
        dernier_tir = t
        local player = Client.GetLocalPlayer()
        local perso = mon_perso()
        local ok, err = pcall(function()
            local origine, regard = player:GetCameraLocation(), player:GetCameraRotation()
            local avant = regard:GetForwardVector()
            local fin = Vector(origine.X + avant.X * PORTEE, origine.Y + avant.Y * PORTEE, origine.Z + avant.Z * PORTEE)
            local canaux = CollisionChannel.WorldStatic | CollisionChannel.WorldDynamic
                | CollisionChannel.PhysicsBody | CollisionChannel.Pawn
            local ignores = { perso }
            if vue_arme and vue_arme:IsValid() then ignores[#ignores + 1] = vue_arme end
            local hit = Trace.LineSingle(origine, fin, canaux,
                TraceMode.ReturnEntity | TraceMode.ReturnNames | TraceMode.TraceComplex, ignores)
            local cible, os_touche, point = nil, nil, fin
            if hit and hit.Success then
                point = hit.Location
                if hit.Entity and hit.Entity:IsValid() and hit.Entity:IsA(CharacterSimple) then
                    cible, os_touche = hit.Entity:GetID(), hit.BoneName
                end
            end
            Events.CallRemote("duel:tir", Reliability.Reliable, cible, os_touche, point)
            -- Chez soi, tout de suite : son, trainee depuis le canon, recul.
            son(origine)
            trainee(bout_du_canon(), point)
            recul = vm.recul or 6
            player:SetCameraRotation(Rotator(regard.Pitch + (vm.recul_camera or 1.4), regard.Yaw, regard.Roll))
        end)
        if not ok then Console.Error("[duel] tir : " .. tostring(err)) end
    end)
end
