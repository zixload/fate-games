-- Ordonnanceur a roue (R4).
--
-- Chaque entite inscrite est traitee une fois par tour de roue, pas a chaque tick.
-- Le cout par tick reste donc constant quand la population grandit, au lieu de croitre
-- lineairement comme le ferait une boucle sur tous les joueurs.

return function(Log, config)
    local Scheduler = {}

    local slot_count = math.max(1, math.floor(config.scheduler.wheel_seconds))
    local tick_ms    = config.scheduler.tick_ms

    local slots  = {}
    local counts = {}
    for i = 1, slot_count do
        slots[i]  = {}
        counts[i] = 0
    end

    local slot_of     = {}   -- cle -> index de slot
    local cursor      = 1
    local interval_id = nil

    -- Repartit sur le slot le moins charge, pour eviter que les inscriptions
    -- consecutives se tassent sur le meme tick.
    local function least_loaded_slot()
        local best, best_count = 1, math.huge
        for i = 1, slot_count do
            if counts[i] < best_count then
                best, best_count = i, counts[i]
            end
        end
        return best
    end

    function Scheduler.Add(key, callback)
        if slot_of[key] then Scheduler.Remove(key) end

        local slot = least_loaded_slot()
        slots[slot][key] = callback
        counts[slot]     = counts[slot] + 1
        slot_of[key]     = slot
    end

    function Scheduler.Remove(key)
        local slot = slot_of[key]
        if not slot then return end

        slots[slot][key] = nil
        counts[slot]     = counts[slot] - 1
        slot_of[key]     = nil
    end

    local function tick()
        local batch = slots[cursor]
        cursor = cursor % slot_count + 1

        -- Instantane des cles : un callback peut inscrire ou retirer une entite
        -- (deconnexion, mort), et muter la table pendant son propre parcours est
        -- un comportement indefini en Lua.
        local keys, n = {}, 0
        for key in pairs(batch) do
            n = n + 1
            keys[n] = key
        end

        for i = 1, n do
            local key      = keys[i]
            local callback = batch[key]
            if callback then
                local ok, err = pcall(callback, key)
                if not ok then
                    Log.Error("scheduler", ("callback en echec pour %s : %s")
                        :format(tostring(key), tostring(err)))
                end
            end
        end
    end

    function Scheduler.Start()
        if interval_id then return end
        interval_id = Timer.SetInterval(tick, tick_ms)
        Log.Info("scheduler", ("roue demarree : %d slots, tick %d ms")
            :format(slot_count, tick_ms))
    end

    function Scheduler.Stop()
        if not interval_id then return end
        Timer.ClearInterval(interval_id)
        interval_id = nil
    end

    return Scheduler
end
