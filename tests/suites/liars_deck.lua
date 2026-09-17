return function(H, Stubs)
    local config    = Package.Require("games/liars_bar/data/config.lua")
    local make_deck = Package.Require("games/liars_bar/data/deck.lua")

    -- rng deterministe : rend toujours la premiere valeur possible, donc Shuffle
    -- devient l'identite et les tests peuvent comparer des listes exactes.
    local function rng_fixe(_) return 1 end

    -- rng scriptable : consomme une file de valeurs, pour les tirages precis.
    local function rng_scripte(valeurs)
        local i = 0
        return function(n)
            i = i + 1
            local v = valeurs[i] or 1
            H.assert_true(v >= 1 and v <= n, "valeur scriptee hors bornes")
            return v
        end
    end

    local function compter(cards)
        local par_rang = {}
        for _, c in ipairs(cards) do par_rang[c] = (par_rang[c] or 0) + 1 end
        return par_rang
    end

    H.describe("liars_bar/deck", function()

        H.it("construit vingt cartes dans la bonne composition", function()
            local Deck = make_deck(config)
            local cards = Deck.Build()

            H.assert_eq(#cards, 20, "taille du paquet")

            local n = compter(cards)
            H.assert_eq(n.king,  6, "rois")
            H.assert_eq(n.queen, 6, "dames")
            H.assert_eq(n.ace,   6, "as")
            H.assert_eq(n.joker, 2, "jokers")
        end)

        H.it("ne propose que trois valeurs de table", function()
            local Deck = make_deck(config)
            H.assert_eq(#Deck.RANKS, 3, "nombre de valeurs")
            for _, r in ipairs(Deck.RANKS) do
                H.assert_true(r ~= "joker", "le joker ne peut pas etre carte de table")
            end
        end)

        H.it("melange sans perdre ni inventer de carte", function()
            local Deck = make_deck(config)
            local cards = Deck.Shuffle(Deck.Build(), rng_scripte({ 7, 3, 12, 1, 5, 9 }))

            H.assert_eq(#cards, 20, "taille apres melange")
            local n = compter(cards)
            H.assert_eq(n.king + n.queen + n.ace + n.joker, 20, "total conserve")
            H.assert_eq(n.joker, 2, "jokers conserves")
        end)

        H.it("melange de facon reproductible a rng identique", function()
            local Deck = make_deck(config)
            local a = Deck.Shuffle(Deck.Build(), rng_scripte({ 4, 11, 2, 6, 5 }))
            local b = Deck.Shuffle(Deck.Build(), rng_scripte({ 4, 11, 2, 6, 5 }))

            for i = 1, 20 do
                H.assert_eq(a[i], b[i], "carte " .. i)
            end
        end)

        H.it("fait correspondre la valeur de table et le joker, rien d'autre", function()
            local Deck = make_deck(config)

            H.assert_true(Deck.Matches("king",  "king"),  "roi contre roi")
            H.assert_true(Deck.Matches("joker", "king"),  "joker contre roi")
            H.assert_true(Deck.Matches("joker", "ace"),   "joker contre as")
            H.assert_false(Deck.Matches("queen", "king"), "dame contre roi")
            H.assert_false(Deck.Matches("ace",   "king"), "as contre roi")
        end)

        H.it("distribue cinq cartes a chacun et rend le reste", function()
            local Deck = make_deck(config)
            local hands, rest = Deck.Deal(Deck.Shuffle(Deck.Build(), rng_fixe), 4, config.hand_size)

            H.assert_count(hands, 4, "nombre de mains")
            for place = 1, 4 do
                H.assert_eq(#hands[place], 5, "main de la place " .. place)
            end
            H.assert_eq(#rest, 0, "a quatre joueurs le paquet entier part")
        end)

        H.it("laisse cinq cartes de cote a trois joueurs", function()
            local Deck = make_deck(config)
            local hands, rest = Deck.Deal(Deck.Shuffle(Deck.Build(), rng_fixe), 3, config.hand_size)

            H.assert_count(hands, 3, "nombre de mains")
            H.assert_eq(#rest, 5, "cartes non distribuees")
        end)

        H.it("refuse de distribuer plus que le paquet", function()
            local Deck = make_deck(config)
            H.assert_error(function()
                Deck.Deal(Deck.Build(), 5, 5)
            end, "paquet insuffisant")
        end)
    end)
end
