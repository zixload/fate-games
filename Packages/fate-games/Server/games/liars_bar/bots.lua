-- Bots de test de Liar's Bar : la decision, et rien d'autre.
--
-- Pur, comme le moteur : il lit l'etat et rend un acte, sans toucher a nanos
-- world. L'adaptateur decide QUAND demander (apres chaque lot d'effets, avec
-- un delai) ; ce fichier decide QUOI jouer. Les coups sont legaux et tires au
-- hasard : un bot de test doit faire avancer la partie, pas la gagner.

return function(config)
    local Bots = {}

    -- La place dont le jeu attend un acte : le tireur designe d'abord, sinon
    -- celui dont c'est le tour.
    function Bots.Awaited(state)
        if not state or state.finished then return nil end
        if state.pending then return state.pending.seat end
        return state.round and state.round.turn or nil
    end

    function Bots.Decide(state, seat, rng)
        if not state or state.finished then return nil end

        if state.pending then
            if state.pending.seat == seat then
                return { kind = "shoot", seat = seat }
            end
            return nil
        end

        local round = state.round
        if not round or round.turn ~= seat then return nil end

        -- On n'accuse que la pose d'un autre : le moteur refuse le reste.
        local last = round.last
        local peut_accuser = last ~= nil and last.seat ~= seat
        if peut_accuser and rng(100) <= config.bots.accuse_percent then
            return { kind = "challenge", seat = seat }
        end

        local hand = round.hands[seat] or {}
        if #hand == 0 then
            -- Inatteignable en jeu normal : le tour ne va qu'a une place qui a
            -- des cartes. Garde-fou pour ne pas rendre une pose vide.
            if peut_accuser then return { kind = "challenge", seat = seat } end
            return nil
        end

        -- Tirage sans remise dans les indices de la main.
        local n = rng(math.min(config.max_play, #hand))
        local pool = {}
        for i = 1, #hand do pool[i] = i end
        local indices = {}
        for k = 1, n do
            indices[k] = table.remove(pool, rng(#pool))
        end
        table.sort(indices)

        return { kind = "play", seat = seat, indices = indices }
    end

    return Bots
end
