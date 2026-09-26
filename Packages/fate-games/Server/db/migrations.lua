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

    {
        id   = 3,
        name = "resultat_liars_bar",
        statements = {
            -- Seule donnee durable du jeu : le resultat d'une partie terminee.
            -- Rien des mains, rien des barillets — ils n'existent que le temps
            -- de la partie et ne regardent personne apres.
            [[CREATE TABLE IF NOT EXISTS liars_matches (
                id         INTEGER PRIMARY KEY,
                started_at TEXT    NOT NULL,
                ended_at   TEXT    NOT NULL,
                rounds     INTEGER NOT NULL,
                winner_id  INTEGER
            )]],

            -- placement vaut 1 pour le vainqueur, puis 2, 3... dans l'ordre
            -- inverse des eliminations.
            [[CREATE TABLE IF NOT EXISTS liars_participants (
                match_id     INTEGER NOT NULL,
                seat         INTEGER NOT NULL,
                character_id INTEGER NOT NULL,
                look         TEXT    NOT NULL,
                placement    INTEGER,
                PRIMARY KEY (match_id, seat)
            )]],
        },
    },

    {
        id   = 4,
        name = "boutique",
        statements = {
            -- Ce qu'un compte a achete. Les articles gratuits n'y figurent pas :
            -- ils sont possedes par construction (Shared/catalogue.lua).
            -- rayon vaut "persos" ou "armes".
            [[CREATE TABLE IF NOT EXISTS possessions (
                account_id  INTEGER NOT NULL,
                rayon       TEXT    NOT NULL,
                article     TEXT    NOT NULL,
                acquired_at TEXT    NOT NULL,
                PRIMARY KEY (account_id, rayon, article)
            )]],

            -- Ce que le compte porte : une ligne par compte, ecrite au choix.
            [[CREATE TABLE IF NOT EXISTS equipement (
                account_id INTEGER PRIMARY KEY,
                perso      TEXT,
                arme       TEXT,
                updated_at TEXT NOT NULL
            )]],
        },
    },
}
