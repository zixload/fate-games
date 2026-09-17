-- Configuration serveur. Ne quitte jamais le serveur, contrairement a Shared/config.lua.

return {
    db = {
        -- SQLite en developpement, PostgreSQL vise en production
        connection = "db=fate.db timeout=2",
        pool_size  = 10,
    },

    persistence = {
        -- R3 : flush groupe des etats marques "sales", jamais d'ecriture par changement
        flush_interval_ms = 30000,
    },

    log = {
        min_level = "DEBUG",
    },

    whitelist = {
        -- A passer a true avant le premier test a plusieurs. Laisse a false, le
        -- serveur accepte tout le monde : pratique en developpement, inacceptable
        -- des qu il est joignable.
        enabled = false,

        -- Steam IDs whitelistes d office des leur premier contact. Sans eux,
        -- personne ne peut entrer pour whitelister qui que ce soit. Un compte deja
        -- cree et ajoute ici ensuite est rattrape a sa prochaine connexion.
        bootstrap = {
            -- "76561198000000000",
        },

        kick_reason = "Serveur prive.",
    },

    -- Apparence par defaut des personnages. Le pack doit etre monte via `assets`
    -- dans Config.toml, sinon le mesh est introuvable a l'execution.
    character_mesh = "nanos-world::SK_Male",

    interaction = {
        -- Portee par defaut en centimetres. Le serveur revalide toujours la
        -- distance a la reception : c'est ici que s'arrete un client modifie.
        max_distance = 250.0,
    },

    dev = {
        -- Test d'integration au demarrage, sans client de jeu : fabrique un faux
        -- joueur et pousse la vraie chaine de connexion. Voir Server/dev/smoke.lua.
        -- A laisser a false en temps normal : il ecrit puis supprime des lignes.
        smoke_test = false,
    },

    -- Point d'arrivee par defaut, utilise quand un personnage n'a pas d'etat
    -- enregistre. Provisoire : le canon veut que le lieu d'arrivee depende du
    -- profil du joueur (voir SYSTEME-EPREUVE.md).
    spawn = {
        x   = -3469.4,
        y   = 15.3,
        z   = 505.0,   -- le sol de la plateforme est a 404.9 : on tombe d'un metre
        yaw = -52.4,
    },
}
