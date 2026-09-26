-- Objets interactifs.
--
-- Un acteur n'est pas interactif parce que sa collision est reglee d'une certaine
-- maniere dans Unreal, mais parce que le **serveur l'a enregistre ici**. Le registre
-- est la source de verite.
--
-- C'est un choix delibere. Le moteur expose bien un canal de collision `Interactable`
-- dans la configuration de l'ADK, mais il n'apparait pas dans l'enumeration
-- CollisionChannel cote Lua, et s'appuyer dessus imposerait au createur de la carte de
-- regler chaque objet correctement. Avec un registre, le Lua decide seul.
--
-- Le client recoit une copie allegee du registre — identifiant, libelle, portee — pour
-- pouvoir afficher une invite sans aller-retour reseau. Cette copie ne sert qu'a
-- l'affichage : le serveur revalide tout a la reception de l'intention (R1).

return function(Log, Intents, Characters, config)
    local Interactables = {}

    local registry = {}

    local function default_distance()
        return (config.interaction and config.interaction.max_distance) or 250.0
    end

    local function public_entry(id, entry)
        return { id = id, label = entry.label, kind = entry.kind,
            max_distance = entry.max_distance }
    end

    local function distance_between(a, b)
        local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
        return math.sqrt(dx * dx + dy * dy + dz * dz)
    end

    ----------------------------------------------------------------------------
    -- Registre
    ----------------------------------------------------------------------------

    -- spec = {
    --     label        = "Examiner"          -- ce que le joueur lit
    --     kind         = "seat"              -- icone client, optionnel
    --     max_distance = 250                 -- optionnel
    --     validate     = function(player, session, entry) -> ok, raison  -- optionnel
    --     on_interact  = function(player, session, entry, cid)           -- requis
    -- }
    function Interactables.Register(actor, spec)
        if not actor then
            error("Interactables.Register : acteur absent", 2)
        end
        if type(spec) ~= "table" or type(spec.on_interact) ~= "function" then
            error("Interactables.Register : on_interact est requis", 2)
        end

        local id = actor:GetID()

        registry[id] = {
            actor        = actor,
            label        = spec.label or "Interagir",
            kind         = spec.kind or "pickup",
            max_distance = spec.max_distance or default_distance(),
            validate     = spec.validate,
            on_interact  = spec.on_interact,
        }

        Events.BroadcastRemote("zix:interactable_added", Reliability.Reliable,
            public_entry(id, registry[id]))
        Log.Debug("interactables", ("enregistre %d (%s)"):format(id, registry[id].label))

        return id
    end

    function Interactables.Unregister(id)
        if not registry[id] then return false end

        registry[id] = nil
        Events.BroadcastRemote("zix:interactable_removed", Reliability.Reliable, id)
        Log.Debug("interactables", "retire " .. tostring(id))

        return true
    end

    function Interactables.Get(id)
        return registry[id]
    end

    function Interactables.Count()
        local n = 0
        for _ in pairs(registry) do n = n + 1 end
        return n
    end

    -- Copie allegee, pour l'affichage cote client.
    function Interactables.Snapshot()
        local list = {}
        for id, entry in pairs(registry) do
            list[#list + 1] = public_entry(id, entry)
        end
        return list
    end

    -- A appeler quand un joueur entre en jeu : il doit connaitre ce qui existe deja.
    function Interactables.SendSnapshotTo(player)
        Events.CallRemote("zix:interactables_full", player, Reliability.Reliable,
            Interactables.Snapshot())
    end

    ----------------------------------------------------------------------------
    -- L'intention
    ----------------------------------------------------------------------------

    Intents.Register("interact", {
        validate = function(player, payload)
            if type(payload) ~= "table" then return false, "payload_invalide" end

            local id = tonumber(payload.target)
            if not id then return false, "cible_invalide" end

            local entry = registry[id]
            if not entry then return false, "cible_inconnue" end

            local session = Characters.SessionByPlayer(player:GetID())
            if not session or not session.character then return false, "pas_en_jeu" end

            -- Le client a pu viser un objet detruit entre-temps.
            local ok, actor_location = pcall(function() return entry.actor:GetLocation() end)
            if not ok or not actor_location then return false, "cible_absente" end

            local distance = distance_between(session.character:GetLocation(), actor_location)
            if distance > entry.max_distance then
                -- Un client modifie peut tres bien envoyer une intention depuis
                -- l'autre bout de la carte : c'est ici que ca s'arrete.
                return false, "trop_loin"
            end

            if entry.validate then
                return entry.validate(player, session, entry)
            end

            return true
        end,

        apply = function(player, payload, cid)
            local id      = tonumber(payload.target)
            local entry   = registry[id]
            local session = Characters.SessionByPlayer(player:GetID())

            local ok, err = pcall(entry.on_interact, player, session, entry, cid)
            if not ok then
                Log.Error("interactables", ("on_interact en echec pour %d : %s")
                    :format(id, tostring(err)), cid)
                return false, { target = "interactable:" .. id, audit = "echec" }
            end

            return true, {
                target   = "interactable:" .. id,
                position = "-",
                audit    = entry.label,
            }
        end,
    })

    return Interactables
end
