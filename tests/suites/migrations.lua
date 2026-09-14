return function(H, Stubs)
    local migrations = Package.Require("db/migrations.lua")
    local make_db    = Package.Require("db/init.lua")
    local make_log   = Package.Require("core/log.lua")

    local function new()
        local Log = make_log({ log = { min_level = "DEBUG" } })
        return make_db(Log, {
            db = { connection = "db=test.db timeout=2", pool_size = 3 },
        })
    end

    -- 1 creation de schema_migrations + les instructions de la migration + 1 insertion
    local function expected_statements()
        local n = 1
        for _, m in ipairs(migrations) do
            n = n + #m.statements + 1
        end
        return n
    end

    H.describe("db/migrations", function()

        H.it("declare des identifiants uniques et croissants depuis 1", function()
            local seen = {}
            for index, m in ipairs(migrations) do
                H.assert_eq(m.id, index, "identifiant de la migration en position " .. index)
                H.assert_nil(seen[m.id], "identifiant en double : " .. tostring(m.id))
                seen[m.id] = true
            end
        end)

        H.it("declare un nom et au moins une instruction par migration", function()
            for _, m in ipairs(migrations) do
                H.assert_true(type(m.name) == "string" and #m.name > 0,
                    "nom de la migration " .. tostring(m.id))
                H.assert_true(#m.statements > 0,
                    "instructions de la migration " .. tostring(m.id))
            end
        end)
    end)

    H.describe("db/init", function()

        H.it("construit la connexion avec le moteur et le pool attendus", function()
            local c  = Stubs.reset()
            local DB = new()

            DB.Connect()

            H.assert_eq(c.db.constructed.engine, "sqlite", "moteur")
            H.assert_eq(c.db.constructed.connection, "db=test.db timeout=2", "chaine de connexion")
            H.assert_eq(c.db.constructed.pool_size, 3, "taille du pool")
        end)

        H.it("applique toutes les migrations sur une base vierge", function()
            local c  = Stubs.reset()
            local DB = new()

            c.db.select_rows = {}
            DB.Connect()

            H.assert_true(DB.Migrate(), "Migrate doit reussir")
            H.assert_eq(#c.db.executed, expected_statements(), "instructions executees")
        end)

        H.it("ne rejoue pas une migration deja appliquee", function()
            local c  = Stubs.reset()
            local DB = new()

            -- Base a jour : toutes les migrations declarees sont deja enregistrees.
            local applied = {}
            for _, m in ipairs(migrations) do
                applied[#applied + 1] = { id = m.id }
            end
            c.db.select_rows = applied
            DB.Connect()

            H.assert_true(DB.Migrate(), "Migrate doit reussir")
            -- seule la creation de schema_migrations a tourne
            H.assert_eq(#c.db.executed, 1, "instructions executees")
        end)

        H.it("echoue proprement si une instruction casse", function()
            local c  = Stubs.reset()
            local DB = new()

            c.db.select_rows = {}
            c.db.execute_error_on = "accounts"
            DB.Connect()

            H.assert_false(DB.Migrate(), "Migrate doit echouer")
            H.assert_eq(c.count_lines("migration 1"), 1, "echec journalise")
        end)

        H.it("echoue proprement si la lecture de schema_migrations casse", function()
            local c  = Stubs.reset()
            local DB = new()

            c.db.select_error = "base verrouillee"
            DB.Connect()

            H.assert_false(DB.Migrate(), "Migrate doit echouer")
        end)

        H.it("passe les parametres en arguments plutot qu'en concatenation", function()
            local c  = Stubs.reset()
            local DB = new()

            c.db.select_rows = {}
            DB.Connect()
            DB.Migrate()

            -- La premiere insertion enregistree correspond a la premiere migration.
            local insert = nil
            for _, call in ipairs(c.db.executed) do
                if not insert and call.query:find("INSERT INTO schema_migrations", 1, true) then
                    insert = call
                end
            end

            H.assert_true(insert ~= nil, "insertion dans schema_migrations trouvee")
            H.assert_eq(#insert.params, 3, "parametres passes a part")
            H.assert_eq(insert.params[1], migrations[1].id, "identifiant de migration")
        end)

        H.it("ferme la connexion sur Close", function()
            local c  = Stubs.reset()
            local DB = new()

            DB.Connect()
            DB.Close()

            H.assert_true(c.db.closed, "connexion fermee")
        end)
    end)
end
