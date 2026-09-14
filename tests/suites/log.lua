return function(H, Stubs)
    local make_log = Package.Require("core/log.lua")

    local function new(min_level)
        return make_log({ log = { min_level = min_level or "DEBUG" } })
    end

    H.describe("core/log", function()

        H.it("filtre les messages sous le niveau minimal", function()
            local c   = Stubs.reset()
            local Log = new("WARN")

            Log.Debug("test", "invisible")
            Log.Info("test", "invisible aussi")
            Log.Warn("test", "visible")
            Log.Error("test", "visible aussi")

            H.assert_eq(#c.console.lines, 2, "lignes emises")
        end)

        H.it("route les niveaux vers la bonne sortie console", function()
            local c   = Stubs.reset()
            local Log = new("DEBUG")

            Log.Info("test", "un")
            Log.Warn("test", "deux")
            Log.Error("test", "trois")

            H.assert_eq(c.count_lines("LOG  "), 1, "lignes Console.Log")
            H.assert_eq(c.count_lines("WARN "), 1, "lignes Console.Warn")
            H.assert_eq(c.count_lines("ERROR"), 1, "lignes Console.Error")
        end)

        H.it("produit des identifiants de correlation distincts", function()
            Stubs.reset()
            local Log = new()

            local seen = {}
            for _ = 1, 50 do
                local id = Log.NewCorrelationId()
                H.assert_nil(seen[id], "identifiant deja vu : " .. tostring(id))
                seen[id] = true
            end
        end)

        H.it("accroche l'identifiant de correlation a la ligne", function()
            local c   = Stubs.reset()
            local Log = new()

            Log.Info("test", "message", "cid-42")

            H.assert_eq(c.count_lines("(cid=cid-42)"), 1, "ligne portant le cid")
        end)

        H.it("ecrit une ligne d'audit exploitable", function()
            local c   = Stubs.reset()
            local Log = new()

            Log.Audit({
                actor          = 7,
                target         = "objet-23",
                action         = "achat",
                position       = "0,0,0",
                payload        = "prix=50",
                correlation_id = "cid-7",
            })

            H.assert_eq(c.count_lines("[audit]"), 1, "ligne d'audit")
            H.assert_eq(c.count_lines("action=achat"), 1, "action journalisee")
            H.assert_eq(c.count_lines("actor=7"), 1, "acteur journalise")
            H.assert_eq(c.count_lines("(cid=cid-7)"), 1, "correlation journalisee")
        end)
    end)
end
