-- L'etat d'une manche.
--
-- Une regle gouverne tout le reste : un joueur sans cartes SORT de la manche,
-- on ne le compte plus. Le tour passe donc a la place vivante suivante qui a
-- encore des cartes.
--
-- Se vider ne met pas a l'abri de son imprudence : la derniere pose reste
-- accusable tant qu'un autre joueur que son auteur a des cartes. La manche
-- n'est nulle que lorsque plus personne ne peut lui repondre.

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
        if type(indices) ~= "table" then
            error("indices invalides : table attendue")
        end

        -- On ne se fie pas a # : sur une table a trous comme { nil, nil, 3 },
        -- # peut rendre 3 alors qu'ipairs n'en parcourt aucun, et la pose
        -- passerait sans retirer une seule carte — une pose vide qui efface la
        -- precedente. On compte donc les cles et les elements separement.
        local cles, elements = 0, 0
        for _ in pairs(indices) do cles = cles + 1 end
        for _ in ipairs(indices) do elements = elements + 1 end

        if cles ~= elements then
            error("indices mal formes : table a trous ou cles non entieres")
        end
        if elements < 1 or elements > config.max_play then
            error(("pose de %d cartes : il en faut entre 1 et %d")
                :format(elements, config.max_play))
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
    --
    -- round.turn peut nommer une place ABSENTE de seats : c'est le cas juste
    -- apres l'elimination du joueur dont c'etait le tour. On repart alors de la
    -- place qu'il occupait dans l'ordre de la table, sinon le tour reviendrait
    -- au debut et sauterait ses voisins.
    function Round.NextTurn(round, seats)
        local depart = 0
        for rank, seat in ipairs(seats) do
            if seat == round.turn then
                depart = rank
                break
            end
            if seat < round.turn then
                depart = rank
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

    -- La manche est nulle quand plus personne ne peut repondre a la derniere
    -- pose. Se vider ne met pas a l'abri : tant qu'un AUTRE joueur que son
    -- auteur a des cartes, cette pose reste accusable et la manche continue.
    -- Avant toute pose, il faut simplement deux porteurs pour jouer.
    function Round.Exhausted(round, seats)
        local porteurs = {}
        for _, seat in ipairs(seats) do
            if Round.HasCards(round, seat) then
                porteurs[#porteurs + 1] = seat
            end
        end

        if #porteurs == 0 then return true end
        if round.last == nil then return #porteurs < 2 end

        for _, seat in ipairs(porteurs) do
            if seat ~= round.last.seat then return false end
        end
        return true
    end

    return Round
end
