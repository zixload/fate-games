-- Sorts (docs/COMBAT.md). Chaque sort : cout en mana, incantation (s, coupee
-- si l'on encaisse fort), recharge (s), forme et effet.
--
-- Formes :
--   projectile : part des yeux, vitesse (cm/s), rayon (cm), gravite (0 : droit)
--   cone       : devant soi, portee et demi-angle
--   ligne      : instantane, premier touche sur la portee
--   soi        : sur le lanceur
--   allie      : un allie vise a portee (ou soi si aucun)

local S = {}

S.trait_de_feu = {
    nom = "Trait de feu", mana = 22, incantation = 0.6, recharge = 1.5, forme = "projectile",
    vitesse = 3200, rayon = 22, gravite = 0, duree = 3,
    degats = 24, type = "magique", statut = "brulure", posture = 12,
}

S.onde_de_choc = {
    nom = "Onde de choc", mana = 30, incantation = 0.45, recharge = 6, forme = "cone",
    portee = 450, demi_angle = 55, degats = 8, type = "magique", posture = 55, repousse = 520,
}

S.eclair = {
    nom = "Éclair", mana = 40, incantation = 0.9, recharge = 8, forme = "ligne",
    portee = 1400, degats = 42, type = "magique", posture = 25, etourdi = 0.4,
}

S.gel = {
    nom = "Gel", mana = 25, incantation = 0.7, recharge = 5, forme = "projectile",
    vitesse = 2600, rayon = 26, gravite = 0, duree = 3,
    degats = 10, type = "magique", statut = "gel", posture = 8,
}

S.soin = {
    nom = "Soin", mana = 35, incantation = 1.2, recharge = 10, forme = "allie", portee = 900,
    soin = 40, duree_soin = 5, arrete = { "saignement", "brulure" },
}

S.barriere = {
    nom = "Barrière", mana = 30, incantation = 0.35, recharge = 14, forme = "soi",
    absorbe = 45, duree = 5,
}

S.bond = {
    nom = "Bond", mana = 18, incantation = 0.1, recharge = 7, forme = "soi", bond = 600,
}

-- Statuts poses par les sorts (duree en s, ralenti : multiplicateur de vitesse).
S.statuts = {
    gel = { duree = 2.5, vitesse = 0.45 },
}

return S
