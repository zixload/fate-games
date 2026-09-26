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

    -- Argent du jeu et boutique (domain/boutique.lua, Shared/catalogue.lua).
    boutique = {
        -- Verse une seule fois, a la premiere arrivee d'un compte.
        bonus_accueil = 500,
        -- Porte par un compte qui n'a encore rien choisi.
        perso_defaut  = "clown",
    },

    -- Vestiaire d'arrivee : le personnage attend, debout sur un socle
    -- invisible haut dans le ciel, face a la camera, pendant que le joueur
    -- choisit ses cartes. Une place par joueur, espacees pour qu'aucun
    -- voisin n'entre dans le champ. Distances en cm, angles en degres.
    vestiaire = {
        enabled  = true,
        altitude = 6000,     -- au-dessus du point d'apparition
        ecart    = 800,      -- entre deux places
        camera_distance = 320,
        -- Camera a hauteur de poitrine, un peu plongeante : le personnage se
        -- retrouve dans le haut de l'ecran, au-dessus de l'eventail de cartes.
        camera_hauteur  = 20,
        camera_tangage  = -10,
        socle_visible   = false,
    },

    -- Voix de proximite native, spatialisée par nanos world.
    voice = {
        -- cm, portee de la voix de proximite (defaut nanos : 3600). Le son
        -- decroit jusqu'a cette distance : a 900, meme la table s'entendait
        -- mal (26/09).
        max_distance = 2500,
        volume = 2.0,   -- multiplicateur (1 = volume d'origine), trop bas a 1
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
            walk_speed = 150,    -- cm/s, marche : le point Walk du Blend Space
            run_speed  = 450,    -- cm/s, Maj enfoncee : le point Run du Blend Space
            -- On recule moins vite qu'on avance : les animations de recul du
            -- pack ont une foulee plus lente, et sans cela les pieds glissent.
            -- A regler en jeu avec "/vitesse arriere <marche> [course]", puis
            -- a reporter sur les echantillons de recul du Blend Space.
            walk_back_speed = 100,
            run_back_speed  = 250,
            -- Saut : l'animation en l'air dure plus longtemps que le saut par
            -- defaut. On monte l'impulsion et on allege la pesanteur pour que
            -- le temps en l'air corresponde. A regler en jeu : "/saut <z>
            -- [pesanteur]". Temps en l'air = 2 x z / (981 x pesanteur).
            jump_z        = 400.0,
            gravity_scale = 0.9,
            rotation_rate = 540, -- degres par seconde
            -- Debout, le corps suit la camera au lieu de pivoter vers sa
            -- marche : sans cela, les pas de cote et le recul du Blend Space
            -- 2D ne se verraient jamais, le personnage se tournant toujours
            -- dans le sens de son deplacement. Faux = comportement d'avant.
            face_camera = true,
            eye_height = 60.0,   -- hauteur de la camera depuis le centre du corps
            arm_length = 250.0,  -- recul de la camera ; 0 = premiere personne
            -- Camera a la hauteur des yeux, dans l'axe du buste. Avancer de
            -- plusieurs dizaines de cm placerait tout le corps derriere elle.
            -- Head et Neck sont caches localement par posture.lua.
            -- /cam permet de peaufiner cette position en jeu.
            seated_camera = { forward = 0.0, up = 132.0, side = 0.0 },
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
