return function(H, Stubs)
    local config         = Package.Require("games/liars_bar/data/config.lua")
    local make_deck      = Package.Require("games/liars_bar/data/deck.lua")
    local make_revolver  = Package.Require("games/liars_bar/revolver.lua")
    local make_challenge = Package.Require("games/liars_bar/challenge.lua")
    local make_round     = Package.Require("games/liars_bar/round.lua")
    local make_match     = Package.Require("games/liars_bar/match.lua")
    local make_effects   = Package.Require("games/liars_bar/effects.lua")
    local Appearances    = Package.Require("Shared/appearances.lua")
    local make_engine    = Package.Require("games/liars_bar/engine.lua")

    local function build()
        local Deck      = make_deck(config)
        local Revolver  = make_revolver(config)
        local Challenge = make_challenge(Deck)
        local RoundM    = make_round(config, Deck)
        local MatchM    = make_match(config, Appearances, Revolver)
        local Effects   = make_effects()
        return make_engine(config, Deck, Revolver, Challenge, RoundM, MatchM, Effects), Effects
    end

    local function rng_croissant()
        local i = 0
        return function(n)
            i = i + 1
            return ((i - 1) % n) + 1
        end
    end

    -- Hasard qui place toujours la balle en derniere chambre : personne ne
    -- meurt avant le sixieme tir, ce qui rend les scenarios previsibles.
    local function rng_sans_mort()
        return function(n) return n end
    end

    local function kinds(effects)
        local out = {}
        for _, e in ipairs(effects) do out[#out + 1] = e.kind end
        return table.concat(out, ",")
    end

    local function find(effects, kind)
        for _, e in ipairs(effects) do
            if e.kind == kind then return e end
        end
        return nil
    end

    H.describe("liars_bar/engine", function()

        H.it("demarre une partie et distribue en prive", function()
            local Engine, Effects = build()
            local state, effects = Engine.Start({ "p1", "p2", "p3" }, rng_croissant())

            H.assert_eq(#state.match.seats, 3, "places")
            H.assert_false(state.finished, "partie en cours")
            H.assert_true(find(effects, "table_card") ~= nil, "carte de table annoncee")
            H.assert_true(find(effects, "turn") ~= nil, "tour annonce")

            local distributions = 0
            for _, e in ipairs(effects) do
                if e.kind == "deal" then
                    distributions = distributions + 1
                    H.assert_eq(e.audience, e.seat, "distribution privee")
                end
            end
            H.assert_eq(distributions, 3, "une distribution par joueur")
            H.assert_true(Effects.AssertNoLeak(effects), "aucune fuite au demarrage")
        end)

        H.it("annonce une apparence distincte par joueur au demarrage", function()
            local Engine = build()
            local _, effects = Engine.Start({ "p1", "p2", "p3" }, rng_croissant())

            local vues, n = {}, 0
            for _, e in ipairs(effects) do
                if e.kind == "appearance" then
                    n = n + 1
                    H.assert_nil(vues[e.look], "apparence en double : " .. tostring(e.look))
                    vues[e.look] = true
                end
            end
            H.assert_eq(n, 3, "une apparence par joueur")
        end)

        H.it("ne publie qu'un compte quand un joueur pose", function()
            local Engine, Effects = build()
            local state = Engine.Start({ "p1", "p2", "p3" }, rng_croissant())

            local seat = state.round.turn
            local _, effects = Engine.Apply(state, { kind = "play", seat = seat, indices = { 1, 2 } })

            local joue = find(effects, "cards_played")
            H.assert_true(joue ~= nil, "effet de pose")
            H.assert_eq(joue.count, 2, "compte publie")
            H.assert_nil(joue.cards, "aucune carte publiee")
            H.assert_true(Effects.AssertNoLeak(effects), "aucune fuite a la pose")
        end)

        H.it("refuse une pose hors de son tour", function()
            local Engine = build()
            local state = Engine.Start({ "p1", "p2", "p3" }, rng_croissant())

            local pas_son_tour = state.round.turn == 1 and 2 or 1
            H.assert_error(function()
                Engine.Apply(state, { kind = "play", seat = pas_son_tour, indices = { 1 } })
            end, "pas son tour")
        end)

        H.it("refuse une contestation quand rien n'a ete pose", function()
            local Engine = build()
            local state = Engine.Start({ "p1", "p2", "p3" }, rng_croissant())

            H.assert_error(function()
                Engine.Apply(state, { kind = "challenge", seat = state.round.turn })
            end, "aucune pose")
        end)

        H.it("refuse de contester sa propre pose", function()
            local Engine = build()
            local state = Engine.Start({ "p1", "p2", "p3" }, rng_croissant())

            local seat = state.round.turn
            state = Engine.Apply(state, { kind = "play", seat = seat, indices = { 1 } })

            -- Le tour a avance apres la pose, donc cette garde n'est PAS joignable
            -- par le jeu normal : on ramene le tour sur l'auteur de la pose pour
            -- l'eprouver. C'est un garde-fou, pas une regle de tour — handlers.leave
            -- reassigne le tour, et rien ne garantit qu'aucun chemin futur ne le
            -- ramene ici.
            state.round.turn = seat

            H.assert_error(function()
                Engine.Apply(state, { kind = "challenge", seat = seat })
            end, "sa propre pose")
        end)

        H.it("revele la pose et designe un tireur a la contestation", function()
            local Engine, Effects = build()
            local state = Engine.Start({ "p1", "p2", "p3" }, rng_sans_mort())

            local poseur = state.round.turn
            state = Engine.Apply(state, { kind = "play", seat = poseur, indices = { 1 } })

            local accusateur = state.round.turn
            local effects
            state, effects = Engine.Apply(state, { kind = "challenge", seat = accusateur })

            H.assert_true(find(effects, "accuse") ~= nil, "geste d'accusation")
            local reveal = find(effects, "reveal")
            H.assert_true(reveal ~= nil, "revelation")
            H.assert_eq(reveal.seat, poseur, "on revele la pose accusee")

            H.assert_true(state.pending ~= nil, "un tireur est en attente")
            local designe = state.pending.seat
            H.assert_true(designe == poseur or designe == accusateur,
                "le tireur est l'un des deux")

            local annonce = find(effects, "designated")
            H.assert_true(annonce ~= nil, "le tireur est annonce : " .. kinds(effects))
            H.assert_eq(annonce.seat, designe, "l'annonce nomme le tireur en attente")
            H.assert_true(Effects.AssertNoLeak(effects), "aucune fuite a la contestation")
        end)

        H.it("designe bien le menteur et non l'accusateur", function()
            local Engine = build()
            local state = Engine.Start({ "p1", "p2", "p3" }, rng_sans_mort())

            local poseur = state.round.turn
            -- Main entierement intruse : la pose est forcement un mensonge.
            local intruse = state.round.rank == "king" and "ace" or "king"
            state.round.hands[poseur] = { intruse, intruse, intruse, intruse, intruse }

            state = Engine.Apply(state, { kind = "play", seat = poseur, indices = { 1 } })
            local accusateur = state.round.turn
            state = Engine.Apply(state, { kind = "challenge", seat = accusateur })

            -- Ternaire inversee : ce serait l'accusateur qui tirerait.
            H.assert_eq(state.pending.seat, poseur, "le menteur tire")
        end)

        H.it("laisse accuser le joueur qui vient de se vider en mentant", function()
            local Engine = build()
            local state = Engine.Start({ "p1", "p2", "p3" }, rng_sans_mort())

            local seats = state.match.seats
            local a, b, c = seats[1], seats[2], seats[3]
            H.assert_eq(state.round.turn, a, "A ouvre")

            -- A n'a plus qu'une carte, et elle ment ; C n'a plus rien. Apres la
            -- pose de A, B est le seul porteur — mais il peut encore repondre.
            local intruse = state.round.rank == "king" and "ace" or "king"
            state.round.hands[a] = { intruse }
            state.round.hands[c] = {}

            local effects
            state, effects = Engine.Apply(state, { kind = "play", seat = a, indices = { 1 } })
            H.assert_nil(find(effects, "round_ended"), "la manche continue : " .. kinds(effects))
            H.assert_eq(state.round.turn, b, "la main passe a B")

            state, effects = Engine.Apply(state, { kind = "challenge", seat = b })
            H.assert_true(state.pending ~= nil, "un tir est en attente")
            H.assert_eq(state.pending.seat, a, "A, qui a menti en se vidant, doit tirer")
            H.assert_eq(find(effects, "designated").seat, a, "A est annonce comme tireur")
        end)

        H.it("n'accepte le tir que du joueur designe", function()
            local Engine = build()
            local state = Engine.Start({ "p1", "p2", "p3" }, rng_sans_mort())

            local poseur = state.round.turn
            state = Engine.Apply(state, { kind = "play", seat = poseur, indices = { 1 } })
            state = Engine.Apply(state, { kind = "challenge", seat = state.round.turn })

            local autre = Engine.OtherThan(state.match, state.pending.seat)
            H.assert_error(function()
                Engine.Apply(state, { kind = "shoot", seat = autre })
            end, "pas designe")
        end)

        H.it("fait clic, ouvre une nouvelle manche et garde le barillet en memoire", function()
            local Engine = build()
            local state = Engine.Start({ "p1", "p2", "p3" }, rng_sans_mort())

            local poseur = state.round.turn
            state = Engine.Apply(state, { kind = "play", seat = poseur, indices = { 1 } })
            state = Engine.Apply(state, { kind = "challenge", seat = state.round.turn })

            local tireur = state.pending.seat
            local effects
            state, effects = Engine.Apply(state, { kind = "shoot", seat = tireur })

            local tir = find(effects, "shoot")
            H.assert_true(tir ~= nil, "effet de tir")
            H.assert_false(tir.fatal, "clic attendu avec ce hasard")
            H.assert_eq(tir.chamber, 1, "premiere chambre")

            H.assert_eq(state.match.revolvers[tireur].fired, 1, "le barillet se souvient")
            H.assert_true(find(effects, "round_ended") ~= nil, "fin de manche")
            H.assert_true(find(effects, "table_card") ~= nil, "nouvelle carte de table")
            H.assert_nil(state.pending, "plus personne en attente")
            H.assert_eq(state.round.turn, tireur, "le perdant ouvre la manche suivante")
        end)

        H.it("elimine le joueur quand la balle part", function()
            local Engine = build()
            -- Balle en premiere chambre pour tout le monde.
            local state = Engine.Start({ "p1", "p2", "p3" }, function(_) return 1 end)

            local poseur = state.round.turn
            state = Engine.Apply(state, { kind = "play", seat = poseur, indices = { 1 } })
            state = Engine.Apply(state, { kind = "challenge", seat = state.round.turn })

            local tireur = state.pending.seat
            local effects
            state, effects = Engine.Apply(state, { kind = "shoot", seat = tireur })

            H.assert_true(find(effects, "shoot").fatal, "tir fatal")
            H.assert_true(find(effects, "eliminated") ~= nil, "elimination annoncee")
            H.assert_nil(state.match.alive[tireur], "le tireur n'est plus vivant")
        end)

        H.it("termine la manche sans tir quand les cartes s'epuisent", function()
            local Engine = build()
            local state = Engine.Start({ "p1", "p2", "p3" }, rng_sans_mort())

            -- On vide les mains de deux joueurs a la main : il ne reste qu'une
            -- place avec des cartes, donc plus personne pour lui repondre.
            local vivants = state.match.seats
            state.round.hands[vivants[1]] = {}
            state.round.hands[vivants[2]] = {}

            local seat = vivants[3]
            state.round.turn = seat
            local effects
            state, effects = Engine.Apply(state, { kind = "play", seat = seat, indices = { 1 } })

            local fin = find(effects, "round_ended")
            H.assert_true(fin ~= nil, "fin de manche")
            H.assert_eq(fin.reason, "exhausted", "motif")
            H.assert_nil(state.pending, "aucun tir")
        end)

        H.it("traite un depart comme une elimination", function()
            local Engine = build()
            local state = Engine.Start({ "p1", "p2", "p3" }, rng_sans_mort())

            local partant = state.match.seats[2]
            local effects
            state, effects = Engine.Apply(state, { kind = "leave", seat = partant })

            H.assert_nil(state.match.alive[partant], "le partant n'est plus vivant")
            H.assert_true(find(effects, "eliminated") ~= nil, "elimination annoncee")
        end)

        H.it("ouvre la manche suivante quand le tireur designe s'en va", function()
            local Engine = build()
            local state = Engine.Start({ "p1", "p2", "p3" }, rng_sans_mort())

            local poseur = state.round.turn
            state = Engine.Apply(state, { kind = "play", seat = poseur, indices = { 1 } })
            state = Engine.Apply(state, { kind = "challenge", seat = state.round.turn })

            local designe       = state.pending.seat
            local manches_avant = state.match.rounds

            local effects
            state, effects = Engine.Apply(state, { kind = "leave", seat = designe })

            -- La manche se termine avec le depart, donc la suivante DOIT s'ouvrir.
            -- Sinon l'etat de manche reste perime alors que les clients ont ete
            -- prevenus de sa fin, et plus rien ne peut la clore.
            H.assert_true(find(effects, "round_ended") ~= nil, "fin de manche annoncee")
            H.assert_true(find(effects, "table_card") ~= nil, "nouvelle carte de table")
            H.assert_true(find(effects, "turn") ~= nil, "nouveau tour annonce")
            H.assert_nil(state.pending, "plus personne en attente")
            H.assert_nil(state.round.last, "la nouvelle manche n'a pas de pose")
            H.assert_eq(state.match.rounds, manches_avant + 1, "une manche de plus")

            -- Un seul round_ended : deux violeraient le contrat d'ordre des effets.
            local fins = 0
            for _, e in ipairs(effects) do
                if e.kind == "round_ended" then fins = fins + 1 end
            end
            H.assert_eq(fins, 1, "un seul round_ended")
        end)

        H.it("clot la manche sans tir quand le menteur accuse est deja parti", function()
            local Engine = build()
            local state = Engine.Start({ "p1", "p2", "p3" }, rng_sans_mort())

            local seats = state.match.seats
            local menteur, accusateur = seats[1], seats[2]
            H.assert_eq(state.round.turn, menteur, "le menteur ouvre")

            local intruse = state.round.rank == "king" and "ace" or "king"
            state.round.hands[menteur] = { intruse, intruse, intruse, intruse, intruse }
            state = Engine.Apply(state, { kind = "play", seat = menteur, indices = { 1 } })
            H.assert_eq(state.round.turn, accusateur, "la main passe a l'accusateur")

            local depart
            state, depart = Engine.Apply(state, { kind = "leave", seat = menteur })
            H.assert_false(state.finished, "deux vivants : la partie continue")

            local manches_avant = state.match.rounds
            local effects
            state, effects = Engine.Apply(state, { kind = "challenge", seat = accusateur })

            H.assert_nil(state.pending, "aucun tir en attente sur un mort")
            H.assert_nil(find(effects, "shoot"), "aucun tir")
            H.assert_nil(find(effects, "designated"), "personne n'est designe")
            local fin = find(effects, "round_ended")
            H.assert_true(fin ~= nil, "fin de manche : " .. kinds(effects))
            H.assert_eq(fin.reason, "challenged", "motif")
            H.assert_true(find(effects, "table_card") ~= nil, "nouvelle manche ouverte")
            H.assert_eq(state.match.rounds, manches_avant + 1, "une manche de plus")
            H.assert_eq(state.round.turn, accusateur,
                "le vivant qui suit le menteur parti ouvre")

            local annonces = 0
            for _, lot in ipairs({ depart, effects }) do
                for _, e in ipairs(lot) do
                    if e.kind == "eliminated" and e.seat == menteur then
                        annonces = annonces + 1
                    end
                end
            end
            H.assert_eq(annonces, 1, "le menteur n'est annonce elimine qu'une fois")
        end)

        H.it("n'annonce pas une seconde elimination pour un tireur deja mort", function()
            local Engine = build()
            local state = Engine.Start({ "p1", "p2", "p3" }, rng_sans_mort())

            local poseur = state.round.turn
            state = Engine.Apply(state, { kind = "play", seat = poseur, indices = { 1 } })
            state = Engine.Apply(state, { kind = "challenge", seat = state.round.turn })

            -- Etat inatteignable par le jeu normal depuis que la contestation
            -- refuse de designer un mort : on le fabrique pour eprouver le
            -- garde-fou du tir. Le tireur est mort et sa prochaine chambre porte
            -- la balle.
            local tireur = state.pending.seat
            state.match.alive[tireur] = nil
            state.match.dead_order[#state.match.dead_order + 1] = tireur
            local rev = state.match.revolvers[tireur]
            rev.bullet = rev.fired + 1

            local effects
            state, effects = Engine.Apply(state, { kind = "shoot", seat = tireur })
            H.assert_true(find(effects, "shoot").fatal, "le coup part")
            H.assert_nil(find(effects, "eliminated"), "aucune seconde annonce : " .. kinds(effects))
        end)

        H.it("declare la partie terminee quand il ne reste qu'un vivant", function()
            local Engine = build()
            local state = Engine.Start({ "p1", "p2", "p3" }, rng_sans_mort())

            local seats = state.match.seats
            state = Engine.Apply(state, { kind = "leave", seat = seats[1] })
            local effects
            state, effects = Engine.Apply(state, { kind = "leave", seat = seats[2] })

            local fin = find(effects, "match_ended")
            H.assert_true(fin ~= nil, "fin de partie : " .. kinds(effects))
            H.assert_eq(fin.winner, seats[3], "vainqueur par forfait")
            H.assert_true(state.finished, "partie terminee")
        end)

        H.it("refuse tout acte apres la fin de la partie", function()
            local Engine = build()
            local state = Engine.Start({ "p1", "p2", "p3" }, rng_sans_mort())

            local seats = state.match.seats
            state = Engine.Apply(state, { kind = "leave", seat = seats[1] })
            state = Engine.Apply(state, { kind = "leave", seat = seats[2] })

            H.assert_error(function()
                Engine.Apply(state, { kind = "play", seat = seats[3], indices = { 1 } })
            end, "partie terminee")
        end)

        H.it("refuse un acte de nature inconnue", function()
            local Engine = build()
            local state = Engine.Start({ "p1", "p2", "p3" }, rng_sans_mort())

            H.assert_error(function()
                Engine.Apply(state, { kind = "danser", seat = 1 })
            end, "acte inconnu")
        end)
    end)
end
