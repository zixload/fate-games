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

    -- id -> { label, max_distance }
    local known = {}

    local focused_id = nil
    local tick_handle = nil

    local REACH = (config and config.reach) or 400.0

    ----------------------------------------------------------------------------
    -- Reception du registre
    ----------------------------------------------------------------------------

    Events.SubscribeRemote("zix:interactables_full", function(list)
        known = {}
        for _, entry in ipairs(list or {}) do
            known[entry.id] = { label = entry.label, max_distance = entry.max_distance }
        end
    end)

    Events.SubscribeRemote("zix:interactable_added", function(entry)
        if entry and entry.id then
            known[entry.id] = { label = entry.label, max_distance = entry.max_distance }
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

    -- Signale le changement de cible. C'est ce que l'interface ecoutera pour
    -- afficher ou masquer l'invite ; aucune UI n'existe encore.
    function Interaction.SetFocus(id)
        if focused_id == id then return end

        focused_id = id
        local entry = id and known[id] or nil

        Events.Call("zix:focus_changed", id, entry and entry.label or nil)
    end

    function Interaction.GetFocus()
        return focused_id
    end

    ----------------------------------------------------------------------------
    -- Boucle de visee
    ----------------------------------------------------------------------------

    local function scan()
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

        if not hit or not hit.Entity then
            return Interaction.SetFocus(nil)
        end

        local id = hit.Entity:GetID()
        if known[id] then
            Interaction.SetFocus(id)
        else
            Interaction.SetFocus(nil)
        end
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
        if not focused_id then return end
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
