-- Reglages du duel (docs/DUEL-ET-ARGENT.md). Distances en cm, temps en ms.

return {
    -- Mises proposees au premier arrive. 0 = duel pour l'honneur.
    paliers = { 0, 50, 100, 250 },
    -- Le format suit le nombre de joueurs dans l'arene : 2 -> 1v1, 4 -> 2v2.
    -- Un nombre impair attend un joueur de plus (ou de moins).
    max_joueurs = 4,
    manches_gagnantes = 2,        -- premier a deux manches
    bonus_participation = 10,     -- verse par la banque a chaque joueur en fin de duel

    decompte_ms   = 5000,          -- de quoi choisir son arme avant de partir
    entre_manches_ms = 3000,
    fin_ms        = 5000,         -- avant que l'arene se rouvre

    sante      = 100,
    degats     = 34,              -- trois balles au corps
    degats_tete = 70,
    chargeur   = 6,
    recharge_ms = 2000,
    cadence_ms = 350,             -- entre deux tirs, verifie par le serveur
    portee     = 6000,

    -- Les arenes se posent dans la map : cylindres DUEL_* lus par
    -- scripts/unreal/export_arenes.py (data/arenes.lua). /arene (dev) en ajoute
    -- une de test sous ses pieds, avec ce rayon par defaut.
    rayon_test = 900,
    -- Rayon autour de l'arene ou l'on peut regarder le duel.
    rayon_spectateurs = 2500,

    -- Murs invisibles poses sur le bord de l'arene pendant un duel : on bute
    -- dessus au lieu d'etre teleporte. Hauteur et epaisseur en cm.
    murs = { hauteur = 700, epaisseur = 40 },

    -- Eclairage de l'arene : lumieres ponctuelles en grille au-dessus du sol,
    -- chaudes, sans ombre (legeres). La doc ne donne pas l'unite d'intensite :
    -- a regler en jeu. enabled = false si la map eclaire deja l'arene.
    lumiere = {
        enabled = true,
        espacement = 1600,        -- cm entre deux lumieres
        hauteur = 320,            -- cm au-dessus du sol de l'arene
        intensite = 150,
        rayon = 1400,             -- portee de chaque lumiere, cm
        couleur = { r = 1.0, g = 0.84, b = 0.62 },
        ombres = false,
    },

    -- Bot de test (/botduel, mode dev) : cadence de tir et chance de toucher.
    -- vitesse : cm/s de ses pas de cote ; virage : degres/s pour se tourner.
    bot = { tir_min_ms = 900, tir_max_ms = 1500, precision = 0.35, pas_ms = 2500, pas = 220,
        vitesse = 160, virage = 360 },

    -- Camera du combat : premiere personne, yeux a cette hauteur (cm, depuis le
    -- bas du personnage), un peu en avant du visage. Valeurs validees en jeu
    -- pour la vue premiere personne de l'atelier, le 19/09.
    camera = { avant = 10, hauteur = 155 },

    -- Arme en main : os du squelette Creative, reglages a ajuster en jeu.
    arme = {
        os = "RightHandProp",
        position = { x = 0, y = 0, z = 0 },
        rotation = { p = 0, y = 0, r = 0 },
    },
}
