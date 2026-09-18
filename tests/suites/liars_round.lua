return function(H, Stubs)
    local config     = Package.Require("games/liars_bar/data/config.lua")
    local make_deck  = Package.Require("games/liars_bar/data/deck.lua")
    local make_round = Package.Require("games/liars_bar/round.lua")

    local function build()
        local Deck = make_deck(config)
        return make_round(config, Deck), Deck
    end

    local function rng_fixe(_) return 1 end

    -- Force une main connue, pour tester les poses sans dependre du melange.
    local function poser_main(round, seat, cards)
        round.hands[seat] = cards
    end

    H.describe("liars_bar/round", function()

        H.it("distribue une main a chaque place et tire une carte de table", function()
            local Round = build()
            local round = Round.Start({ 1, 2, 3, 4 }, 1, rng_fixe)

            H.assert_count(round.hands, 4, "nombre de mains")
            H.assert_eq(#round.hands[1], 5, "taille de main")
            H.assert_true(round.rank == "king" or round.rank == "queen" or round.rank == "ace",
                "carte de table valide : " .. tostring(round.rank))
            H.assert_nil(round.last, "aucune pose au depart")
            H.assert_eq(round.turn, 1, "l'ouvreur commence")
        end)

        H.it("ouvre sur la place demandee", function()
            local Round = build()
            local round = Round.Start({ 1, 2, 3, 4 }, 3, rng_fixe)
            H.assert_eq(round.turn, 3, "ouvreur")
        end)

        H.it("retire les cartes posees de la main et enregistre la pose", function()
            local Round = build()
            local round = Round.Start({ 1, 2 }, 1, rng_fixe)
            poser_main(round, 1, { "king", "queen", "ace", "joker", "king" })

            local posees = Round.Play(round, 1, { 1, 3 })

            H.assert_eq(#posees, 2, "cartes posees")
            H.assert_eq(posees[1], "king", "premiere posee")
            H.assert_eq(posees[2], "ace", "seconde posee")
            H.assert_eq(#round.hands[1], 3, "main restante")
            H.assert_eq(round.last.seat, 1, "auteur de la pose")
            H.assert_eq(#round.last.cards, 2, "pose enregistree")
        end)

        H.it("refuse une pose vide ou trop grosse", function()
            local Round = build()
            local round = Round.Start({ 1, 2 }, 1, rng_fixe)

            H.assert_error(function() Round.Play(round, 1, {} ) end, "entre 1 et 3")
            H.assert_error(function() Round.Play(round, 1, { 1, 2, 3, 4 }) end, "entre 1 et 3")
        end)

        H.it("refuse une table d'indices a trous", function()
            local Round = build()
            local round = Round.Start({ 1, 2 }, 1, rng_fixe)
            poser_main(round, 1, { "king", "queen", "ace", "joker", "king" })

            -- La faille n'existe que si # et ipairs divergent reellement dans ce
            -- Lua : on le verifie ici, sinon le refus ci-dessous ne prouverait rien.
            local trouee = { nil, nil, 3 }
            local parcourus = 0
            for _ in ipairs(trouee) do parcourus = parcourus + 1 end
            H.assert_eq(#trouee, 3, "# compte trois indices")
            H.assert_eq(parcourus, 0, "ipairs n'en parcourt aucun")

            H.assert_error(function() Round.Play(round, 1, trouee) end, "indices mal formes")
            H.assert_eq(#round.hands[1], 5, "aucune carte retiree")
            H.assert_nil(round.last, "aucune pose enregistree")

            -- Une cle non entiere a cote d'indices valides : meme refus.
            H.assert_error(function() Round.Play(round, 1, { 1, extra = 2 }) end,
                "indices mal formes")
        end)

        H.it("refuse un indice absent de la main", function()
            local Round = build()
            local round = Round.Start({ 1, 2 }, 1, rng_fixe)
            poser_main(round, 1, { "king", "queen" })

            H.assert_error(function() Round.Play(round, 1, { 5 }) end, "indice invalide")
        end)

        H.it("refuse le meme indice deux fois", function()
            local Round = build()
            local round = Round.Start({ 1, 2 }, 1, rng_fixe)
            poser_main(round, 1, { "king", "queen", "ace" })

            H.assert_error(function() Round.Play(round, 1, { 2, 2 }) end, "indice en double")
        end)

        H.it("passe le tour a la place suivante qui a des cartes", function()
            local Round = build()
            local round = Round.Start({ 1, 2, 3 }, 1, rng_fixe)
            poser_main(round, 2, {})                -- la place 2 est vide

            round.turn = 1
            H.assert_eq(Round.NextTurn(round, { 1, 2, 3 }), 3, "on saute la place vide")
        end)

        H.it("boucle sur l'ordre des places", function()
            local Round = build()
            local round = Round.Start({ 1, 2, 3 }, 1, rng_fixe)

            round.turn = 3
            H.assert_eq(Round.NextTurn(round, { 1, 2, 3 }), 1, "retour a la premiere place")
        end)

        H.it("ne rend aucun tour quand plus personne n'a de cartes", function()
            local Round = build()
            local round = Round.Start({ 1, 2 }, 1, rng_fixe)
            poser_main(round, 1, {})
            poser_main(round, 2, {})

            H.assert_nil(Round.NextTurn(round, { 1, 2 }), "aucun tour possible")
        end)

        H.it("declare la manche epuisee quand moins de deux places ont des cartes", function()
            local Round = build()
            local round = Round.Start({ 1, 2, 3 }, 1, rng_fixe)

            H.assert_false(Round.Exhausted(round, { 1, 2, 3 }), "au depart")

            poser_main(round, 1, {})
            poser_main(round, 2, {})
            H.assert_true(Round.Exhausted(round, { 1, 2, 3 }),
                "une seule place a des cartes : plus personne pour lui repondre")
        end)

        H.it("sait si une place a encore des cartes", function()
            local Round = build()
            local round = Round.Start({ 1, 2 }, 1, rng_fixe)

            H.assert_true(Round.HasCards(round, 1), "main pleine")
            poser_main(round, 1, {})
            H.assert_false(Round.HasCards(round, 1), "main vide")
        end)

        H.it("ne declare pas la manche epuisee a deux places avec des cartes", function()
            local Round = build()
            local round = Round.Start({ 1, 2, 3 }, 1, rng_fixe)
            poser_main(round, 1, {})

            -- Deux places gardent des cartes : la manche continue. C'est la borne
            -- exacte de la regle "moins de deux", et un `<= 2` la franchirait ici.
            H.assert_false(Round.Exhausted(round, { 1, 2, 3 }), "deux places avec des cartes")
        end)

        H.it("garde la derniere pose accusable quand son auteur se vide", function()
            local Round = build()
            local round = Round.Start({ 1, 2, 3 }, 1, rng_fixe)
            poser_main(round, 1, { "ace" })
            poser_main(round, 2, { "king", "queen" })
            poser_main(round, 3, {})

            -- A pose sa derniere carte : il ne reste que B comme porteur. B peut
            -- encore contester la pose de A, donc la manche n'est PAS nulle.
            Round.Play(round, 1, { 1 })
            H.assert_eq(round.last.seat, 1, "A est l'auteur de la derniere pose")
            H.assert_false(Round.HasCards(round, 1), "A s'est vide")
            H.assert_false(Round.Exhausted(round, { 1, 2, 3 }),
                "B a des cartes et peut repondre a A")
        end)

        H.it("declare la manche nulle quand seul l'auteur de la pose a des cartes", function()
            local Round = build()
            local round = Round.Start({ 1, 2, 3 }, 1, rng_fixe)
            poser_main(round, 1, { "ace", "king" })
            poser_main(round, 2, {})
            poser_main(round, 3, {})

            Round.Play(round, 1, { 1 })
            H.assert_true(Round.Exhausted(round, { 1, 2, 3 }),
                "personne d'autre que l'auteur ne peut repondre")
        end)

        H.it("reprend apres la place disparue et non au debut de la table", function()
            local Round = build()
            local round = Round.Start({ 1, 2, 3, 4 }, 1, rng_fixe)

            -- La place 2 vient d'etre eliminee alors que c'etait son tour : elle
            -- ne figure plus parmi les vivants. Le tour doit passer a la place 3,
            -- pas revenir a la place 1.
            round.turn = 2
            H.assert_eq(Round.NextTurn(round, { 1, 3, 4 }), 3, "place suivante en ordre de table")
        end)
    end)
end
