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

        -- Bots de test de Liar's Bar : "/bots N" dans le chat. A mettre a
        -- false sur un serveur ouvert au public.
        liars_bots = true,

        -- ESSAI CharacterSimple (voir domain/characters.lua) : jouer le clown
        -- du pack Creative Characters, copie dans MyAssetPack. Laisser
        -- enabled a false tant que le pack et ABP_Creative ne sont pas cuits.
        creative_character = {
            enabled        = true,
            body           = "my-asset-pack::SK_Body_010",
            anim_blueprint = "my-asset-pack::ABP_Creative",
            parts = {
                "my-asset-pack::SK_Male_emotion_happy_002",
                "my-asset-pack::SK_Clown_nose_001",
                "my-asset-pack::SK_Costume_10_001",
                "my-asset-pack::SK_Shoe_Slippers_005",
            },
            scale      = 0.8,    -- le corps du pack mesure ~190 cm, un peu grand
            walk_speed = 450,    -- cm/s, a accorder avec le Blend Space
            eye_height = 60.0,   -- hauteur de la camera depuis le centre du corps
            arm_length = 250.0,  -- recul de la camera ; 0 = premiere personne
            -- Camera assise, en premiere personne. Reglee en jeu avec /cam le
            -- 18/09 : l'origine est aux pieds, d'ou la hauteur. side > 0 = droite.
            seated_camera = { forward = -25.0, up = 125.0, side = 0.0 },
        },
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
