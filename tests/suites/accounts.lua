return function(H, Stubs)
    local make_accounts = Package.Require("domain/accounts.lua")
    local make_ids      = Package.Require("core/ids.lua")
    local make_db       = Package.Require("db/init.lua")
    local make_log      = Package.Require("core/log.lua")

    -- Monte la chaine complete avec les compteurs amorces a zero.
    local function build(c, bootstrap)
        c.answer("MAX(id)", { { max_id = 0 } })

        local Log = make_log({ log = { min_level = "DEBUG" } })
        local DB  = make_db(Log, { db = { connection = "db=test.db", pool_size = 1 } })
        DB.Connect()

        local Ids = make_ids(Log, DB)
        Ids.Seed({ "accounts" })
        DB.EndStartup()

        return make_accounts(Log, DB, Ids, {
            whitelist = { bootstrap = bootstrap or {} },
        }), Ids
    end

    H.describe("domain/accounts", function()

        H.it("retourne un compte existant", function()
            local c = Stubs.reset()
            local Accounts = build(c)

            c.answer("FROM accounts WHERE steam_id", {
                { id = 7, steam_id = "steam:abc", whitelisted = 1, created_at = "2026-01-01T00:00:00Z" },
            })

            local got
            Accounts.Resolve("steam:abc", function(account) got = account end)

            H.assert_true(got ~= nil, "compte retourne")
            H.assert_eq(got.id, 7, "identifiant")
            H.assert_true(got.whitelisted, "whitelist lue comme booleen")
            H.assert_eq(#c.db.executed, 0, "aucune ecriture pour un compte existant")
        end)

        H.it("cree un compte inconnu, hors whitelist par defaut", function()
            local c = Stubs.reset()
            local Accounts = build(c)

            c.answer("FROM accounts WHERE steam_id", {})

            local got
            Accounts.Resolve("steam:nouveau", function(account) got = account end)

            H.assert_true(got ~= nil, "compte retourne")
            H.assert_eq(got.id, 1, "identifiant attribue par Ids")
            H.assert_false(got.whitelisted, "pas whitelist a la creation")

            H.assert_eq(#c.db.executed, 1, "une insertion")
            H.assert_true(c.db.executed[1].query:find("INSERT INTO accounts", 1, true) ~= nil,
                "insertion dans accounts")
            H.assert_eq(c.db.executed[1].params[3], 0, "whitelisted a zero")
        end)

        H.it("ne relit pas la base pour un compte deja resolu", function()
            local c = Stubs.reset()
            local Accounts = build(c)

            c.answer("FROM accounts WHERE steam_id", {
                { id = 3, steam_id = "steam:cache", whitelisted = 0, created_at = "x" },
            })

            Accounts.Resolve("steam:cache", function() end)
            local reads_after_first = #c.db.selected

            Accounts.Resolve("steam:cache", function() end)

            H.assert_eq(#c.db.selected, reads_after_first, "aucune lecture supplementaire")
        end)

        H.it("refuse un steam id vide ou absent", function()
            local c = Stubs.reset()
            local Accounts = build(c)

            -- L'amorcage des identifiants a deja lu la base : on part de ce niveau.
            local reads_before = #c.db.selected

            local err_nil, err_empty
            Accounts.Resolve(nil, function(_, e) err_nil = e end)
            Accounts.Resolve("",  function(_, e) err_empty = e end)

            H.assert_eq(err_nil, "steam_id_invalide", "steam id absent")
            H.assert_eq(err_empty, "steam_id_invalide", "steam id vide")
            H.assert_eq(#c.db.selected, reads_before, "aucune requete lancee")
        end)

        H.it("remonte une erreur de lecture sans creer de compte", function()
            local c = Stubs.reset()
            local Accounts = build(c)
            c.db.select_error = "base verrouillee"

            local got, err
            Accounts.Resolve("steam:erreur", function(a, e) got, err = a, e end)

            H.assert_nil(got, "aucun compte")
            H.assert_eq(err, "db_select", "erreur remontee")
            H.assert_eq(#c.db.executed, 0, "aucune ecriture")
        end)

        H.it("journalise une decision de whitelist", function()
            local c = Stubs.reset()
            local Accounts = build(c)

            local account = { id = 12, steam_id = "steam:xyz", whitelisted = false }
            local ok
            Accounts.SetWhitelisted(account, true, "cid-1", function(r) ok = r end)

            H.assert_true(ok, "mise a jour reussie")
            H.assert_true(account.whitelisted, "etat en memoire mis a jour")
            H.assert_eq(c.count_lines("action=whitelist_accordee"), 1, "ligne d'audit")
            H.assert_eq(c.count_lines("(cid=cid-1)"), 1, "correlation journalisee")
        end)

        H.it("whiteliste d'office un compte du bootstrap a sa creation", function()
            local c = Stubs.reset()
            local Accounts = build(c, { "steam:fondateur" })

            c.answer("FROM accounts WHERE steam_id", {})

            local got
            Accounts.Resolve("steam:fondateur", function(account) got = account end)

            H.assert_true(got.whitelisted, "compte whiteliste des la creation")
            H.assert_eq(c.db.executed[1].params[3], 1, "whitelisted a un en base")
        end)

        H.it("rattrape un compte deja cree ajoute au bootstrap ensuite", function()
            local c = Stubs.reset()
            local Accounts = build(c, { "steam:fondateur" })

            c.answer("FROM accounts WHERE steam_id", {
                { id = 4, steam_id = "steam:fondateur", whitelisted = 0, created_at = "x" },
            })

            local got
            Accounts.Resolve("steam:fondateur", function(account) got = account end)

            H.assert_true(got ~= nil, "compte retourne")
            H.assert_true(got.whitelisted, "compte promu")
            H.assert_eq(c.count_lines("promu par le bootstrap"), 1, "promotion journalisee")
            H.assert_eq(c.count_lines("action=whitelist_accordee"), 1, "promotion auditee")
        end)

        H.it("laisse hors whitelist un compte absent du bootstrap", function()
            local c = Stubs.reset()
            local Accounts = build(c, { "steam:fondateur" })

            c.answer("FROM accounts WHERE steam_id", {})

            local got
            Accounts.Resolve("steam:quidam", function(account) got = account end)

            H.assert_false(got.whitelisted, "compte ordinaire hors whitelist")
        end)

        H.it("IsWhitelisted ne se laisse pas avoir par nil", function()
            Stubs.reset()
            local Accounts = build(Stubs.current)

            H.assert_false(Accounts.IsWhitelisted(nil), "compte absent")
            H.assert_false(Accounts.IsWhitelisted({ whitelisted = false }), "compte non whitelist")
            H.assert_true(Accounts.IsWhitelisted({ whitelisted = true }), "compte whitelist")
        end)
    end)
end
