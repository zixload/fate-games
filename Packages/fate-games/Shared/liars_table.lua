-- Disposition de la table de Liar's Bar dans MapEgypt.
--
-- Transformations des meubles SM_Liars_Table / SM_Liars_Chair dans MapEgypt
-- communiquees le 25/09/2026. Origine des FBX au sol. Le serveur ne cree
-- que les volumes interactifs et les revolvers mobiles.
return {
    -- Calibration : les quatre reperes sont visibles pour verifier en jeu
    -- qu'ils recouvrent leur chaise. Mettre false une fois verifie.
    debug_visible = false,

    -- Hauteur de la surface du coussin au-dessus du pivot de chaque chaise.
    seat_height = 46.0,
    -- Hauteur du centre du personnage assis au-dessus du pivot de la chaise.
    character_height = 70.0,
    -- Avance le buste sur le coussin, vers le centre de la table.
    seat_forward = 8.0,
    -- Hauteur du feutre au-dessus du pivot de la table (modele Blender).
    table_height = 76.0,
    -- Distance du centre du plateau au centre de chaque revolver.
    revolver_radius = 58.0,

    chairs = {
        -- Ordre des places : nord, est, sud, ouest.
        {
            location = { x = -3440.0, y = 170.0, z = 310.0 },
            yaw = 0.0,
            scale = { x = 0.55, y = 0.55, z = 0.13 },
        },
        {
            location = { x = -3300.813574, y = 48.004115, z = 303.939434 },
            yaw = -90.0,
            scale = { x = 0.55, y = 0.55, z = 0.13 },
        },
        {
            location = { x = -3430.0, y = -70.0, z = 300.0 },
            yaw = 180.0,
            scale = { x = 0.55, y = 0.55, z = 0.13 },
        },
        {
            location = { x = -3560.0, y = 50.0, z = 310.0 },
            yaw = 90.0,
            scale = { x = 0.55, y = 0.55, z = 0.13 },
        },
    },

    -- Sommet du plateau : pivot z=310 + feutre z=76.
    revolver_home = { x = -3440.0, y = 50.0, z = 386.0 },
}
