return function(H, Stubs)
    local make_effects = Package.Require("games/liars_bar/effects.lua")

    H.describe("liars_bar/effects", function()

        H.it("adresse une distribution au seul destinataire", function()
            local E = make_effects()
            local e = E.Deal(3, { "king", "joker" })

            H.assert_eq(e.kind, "deal", "nature")
            H.assert_eq(e.audience, 3, "audience limitee au proprietaire")
            H.assert_eq(#e.cards, 2, "cartes transmises")
        end)

        H.it("ne publie qu'un nombre quand des cartes sont posees", function()
            local E = make_effects()
            local e = E.CardsPlayed(2, 3)

            H.assert_eq(e.audience, "all", "audience publique")
            H.assert_eq(e.count, 3, "compte publie")
            H.assert_nil(e.cards, "aucune carte ne doit fuiter")
        end)

        H.it("publie les cartes seulement lors d'une revelation", function()
            local E = make_effects()
            local e = E.Reveal(1, { "king", "ace" })

            H.assert_eq(e.audience, "all", "revelation publique")
            H.assert_eq(#e.cards, 2, "cartes revelees")
        end)

        H.it("decrit un tir avec sa chambre et son issue", function()
            local E = make_effects()
            local e = E.Shoot(4, 3, true)

            H.assert_eq(e.seat, 4, "tireur")
            H.assert_eq(e.chamber, 3, "chambre")
            H.assert_true(e.fatal, "issue")
            H.assert_eq(e.audience, "all", "le decompte est public")
        end)

        H.it("annonce publiquement qui doit tirer", function()
            local E = make_effects()
            local e = E.Designated(2)

            H.assert_eq(e.kind, "designated", "nature")
            H.assert_eq(e.seat, 2, "tireur designe")
            H.assert_eq(e.audience, "all", "toute la table le sait")
        end)

        H.it("rejette un effet de nature inconnue", function()
            local E = make_effects()
            H.assert_error(function() E.Validate({ kind = "teleporte", audience = "all" }) end,
                "nature inconnue")
        end)

        H.it("rejette un effet sans audience", function()
            local E = make_effects()
            H.assert_error(function() E.Validate({ kind = "turn", seat = 1 }) end,
                "audience manquante")
        end)

        H.it("valide tous les constructeurs", function()
            local E = make_effects()
            local tous = {
                E.Appearance(1, "clown"),
                E.Deal(1, { "king" }),
                E.TableCard("ace"),
                E.CardsPlayed(1, 2),
                E.Reveal(1, { "king" }),
                E.Accuse(2, 1),
                E.Designated(1),
                E.Shoot(1, 1, false),
                E.Eliminated(1),
                E.Turn(2),
                E.RoundEnded("challenged"),
                E.MatchEnded(2, { rounds = 7 }),
            }
            for _, e in ipairs(tous) do
                H.assert_true(E.Validate(e), "effet valide : " .. tostring(e.kind))
            end
        end)

        H.it("rejette une main glissee dans une pose publique", function()
            local E = make_effects()
            local truque = E.CardsPlayed(1, 2)
            truque.hand = { "king", "queen" }

            H.assert_error(function() E.Validate(truque) end, "champ inconnu hand")
        end)

        H.it("rejette tout champ etranger a la nature de l'effet", function()
            local E = make_effects()
            local tour = E.Turn(2)
            tour.cards = { "ace" }
            H.assert_error(function() E.Validate(tour) end, "champ inconnu cards")

            local tir = E.Shoot(1, 1, false)
            tir.bullet = 4
            H.assert_error(function() E.Validate(tir) end, "champ inconnu bullet")
        end)

        H.it("exige un compte entier d'au moins une carte", function()
            local E = make_effects()
            H.assert_true(E.Validate(E.CardsPlayed(1, 1)), "une carte")
            H.assert_error(function() E.Validate(E.CardsPlayed(1, 0)) end, "compte de cartes invalide")
            H.assert_error(function() E.Validate(E.CardsPlayed(1, 1.5)) end, "compte de cartes invalide")
            H.assert_error(function() E.Validate(E.CardsPlayed(1, nil)) end, "compte de cartes invalide")
        end)

        H.it("detecte une fuite de cartes dans un effet public", function()
            local E = make_effects()

            -- Un effet public qui porterait des cartes est la seule faille qui
            -- ruinerait le jeu : un client curieux lirait le paquet.
            local truque = E.CardsPlayed(1, 2)
            truque.cards = { "king", "queen" }

            H.assert_error(function() E.AssertNoLeak({ truque }) end, "fuite")
        end)

        H.it("accepte une liste d'effets sans fuite", function()
            local E = make_effects()
            H.assert_true(E.AssertNoLeak({
                E.Deal(1, { "king" }),        -- prive, donc autorise
                E.Reveal(1, { "ace" }),       -- revelation, donc autorisee
                E.CardsPlayed(1, 2),
                E.Turn(2),
            }), "aucune fuite")
        end)

        H.it("n'accepte que les deux motifs de fin de manche", function()
            local E = make_effects()
            H.assert_true(E.Validate(E.RoundEnded("challenged")), "contestation")
            H.assert_true(E.Validate(E.RoundEnded("exhausted")), "epuisement")
            H.assert_error(function() E.Validate(E.RoundEnded("ennui")) end, "motif inconnu")
        end)
    end)
end
