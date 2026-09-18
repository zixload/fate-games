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
    local Bots           = Package.Require("games/liars_bar/bots.lua")(config)

    local function build()
        local Deck      = make_deck(config)
        local Revolver  = make_revolver(config)
        local Challenge = make_challenge(Deck)
        local RoundM    = make_round(config, Deck)
        local MatchM    = make_match(config, Appearances, Revolver)
        return make_engine(config, Deck, Revolver, Challenge, RoundM, MatchM, make_effects())
    end

    -- Meme generateur que liars_game : reproductible et varie.
    local function rng_graine(graine)
        local etat = graine
        return function(n)
            etat = (1103515245 * etat + 12345) % 2147483648
            return (etat % n) + 1
        end
    end

    -- Rend toujours la meme valeur, plafonnee a n : 1 = le plus petit tirage,
    -- 100 = le plus grand.
    local function rng_fixe(valeur)
        return function(n) return math.min(valeur, n) end
    end

    local function etat(round, pending)
        return { round = round, pending = pending, finished = false }
    end

    H.describe("liars_bar/bots", function()
        H.it("tire quand il est designe", function()
            local act = Bots.Decide(etat({ turn = 3, hands = {} }, { seat = 2 }), 2, rng_fixe(1))
            H.assert_eq(act.kind, "shoot", "acte")
            H.assert_eq(act.seat, 2, "place")
        end)

        H.it("ne fait rien quand un autre doit tirer", function()
            local s = etat({ turn = 3, hands = { [3] = { "king" } } }, { seat = 2 })
            H.assert_nil(Bots.Decide(s, 3, rng_fixe(1)), "acte")
        end)

        H.it("ne joue pas hors de son tour", function()
            local s = etat({ turn = 1, hands = { [2] = { "king" } } })
            H.assert_nil(Bots.Decide(s, 2, rng_fixe(1)), "acte")
        end)

        H.it("n'accuse jamais sans pose precedente", function()
            -- rng_fixe(1) : un tirage d'accusation, s'il avait lieu, dirait oui
            local s = etat({ turn = 1, last = nil, hands = { [1] = { "king", "queen" } } })
            H.assert_eq(Bots.Decide(s, 1, rng_fixe(1)).kind, "play", "acte")
        end)

        H.it("n'accuse pas sa propre pose", function()
            local s = etat({ turn = 1, last = { seat = 1 }, hands = { [1] = { "king" } } })
            H.assert_eq(Bots.Decide(s, 1, rng_fixe(1)).kind, "play", "acte")
        end)

        H.it("accuse quand le tirage tombe sous le seuil", function()
            local s = etat({ turn = 1, last = { seat = 4 }, hands = { [1] = { "king" } } })
            local act = Bots.Decide(s, 1, rng_fixe(1))
            H.assert_eq(act.kind, "challenge", "acte")
            H.assert_eq(act.seat, 1, "place")
        end)

        H.it("pose des indices distincts et valides, trois au plus", function()
            local main = { "king", "queen", "ace", "joker", "king" }
            local s = etat({ turn = 1, last = { seat = 4 }, hands = { [1] = main } })
            local act = Bots.Decide(s, 1, rng_fixe(100))
            H.assert_eq(act.kind, "play", "acte")
            H.assert_eq(#act.indices, 3, "nombre")
            local vus = {}
            for _, i in ipairs(act.indices) do
                H.assert_true(i >= 1 and i <= #main, "indice dans la main")
                H.assert_nil(vus[i], "indice en double")
                vus[i] = true
            end
        end)

        H.it("ne pose jamais plus que sa main", function()
            local s = etat({ turn = 1, hands = { [1] = { "king", "ace" } } })
            H.assert_eq(#Bots.Decide(s, 1, rng_fixe(100)).indices, 2, "nombre")
        end)

        H.it("attend le tireur avant le tour", function()
            H.assert_eq(Bots.Awaited(etat({ turn = 3 }, { seat = 2 })), 2, "tireur")
            H.assert_eq(Bots.Awaited(etat({ turn = 3 })), 3, "tour")
            H.assert_nil(Bots.Awaited(nil), "hors partie")
            H.assert_nil(Bots.Awaited({ finished = true, round = { turn = 1 } }), "partie finie")
        end)

        H.it("quatre bots jouent 50 parties jusqu'au vainqueur", function()
            local Engine = build()
            for partie = 1, 50 do
                local rng = rng_graine(partie)
                local state = Engine.Start({ 1, 2, 3, 4 }, rng)
                local actes = 0
                while not state.finished do
                    local seat = Bots.Awaited(state)
                    H.assert_true(seat ~= nil, ("partie %d : personne n'est attendu"):format(partie))
                    local act = Bots.Decide(state, seat, rng)
                    H.assert_true(act ~= nil, ("partie %d : aucun coup pour la place %d"):format(partie, seat))
                    local ok, nouveau = pcall(Engine.Apply, state, act)
                    H.assert_true(ok, ("partie %d, acte %d (%s) : %s")
                        :format(partie, actes, act.kind, tostring(nouveau)))
                    state = nouveau
                    actes = actes + 1
                    H.assert_true(actes < 2000, ("partie %d sans fin"):format(partie))
                end
            end
        end)
    end)
end
