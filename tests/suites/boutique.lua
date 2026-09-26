return function(H, Stubs)
    local make_boutique = Package.Require("domain/boutique.lua")
    local make_ids      = Package.Require("core/ids.lua")
    local make_db       = Package.Require("db/init.lua")
    local make_log      = Package.Require("core/log.lua")
    local Catalogue     = Package.Require("Shared/catalogue.lua")

    local ACCOUNT = { id = 7 }

    local function build(c, cfg)
        c.answer("MAX(id)", { { max_id = 0 } })
        local Log = make_log({ log = { min_level = "DEBUG" } })
        local DB  = make_db(Log, { db = { connection = "db=test.db", pool_size = 1 } })
        DB.Connect()
        local Ids = make_ids(Log, DB)
        Ids.Seed({ "ledger" })
        DB.EndStartup()
        return make_boutique(Log, DB, Ids, Catalogue, {
            boutique = cfg or { bonus_accueil = 0, perso_defaut = "clown" },
        })
    end

    -- Charge un compte dont le journal donne credits - debits, accueil deja verse.
    local function charger(c, Boutique, credits, debits, possessions, equipement)
        c.answer("FROM ledger", { { credits = credits, debits = debits or 0, accueil = 1 } })
        c.answer("FROM possessions", possessions or {})
        c.answer("FROM equipement", equipement or {})
        local etat
        Boutique.Charger(ACCOUNT, function(e) etat = e end)
        return etat
    end

    local function ecrits(c, motif)
        local n = 0
        for _, e in ipairs(c.db.executed) do
            if e.query:find(motif, 1, true) then n = n + 1 end
        end
        return n
    end

    H.describe("domain/boutique", function()

        H.it("deduit le solde du journal et equipe le defaut", function()
            local c = Stubs.reset()
            local Boutique = build(c)
            local etat = charger(c, Boutique, 900, 250)

            H.assert_eq(etat.solde, 650, "credits moins debits")
            H.assert_eq(etat.perso, "clown", "perso par defaut")
            H.assert_eq(etat.arme, Catalogue.arme_de_base, "arme de base")
            H.assert_true(Boutique.Possede(etat, "persos", "clown"), "gratuit possede d'office")
            H.assert_false(Boutique.Possede(etat, "persos", "gantier"), "payant non possede")
        end)

        H.it("verse le bonus d'accueil une seule fois", function()
            local c = Stubs.reset()
            local Boutique = build(c, { bonus_accueil = 500, perso_defaut = "clown" })
            c.answer("FROM ledger", { { credits = 0, debits = 0, accueil = 0 } })
            local etat
            Boutique.Charger(ACCOUNT, function(e) etat = e end)

            H.assert_eq(etat.solde, 500, "bonus credite")
            H.assert_eq(ecrits(c, "INSERT INTO ledger"), 1, "un mouvement")
            local p = c.db.executed[#c.db.executed].params
            H.assert_eq(p[2], "banque", "debit de la banque")
            H.assert_eq(p[3], "compte:7", "credit du joueur")
            H.assert_eq(p[5], "bienvenue", "raison")
        end)

        H.it("achete : debite, livre, et le solde suit", function()
            local c = Stubs.reset()
            local Boutique = build(c)
            local etat = charger(c, Boutique, 1000)

            local ok
            Boutique.Acheter(ACCOUNT, "persos", "nourrisson", nil, function(r) ok = r end)

            H.assert_true(ok, "achat accepte")
            H.assert_eq(etat.solde, 1000 - Catalogue.article("persos", "nourrisson").prix, "solde debite")
            H.assert_true(Boutique.Possede(etat, "persos", "nourrisson"), "possede apres achat")
            H.assert_eq(ecrits(c, "INSERT INTO possessions"), 1, "livraison ecrite")
        end)

        H.it("refuse un achat sans assez d'argent, sans rien ecrire", function()
            local c = Stubs.reset()
            local Boutique = build(c)
            charger(c, Boutique, 100)

            local ok, raison
            Boutique.Acheter(ACCOUNT, "armes", "glace", nil, function(r, why) ok, raison = r, why end)

            H.assert_false(ok, "refuse")
            H.assert_eq(raison, "solde", "raison")
            H.assert_eq(#c.db.executed, 0, "aucune ecriture")
        end)

        H.it("refuse un article deja possede ou inconnu", function()
            local c = Stubs.reset()
            local Boutique = build(c)
            charger(c, Boutique, 5000, 0, { { rayon = "armes", article = "canon" } })

            local r1, r2, r3
            Boutique.Acheter(ACCOUNT, "armes", "canon", nil, function(_, why) r1 = why end)
            Boutique.Acheter(ACCOUNT, "armes", "revolver", nil, function(_, why) r2 = why end)
            Boutique.Acheter(ACCOUNT, "armes", "bazooka", nil, function(_, why) r3 = why end)

            H.assert_eq(r1, "possede", "achete auparavant")
            H.assert_eq(r2, "possede", "gratuit")
            H.assert_eq(r3, "inconnu", "hors catalogue")
        end)

        H.it("rembourse si la livraison echoue", function()
            local c = Stubs.reset()
            local Boutique = build(c)
            local etat = charger(c, Boutique, 1000)
            c.db.execute_error_on = "INSERT INTO possessions"

            local ok
            Boutique.Acheter(ACCOUNT, "persos", "chauve", nil, function(r) ok = r end)

            H.assert_false(ok, "achat echoue")
            H.assert_eq(etat.solde, 1000, "solde rendu")
            H.assert_eq(ecrits(c, "INSERT INTO ledger"), 2, "debit puis remboursement")
            H.assert_false(Boutique.Possede(etat, "persos", "chauve"), "non livre")
        end)

        H.it("n'equipe que ce qui est possede", function()
            local c = Stubs.reset()
            local Boutique = build(c)
            local etat = charger(c, Boutique, 0)

            local refuse, accepte
            Boutique.Equiper(ACCOUNT, "armes", "duel", function(r) refuse = r end)
            Boutique.Equiper(ACCOUNT, "persos", "souris", function(r) accepte = r end)

            H.assert_false(refuse, "arme non possedee")
            H.assert_true(accepte, "perso gratuit")
            H.assert_eq(etat.perso, "souris", "perso equipe")
            H.assert_eq(ecrits(c, "INSERT INTO equipement"), 1, "une ecriture")
        end)

        H.it("retombe sur le defaut si l'equipement n'est plus possede", function()
            local c = Stubs.reset()
            local Boutique = build(c)
            local etat = charger(c, Boutique, 0, 0, {}, { { perso = "gantier", arme = "glace" } })

            H.assert_eq(etat.perso, "clown", "perso non possede remplace")
            H.assert_eq(etat.arme, "revolver", "arme non possedee remplacee")
        end)

        H.it("la vue liste les deux rayons avec prix et possession", function()
            local c = Stubs.reset()
            local Boutique = build(c)
            local etat = charger(c, Boutique, 42)
            local vue = Boutique.Vue(etat)

            H.assert_eq(vue.solde, 42, "solde")
            H.assert_eq(#vue.persos, #Catalogue.persos, "tous les persos")
            H.assert_eq(#vue.armes, #Catalogue.armes, "toutes les armes")
            H.assert_true(vue.armes[1].possede, "arme de base possedee")
        end)
    end)

    H.describe("domain/boutique (mises)", function()
        local A, B = { id = 7 }, { id = 8 }

        local function deux_comptes(c, Boutique, solde_a, solde_b)
            c.answer("FROM possessions", {})
            c.answer("FROM equipement", {})
            c.answer("FROM ledger", { { credits = solde_a, debits = 0, accueil = 1 } })
            local ea; Boutique.Charger(A, function(e) ea = e end)
            c.db.answers[#c.db.answers] = nil
            c.answer("FROM ledger", { { credits = solde_b, debits = 0, accueil = 1 } })
            local eb; Boutique.Charger(B, function(e) eb = e end)
            return ea, eb
        end

        H.it("preleve la mise de chacun vers le sequestre", function()
            local c = Stubs.reset()
            local Boutique = build(c)
            local ea, eb = deux_comptes(c, Boutique, 300, 200)
            local ok
            Boutique.Miser({ A, B }, 100, "duel:1", nil, function(r) ok = r end)
            H.assert_true(ok, "mise acceptee")
            H.assert_eq(ea.solde, 200, "A debite")
            H.assert_eq(eb.solde, 100, "B debite")
            H.assert_eq(ecrits(c, "INSERT INTO ledger"), 2, "deux mouvements")
            H.assert_eq(c.db.executed[#c.db.executed].params[3], "sequestre:duel:1", "vers le sequestre")
        end)

        H.it("refuse sans rien prelever si un joueur est trop pauvre", function()
            local c = Stubs.reset()
            local Boutique = build(c)
            local ea = deux_comptes(c, Boutique, 300, 20)
            local ok, raison, fauches
            Boutique.Miser({ A, B }, 50, "duel:2", nil, function(r, why, f) ok, raison, fauches = r, why, f end)
            H.assert_false(ok, "refuse")
            H.assert_eq(raison, "solde", "raison")
            H.assert_eq(fauches[1].id, 8, "B signale")
            H.assert_eq(ea.solde, 300, "A intact")
            H.assert_eq(ecrits(c, "INSERT INTO ledger"), 0, "aucun mouvement")
        end)

        H.it("solde : cagnotte aux gagnants, reste au premier, bonus a tous", function()
            local c = Stubs.reset()
            local Boutique = build(c)
            local ea, eb = deux_comptes(c, Boutique, 0, 0)
            Boutique.Solder("duel:3", { A, B }, { A, B }, 101, 10, nil)
            H.assert_eq(ea.solde, 51 + 10, "A : moitie + reste + bonus")
            H.assert_eq(eb.solde, 50 + 10, "B : moitie + bonus")
        end)
    end)

    H.describe("Shared/catalogue", function()
        H.it("chaque perso du catalogue existe dans les apparences", function()
            local Appearances = Package.Require("Shared/appearances.lua")
            for _, a in ipairs(Catalogue.persos) do
                H.assert_true(Appearances.by_id[a.id] ~= nil, "apparence " .. a.id)
            end
        end)

        H.it("l'arme de base est gratuite", function()
            H.assert_true(Catalogue.gratuit("armes", Catalogue.arme_de_base), "gratuite")
        end)
    end)
end
