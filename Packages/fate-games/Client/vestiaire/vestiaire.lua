-- Vestiaire d'arrivee : l'eventail de cartes (personnages, armes) par-dessus
-- le personnage qui attend dans le ciel. Presentation seule (R1) : chaque
-- choix part au serveur, qui renvoie l'etat qui fait foi.

return function(SharedConfig)
    local Catalogue = Package.Require("Shared/catalogue.lua")
    local reglage = (SharedConfig.vestiaire or {}).arme or {}

    local page = WebUI("vestiaire", "file://vestiaire/vestiaire.html",
        WidgetVisibility.Hidden, true, true)

    ------------------------------------------------------------ arme en 3D
    -- Un StaticMesh cree ici n'existe que pour ce client (doc StaticMesh) :
    -- il tourne sans saccade et personne d'autre ne le voit.
    --
    -- Le jeu a plante deux fois le 25-26/09 en changeant vite d'arme, d'abord
    -- quand chaque carte creait et detruisait un modele, puis quand elle en
    -- creait un et basculait sa visibilite. Desormais :
    --   * les six modeles sont crees une fois, un par un, a l'ouverture du
    --     vestiaire, et ranges loin sous le ciel ;
    --   * changer de carte ne fait que deplacer un modele deja pret, jamais
    --     creer, detruire ni cacher ;
    --   * le deplacement attend que la carte soit restee choisie un instant :
    --     faire defiler les cartes ne touche pas au monde.
    -- Les lignes "[vestiaire] 3D" de la console disent ou en etait le client.
    local RANGEMENT = Vector(0, 0, -100000)
    local ATTENTE_MS = 200
    local modeles = {}          -- id d'arme -> StaticMesh
    local montree = nil         -- id de l'arme devant la camera
    local minuteur = nil
    local precharge = false
    local angle = 0

    local function trace(message)
        Console.Log("[vestiaire] 3D " .. message)
    end

    local function creer(id)
        local article = Catalogue.article("armes", id)
        if not (article and Catalogue.en_3d(id)) then return nil end
        local m = modeles[id]
        if m and m:IsValid() then return m end
        trace("creation " .. id)
        m = StaticMesh(RANGEMENT, Rotator(0, 0, 0), article.mesh, CollisionType.NoCollision)
        local s = reglage.echelle or 1
        m:SetScale(Vector(s, s, s))
        modeles[id] = m
        return m
    end

    -- Cree les six modeles a 150 ms d'intervalle, une seule fois par session.
    local function precharger()
        if precharge or not Catalogue.armes_3d then return end
        precharge = true
        for i, article in ipairs(Catalogue.armes) do
            Timer.SetTimeout(function()
                local ok, err = pcall(creer, article.id)
                if not ok then Console.Error("[vestiaire] prechargement impossible : " .. tostring(err)) end
            end, i * 150)
        end
    end

    local function ranger()
        local m = montree and modeles[montree]
        if m and m:IsValid() then m:SetLocation(RANGEMENT) end
        montree = nil
    end

    -- Devant la camera fixe du vestiaire, au-dessus de l'eventail.
    local function place_devant()
        local player = Client.GetLocalPlayer()
        local loc, rot = player:GetCameraLocation(), player:GetCameraRotation()
        local centre = loc + rot:GetForwardVector() * (reglage.distance or 150)
            + rot:GetUpVector() * (reglage.hauteur or 30)
        return centre, rot
    end

    local function montrer(id)
        local ok, err = pcall(function()
            local m = creer(id)
            if not m then return end
            local centre, rot = place_devant()
            angle = rot.Yaw + 90
            m:SetRotation(Rotator(reglage.inclinaison or 0, angle, 0))
            m:SetLocation(centre)
            montree = id
            trace("affichee " .. id)
        end)
        if not ok then Console.Error("[vestiaire] arme 3D impossible : " .. tostring(err)) end
    end

    local function annuler_minuteur()
        if minuteur then Timer.ClearTimeout(minuteur) end
        minuteur = nil
    end

    local function cacher_vitrine()
        annuler_minuteur()
        ranger()
    end

    local function poser_vitrine(id)
        cacher_vitrine()
        if not Catalogue.en_3d(id) then return end
        minuteur = Timer.SetTimeout(function()
            minuteur = nil
            montrer(id)
        end, ATTENTE_MS)
    end

    Client.Subscribe("Tick", function(delta)
        local m = montree and modeles[montree]
        if not (m and m:IsValid()) then return end
        angle = (angle + delta * (reglage.vitesse or 35)) % 360
        m:SetRotation(Rotator(reglage.inclinaison or 0, angle, 0))
    end)

    -- On quitte le serveur ou le package se recharge : les modeles locaux
    -- partent avec lui.
    Package.Subscribe("Unload", function()
        annuler_minuteur()
        for _, m in pairs(modeles) do
            if m and m:IsValid() then m:Destroy() end
        end
        modeles, montree = {}, nil
    end)

    local pret = false
    local attente = nil

    local function envoyer(vue, refus)
        if not pret then
            attente = { vue, refus }
            return
        end
        page:CallEvent("vestiaire:etat", vue, refus)
    end

    local function marquer_pret()
        if pret then return end
        pret = true
        if attente then
            page:CallEvent("vestiaire:etat", attente[1], attente[2])
            attente = nil
        end
    end

    page:Subscribe("Ready", marquer_pret)
    page:Subscribe("pret", marquer_pret)
    page:Subscribe("Fail", function(_, code, message)
        Console.Error(("[vestiaire] WebUI impossible (%s) : %s")
            :format(tostring(code), tostring(message)))
    end)

    page:Subscribe("apercu", function(id)
        Events.CallRemote("vestiaire:apercu", Reliability.Reliable, id)
    end)
    page:Subscribe("acheter", function(rayon, id)
        Events.CallRemote("vestiaire:acheter", Reliability.Reliable, rayon, id)
    end)
    page:Subscribe("equiper", function(id)
        Events.CallRemote("vestiaire:equiper", Reliability.Reliable, id)
    end)
    page:Subscribe("entrer", function(id)
        Events.CallRemote("vestiaire:entrer", Reliability.Reliable, id)
    end)
    -- Rayon des armes : l'arme choisie ("" hors du rayon). Le serveur cache
    -- le personnage pendant ce temps, pour qu'il ne passe pas derriere.
    page:Subscribe("vitrine", function(id)
        Events.CallRemote("vestiaire:vitrine", Reliability.Reliable, id)
        if id ~= "" then poser_vitrine(id) else cacher_vitrine() end
    end)

    Events.SubscribeRemote("vestiaire:ouvrir", function(vue)
        page:SetVisibility(WidgetVisibility.Visible)
        page:BringToFront()
        page:SetFocus()
        Input.SetMouseEnabled(true)
        -- Pas de pas ni de camera pendant le choix : le clavier va a la page.
        Input.SetInputEnabled(false)
        page:CallEvent("vestiaire:ouvrir")
        envoyer(vue)
        precharger()
    end)

    Events.SubscribeRemote("vestiaire:etat", envoyer)

    -- I : remonter au vestiaire, debout et hors du chat. Le serveur refuse si
    -- l'on est assis. Pendant le choix, le clavier va a la page, donc cette
    -- touche ne se declenche pas deux fois.
    local chat_ouvert = false
    Chat.Subscribe("Open", function() chat_ouvert = true end)
    Chat.Subscribe("Close", function() chat_ouvert = false end)
    Input.Subscribe("KeyPress", function(key_name)
        if key_name ~= "I" or chat_ouvert then return end
        Events.CallRemote("vestiaire:retour", Reliability.Reliable)
    end)

    Events.SubscribeRemote("vestiaire:fermer", function()
        cacher_vitrine()
        page:SetVisibility(WidgetVisibility.Hidden)
        page:RemoveFocus()
        Input.SetMouseEnabled(false)
        Input.SetInputEnabled(true)
    end)
end
