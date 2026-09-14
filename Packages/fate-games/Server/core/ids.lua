-- Generation des identifiants de ligne, cote serveur.
--
-- Pourquoi ne pas laisser la base s'en charger : le moteur ouvre un pool de dix
-- connexions, et `last_insert_rowid()` de SQLite est propre a une connexion. Le lire
-- apres un ExecuteAsync ne garantit donc rien.
--
-- Effet de bord bienvenu : ca regle la seule entorse connue a la portabilite
-- SQLite / PostgreSQL. "INTEGER PRIMARY KEY" s'auto-incremente en SQLite mais pas en
-- PostgreSQL ; en fournissant nous-memes les identifiants, la question disparait.

return function(Log, DB)
    local Ids = {}

    local counters = {}

    -- Amorce les compteurs depuis la base. Bloquant, donc uniquement au demarrage,
    -- avant qu'un joueur puisse se connecter.
    function Ids.Seed(tables)
        for _, name in ipairs(tables) do
            -- Le nom de table ne peut pas etre passe en parametre lie ; il vient d'une
            -- liste en dur dans le code, jamais d'une entree exterieure.
            local rows, err = DB.SelectAtStartup(("SELECT MAX(id) AS max_id FROM %s"):format(name))

            if err then
                Log.Error("ids", ("amorcage impossible pour %s : %s"):format(name, tostring(err)))
                return false
            end

            local max_id = 0
            if rows and rows[1] and rows[1].max_id then
                max_id = tonumber(rows[1].max_id) or 0
            end

            counters[name] = max_id
            Log.Debug("ids", ("%s amorce a %d"):format(name, max_id))
        end

        return true
    end

    function Ids.Next(table_name)
        local current = counters[table_name]
        if not current then
            error("table non amorcee dans Ids : " .. tostring(table_name), 2)
        end

        current = current + 1
        counters[table_name] = current
        return current
    end

    -- Pour les tests et le diagnostic.
    function Ids.Current(table_name)
        return counters[table_name]
    end

    return Ids
end
