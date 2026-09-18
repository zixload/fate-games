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

    -- Generateur congruentiel minimal : reproductible, et suffisamment varie
    -- pour ne pas biaiser une partie entiere vers un seul scenario.
    local function rng_graine(graine)
        local etat = graine
        return function(n)
            etat = (1103515245 * etat + 12345) % 2147483648
            return (etat % n) + 1
        end
    end

    -- Meme contenu, meme ordre. L'audience seule ne prouve rien : Effects.Deal
    -- la remplit par construction. Il faut comparer les cartes elles-memes a
    -- la main de la place, sinon une main distribuee au voisin passerait.
    local function memes_cartes(a, b)
        if #a ~= #b then return false end
        for i = 1, #a do
            if a[i] ~= b[i] then return false end
        end
        return true
    end

    -- A appeler juste apres Engine.Start ou Engine.Apply : toute distribution
    -- du lot ouvre la manche courante, donc chaque main est encore intacte.
    local function verifier_distributions(H, state, effects, contexte)
        local n = 0
        for _, e in ipairs(effects) do
            if e.kind == "deal" then
                n = n + 1
                H.assert_eq(e.audience, e.seat,
                    "une distribution doit etre adressee a son proprietaire, " .. contexte)
                local main = state.round.hands[e.seat]
                H.assert_true(main ~= nil and memes_cartes(e.cards, main),
                    ("place %d recoit {%s} au lieu de sa main {%s}, %s"):format(
                        e.seat, table.concat(e.cards, ","),
                        table.concat(main or {}, ","), contexte))
            end
        end
        return n
    end

    -- Controle independant de ceux du moteur : il ne s'appuie ni sur
    -- AssertNoLeak ni sur Validate, qui pourraient s'affaiblir ensemble. Un
    -- effet public ne porte que des valeurs simples, sauf la revelation, dont
    -- c'est le but, et la fin de partie, dont le resume ne contient que le
    -- nombre de manches et la liste des morts.
    local function controler_publics(H, effects, contexte)
        for _, e in ipairs(effects) do
            if e.audience == "all" and e.kind ~= "reveal" then
                for champ, valeur in pairs(e) do
                    if e.kind == "match_ended" and champ == "summary" then
                        for cle in pairs(valeur) do
                            H.assert_true(cle == "rounds" or cle == "dead",
                                ("resume de fin de partie : cle %s, %s"):format(
                                    tostring(cle), contexte))
                        end
                    else
                        H.assert_true(type(valeur) ~= "table",
                            ("effet public %s : le champ %s est une table, %s"):format(
                                tostring(e.kind), tostring(champ), contexte))
                    end
                end
            end
        end
    end

    -- Joue une partie entiere en pilote automatique : le joueur actif pose
    -- toujours une carte, sauf s'il ne peut que contester.
    local function jouer_partie(Engine, Effects, graine, H)
        local state, effects = Engine.Start({ "p1", "p2", "p3", "p4" }, rng_graine(graine))
        Effects.AssertNoLeak(effects)
        controler_publics(H, effects, "graine " .. graine .. ", demarrage")
        verifier_distributions(H, state, effects, "graine " .. graine .. ", demarrage")

        local tours = 0
        while not state.finished do
            tours = tours + 1
            H.assert_true(tours < 2000, "la partie doit se terminer, graine " .. graine)

            local act
            if state.pending then
                act = { kind = "shoot", seat = state.pending.seat }
            else
                local seat = state.round.turn
                local main = state.round.hands[seat] or {}
                if #main > 0 and state.round.last and state.round.last.seat ~= seat and (tours % 3 == 0) then
                    act = { kind = "challenge", seat = seat }
                elseif #main > 0 then
                    local n = math.min(#main, 1 + (tours % config.max_play))
                    local indices = {}
                    for i = 1, n do indices[i] = i end
                    act = { kind = "play", seat = seat, indices = indices }
                else
                    act = { kind = "challenge", seat = seat }
                end
            end

            local out
            state, out = Engine.Apply(state, act)
            Effects.AssertNoLeak(out)
            controler_publics(H, out, "graine " .. graine .. ", tour " .. tours)
            verifier_distributions(H, state, out, "graine " .. graine .. ", tour " .. tours)
        end

        return state
    end

    local function find(effects, kind)
        for _, e in ipairs(effects) do
            if e.kind == kind then return e end
        end
        return nil
    end

    H.describe("liars_bar/partie complete", function()

        H.it("atteint un vainqueur sur dix graines differentes", function()
            local Engine, Effects = build()
            for graine = 1, 10 do
                local state = jouer_partie(Engine, Effects, graine, H)

                H.assert_true(state.finished, "partie terminee, graine " .. graine)
                local vivants = 0
                for _ in pairs(state.match.alive) do vivants = vivants + 1 end
                H.assert_eq(vivants, 1, "un seul survivant, graine " .. graine)
                H.assert_true(state.match.rounds >= 1, "au moins une manche, graine " .. graine)
            end
        end)

        H.it("ne laisse jamais fuiter une carte sur une partie entiere", function()
            local Engine, Effects = build()
            -- jouer_partie controle chaque lot d'effets par lui-meme, sans se fier
            -- a AssertNoLeak : une fuite ferait echouer ce test avec son contexte.
            local state = jouer_partie(Engine, Effects, 42, H)
            H.assert_true(state.finished, "partie terminee")
        end)

        H.it("n'envoie la main d'un joueur qu'a lui seul, sur une partie entiere", function()
            local Engine, Effects = build()
            local state, effects = Engine.Start({ "p1", "p2", "p3", "p4" }, rng_graine(7))

            local verifies, tours = 0, 0
            while not state.finished do
                tours = tours + 1
                H.assert_true(tours < 2000, "la partie doit se terminer")

                Effects.AssertNoLeak(effects)
                verifies = verifies + verifier_distributions(H, state, effects, "tour " .. tours)

                local act
                if state.pending then
                    act = { kind = "shoot", seat = state.pending.seat }
                else
                    local seat = state.round.turn
                    local main = state.round.hands[seat] or {}

                    -- Meme clause periodique que jouer_partie. Sans elle ce pilote
                    -- ne contesterait jamais, puisque NextTurn ne rend que des places
                    -- qui ont des cartes : la partie ne finirait pas, et aucune
                    -- distribution ne serait verifiee apres un tir ou une elimination.
                    if #main == 0 then
                        act = { kind = "challenge", seat = seat }
                    elseif state.round.last and state.round.last.seat ~= seat and (tours % 3 == 0) then
                        act = { kind = "challenge", seat = seat }
                    else
                        act = { kind = "play", seat = seat, indices = { 1 } }
                    end
                end

                state, effects = Engine.Apply(state, act)
            end

            H.assert_true(state.finished, "la partie doit se terminer")
            H.assert_true(verifies > 0, "au moins une distribution verifiee")
        end)

        H.it("scenario : le menteur demasque tire", function()
            local Engine = build()
            local state = Engine.Start({ "p1", "p2", "p3" }, function(n) return n end)

            local poseur = state.round.turn
            -- On impose une main qui mentira a coup sur.
            local intruse = state.round.rank == "king" and "ace" or "king"
            state.round.hands[poseur] = { intruse, intruse, intruse, intruse, intruse }

            state = Engine.Apply(state, { kind = "play", seat = poseur, indices = { 1 } })
            local accusateur = state.round.turn
            state = Engine.Apply(state, { kind = "challenge", seat = accusateur })

            H.assert_eq(state.pending.seat, poseur, "le menteur doit tirer")
        end)

        H.it("scenario : l'accusateur qui se trompe tire", function()
            local Engine = build()
            local state = Engine.Start({ "p1", "p2", "p3" }, function(n) return n end)

            local poseur = state.round.turn
            state.round.hands[poseur] = { "joker", "joker", "joker", "joker", "joker" }

            state = Engine.Apply(state, { kind = "play", seat = poseur, indices = { 1 } })
            local accusateur = state.round.turn
            state = Engine.Apply(state, { kind = "challenge", seat = accusateur })

            H.assert_eq(state.pending.seat, accusateur, "l'accusateur doit tirer")
        end)

        H.it("scenario : manche nulle par epuisement, sans aucun tir", function()
            local Engine = build()
            local state = Engine.Start({ "p1", "p2", "p3" }, function(n) return n end)

            local manches_avant = state.match.rounds
            local seats = state.match.seats
            state.round.hands[seats[1]] = {}
            state.round.hands[seats[2]] = {}
            state.round.turn = seats[3]

            local effects
            state, effects = Engine.Apply(state,
                { kind = "play", seat = seats[3], indices = { 1 } })

            H.assert_eq(find(effects, "round_ended").reason, "exhausted", "motif")
            H.assert_nil(find(effects, "shoot"), "aucun tir")
            H.assert_eq(state.match.rounds, manches_avant + 1, "une manche de plus")
        end)

        H.it("scenario : un depart en cours de partie ne bloque rien", function()
            local Engine, Effects = build()
            local state = Engine.Start({ "p1", "p2", "p3", "p4" }, rng_graine(3))

            state = Engine.Apply(state, { kind = "leave", seat = state.match.seats[2] })
            H.assert_false(state.finished, "la partie continue a trois")

            -- Comme dans jouer_partie : une contestation de temps en temps, sinon
            -- personne ne conteste jamais (le tour ne tombe que sur une place qui a
            -- des cartes) et la manche se contente de se redistribuer a l'infini par
            -- epuisement, sans qu'aucun tir ne puisse jamais reduire le nombre de
            -- vivants. Verifie par simulation : sans cette clause, la partie atteint
            -- le plafond de tours sans jamais se terminer, meme sur un moteur correct.
            local tours = 0
            while not state.finished and tours < 2000 do
                tours = tours + 1
                local act
                if state.pending then
                    act = { kind = "shoot", seat = state.pending.seat }
                else
                    local seat = state.round.turn
                    local main = state.round.hands[seat] or {}
                    if #main > 0 and state.round.last and state.round.last.seat ~= seat and (tours % 3 == 0) then
                        act = { kind = "challenge", seat = seat }
                    elseif #main > 0 then
                        act = { kind = "play", seat = seat, indices = { 1 } }
                    else
                        act = { kind = "challenge", seat = seat }
                    end
                end
                local out
                state, out = Engine.Apply(state, act)
                Effects.AssertNoLeak(out)
            end

            H.assert_true(state.finished, "la partie se termine malgre le depart")
        end)
    end)
end
