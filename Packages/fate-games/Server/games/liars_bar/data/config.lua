-- Reglages de Liar's Bar. Valeurs a ajuster a l'usage : elles ont ete posees
-- sur le papier et n'ont encore jamais ete jouees a quatre.
return {
    -- cartes distribuees a chacun en debut de manche
    hand_size = 5,

    -- nombre maximal de cartes posables en un tour
    max_play = 3,

    -- Quatre places, pas six : le paquet de vingt cartes et les mains de cinq
    -- ne servent que quatre joueurs. C'est la table canonique du jeu, et la
    -- seule compatible avec l'arithmetique decrite dans data/deck.lua.
    min_players = 3,
    max_seats   = 4,

    -- chambres du barillet ; une seule balle, position tiree au hasard
    chambers = 6,

    -- delai avant qu'un tir se resolve tout seul, si le joueur designe se
    -- deconnecte ou reste inerte : sans lui la partie se bloque
    shoot_timeout = 15.0,

    -- Bots de test (voir bots.lua). Ils ne jouent que si dev.liars_bots est
    -- vrai dans Server/core/config.lua.
    bots = {
        delay          = 1.5,   -- secondes avant qu'un bot joue
        accuse_percent = 30,    -- chance d'accuser quand une pose le permet
        body_offset    = 60.0,  -- recul du corps derriere sa chaise, en cm
    },

    -- Reperes mesures dans MapEgypt avec des cubes Unreal. Les meubles sont
    -- cuits dans la carte : le serveur ne doit creer que les volumes
    -- interactifs et le revolver mobile.
    layout = {
        -- Calibration : les quatre reperes sont visibles pour verifier en jeu
        -- qu'ils recouvrent leur chaise. Mettre false une fois verifie.
        debug_visible = true,

        chairs = {
            -- ordre du tour : Cube2, Cube, Cube4, Cube3
            {
                location = { x = -3361.988548, y = -40.611231, z = 326.171189 },
                yaw = 140.0,
                scale = { x = 0.3275, y = 0.3025, z = 0.4750 },
            },
            {
                location = { x = -3471.988548, y = -30.611231, z = 326.171189 },
                yaw = 50.0,
                scale = { x = 0.3375, y = 0.4100, z = 0.4750 },
            },
            {
                location = { x = -3481.988548, y = 79.388769, z = 316.171189 },
                yaw = 140.0,
                scale = { x = 0.3375, y = 0.4100, z = 0.5200 },
            },
            {
                location = { x = -3361.988548, y = 99.388769, z = 326.171189 },
                yaw = 140.0,
                scale = { x = 0.3375, y = 0.4100, z = 0.4325 },
            },
        },

        -- Sommet du cube pose sur le plateau : 327.086143 + 68.5 / 2.
        revolver_home = { x = -3414.257385, y = 35.547911, z = 361.336143 },
    },
}
