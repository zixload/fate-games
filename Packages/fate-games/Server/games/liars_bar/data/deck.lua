-- Le paquet reduit de Liar's Bar.
--
-- Vingt cartes : six rois, six dames, six as, deux jokers. Cette composition
-- n'est pas decorative, elle fait le jeu. A quatre joueurs le paquet entier est
-- distribue, donc au maximum huit cartes peuvent legitimement etre annoncees
-- comme des rois — six rois plus deux jokers. Des que les pretentions cumulees
-- depassent huit, quelqu'un ment avec certitude, et contester devient fonde.

return function(config)
    local Deck = {}

    -- Le joker n'y figure pas : il vaut n'importe quoi, il ne peut donc pas
    -- etre la valeur imposee de la manche.
    Deck.RANKS = { "king", "queen", "ace" }

    local COMPOSITION = {
        { rank = "king",  count = 6 },
        { rank = "queen", count = 6 },
        { rank = "ace",   count = 6 },
        { rank = "joker", count = 2 },
    }

    function Deck.Build()
        local cards = {}
        for _, entry in ipairs(COMPOSITION) do
            for _ = 1, entry.count do
                cards[#cards + 1] = entry.rank
            end
        end
        return cards
    end

    -- Fisher-Yates, avec le hasard injecte. On melange en place et on rend la
    -- meme table, pour pouvoir chainer Shuffle(Build()).
    function Deck.Shuffle(cards, rng)
        for i = #cards, 2, -1 do
            local j = rng(i)
            cards[i], cards[j] = cards[j], cards[i]
        end
        return cards
    end

    function Deck.Matches(card, rank)
        return card == rank or card == "joker"
    end

    -- Rend les mains indexees par numero de place, et ce qui reste du paquet.
    function Deck.Deal(cards, seats, size)
        local needed = seats * size
        if needed > #cards then
            error(("paquet insuffisant : %d cartes demandees, %d disponibles")
                :format(needed, #cards))
        end

        local hands, next_card = {}, 1
        for place = 1, seats do
            local hand = {}
            for _ = 1, size do
                hand[#hand + 1] = cards[next_card]
                next_card = next_card + 1
            end
            hands[place] = hand
        end

        local rest = {}
        for i = next_card, #cards do
            rest[#rest + 1] = cards[i]
        end

        return hands, rest
    end

    return Deck
end
