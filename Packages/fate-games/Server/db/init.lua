-- Acces base de donnees (R2).
--
-- Database:Select() et Database:Execute() sont BLOQUANTS : ils gelent le serveur le temps
-- de la requete. Ils ne sont utilises qu'ici, au demarrage, pour les migrations, avant
-- qu'un joueur puisse etre connecte. Tout le reste du jeu passe par les formes async.

local migrations = Package.Require("db/migrations.lua")

return function(Log, config)
    local DB = {}
    local db = nil

    -- R2 rendue executable : une fois EndStartup() appele, toute requete bloquante
    -- leve une erreur au lieu de geler discretement le serveur en production.
    local in_startup = true

    function DB.Connect()
        -- La construction se connecte sur le main thread et peut provoquer un micro-freeze :
        -- elle n'a lieu qu'une fois, au demarrage.
        db = Database(DatabaseEngine.SQLite, config.db.connection, config.db.pool_size)
        Log.Info("db", "connexion SQLite etablie (" .. config.db.connection .. ")")
    end

    -- Bloquant, volontairement. Retourne false si une migration echoue, auquel cas
    -- l'initialisation doit s'arreter plutot que tourner sur un schema incomplet.
    function DB.Migrate()
        local _, err = db:Execute([[CREATE TABLE IF NOT EXISTS schema_migrations (
            id         INTEGER PRIMARY KEY,
            name       TEXT NOT NULL,
            applied_at TEXT NOT NULL
        )]])
        if err then
            Log.Error("db", "impossible de creer schema_migrations : " .. tostring(err))
            return false
        end

        local rows, select_err = db:Select("SELECT id FROM schema_migrations")
        if select_err then
            Log.Error("db", "lecture de schema_migrations impossible : " .. tostring(select_err))
            return false
        end

        local applied = {}
        for _, row in ipairs(rows or {}) do
            applied[tonumber(row.id)] = true
        end

        for _, migration in ipairs(migrations) do
            if not applied[migration.id] then
                for _, statement in ipairs(migration.statements) do
                    local _, stmt_err = db:Execute(statement)
                    if stmt_err then
                        Log.Error("db", ("migration %d (%s) echouee : %s")
                            :format(migration.id, migration.name, tostring(stmt_err)))
                        return false
                    end
                end

                db:Execute(
                    "INSERT INTO schema_migrations (id, name, applied_at) VALUES (:0, :1, :2)",
                    migration.id, migration.name, os.date("!%Y-%m-%dT%H:%M:%SZ")
                )
                Log.Info("db", ("migration %d appliquee : %s")
                    :format(migration.id, migration.name))
            end
        end

        return true
    end

    -- Lecture bloquante, autorisee uniquement pendant le demarrage. Sert a amorcer
    -- ce qui doit etre connu avant qu'un joueur puisse se connecter.
    function DB.SelectAtStartup(query, ...)
        if not in_startup then
            error("DB.SelectAtStartup appele apres le demarrage : utiliser DB.Select (R2)", 2)
        end
        return db:Select(query, ...)
    end

    -- Ferme la phase de demarrage. A appeler une fois l'initialisation terminee.
    function DB.EndStartup()
        in_startup = false
    end

    -- Seules formes autorisees une fois le serveur demarre.
    -- Les parametres sont toujours passes en arguments (:0, :1), jamais concatenes.
    function DB.Select(query, callback, ...)
        db:SelectAsync(query, callback, ...)
    end

    function DB.Execute(query, callback, ...)
        db:ExecuteAsync(query, callback, ...)
    end

    function DB.Close()
        if db then
            db:Close()
            db = nil
        end
    end

    return DB
end
