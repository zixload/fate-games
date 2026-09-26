-- Duel cote client : le HUD, les touches, le choix de l'arme et le tir en
-- premiere personne. Presentation seule (R1) : le client dit ce qu'il vise,
-- le serveur tranche (games/duel/adapter.lua).

return function(SharedConfig)
    SharedConfig = SharedConfig or {}
    Package.Require("duel/contour.lua")(SharedConfig.duel_contour)
    local Catalogue = Package.Require("Shared/catalogue.lua")
    local vm = SharedConfig.duel_arme or {}

    local page = WebUI("duel", "file://duel/hud.html", WidgetVisibility.VisibleNotHitTestable, true, true)
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

    -- Trainee de balle : un trait fin laiton, du canon au point touche, qui
    -- s'efface aussitot. Un petit eclat marque l'impact.
    local function trainee(depart, fin)
        if not (depart and fin) then return end
        pcall(function()
            local dx, dy, dz = fin.X - depart.X, fin.Y - depart.Y, fin.Z - depart.Z
            local n = math.sqrt(dx * dx + dy * dy + dz * dz)
            if n < 1 then return end
            local milieu = Vector(depart.X + dx / 2, depart.Y + dy / 2, depart.Z + dz / 2)
            local rot = Vector(dx, dy, dz):ToOrientationRotator()
            local trait = StaticMesh(milieu, rot, "nanos-world::SM_Cube", CollisionType.NoCollision)
            trait:SetScale(Vector(n / 100, 0.015, 0.015))
            trait:SetMaterial("nanos-world::M_Default_Masked_Unlit")
            trait:SetMaterialColorParameter("Tint", Color(1.0, 0.85, 0.45))
            local eclat = StaticMesh(fin, rot, "nanos-world::SM_Cube", CollisionType.NoCollision)
            eclat:SetScale(Vector(0.08, 0.08, 0.08))
            eclat:SetMaterial("nanos-world::M_Default_Masked_Unlit")
            eclat:SetMaterialColorParameter("Tint", Color(0.95, 0.9, 0.75))
            Timer.SetTimeout(function() if trait:IsValid() then trait:Destroy() end end, 60)
            Timer.SetTimeout(function() if eclat:IsValid() then eclat:Destroy() end end, 140)
        end)
    end

    ------------------------------------------------------------ arme en premiere personne

    -- Le personnage n'a pas de pose de visee : sa main pend. Le tireur voit
    -- donc un modele de son arme pose devant sa camera ; les autres voient
    -- celle que le serveur met dans la main (et on cache celle-la chez soi).
    local vue_arme, vue_id, recul = nil, nil, 0

    local function retirer_vue_arme()
        if vue_arme and vue_arme:IsValid() then vue_arme:Destroy() end
        vue_arme, vue_id = nil, nil
    end

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
        local d = perso and perso:IsValid() and perso:GetValue("duel", nil)
        local combat = type(d) == "table" and d.combat == true and en_combat()
        if not combat then
            if vue_arme then retirer_vue_arme(); masquer_soi(false) end
        else
            if not vue_arme or vue_id ~= d.arme then poser_vue_arme(d.arme); masquer_soi(true) end
            if vue_arme and vue_arme:IsValid() then
                local p = Client.GetLocalPlayer()
                local loc, rot = p:GetCameraLocation(), p:GetCameraRotation()
                recul = math.max(0, recul - delta * 1000 / (vm.retour_ms or 90) * (vm.recul or 6))
                local pos = loc + rot:GetForwardVector() * ((vm.avant or 38) - recul)
                    + rot:GetRightVector() * (vm.droite or 16) - rot:GetUpVector() * (vm.bas or 15)
                local r = vm.rotation or { p = 0, y = 180, r = 0 }
                vue_arme:SetLocation(pos)
                vue_arme:SetRotation(Rotator(rot.Pitch + r.p, rot.Yaw + r.y, rot.Roll + r.r))
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
            local hit = Trace.LineSingle(origine, fin, canaux, TraceMode.ReturnEntity | TraceMode.ReturnNames, ignores)
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
