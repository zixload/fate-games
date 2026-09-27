-- Boutique : l'argent du jeu, ce qu'il achete, ce que l'on porte.
--
-- Le solde n'est jamais ecrit (R6) : il se deduit du journal `ledger`, ou
-- chaque mouvement va d'un compte a un autre. Trois sortes de comptes :
--   "compte:<id>"  un joueur
--   "banque"       la source des gains (bonus d'accueil, gains des modes)
--   "boutique"     la ou partent les achats
-- Le solde d'un joueur est lu une fois a son arrivee, puis tenu en memoire
-- et mis a jour a chaque ecriture reussie.
--
-- Tout se decide ici, cote serveur (R1) : le client demande, le serveur
-- verifie le prix dans SA copie du catalogue.

return function(Log, DB, Ids, Catalogue, config)
    local Boutique = {}

    local cfg = config.boutique or {}
    local etats = {}   -- account_id -> etat en memoire

    local function now()
        return os.date("!%Y-%m-%dT%H:%M:%SZ")
    end

    local function compte(account)
        return "compte:" .. tostring(account.id)
    end

    -- Ecrit un mouvement. callback(ok)
    local function mouvement(debit, credit, montant, raison, cid, callback)
        DB.Execute(
            [[INSERT INTO ledger (id, debit_account, credit_account, amount, reason, correlation_id, created_at)
              VALUES (:0, :1, :2, :3, :4, :5, :6)]],
            function(_, err)
                if err then
                    Log.Error("boutique", ("mouvement %s -> %s (%d, %s) impossible : %s")
                        :format(debit, credit, montant, raison, tostring(err)), cid)
                    return callback(false)
                end
                callback(true)
            end,
            Ids.Next("ledger"), debit, credit, montant, raison, cid or "", now()
        )
    end

    function Boutique.Possede(etat, rayon, id)
        if not Catalogue.article(rayon, id) then return false end
        return Catalogue.gratuit(rayon, id) or (etat.possede[rayon] and etat.possede[rayon][id] == true)
    end

    -- Ce que le vestiaire du client affiche. Le catalogue du client ne sert
    -- que de repli : les prix et les possessions viennent d'ici.
    function Boutique.Vue(etat)
        local vue = { solde = etat.solde, perso = etat.perso, arme = etat.arme, persos = {}, armes = {},
            armes_3d = Catalogue.armes_3d == true }
        for _, rayon in ipairs({ "persos", "armes" }) do
            for _, article in ipairs(Catalogue[rayon]) do
                vue[rayon][#vue[rayon] + 1] = {
                    id = article.id, prix = article.prix,
                    possede = Boutique.Possede(etat, rayon, article.id),
                    en_3d = rayon == "armes" and Catalogue.en_3d(article.id) or nil,
                }
            end
        end
        return vue
    end

    function Boutique.Etat(account)
        return account and etats[account.id] or nil
    end

    -- Credite un joueur depuis la banque (bonus, gains). callback(ok)
    function Boutique.Crediter(account, montant, raison, cid, callback)
        callback = callback or function() end
        local etat = etats[account.id]
        if type(montant) ~= "number" or montant <= 0 or montant ~= math.floor(montant) then
            return callback(false)
        end
        mouvement("banque", compte(account), montant, raison, cid, function(ok)
            if ok and etat then etat.solde = etat.solde + montant end
            callback(ok)
        end)
    end

    ------------------------------------------------------------ mises des modes
    -- La mise d'une partie part dans "sequestre:<partie>" au lancement, puis
    -- revient aux gagnants a la fin (docs/DUEL-ET-ARGENT.md).

    local function sequestre(partie)
        return "sequestre:" .. tostring(partie)
    end

    -- Vrai si chaque compte est charge et peut payer `montant`. Sinon, la liste
    -- des comptes qui ne le peuvent pas.
    function Boutique.PeuventMiser(accounts, montant)
        local fauches = {}
        for _, account in ipairs(accounts) do
            local etat = etats[account.id]
            if not etat or etat.solde < montant then fauches[#fauches + 1] = account end
        end
        return #fauches == 0, fauches
    end

    -- Preleve la mise de chacun. Si un prelevement echoue, ceux deja faits sont
    -- rendus : tout ou rien. callback(ok, raison)
    function Boutique.Miser(accounts, montant, partie, cid, callback)
        if montant <= 0 then return callback(true) end
        local ok, fauches = Boutique.PeuventMiser(accounts, montant)
        if not ok then return callback(false, "solde", fauches) end

        local faits = {}
        local function suivant(i)
            local account = accounts[i]
            if not account then return callback(true) end
            mouvement(compte(account), sequestre(partie), montant, "mise", cid, function(reussi)
                if not reussi then
                    local function rendre(j)
                        local a = faits[j]
                        if not a then return callback(false, "base") end
                        mouvement(sequestre(partie), compte(a), montant, "mise_rendue", cid, function(rendu)
                            if rendu and etats[a.id] then etats[a.id].solde = etats[a.id].solde + montant end
                            rendre(j + 1)
                        end)
                    end
                    return rendre(1)
                end
                if etats[account.id] then etats[account.id].solde = etats[account.id].solde - montant end
                faits[#faits + 1] = account
                suivant(i + 1)
            end)
        end
        suivant(1)
    end

    -- Verse la cagnotte aux gagnants (le reste de la division au premier), puis
    -- le bonus de participation a chacun. callback()
    -- Abonne aux gains (ecran d'accueil, fil des derniers gains) : appele pour
    -- chaque versement de cagnotte reussi, pas pour les bonus de participation.
    local sur_gain = nil
    function Boutique.SurGain(fn)
        sur_gain = fn
    end

    function Boutique.Solder(partie, participants, gagnants, cagnotte, bonus, cid, callback)
        callback = callback or function() end
        local versements = {}
        if cagnotte > 0 and #gagnants > 0 then
            local part = math.floor(cagnotte / #gagnants)
            local reste = cagnotte - part * #gagnants
            for i, account in ipairs(gagnants) do
                versements[#versements + 1] = { de = sequestre(partie), a = account,
                    montant = part + (i == 1 and reste or 0), raison = "gain" }
            end
        end
        if bonus > 0 then
            for _, account in ipairs(participants) do
                versements[#versements + 1] = { de = "banque", a = account, montant = bonus, raison = "participation" }
            end
        end

        local function suivant(i)
            local v = versements[i]
            if not v then return callback() end
            if v.montant <= 0 then return suivant(i + 1) end
            mouvement(v.de, compte(v.a), v.montant, v.raison, cid, function(ok)
                if ok and etats[v.a.id] then etats[v.a.id].solde = etats[v.a.id].solde + v.montant end
                if ok and v.raison == "gain" and sur_gain then pcall(sur_gain, partie, v.a, v.montant) end
                suivant(i + 1)
            end)
        end
        suivant(1)
    end

    -- Rend sa mise a chacun (partie qui ne demarre pas) : ce n'est pas un gain,
    -- le fil de l'accueil n'en entend pas parler. callback()
    function Boutique.Rendre(partie, comptes, montant, cid, callback)
        callback = callback or function() end
        local i = 0
        local function suivant()
            i = i + 1
            local account = comptes[i]
            if not account then return callback() end
            if montant <= 0 then return suivant() end
            mouvement(sequestre(partie), compte(account), montant, "mise_rendue", cid, function(ok)
                if ok and etats[account.id] then etats[account.id].solde = etats[account.id].solde + montant end
                suivant()
            end)
        end
        suivant()
    end

    -- Une recompense versee par la banque (le musicien, une fois par jour).
    -- callback(ok)
    function Boutique.Recompenser(account, montant, raison, cid, callback)
        local etat = etats[account.id]
        if not etat or montant <= 0 then return callback(false) end
        mouvement("banque", compte(account), montant, raison, cid, function(ok)
            if ok then etat.solde = etat.solde + montant end
            callback(ok)
        end)
    end

    -- Le jour (UTC, AAAA-MM-JJ) de la derniere recompense de cette raison, ou
    -- nil si jamais. callback(jour, err)
    function Boutique.DerniereRecompense(account, raison, callback)
        DB.Select("SELECT MAX(created_at) AS quand FROM ledger WHERE credit_account = :0 AND reason = :1",
            function(rows, err)
                if err then return callback(nil, err) end
                local q = rows and rows[1] and rows[1].quand
                callback(q and tostring(q):sub(1, 10) or nil)
            end, compte(account), raison)
    end

    local function lire_possessions(account, etat, callback)
        DB.Select(
            "SELECT rayon, article FROM possessions WHERE account_id = :0",
            function(rows, err)
                if err then
                    Log.Error("boutique", "lecture des possessions impossible : " .. tostring(err))
                    return callback(false)
                end
                for _, row in ipairs(rows or {}) do
                    if etat.possede[row.rayon] then etat.possede[row.rayon][row.article] = true end
                end
                callback(true)
            end,
            account.id
        )
    end

    local function lire_equipement(account, etat, callback)
        DB.Select(
            "SELECT perso, arme FROM equipement WHERE account_id = :0",
            function(rows, err)
                if err then
                    Log.Error("boutique", "lecture de l'equipement impossible : " .. tostring(err))
                    return callback(false)
                end
                local row = rows and rows[1]
                if row then
                    etat.perso = row.perso
                    etat.arme  = row.arme
                else
                    -- Premiere venue : une apparence de base des bots, gratuite
                    -- donc possedee ; l'accueil l'enregistre (Server/Index.lua).
                    -- Il la change ensuite piece par piece chez le tailleur.
                    local gratuits = {}
                    for _, a in ipairs(Catalogue.persos) do
                        if a.prix == 0 then gratuits[#gratuits + 1] = a.id end
                    end
                    if #gratuits > 0 then
                        etat.perso = gratuits[(cfg.rng or math.random)(#gratuits)]
                        etat.nouveau = true
                    end
                end
                -- Un article retire du catalogue, ou plus possede, retombe sur
                -- le defaut plutot que de laisser le joueur nu.
                if not Boutique.Possede(etat, "persos", etat.perso) then etat.perso = cfg.perso_defaut end
                if not Boutique.Possede(etat, "armes", etat.arme) then etat.arme = Catalogue.arme_de_base end
                callback(true)
            end,
            account.id
        )
    end

    -- La tenue portee (tailleur), rangee par categorie. Lue sans attendre :
    -- une tenue absente laisse simplement l'apparence de base.
    local function lire_tenue(account, etat)
        DB.Select("SELECT emplacement, article FROM tenue WHERE account_id = :0", function(rows, err)
            if err then return Log.Error("boutique", "lecture de la tenue impossible : " .. tostring(err)) end
            for _, row in ipairs(rows or {}) do etat.tenue[row.emplacement] = row.article end
        end, account.id)
    end

    -- Charge le solde, les possessions et l'equipement, et verse le bonus
    -- d'accueil a la premiere visite. callback(etat) ; nil si la base a echoue.
    function Boutique.Charger(account, callback)
        if etats[account.id] then return callback(etats[account.id]) end

        local c = compte(account)
        DB.Select(
            [[SELECT
                COALESCE(SUM(CASE WHEN credit_account = :0 THEN amount ELSE 0 END), 0) AS credits,
                COALESCE(SUM(CASE WHEN debit_account = :1 THEN amount ELSE 0 END), 0) AS debits,
                COALESCE(SUM(CASE WHEN credit_account = :2 AND reason = 'bienvenue' THEN 1 ELSE 0 END), 0) AS accueil
              FROM ledger WHERE credit_account = :3 OR debit_account = :4]],
            function(rows, err)
                if err then
                    Log.Error("boutique", "lecture du solde impossible : " .. tostring(err))
                    return callback(nil)
                end
                local row = (rows and rows[1]) or {}
                local etat = {
                    solde   = (tonumber(row.credits) or 0) - (tonumber(row.debits) or 0),
                    possede = { persos = {}, armes = {}, cosmetiques = {} },
                    tenue   = {},
                }

                lire_possessions(account, etat, function(ok)
                    if not ok then return callback(nil) end
                    lire_equipement(account, etat, function(ok2)
                        if not ok2 then return callback(nil) end
                        lire_tenue(account, etat)
                        etats[account.id] = etat

                        local bonus = cfg.bonus_accueil or 0
                        if bonus > 0 and (tonumber(row.accueil) or 0) == 0 then
                            return Boutique.Crediter(account, bonus, "bienvenue", nil, function(ok3)
                                if ok3 then
                                    Log.Info("boutique", ("bonus d'accueil de %d pour le compte %d")
                                        :format(bonus, account.id))
                                end
                                callback(etat)
                            end)
                        end
                        callback(etat)
                    end)
                end)
            end,
            c, c, c, c, c
        )
    end

    -- Achat. callback(ok, raison) ; raison vaut "inconnu", "possede",
    -- "solde", "occupe" ou "base".
    function Boutique.Acheter(account, rayon, id, cid, callback)
        local etat = etats[account.id]
        local article = Catalogue.article(rayon, id)
        if not etat then return callback(false, "occupe") end
        if not article then return callback(false, "inconnu") end
        if Boutique.Possede(etat, rayon, id) then return callback(false, "possede") end
        if etat.occupe then return callback(false, "occupe") end
        if etat.solde < article.prix then return callback(false, "solde") end

        -- Verrou : deux clics rapides ne doivent pas payer deux fois.
        etat.occupe = true
        mouvement(compte(account), "boutique", article.prix, "achat:" .. rayon .. ":" .. id, cid, function(ok)
            if not ok then
                etat.occupe = nil
                return callback(false, "base")
            end
            etat.solde = etat.solde - article.prix

            DB.Execute(
                "INSERT INTO possessions (account_id, rayon, article, acquired_at) VALUES (:0, :1, :2, :3)",
                function(_, err)
                    if err then
                        -- Paye mais pas livre : on rembourse plutot que de laisser
                        -- le joueur sans l'article ni l'argent.
                        Log.Error("boutique", ("livraison de %s:%s impossible, remboursement : %s")
                            :format(rayon, id, tostring(err)), cid)
                        return mouvement("boutique", compte(account), article.prix, "remboursement", cid, function(rembourse)
                            if rembourse then etat.solde = etat.solde + article.prix end
                            etat.occupe = nil
                            callback(false, "base")
                        end)
                    end

                    etat.possede[rayon][id] = true
                    etat.occupe = nil
                    Log.Audit({
                        actor          = compte(account),
                        target         = rayon .. ":" .. id,
                        action         = "achat",
                        position       = "-",
                        payload        = tostring(article.prix),
                        correlation_id = cid,
                    })
                    callback(true)
                end,
                account.id, rayon, id, now()
            )
        end)
    end

    -- Equipe un article possede. callback(ok, raison)
    function Boutique.Equiper(account, rayon, id, callback)
        local etat = etats[account.id]
        if not etat then return callback(false, "occupe") end
        if not Boutique.Possede(etat, rayon, id) then return callback(false, "non_possede") end

        local perso = rayon == "persos" and id or etat.perso
        local arme  = rayon == "armes" and id or etat.arme
        DB.Execute(
            [[INSERT INTO equipement (account_id, perso, arme, updated_at) VALUES (:0, :1, :2, :3)
              ON CONFLICT (account_id) DO UPDATE SET
                perso = excluded.perso, arme = excluded.arme, updated_at = excluded.updated_at]],
            function(_, err)
                if err then
                    Log.Error("boutique", "ecriture de l'equipement impossible : " .. tostring(err))
                    return callback(false, "base")
                end
                etat.perso, etat.arme = perso, arme
                callback(true)
            end,
            account.id, perso, arme, now()
        )
    end

    -- Une piece du tailleur est-elle a lui ? Une couleur l'est des que son
    -- article (le groupe) l'est ; une couleur achetee seule avant le 27/09
    -- donne aussi tout l'article.
    function Boutique.PossedeCosmetique(etat, id)
        local C = Package.Require("Shared/cosmetiques.lua")
        local achat = C.achat_id(id)
        if Boutique.Possede(etat, "cosmetiques", achat) then return true end
        local g = C.groupes[achat]
        local a_moi = etat.possede.cosmetiques or {}
        for _, v in ipairs(g and g.variantes or {}) do
            if a_moi[v.id] then return true end
        end
        return false
    end

    -- A la deconnexion : la base reste la verite, le cache se reconstruit.
    -- Le panier du tailleur : tout ou rien sur le prix total, puis un achat par
    -- piece (Boutique.Acheter revalide chacune). callback(ok, raison).
    function Boutique.AcheterPanier(account, ids, cid, callback)
        local etat = etats[account.id]
        if not etat then return callback(false, "etat") end
        local total, liste = 0, {}
        for _, id in ipairs(ids) do
            local a = Catalogue.article("cosmetiques", id)
            if not a then return callback(false, "inconnu") end
            if not Boutique.PossedeCosmetique(etat, id) then
                total = total + a.prix
                liste[#liste + 1] = id
            end
        end
        if total > etat.solde then return callback(false, "solde") end
        local i = 0
        local function suivant()
            i = i + 1
            if i > #liste then return callback(true) end
            Boutique.Acheter(account, "cosmetiques", liste[i], cid, function(ok, raison)
                if not ok then return callback(false, raison) end
                suivant()
            end)
        end
        suivant()
    end

    -- Porter une piece possedee (ou "aucun") dans sa categorie. callback(ok, raison).
    function Boutique.Porter(account, emplacement, id, callback)
        local etat = etats[account.id]
        if not etat then return callback(false, "etat") end
        local C = Package.Require("Shared/cosmetiques.lua")
        local connu = false
        for _, e in ipairs(C.emplacements) do connu = connu or e.id == emplacement end
        if not connu then return callback(false, "emplacement") end
        if id ~= "aucun" then
            local piece = C.par_id[id]
            if not (piece and piece.emplacement == emplacement) then return callback(false, "inconnu") end
            if not Boutique.PossedeCosmetique(etat, id) then return callback(false, "non_possede") end
        end
        DB.Execute(
            [[INSERT INTO tenue (account_id, emplacement, article, updated_at) VALUES (:0, :1, :2, :3)
              ON CONFLICT(account_id, emplacement) DO UPDATE SET article = excluded.article,
              updated_at = excluded.updated_at]],
            function(_, err)
                if err then
                    Log.Error("boutique", "tenue non ecrite : " .. tostring(err))
                    return callback(false, "base")
                end
                etat.tenue[emplacement] = id
                callback(true)
            end,
            account.id, emplacement, id, now())
    end

    -- Ce que la boutique du tailleur affiche : solde, articles (prix, possede,
    -- porte), tenue. Un article en plusieurs couleurs vient une fois, avec ses
    -- variantes (identifiant, teinte, couleur) et celle qui est portee.
    function Boutique.VueTailleur(etat)
        local C = Package.Require("Shared/cosmetiques.lua")
        local vue = { solde = etat.solde, tenue = etat.tenue, articles = {} }
        local vus = {}
        for _, c in ipairs(C.liste) do
            local id = c.groupe or c.id
            if not vus[id] then
                vus[id] = true
                local a = Catalogue.article("cosmetiques", id)
                local article = {
                    id = id, nom = c.nom, numero = c.numero, rarete = c.rarete, emplacement = c.emplacement,
                    prix = a and a.prix or 0, possede = Boutique.PossedeCosmetique(etat, c.id),
                    porte = etat.tenue[c.emplacement] == c.id,
                }
                local g = c.groupe and C.groupes[c.groupe]
                if g then
                    article.nom, article.rarete, article.variantes = g.nom, g.rarete, {}
                    article.porte = false
                    for _, v in ipairs(g.variantes) do
                        article.variantes[#article.variantes + 1] = { id = v.id, teinte = v.teinte, couleur = v.couleur }
                        if etat.tenue[c.emplacement] == v.id then article.porte, article.porte_id = true, v.id end
                    end
                end
                vue.articles[#vue.articles + 1] = article
            end
        end
        return vue
    end

    function Boutique.Oublier(account)
        if account then etats[account.id] = nil end
    end

    return Boutique
end
