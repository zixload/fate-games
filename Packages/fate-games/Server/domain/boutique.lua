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
                    possede = { persos = {}, armes = {} },
                }

                lire_possessions(account, etat, function(ok)
                    if not ok then return callback(nil) end
                    lire_equipement(account, etat, function(ok2)
                        if not ok2 then return callback(nil) end
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

    -- A la deconnexion : la base reste la verite, le cache se reconstruit.
    function Boutique.Oublier(account)
        if account then etats[account.id] = nil end
    end

    return Boutique
end
