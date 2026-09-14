-- Point de passage unique des actions joueur (R1).
--
-- Le client envoie une intention, jamais un resultat. Toute intention suit le meme chemin :
--     validation -> application -> audit -> reponse
-- Un seul goulot d'etranglement, donc l'anti-exploit et l'audit sont structurels et non
-- saupoudres dans chaque systeme.

return function(Log)
    local Intents = {}
    local handlers = {}

    -- spec = {
    --     validate = function(player, payload) -> ok, raison
    --     apply    = function(player, payload, cid) -> ok, resultat
    -- }
    function Intents.Register(name, spec)
        if handlers[name] then
            Log.Warn("intents", "intention redefinie : " .. tostring(name))
        end
        handlers[name] = spec
    end

    -- Attention a la signature : cote serveur c'est
    -- CallRemote(evenement, joueur, fiabilite, ...). Oublier la fiabilite fait
    -- glisser le premier argument utile dans ce parametre.
    local function respond(player, name, ok, detail)
        Events.CallRemote("zix:intent_result", player, Reliability.Reliable, name, ok, detail)
    end

    local function handle(player, name, payload)
        local cid  = Log.NewCorrelationId()
        local spec = handlers[name]

        if not spec then
            -- Intention inconnue : soit un bug, soit un client modifie. Les deux
            -- meritent une trace.
            Log.Warn("intents", "intention inconnue : " .. tostring(name), cid)
            return respond(player, name, false, "unknown_intent")
        end

        local valid, reason = spec.validate(player, payload)
        if not valid then
            Log.Info("intents", ("refusee %s : %s"):format(tostring(name), tostring(reason)), cid)
            return respond(player, name, false, reason)
        end

        local ok, result = spec.apply(player, payload, cid)

        Log.Audit({
            actor          = player and player:GetID() or "?",
            target         = result and result.target or "-",
            action         = name,
            position       = result and result.position or "-",
            payload        = result and result.audit or "-",
            correlation_id = cid,
        })

        respond(player, name, ok, result)
    end

    Events.SubscribeRemote("zix:intent", function(player, name, payload)
        local ok, err = pcall(handle, player, name, payload)
        if not ok then
            -- Une intention qui plante ne doit jamais emporter le serveur avec elle.
            Log.Error("intents", ("exception sur %s : %s"):format(tostring(name), tostring(err)))
        end
    end)

    return Intents
end
