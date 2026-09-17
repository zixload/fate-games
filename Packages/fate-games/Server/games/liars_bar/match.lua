-- L'etat d'une partie.
--
-- Les apparences sont attribuees au hasard et DISTINCTES : tirage sans remise
-- dans le catalogue de Shared/appearances.lua. La distinction est donc garantie
-- par construction et non laissee a la chance — ce qui compte dans un jeu de
-- bluff n'est pas de choisir sa tete, c'est de pouvoir distinguer les autres.
--
-- Dix apparences pour six places au maximum : le tirage ne peut pas echouer.

return function(config, Appearances, Revolver)
    local Match = {}

    -- Tirage sans remise : on copie le catalogue, on pioche, on retire.
    local function tirer_apparences(count, rng)
        local pool = {}
        for _, a in ipairs(Appearances.list) do
            pool[#pool + 1] = a.id
        end

        if count > #pool then
            error(("apparences insuffisantes : %d demandees, %d au catalogue")
                :format(count, #pool))
        end

        local choisies = {}
        for _ = 1, count do
            local i = rng(#pool)
            choisies[#choisies + 1] = table.remove(pool, i)
        end
        return choisies
    end

    function Match.New(player_ids, rng)
        if #player_ids < config.min_players then
            error(("il faut au moins trois joueurs, %d presents"):format(#player_ids))
        end
        if #player_ids > config.max_seats then
            error(("%d joueurs pour %d places"):format(#player_ids, config.max_seats))
        end

        local looks = tirer_apparences(#player_ids, rng)

        local match = {
            seats      = {},
            players    = {},
            revolvers  = {},
            looks      = {},
            alive      = {},
            dead_order = {},
            rounds     = 0,
        }

        for i, player_id in ipairs(player_ids) do
            local seat = i
            match.seats[#match.seats + 1] = seat
            match.players[seat]   = player_id
            match.revolvers[seat] = Revolver.New(rng)
            match.looks[seat]     = looks[i]
            match.alive[seat]     = true
        end

        return match
    end

    function Match.AliveSeats(match)
        local vivants = {}
        for _, seat in ipairs(match.seats) do
            if match.alive[seat] then
                vivants[#vivants + 1] = seat
            end
        end
        return vivants
    end

    function Match.Eliminate(match, seat)
        if not match.alive[seat] then return end
        match.alive[seat] = nil
        match.dead_order[#match.dead_order + 1] = seat
    end

    function Match.Winner(match)
        local vivants = Match.AliveSeats(match)
        if #vivants == 1 then
            return vivants[1]
        end
        return nil
    end

    -- Place vivante suivante dans l'ordre des places, en bouclant.
    function Match.NextAlive(match, seat)
        local depart
        for rank, s in ipairs(match.seats) do
            if s == seat then
                depart = rank
                break
            end
        end
        if not depart then return nil end

        for step = 1, #match.seats do
            local rank = ((depart - 1 + step) % #match.seats) + 1
            local candidat = match.seats[rank]
            if match.alive[candidat] then
                return candidat
            end
        end

        return nil
    end

    return Match
end
