-- Disposition de la table de Liar's Bar dans MapEgypt.
--
-- Reperes mesures dans MapEgypt avec des cubes Unreal. Les meubles sont
-- cuits dans la carte : le serveur ne doit creer que les volumes
-- interactifs et le revolver mobile.
return {
    -- Calibration : les quatre reperes sont visibles pour verifier en jeu
    -- qu'ils recouvrent leur chaise. Mettre false une fois verifie.
    debug_visible = false,

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
}
