-- Archetypes d'armes (docs/COMBAT.md). En PvP, une arme achetee n'est qu'une
-- apparence qui pointe vers un de ces archetypes : memes chiffres pour tous.
--
-- Corps a corps : deux attaques (legere, lourde), chacune en trois temps
-- (armement, frappe, recuperation, en secondes), avec ses degats, son type,
-- son cout d'endurance et la posture qu'elle inflige. `portee` en cm (du
-- centre de l'attaquant au bord de la cible), `demi_angle` en degres.
-- `poids` : une attaque lourde ne se pare pas avec une arme legere.
-- `portee_min` : en deca, l'arme ne touche pas (la lance a bout portant).
-- `mobilite` : multiplicateur de vitesse de deplacement (lege, on bouge vite).
-- `interrompt_lourdes` : ses coups coupent aussi les lourdes en armement.
-- Les armements (0,35 a 0,55 s pour une legere) laissent le temps de lire le
-- coup : un humain reagit en 0,25 s environ.
-- `garde` : ce qui traverse une garde (part des degats), et combien de
-- posture et d'endurance la garde coute (multiplicateurs).
--
-- Tir : degats par balle, cadence (s entre deux tirs), chargeur, recharge,
-- portee, baisse avec la distance (`chute`), dispersion en degres.
-- Arc : projectile simule par le serveur ; plus on bande, plus il part vite
-- et fort.

local A = {}

local function melee(t) t.famille = "melee" return t end

A.poings = melee {
    mobilite = 1.12, nom = "Poings", mains = 2, poids = "leger", portee = 110, demi_angle = 40,
    legere = { degats = 7, type = "contondant", armement = 0.35, frappe = 0.12, recuperation = 0.25, endurance = 6, posture = 10 },
    lourde = { degats = 14, type = "contondant", armement = 0.7, frappe = 0.15, recuperation = 0.5, endurance = 14, posture = 28 },
    garde = { traverse = 0.5, posture = 1.3, endurance = 1.2 },
}

A.dague = melee {
    mobilite = 1.1, nom = "Dague", mains = 1, poids = "leger", portee = 130, demi_angle = 35, penetration = 0.3,
    interrompt_lourdes = true,       -- un coup d'estoc coupe meme un grand moulinet
    legere = { degats = 14, type = "perforant", armement = 0.35, frappe = 0.1, recuperation = 0.2, endurance = 7, posture = 10 },
    lourde = { degats = 28, type = "perforant", armement = 0.65, frappe = 0.12, recuperation = 0.5, endurance = 16, posture = 18, saignement = true },
    garde = { traverse = 0.35, posture = 1.2, endurance = 1.1 },
}

A.epee_courte = melee {
    mobilite = 1.03, nom = "Épée courte", mains = 1, poids = "leger", portee = 160, demi_angle = 55,
    legere = { degats = 16, type = "tranchant", armement = 0.42, frappe = 0.14, recuperation = 0.3, endurance = 9, posture = 14 },
    lourde = { degats = 30, type = "tranchant", armement = 0.8, frappe = 0.16, recuperation = 0.55, endurance = 18, posture = 30, saignement = true },
    garde = { traverse = 0.15, posture = 1.0, endurance = 1.0 },
}

A.epee_longue = melee {
    mobilite = 0.97, nom = "Épée longue", mains = 2, poids = "moyen", portee = 200, demi_angle = 60,
    legere = { degats = 20, type = "tranchant", armement = 0.5, frappe = 0.16, recuperation = 0.38, endurance = 12, posture = 18 },
    lourde = { degats = 40, type = "tranchant", armement = 0.95, frappe = 0.18, recuperation = 0.7, endurance = 24, posture = 40, saignement = true },
    garde = { traverse = 0.1, posture = 0.9, endurance = 0.9 },
}

A.hache = melee {
    mobilite = 0.93, nom = "Hache", mains = 2, poids = "lourd", portee = 175, demi_angle = 75, penetration = 0.15,
    legere = { degats = 22, type = "tranchant", armement = 0.55, frappe = 0.16, recuperation = 0.45, endurance = 14, posture = 24 },
    lourde = { degats = 46, type = "tranchant", armement = 1.1, frappe = 0.2, recuperation = 0.85, endurance = 28, posture = 55, saignement = true },
    garde = { traverse = 0.2, posture = 1.1, endurance = 1.0 },
}

A.masse = melee {
    mobilite = 0.94, nom = "Masse", mains = 1, poids = "lourd", portee = 165, demi_angle = 60,
    legere = { degats = 20, type = "contondant", armement = 0.55, frappe = 0.16, recuperation = 0.45, endurance = 14, posture = 26 },
    lourde = { degats = 42, type = "contondant", armement = 1.1, frappe = 0.2, recuperation = 0.85, endurance = 28, posture = 65 },
    garde = { traverse = 0.2, posture = 1.1, endurance = 1.0 },
}

A.lance = melee {
    -- Longue et etroite ; inutile a bout portant : rentrer dans sa garde la contre.
    mobilite = 0.96, nom = "Lance", mains = 2, poids = "moyen", portee = 290, portee_min = 100, demi_angle = 18, penetration = 0.35,
    legere = { degats = 16, type = "perforant", armement = 0.48, frappe = 0.15, recuperation = 0.4, endurance = 11, posture = 14 },
    lourde = { degats = 36, type = "perforant", armement = 0.9, frappe = 0.18, recuperation = 0.7, endurance = 22, posture = 30 },
    garde = { traverse = 0.15, posture = 1.0, endurance = 1.0 },
}

A.epee_bouclier = melee {
    mobilite = 0.95, nom = "Épée et bouclier", mains = 1, poids = "moyen", portee = 175, demi_angle = 55,
    legere = { degats = 16, type = "tranchant", armement = 0.42, frappe = 0.14, recuperation = 0.32, endurance = 9, posture = 14 },
    -- La lourde est un coup de bouclier : peu de degats, beaucoup de posture.
    lourde = { degats = 22, type = "contondant", armement = 0.75, frappe = 0.16, recuperation = 0.5, endurance = 18, posture = 48 },
    garde = { traverse = 0, posture = 0.8, endurance = 1.0, bouclier = true },
}

A.baton = melee {
    mobilite = 1.0, nom = "Bâton", mains = 2, poids = "moyen", portee = 230, demi_angle = 70, focus = 0.8,
    legere = { degats = 14, type = "contondant", armement = 0.45, frappe = 0.15, recuperation = 0.35, endurance = 10, posture = 20 },
    lourde = { degats = 28, type = "contondant", armement = 0.85, frappe = 0.18, recuperation = 0.6, endurance = 20, posture = 45 },
    garde = { traverse = 0.15, posture = 0.9, endurance = 0.9 },
}

local function tir(t) t.famille = "tir" t.type = t.type or "balistique" return t end

A.pistolet = tir {
    nom = "Pistolet", mains = 1, degats = 24, cadence = 0.3, chargeur = 12, recharge = 1.6, portee = 5000,
    chute = { debut = 1500, fin = 4000, min = 0.6 },
    dispersion = { base = 0.6, mouvement = 2.5, visee = 0.25, accroupi = 0.7 },
}

A.revolver = tir {
    nom = "Revolver", mains = 1, degats = 38, cadence = 0.55, chargeur = 6, recharge = 2.2, portee = 6000,
    chute = { debut = 2000, fin = 5000, min = 0.65 },
    dispersion = { base = 0.5, mouvement = 3, visee = 0.2, accroupi = 0.7 },
}

A.fusil = tir {
    nom = "Fusil d'assaut", mains = 2, degats = 30, cadence = 0.11, chargeur = 30, recharge = 2.4, portee = 9000, auto = true,
    chute = { debut = 3000, fin = 8000, min = 0.7 },
    dispersion = { base = 0.8, mouvement = 3.5, visee = 0.35, accroupi = 0.7, rafale = 0.15 },
}

A.fusil_pompe = tir {
    nom = "Fusil à pompe", mains = 2, degats = 11, plombs = 8, cone = 4.5, cadence = 0.9, chargeur = 6, recharge = 2.8, portee = 2600,
    chute = { debut = 600, fin = 2200, min = 0.25 },
    dispersion = { base = 0, mouvement = 1, visee = 0, accroupi = 1 },
}

A.fusil_precision = tir {
    nom = "Fusil de précision", mains = 2, degats = 80, cadence = 1.4, chargeur = 5, recharge = 3.0, portee = 20000,
    chute = { debut = 20000, fin = 20000, min = 1 },
    dispersion = { base = 4, mouvement = 8, visee = 0, accroupi = 0.5 },
}

local function arc(t) t.famille = "arc" t.type = "perforant" return t end

A.arc = arc {
    nom = "Arc", mains = 2, degats_min = 12, degats_max = 46, charge = 1.1, fatigue_apres = 4, fatigue_cout = 10,
    vitesse_min = 2500, vitesse_max = 6500, gravite = 0.6, rayon = 6, endurance = 8, penetration = 0.2, duree = 4,
}

A.arbalete = arc {
    nom = "Arbalète", mains = 2, degats_min = 55, degats_max = 55, charge = 0, recharge = 2.6,
    vitesse_min = 7500, vitesse_max = 7500, gravite = 0.35, rayon = 5, endurance = 4, penetration = 0.4, duree = 4,
}

-- Le motif des plombs d'un fusil a pompe est fixe (pas de hasard) : un
-- cercle autour du centre, en part du cone.
A.motif_plombs = {
    { 0, 0 }, { 0.5, 0 }, { -0.5, 0 }, { 0, 0.5 }, { 0, -0.5 },
    { 0.85, 0.5 }, { -0.85, 0.5 }, { 0.85, -0.5 }, { -0.85, -0.5 }, { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 },
}

return A
