-- Reglages du duel (docs/DUEL-ET-ARGENT.md). Distances en cm, temps en ms.

return {
    -- Mises proposees au premier arrive. 0 = duel pour l'honneur.
    paliers = { 0, 50, 100, 250 },
    formats = { 1, 2 },           -- joueurs par camp : 1v1 ou 2v2
    manches_gagnantes = 2,        -- premier a deux manches
    bonus_participation = 10,     -- verse par la banque a chaque joueur en fin de duel

    decompte_ms   = 3000,
    entre_manches_ms = 3000,
    fin_ms        = 5000,         -- avant que l'arene se rouvre

    sante      = 100,
    degats     = 34,              -- trois balles au corps
    degats_tete = 70,
    chargeur   = 6,
    recharge_ms = 2000,
    cadence_ms = 350,             -- entre deux tirs, verifie par le serveur
    portee     = 6000,

    -- L'arene : un cercle au sol. /arene (dev) la pose sous ses pieds et
    -- affiche les valeurs a recopier ici.
    arene = {
        x = 0, y = 0, z = 0,
        rayon = 900,
        yaw = 0,                  -- axe sur lequel les deux camps se font face
        placee = false,           -- faux tant qu'elle n'a pas ete posee
    },
    -- Rayon autour de l'arene ou l'on peut regarder le duel.
    rayon_spectateurs = 2500,

    -- Arme en main : os du squelette Creative, reglages a ajuster en jeu.
    arme = {
        os = "RightHandProp",
        position = { x = 0, y = 0, z = 0 },
        rotation = { p = 0, y = 0, r = 0 },
    },
}
