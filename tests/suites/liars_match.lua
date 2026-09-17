return function(H, Stubs)
    local config        = Package.Require("games/liars_bar/data/config.lua")
    local make_revolver = Package.Require("games/liars_bar/revolver.lua")
    local Appearances   = Package.Require("Shared/appearances.lua")
    local make_match    = Package.Require("games/liars_bar/match.lua")

    local function build()
        return make_match(config, Appearances, make_revolver(config))
    end

    local function rng_fixe(_) return 1 end

    local function rng_croissant()
        local i = 0
        return function(n)
            i = i + 1
            return ((i - 1) % n) + 1
        end
    end

    H.describe("liars_bar/match", function()

        H.it("attribue une place, un revolver et une apparence a chacun", function()
            local M = build()
            local match = M.New({ "p1", "p2", "p3", "p4" }, rng_fixe)

            H.assert_eq(#match.seats, 4, "places occupees")
            for _, seat in ipairs(match.seats) do
                H.assert_true(match.players[seat] ~= nil, "joueur a la place " .. seat)
                H.assert_true(match.revolvers[seat] ~= nil, "revolver a la place " .. seat)
                H.assert_true(match.looks[seat] ~= nil, "apparence a la place " .. seat)
                H.assert_true(match.alive[seat], "vivant a la place " .. seat)
            end
        end)

        H.it("attribue des apparences TOUTES distinctes", function()
            local M = build()
            local match = M.New({ "p1", "p2", "p3", "p4", "p5", "p6" }, rng_croissant())

            local vues = {}
            for _, seat in ipairs(match.seats) do
                local id = match.looks[seat]
                H.assert_nil(vues[id], "apparence en double : " .. tostring(id))
                vues[id] = true
            end
        end)

        H.it("attribue des apparences distinctes meme si le hasard insiste", function()
            local M = build()
            -- Un rng qui rend toujours 1 : sans tirage sans remise, les six
            -- joueurs recevraient la meme apparence.
            local match = M.New({ "p1", "p2", "p3", "p4", "p5", "p6" }, rng_fixe)

            local vues = {}
            for _, seat in ipairs(match.seats) do
                local id = match.looks[seat]
                H.assert_nil(vues[id], "apparence en double : " .. tostring(id))
                vues[id] = true
            end
        end)

        H.it("n'attribue que des apparences du catalogue", function()
            local M = build()
            local match = M.New({ "p1", "p2", "p3" }, rng_croissant())

            for _, seat in ipairs(match.seats) do
                H.assert_true(Appearances.Resolve(match.looks[seat]) ~= nil,
                    "apparence inconnue : " .. tostring(match.looks[seat]))
            end
        end)

        H.it("refuse une partie sous le minimum de joueurs", function()
            local M = build()
            H.assert_error(function() M.New({ "p1", "p2" }, rng_fixe) end, "trois joueurs")
        end)

        H.it("refuse plus de joueurs qu'il y a de places", function()
            local M = build()
            H.assert_error(function()
                M.New({ "p1", "p2", "p3", "p4", "p5", "p6", "p7" }, rng_fixe)
            end, "places")
        end)

        H.it("retire un joueur elimine des vivants", function()
            local M = build()
            local match = M.New({ "p1", "p2", "p3" }, rng_croissant())

            M.Eliminate(match, 2)

            H.assert_nil(match.alive[2], "la place 2 n'est plus vivante")
            local vivants = M.AliveSeats(match)
            H.assert_eq(#vivants, 2, "vivants restants")
            H.assert_eq(vivants[1], 1, "premier vivant")
            H.assert_eq(vivants[2], 3, "second vivant")
        end)

        H.it("ne declare aucun vainqueur tant qu'il en reste deux", function()
            local M = build()
            local match = M.New({ "p1", "p2", "p3" }, rng_croissant())

            M.Eliminate(match, 1)
            H.assert_nil(M.Winner(match), "deux vivants, pas de vainqueur")
        end)

        H.it("declare vainqueur le dernier debout", function()
            local M = build()
            local match = M.New({ "p1", "p2", "p3" }, rng_croissant())

            M.Eliminate(match, 1)
            M.Eliminate(match, 3)

            H.assert_eq(M.Winner(match), 2, "dernier debout")
        end)

        H.it("rend la place vivante suivante, en bouclant", function()
            local M = build()
            local match = M.New({ "p1", "p2", "p3", "p4" }, rng_croissant())

            H.assert_eq(M.NextAlive(match, 1), 2, "suivant de 1")
            H.assert_eq(M.NextAlive(match, 4), 1, "on boucle apres la derniere place")

            M.Eliminate(match, 2)
            H.assert_eq(M.NextAlive(match, 1), 3, "on saute un elimine")
        end)

        H.it("enregistre l'ordre des morts", function()
            local M = build()
            local match = M.New({ "p1", "p2", "p3", "p4" }, rng_croissant())

            M.Eliminate(match, 3)
            M.Eliminate(match, 1)

            -- La tache 9 lit ce champ a l'envers pour classer : le dernier tombe
            -- est deuxieme, l'avant-dernier troisieme. L'ordre est donc porteur.
            H.assert_eq(#match.dead_order, 2, "nombre de morts")
            H.assert_eq(match.dead_order[1], 3, "premier tombe")
            H.assert_eq(match.dead_order[2], 1, "second tombe")
        end)

        H.it("n'enregistre pas deux fois la meme mort", function()
            local M = build()
            local match = M.New({ "p1", "p2", "p3" }, rng_croissant())

            M.Eliminate(match, 2)
            M.Eliminate(match, 2)

            H.assert_eq(#match.dead_order, 1, "une seule entree")
            H.assert_eq(match.dead_order[1], 2, "la bonne place")
        end)
    end)
end
