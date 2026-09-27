return function(H, Stubs)
    local function module()
        local c = Stubs.reset()
        local Log = Package.Require("core/log.lua")({ log = { min_level = "DEBUG" } })
        local DB = Package.Require("db/init.lua")(Log, { db = { connection = "db=test.db", pool_size = 1 } })
        DB.Connect()
        DB.EndStartup()
        return Package.Require("domain/stats.lua")(Log, DB), c
    end

    H.describe("domain/stats (calcul)", function()

        H.it("loup-garou : parties, victoires, taux, survies, roles en pourcentage", function()
            local S = module()
            local st = S.Calculer({ roles = {
                { role = "villager", n = 4, w = 2, s = 1 }, { role = "wolf", n = 3, w = 2, s = 2 },
                { role = "seer", n = 2, w = 1, s = 0 }, { role = "witch", n = 1, w = 0, s = 0 } } })
            local lg = st.loup_garou
            H.assert_eq(lg.parties, 10, "parties")
            H.assert_eq(lg.victoires, 5, "victoires")
            H.assert_eq(lg.taux, 50, "taux")
            H.assert_eq(lg.survies, 3, "survies")
            H.assert_eq(lg.roles[1].nom, "Villageois", "role le plus joue")
            H.assert_eq(lg.roles[1].pourcent, 40, "40 %")
            H.assert_eq(lg.roles[2].nom, "Loup", "puis loup")
            H.assert_count(lg.roles, 4, "quatre roles, pas d'autres")
            H.assert_false(st.vide, "pas vide")
        end)

        H.it("au-dela de quatre roles, le reste devient autres", function()
            local S = module()
            local st = S.Calculer({ roles = {
                { role = "villager", n = 5 }, { role = "wolf", n = 2 }, { role = "seer", n = 1 },
                { role = "witch", n = 1 }, { role = "hunter", n = 1 } } })
            local r = st.loup_garou.roles
            H.assert_count(r, 5, "quatre plus autres")
            H.assert_eq(r[5].nom, "autres", "autres")
            H.assert_eq(r[5].pourcent, 10, "10 %")
        end)

        H.it("valeurs en texte ou nil, role inconnu : pas de plantage", function()
            local S = module()
            local st = S.Calculer({ roles = { { role = "sorcier_rouge", n = "2", w = nil, s = "1" } },
                liars = { n = "3", w = "1", p = "2.3333" }, duel = { n = 0, w = nil }, argent = { total = nil } })
            H.assert_eq(st.loup_garou.parties, 2, "texte lu")
            H.assert_eq(st.loup_garou.victoires, 0, "nil -> 0")
            H.assert_eq(st.loup_garou.roles[1].nom, "sorcier_rouge", "identifiant garde")
            H.assert_eq(st.liars.parties, 3, "liars")
            H.assert_eq(st.liars.taux, 33, "taux arrondi")
            H.assert_eq(st.liars.place, 2.3, "une decimale")
            H.assert_nil(st.duel, "duel sans partie : pas de ligne")
            H.assert_eq(st.argent.total, 0, "argent nil -> 0")
        end)

        H.it("aucune partie : vide", function()
            local S = module()
            local st = S.Calculer({})
            H.assert_true(st.vide, "vide")
            H.assert_nil(st.loup_garou, "pas de loup-garou")
            H.assert_nil(st.liars, "pas de liars")
            H.assert_eq(st.argent.meilleur, 0, "argent a zero")
        end)
    end)
end
