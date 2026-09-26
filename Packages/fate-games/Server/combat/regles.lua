-- Regles du combat (docs/COMBAT.md) : zones, types de degats, armures,
-- jauges, fenetres de defense. Temps en secondes, distances en cm. Un mode
-- peut surcharger n'importe quelle valeur (Combat.nouveau(config)).

local R = {}

-- Silhouette : proportions de la hauteur (depuis les pieds) et ecart a l'axe
-- (en part du rayon) au-dela duquel un coup au torse touche un bras.
R.silhouette = { tete = 0.84, jambes = 0.47, bras = 0.62, demi_hauteur = 90, rayon = 34 }

R.zones = { tete = 2.0, torse = 1.0, bras = 0.75, jambes = 0.8 }

R.types = { "tranchant", "perforant", "contondant", "balistique", "magique", "chute" }

-- Reduction des degats par armure et par type (0..1).
R.armures = {
    aucune  = { tranchant = 0,    perforant = 0,    contondant = 0,    balistique = 0,    magique = 0 },
    tissu   = { tranchant = 0.10, perforant = 0.05, contondant = 0.10, balistique = 0,    magique = 0.15 },
    cuir    = { tranchant = 0.25, perforant = 0.15, contondant = 0.15, balistique = 0.10, magique = 0.10 },
    mailles = { tranchant = 0.50, perforant = 0.20, contondant = 0.15, balistique = 0.20, magique = 0 },
    plaques = { tranchant = 0.65, perforant = 0.45, contondant = 0.10, balistique = 0.35, magique = 0 },
}
-- Une armure pese : multiplicateur de vitesse et surcout d'endurance.
R.poids_armures = {
    aucune = { vitesse = 1.0, endurance = 1.0 }, tissu = { vitesse = 1.0, endurance = 1.0 },
    cuir = { vitesse = 0.97, endurance = 1.05 }, mailles = { vitesse = 0.92, endurance = 1.15 },
    plaques = { vitesse = 0.85, endurance = 1.3 },
}

R.combattant = {
    sante = 100, endurance = 100, posture = 100, mana = 100,
    -- Recuperation par seconde, apres un delai sans effort.
    endurance_regen = 28, endurance_delai = 0.9, endurance_regen_garde = 0.4,
    posture_regen = 18, posture_delai = 1.4,
    mana_regen = 6,
    sprint_cout = 9,               -- endurance par seconde
}

R.defense = {
    parade = 0.18,                 -- garde posee au plus tant de temps avant l'impact
    garde_demi_angle = 70,         -- l'attaquant doit etre devant, a moins de tant de degres
    bouclier_demi_angle = 85,
    esquive_invulnerable = 0.25,
    esquive_duree = 0.55,
    esquive_cout = 22,
    esquive_distance = 260,        -- cm, applique par l'adaptateur
    feinte_cout = 12,
    feinte_jusqua = 0.75,          -- part de l'armement pendant laquelle on peut encore feinter
    parade_posture = 38,           -- posture infligee a l'attaquant pare
    parade_expose = 0.7,           -- l'attaquant pare ne peut rien faire pendant tant de secondes
    parade_rendue = 10,            -- endurance rendue au defenseur qui pare
}

R.etats = {
    garde_brisee_etourdi = 1.3,
    vulnerable = 3.0, vulnerable_mult = 1.5,
    recul_touche = 0.35,           -- un coup encaisse interrompt l'armement (pas les lourdes)
    jambes_ralenti = { duree = 1.2, vitesse = 0.65 },
    tete_etourdi = 0.8,            -- coup contondant lourd a la tete
    saignement = { duree = 5, dps = 2.2 },
    brulure = { duree = 4, dps = 3 },
    interruption_sort = 12,        -- degats a partir desquels une incantation est coupee
}

R.a_terre = {
    actif = false,                 -- les modes RP l'activent
    saignement = 35,               -- secondes avant de mourir a terre
    relever = 4,                   -- secondes a rester pres de lui sans etre touche
    distance = 160,                -- cm pour relever ou achever
    sante_relevee = 25,
}

R.tir = {
    latence_max = 0.25,            -- compensation de latence plafonnee
    historique = 0.6,              -- secondes de positions gardees
    oeil = { z = 62, tolerance = 90 }, -- l'origine d'un tir doit etre pres des yeux
    tir_ami = false,
}

R.intentions_min = 0.05            -- deux intentions plus rapprochees : la seconde est ignoree

return R
