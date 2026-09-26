-- Detection de l'objet vise, cote client.
--
-- Le client trace depuis la camera, regarde si ce qu'il touche figure dans la copie
-- allegee du registre envoyee par le serveur, et signale le changement de cible. Il ne
-- decide rien : appuyer sur la touche envoie une **intention**, que le serveur revalide
-- entierement, distance comprise (R1).
--
-- La copie du registre n'est donc pas une faille : un client modifie qui s'en
-- inventerait une se ferait refuser par le serveur.

return function(config)
    local Interaction = {}

    -- Un outil de l'atelier en main : E sert a tourner l'objet tenu.
    local outil_atelier = Package.Require("outil_atelier.lua")

    -- id -> { label, kind, max_distance }
    local known = {}

    local focused_id = nil
    local tick_handle = nil

    -- Filtre pose par un jeu (ex. Liar's Bar en partie) : fonction(entite) ->
    -- vrai si l'objet peut etre vise. Aucun filtre : tout ce qui est connu.
    local filtre = nil

    function Interaction.SetFiltre(f)
        filtre = f
    end

    local function permis(entite)
        if not filtre then return true end
        local ok, oui = pcall(filtre, entite)
        return ok and oui == true
    end

    local REACH = (config and config.reach) or 400.0

    -- Demi-angle du cone de rattrapage, en degres (voir plus_proche_du_regard).
    local CONE = math.cos(math.rad((config and config.cone_degrees) or 10.0))

    ----------------------------------------------------------------------------
    -- Reception du registre
    ----------------------------------------------------------------------------

    Events.SubscribeRemote("zix:interactables_full", function(list)
        known = {}
        for _, entry in ipairs(list or {}) do
            known[entry.id] = { label = entry.label, kind = entry.kind,
                max_distance = entry.max_distance }
        end
    end)

    Events.SubscribeRemote("zix:interactable_added", function(entry)
        if entry and entry.id then
            known[entry.id] = { label = entry.label, kind = entry.kind,
                max_distance = entry.max_distance }
        end
    end)

    Events.SubscribeRemote("zix:interactable_removed", function(id)
        known[id] = nil
        if focused_id == id then
            Interaction.SetFocus(nil)
        end
    end)

    ----------------------------------------------------------------------------
    -- Focus
    ----------------------------------------------------------------------------

    -- Signale le changement de cible pour l'invite sans texte.
    function Interaction.SetFocus(id)
        if focused_id == id then return end

        focused_id = id
        local entry = id and known[id] or nil

        Events.Call("zix:focus_changed", id, entry and entry.label or nil,
            entry and entry.kind or nil)
    end

    function Interaction.GetFocus()
        return focused_id
    end

    ----------------------------------------------------------------------------
    -- Boucle de visee
    ----------------------------------------------------------------------------

    -- Rattrapage quand la trace ne touche rien d'interactif : l'objet connu le
    -- plus proche de l'axe du regard, dans un cone etroit. Viser au pixel un
    -- petit objet sur une table demandait des angles precis, et le moindre
    -- volume devant (une main, une carte) volait la trace.
    --
    -- La distance est celle que le serveur revalide (personnage -> objet,
    -- portee de l'objet) : l'invite ne promet rien qu'il refuserait. Pas de
    -- test de ligne de vue : l'objet peut etre derriere un obstacle mince, le
    -- serveur ne regarde de toute facon que la distance.
    --
    -- Les objets du registre sont des Props (games/*/adapter.lua).
    local function plus_proche_du_regard(character, origin, forward)
        local pied = character:GetLocation()
        local meilleur, meilleur_cos = nil, CONE
        for _, prop in pairs(Prop.GetPairs()) do
            local entry = prop:IsValid() and known[prop:GetID()] or nil
            if entry and permis(prop) then
                local l = prop:GetLocation()
                local dx, dy, dz = l.X - pied.X, l.Y - pied.Y, l.Z - pied.Z
                if math.sqrt(dx * dx + dy * dy + dz * dz) <= (entry.max_distance or REACH) then
                    local vx, vy, vz = l.X - origin.X, l.Y - origin.Y, l.Z - origin.Z
                    local d = math.sqrt(vx * vx + vy * vy + vz * vz)
                    if d > 0 then
                        local c = (vx * forward.X + vy * forward.Y + vz * forward.Z) / d
                        if c > meilleur_cos then meilleur, meilleur_cos = prop:GetID(), c end
                    end
                end
            end
        end
        return meilleur
    end

    local function scan()
        if outil_atelier.actif then return Interaction.SetFocus(nil) end
        local player = Client.GetLocalPlayer()
        if not player then return Interaction.SetFocus(nil) end

        local character = player:GetControlledCharacter()
        if not character then return Interaction.SetFocus(nil) end

        local origin   = player:GetCameraLocation()
        local rotation = player:GetCameraRotation()
        if not origin or not rotation then return Interaction.SetFocus(nil) end

        local forward = rotation:GetForwardVector()
        local target  = Vector(
            origin.X + forward.X * REACH,
            origin.Y + forward.Y * REACH,
            origin.Z + forward.Z * REACH
        )

        -- On ignore le personnage du joueur, sinon on se vise soi-meme.
        local channels = CollisionChannel.WorldStatic
            | CollisionChannel.WorldDynamic
            | CollisionChannel.PhysicsBody
            | CollisionChannel.Pawn

        -- ReturnEntity est indispensable : sans ce mode, la trace ne renvoie pas
        -- l'entite touchee et on ne saurait pas quoi viser.
        local hit = Trace.LineSingle(origin, target, channels, TraceMode.ReturnEntity, { character })

        -- Ce que la trace touche l'emporte ; sinon, le cone.
        local id = hit and hit.Entity and hit.Entity:GetID() or nil
        if id and known[id] and permis(hit.Entity) then
            return Interaction.SetFocus(id)
        end
        Interaction.SetFocus(plus_proche_du_regard(character, origin, forward))
    end

    -- Volontairement pas a chaque image : viser n'a pas besoin de 60 traces par
    -- seconde, et c'est du travail pur cote client.
    function Interaction.Start()
        if tick_handle then return end
        tick_handle = Timer.SetInterval(function()
            local ok, err = pcall(scan)
            if not ok then
                Console.Error("[interaction] scan en echec : " .. tostring(err))
            end
        end, (config and config.scan_interval_ms) or 150)
    end

    function Interaction.Stop()
        if not tick_handle then return end
        Timer.ClearInterval(tick_handle)
        tick_handle = nil
        Interaction.SetFocus(nil)
    end

    ----------------------------------------------------------------------------
    -- Entree joueur
    ----------------------------------------------------------------------------

    -- Le client envoie une intention, jamais un resultat.
    -- Cote client la signature est CallRemote(evenement, fiabilite, ...) : il n'y a
    -- pas de joueur a viser, ca part vers le serveur.
    function Interaction.Trigger()
        if not focused_id or outil_atelier.actif then return end
        Events.CallRemote("zix:intent", Reliability.Reliable, "interact", { target = focused_id })
    end

    -- On ecoute la touche brute plutot que Input.Bind : celui-ci exige un
    -- identifiant de raccourci deja declare dans le jeu, et rien ne garantit qu'un
    -- raccourci "Interact" existe. Une touche nommee, elle, marche toujours.
    local KEY = (config and config.key) or "E"

    Input.Subscribe("KeyPress", function(key_name)
        if key_name == KEY then
            Interaction.Trigger()
        end
    end)

    return Interaction
end
