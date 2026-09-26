-- Duel cote client : le HUD, les touches, le tir. Presentation seule (R1) :
-- le client dit ce qu'il vise, le serveur tranche (games/duel/adapter.lua).

return function()
    local page = WebUI("duel", "file://duel/hud.html", WidgetVisibility.VisibleNotHitTestable, true, true)
    local pret_page = false
    local attente = {}
    local etat = nil
    local chat_ouvert = false
    local dernier_tir = 0
    local balles = 6
    local pv_affiches = nil
    local regarde = false

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

    ------------------------------------------------------------ evenements

    Events.SubscribeRemote("duel:etat", function(e)
        etat = e
        appeler("etat", e, moi())
    end)
    Events.SubscribeRemote("duel:decompte", function(ms) appeler("decompte", ms) end)
    Events.SubscribeRemote("duel:manche", function(n) appeler("manche", n) end)
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
    Events.SubscribeRemote("duel:touche", function() appeler("touche") end)
    Events.SubscribeRemote("duel:coup", function(position) son(position) end)

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
            elseif etat.createur == moi() then
                local paliers = etat.paliers or PALIERS_REPLI
                if touche == "Right" or touche == "Left" then
                    local i = index_de(paliers, etat.mise) + (touche == "Right" and 1 or -1)
                    i = math.max(1, math.min(#paliers, i))
                    Events.CallRemote("duel:choisir", Reliability.Reliable, etat.format, paliers[i])
                elseif touche == "Up" or touche == "Down" then
                    Events.CallRemote("duel:choisir", Reliability.Reliable, touche == "Up" and 2 or 1, etat.mise)
                end
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
            local hit = Trace.LineSingle(origine, fin, canaux, TraceMode.ReturnEntity | TraceMode.ReturnNames,
                perso and { perso } or {})
            local cible, os_touche = nil, nil
            if hit and hit.Success and hit.Entity and hit.Entity:IsValid() and hit.Entity:IsA(CharacterSimple) then
                cible, os_touche = hit.Entity:GetID(), hit.BoneName
            end
            Events.CallRemote("duel:tir", Reliability.Reliable, cible, os_touche)
            if perso then son(perso:GetLocation()) end
        end)
        if not ok then Console.Error("[duel] tir : " .. tostring(err)) end
    end)

    -- La barre de vie suit la sante du personnage, lue chez soi.
    Client.Subscribe("Tick", function()
        local j = mon_joueur()
        if not (j and etat and etat.phase ~= "attente") then return end
        local perso = mon_perso()
        if not (perso and perso:IsValid()) then return end
        local pv = perso:GetHealth()
        if pv ~= pv_affiches then
            pv_affiches = pv
            appeler("vie", pv, perso:GetMaxHealth())
        end
    end)
end
