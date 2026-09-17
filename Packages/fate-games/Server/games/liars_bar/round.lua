-- L'etat d'une manche.
--
-- Une regle gouverne tout le reste : un joueur sans cartes SORT de la manche,
-- on ne le compte plus. Le tour passe donc a la place vivante suivante qui a
-- encore des cartes. Et quand il ne reste qu'une seule place avec des cartes,
-- la manche s'arrete : il n'y a plus personne pour lui repondre.
--
-- Se vider ne met pas a l'abri de son imprudence : la derniere pose reste
-- accusable tant que la manche n'est pas finie.

return function(config, Deck)
    local Round = {}

    function Round.Start(seats, opener, rng)
        local cards = Deck.Shuffle(Deck.Build(), rng)
        local hands = Deck.Deal(cards, #seats, config.hand_size)

        -- Les mains sont indexees par numero de place, pas par rang dans seats.
        local par_place = {}
        for rank, seat in ipairs(seats) do
            par_place[seat] = hands[rank]
        end

        return {
            rank   = Deck.RANKS[rng(#Deck.RANKS)],
            hands  = par_place,
            last   = nil,
            opener = opener,
            turn   = opener,
        }
    end

    function Round.HasCards(round, seat)
        local hand = round.hands[seat]
        return hand ~= nil and #hand > 0
    end

    function Round.Play(round, seat, indices)
        if #indices < 1 or #indices > config.max_play then
            error(("pose de %d cartes : il en faut entre 1 et %d")
                :format(#indices, config.max_play))
        end

        local hand = round.hands[seat] or {}

        local vus = {}
        for _, i in ipairs(indices) do
            if type(i) ~= "number" or i < 1 or i > #hand or i % 1 ~= 0 then
                error("indice invalide : " .. tostring(i))
            end
            if vus[i] then
                error("indice en double : " .. tostring(i))
            end
            vus[i] = true
        end

        -- On retire du plus grand indice au plus petit pour que les suivants
        -- restent valides pendant la suppression.
        local tries = {}
        for _, i in ipairs(indices) do tries[#tries + 1] = i end
        table.sort(tries)

        local cards = {}
        for _, i in ipairs(tries) do
            cards[#cards + 1] = hand[i]
        end
        for k = #tries, 1, -1 do
            table.remove(hand, tries[k])
        end

        round.last = { seat = seat, cards = cards }
        return cards
    end

    -- Prochaine place vivante AVEC des cartes, en partant de round.turn et en
    -- bouclant. Rend nil s'il n'y en a aucune.
    function Round.NextTurn(round, seats)
        local depart = 0
        for rank, seat in ipairs(seats) do
            if seat == round.turn then
                depart = rank
                break
            end
        end

        for step = 1, #seats do
            local rank = ((depart - 1 + step) % #seats) + 1
            local seat = seats[rank]
            if Round.HasCards(round, seat) then
                return seat
            end
        end

        return nil
    end

    -- La manche est epuisee des qu'il reste moins de deux places avec des
    -- cartes : une place seule ne peut ni etre accusee ni accuser utilement.
    function Round.Exhausted(round, seats)
        local avec = 0
        for _, seat in ipairs(seats) do
            if Round.HasCards(round, seat) then
                avec = avec + 1
                if avec >= 2 then return false end
            end
        end
        return true
    end

    return Round
end
