-- Migrations numerotees, appliquees dans l'ordre au demarrage.
--
-- Regle : une migration deja appliquee ne se modifie jamais, on en ajoute une nouvelle.
--
-- Portabilite SQLite -> PostgreSQL : le SQL ci-dessous evite les particularites SQLite,
-- a une exception connue. "INTEGER PRIMARY KEY" s'auto-incremente en SQLite mais pas en
-- PostgreSQL, qui demande GENERATED ALWAYS AS IDENTITY. Le jour du passage en production,
-- ce point se traite dans une couche de dialecte, pas en reecrivant les migrations.

return {
    {
        id   = 1,
        name = "schema_initial",
        statements = {
            [[CREATE TABLE IF NOT EXISTS accounts (
                id          INTEGER PRIMARY KEY,
                steam_id    TEXT NOT NULL UNIQUE,
                whitelisted INTEGER NOT NULL DEFAULT 0,
                created_at  TEXT NOT NULL
            )]],

            [[CREATE TABLE IF NOT EXISTS characters (
                id         INTEGER PRIMARY KEY,
                account_id INTEGER NOT NULL,
                first_name TEXT NOT NULL,
                last_name  TEXT NOT NULL,
                created_at TEXT NOT NULL,
                died_at    TEXT
            )]],

            [[CREATE INDEX IF NOT EXISTS idx_characters_account
                ON characters (account_id)]],

            -- R6 : le solde est derive de ce journal, jamais ecrit directement.
            [[CREATE TABLE IF NOT EXISTS ledger (
                id             INTEGER PRIMARY KEY,
                debit_account  TEXT NOT NULL,
                credit_account TEXT NOT NULL,
                amount         INTEGER NOT NULL,
                reason         TEXT NOT NULL,
                correlation_id TEXT,
                created_at     TEXT NOT NULL
            )]],

            [[CREATE INDEX IF NOT EXISTS idx_ledger_accounts
                ON ledger (debit_account, credit_account)]],
        },
    },

    {
        id   = 2,
        name = "etat_des_personnages",
        statements = {
            -- Etat volatil d'un personnage : ecrit en differe par la roue
            -- d'ordonnancement (R3), pas a chaque changement.
            [[CREATE TABLE IF NOT EXISTS character_state (
                character_id INTEGER PRIMARY KEY,
                pos_x        REAL NOT NULL DEFAULT 0,
                pos_y        REAL NOT NULL DEFAULT 0,
                pos_z        REAL NOT NULL DEFAULT 0,
                yaw          REAL NOT NULL DEFAULT 0,
                updated_at   TEXT NOT NULL
            )]],

            -- Le monde se souvient du nom, pas du personnage : un joueur qui meurt
            -- recree un avatar, et la legende s'accumule sur le nom. Voir UNIVERS.md.
            [[ALTER TABLE characters ADD COLUMN legacy_name TEXT]],

            [[CREATE INDEX IF NOT EXISTS idx_characters_legacy
                ON characters (legacy_name)]],
        },
    },
}
