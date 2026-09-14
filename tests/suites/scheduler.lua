return function(H, Stubs)
    local make_scheduler = Package.Require("core/scheduler.lua")
    local make_log       = Package.Require("core/log.lua")

    -- Roue de `slots` tours, un tick par seconde : un tour complet = slots * 1000 ms.
    local function new(slots)
        local Log = make_log({ log = { min_level = "DEBUG" } })
        return make_scheduler(Log, {
            scheduler = { wheel_seconds = slots, tick_ms = 1000 },
        })
    end

    H.describe("core/scheduler", function()

        H.it("traite chaque entite exactement une fois par tour de roue", function()
            local c = Stubs.reset()
            local S = new(5)

            local calls = {}
            for i = 1, 10 do
                S.Add("e" .. i, function(key) calls[key] = (calls[key] or 0) + 1 end)
            end
            S.Start()

            c.advance(5 * 1000)

            for i = 1, 10 do
                H.assert_eq(calls["e" .. i], 1, "appels pour e" .. i)
            end
        end)

        H.it("etale la charge au lieu de tout traiter au meme tick", function()
            local c = Stubs.reset()
            local S = new(4)

            local per_tick = {}
            local fired    = 0
            for i = 1, 8 do
                S.Add("e" .. i, function() fired = fired + 1 end)
            end
            S.Start()

            for tick = 1, 4 do
                fired = 0
                c.advance(1000)
                per_tick[tick] = fired
            end

            -- 8 entites sur 4 slots : deux par tick, jamais huit d'un coup.
            for tick = 1, 4 do
                H.assert_eq(per_tick[tick], 2, "entites traitees au tick " .. tick)
            end
        end)

        H.it("n'appelle plus une entite retiree", function()
            local c = Stubs.reset()
            local S = new(3)

            local calls = 0
            S.Add("e1", function() calls = calls + 1 end)
            S.Start()

            S.Remove("e1")
            c.advance(3 * 1000)

            H.assert_eq(calls, 0, "appels apres retrait")
        end)

        H.it("ne duplique pas une cle inscrite deux fois", function()
            local c = Stubs.reset()
            local S = new(3)

            local calls = 0
            S.Add("e1", function() calls = calls + 1 end)
            S.Add("e1", function() calls = calls + 1 end)
            S.Start()

            c.advance(3 * 1000)

            H.assert_eq(calls, 1, "appels sur un tour complet")
        end)

        H.it("isole un callback qui plante et journalise l'erreur", function()
            local c = Stubs.reset()
            local S = new(1)   -- un seul slot : tout tombe sur le meme tick

            local survivor = 0
            S.Add("casse", function() error("boum") end)
            S.Add("sain",  function() survivor = survivor + 1 end)
            S.Start()

            c.advance(1000)

            H.assert_eq(survivor, 1, "le callback sain a bien tourne")
            H.assert_eq(c.count_lines("callback en echec pour casse"), 1, "erreur journalisee")
        end)

        H.it("permet de retirer une entite depuis son propre callback", function()
            local c = Stubs.reset()
            local S = new(1)

            local calls = 0
            S.Add("e1", function(key)
                calls = calls + 1
                S.Remove(key)
            end)
            S.Start()

            c.advance(3 * 1000)

            H.assert_eq(calls, 1, "appels apres auto-retrait")
        end)

        H.it("arrete la roue sur Stop", function()
            local c = Stubs.reset()
            local S = new(2)

            local calls = 0
            S.Add("e1", function() calls = calls + 1 end)
            S.Start()
            S.Stop()

            c.advance(10 * 1000)

            H.assert_eq(calls, 0, "appels apres arret")
        end)

        H.it("ignore un second Start", function()
            local c = Stubs.reset()
            local S = new(1)

            local calls = 0
            S.Add("e1", function() calls = calls + 1 end)
            S.Start()
            S.Start()

            c.advance(1000)

            H.assert_eq(calls, 1, "un seul intervalle actif")
        end)
    end)
end
