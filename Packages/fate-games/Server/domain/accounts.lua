-- Comptes joueurs.
--
-- Un compte est lie a un Steam ID et porte le droit d'entree sur le serveur. Le
-- personnage, lui, est mortel et remplacable ; le compte ne l'est pas.

return function(Log, DB, Ids, config)
    local Accounts = {}

    -- Cache en memoire, cle par steam_id. Evite une requete par connexion et par
    -- lecture ulterieure. Vide au demarrage : la base reste la source de verite.
    local by_steam = {}

    local function now()
        return os.date("!%Y-%m-%dT%H:%M:%SZ")
    end

    -- Comptes whitelistes d'office. Resout le probleme de l'oeuf et de la poule :
    -- sans eux, personne ne peut entrer pour whitelister qui que ce soit.
    local bootstrap = {}
    for _, steam_id in ipairs((config.whitelist and config.whitelist.bootstrap) or {}) do
        bootstrap[steam_id] = true
    end

    local function is_bootstrap(steam_id)
        return bootstrap[steam_id] == true
    end

    local function cache(account)
        by_steam[account.steam_id] = account
        return account
    end

    -- Resout un compte a partir d'un Steam ID, en le creant s'il n'existe pas.
    -- callback(account, err)
    function Accounts.Resolve(steam_id, callback)
        if type(steam_id) ~= "string" or steam_id == "" then
            return callback(nil, "steam_id_invalide")
        end

        local cached = by_steam[steam_id]
        if cached then
            return callback(cached)
        end

        DB.Select(
            "SELECT id, steam_id, whitelisted, created_at FROM accounts WHERE steam_id = :0",
            function(rows, err)
                if err then
                    Log.Error("accounts", "lecture impossible : " .. tostring(err))
                    return callback(nil, "db_select")
                end

                if rows and rows[1] then
                    local row = rows[1]
                    local account = cache({
                        id          = tonumber(row.id),
                        steam_id    = row.steam_id,
                        whitelisted = tonumber(row.whitelisted) == 1,
                        created_at  = row.created_at,
                    })

                    -- Un compte deja cree peut avoir ete ajoute au bootstrap depuis :
                    -- on rattrape au lieu d'obliger a editer la base a la main.
                    if not account.whitelisted and is_bootstrap(steam_id) then
                        Log.Info("accounts", "compte promu par le bootstrap : " .. steam_id)
                        return Accounts.SetWhitelisted(account, true, nil, function()
                            callback(account)
                        end)
                    end

                    return callback(account)
                end

                -- Compte inconnu : creation immediate. C'est une donnee
                -- transactionnelle, elle echappe au write-behind de R3.
                local account = {
                    id          = Ids.Next("accounts"),
                    steam_id    = steam_id,
                    whitelisted = is_bootstrap(steam_id),
                    created_at  = now(),
                }

                DB.Execute(
                    "INSERT INTO accounts (id, steam_id, whitelisted, created_at) VALUES (:0, :1, :2, :3)",
                    function(_, insert_err)
                        if insert_err then
                            Log.Error("accounts", "creation impossible : " .. tostring(insert_err))
                            return callback(nil, "db_insert")
                        end

                        Log.Info("accounts", ("compte %d cree pour %s%s"):format(
                            account.id, steam_id,
                            account.whitelisted and " (whitelist par bootstrap)" or ""))
                        return callback(cache(account))
                    end,
                    account.id, account.steam_id, account.whitelisted and 1 or 0, account.created_at
                )
            end,
            steam_id
        )
    end

    function Accounts.IsWhitelisted(account)
        return account ~= nil and account.whitelisted == true
    end

    -- Bascule le droit d'entree. Transactionnel, donc ecrit tout de suite, et
    -- journalise : c'est une decision de staff.
    function Accounts.SetWhitelisted(account, value, cid, callback)
        DB.Execute(
            "UPDATE accounts SET whitelisted = :0 WHERE id = :1",
            function(_, err)
                if err then
                    Log.Error("accounts", "mise a jour de whitelist impossible : " .. tostring(err), cid)
                    if callback then callback(false) end
                    return
                end

                account.whitelisted = value and true or false

                Log.Audit({
                    actor          = "staff",
                    target         = "account:" .. tostring(account.id),
                    action         = value and "whitelist_accordee" or "whitelist_retiree",
                    position       = "-",
                    payload        = account.steam_id,
                    correlation_id = cid,
                })

                if callback then callback(true) end
            end,
            value and 1 or 0, account.id
        )
    end

    -- Pour les tests et le rechargement a chaud : la base reste la verite.
    function Accounts.ClearCache()
        by_steam = {}
    end

    return Accounts
end
