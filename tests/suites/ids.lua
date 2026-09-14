return function(H, Stubs)
    local make_ids = Package.Require("core/ids.lua")
    local make_db  = Package.Require("db/init.lua")
    local make_log = Package.Require("core/log.lua")

    local function build()
        local Log = make_log({ log = { min_level = "DEBUG" } })
        local DB  = make_db(Log, { db = { connection = "db=test.db", pool_size = 1 } })
        DB.Connect()
        return make_ids(Log, DB), DB
    end

    H.describe("core/ids", function()

        H.it("amorce a zero sur une table vide", function()
            local c = Stubs.reset()
            c.answer("MAX(id)", { { max_id = nil } })

            local Ids = build()
            H.assert_true(Ids.Seed({ "accounts" }), "amorcage")
            H.assert_eq(Ids.Current("accounts"), 0, "compteur initial")
            H.assert_eq(Ids.Next("accounts"), 1, "premier identifiant")
        end)

        H.it("reprend apres le plus grand identifiant existant", function()
            local c = Stubs.reset()
            c.answer("MAX(id)", { { max_id = 41 } })

            local Ids = build()
            Ids.Seed({ "characters" })

            H.assert_eq(Ids.Next("characters"), 42, "identifiant suivant")
            H.assert_eq(Ids.Next("characters"), 43, "puis le suivant")
        end)

        H.it("ne rend jamais deux fois le meme identifiant", function()
            local c = Stubs.reset()
            c.answer("MAX(id)", { { max_id = 0 } })

            local Ids = build()
            Ids.Seed({ "ledger" })

            local seen = {}
            for _ = 1, 200 do
                local id = Ids.Next("ledger")
                H.assert_nil(seen[id], "identifiant en double : " .. tostring(id))
                seen[id] = true
            end
        end)

        H.it("amorce chaque table independamment", function()
            local c = Stubs.reset()
            c.answer("FROM accounts",   { { max_id = 10 } })
            c.answer("FROM characters", { { max_id = 99 } })

            local Ids = build()
            Ids.Seed({ "accounts", "characters" })

            H.assert_eq(Ids.Next("accounts"), 11, "compteur des comptes")
            H.assert_eq(Ids.Next("characters"), 100, "compteur des personnages")
        end)

        H.it("refuse une table non amorcee", function()
            local c = Stubs.reset()
            c.answer("MAX(id)", { { max_id = 0 } })

            local Ids = build()
            Ids.Seed({ "accounts" })

            H.assert_error(function() Ids.Next("inconnue") end, "non amorcee")
        end)

        H.it("echoue proprement si la lecture casse", function()
            local c = Stubs.reset()
            c.db.select_error = "base verrouillee"

            local Ids = build()
            H.assert_false(Ids.Seed({ "accounts" }), "amorcage doit echouer")
            H.assert_eq(c.count_lines("amorcage impossible"), 1, "echec journalise")
        end)

        H.it("interdit une lecture bloquante apres le demarrage", function()
            local c = Stubs.reset()
            c.answer("MAX(id)", { { max_id = 0 } })

            local Ids, DB = build()
            Ids.Seed({ "accounts" })
            DB.EndStartup()

            H.assert_error(function() Ids.Seed({ "accounts" }) end, "apres le demarrage")
        end)
    end)
end
