-- Constantes de gameplay partagees client/serveur.
--
-- Ce fichier part chez le client : rien ici ne doit etre secret, et le serveur ne doit
-- jamais faire confiance a une valeur que le client pourrait avoir modifiee de son cote.
-- La configuration serveur (base, intervalles de flush) vit dans Server/core/config.lua.

return {
    -- Arme posee en 3D au vestiaire (Client/vestiaire/vestiaire.lua), devant
    -- la camera fixe : a `distance` cm, remontee de `hauteur` cm pour flotter
    -- au-dessus de l'eventail. Les modeles font 100 cm de long a l'import,
    -- `echelle` les met a la taille voulue a l'ecran. Rotation en degres/s.
    vestiaire = {
        arme = { distance = 150, hauteur = 30, echelle = 1.05, vitesse = 35, inclinaison = -8 },
    },

    -- Arme vue par le tireur en premiere personne (Client/duel/duel.lua) :
    -- posee devant la camera, en cm (avant, droite, bas) ; `rotation` corrige
    -- l'orientation du modele (le canon est le long de -X a l'export).
    duel_arme = {
        avant = 38, droite = 16, bas = 15,
        rotation = { p = 0, y = 180, r = 0 },
        recul = 6, retour_ms = 90,
        recul_camera = 1.4,           -- degres de tangage par tir
        -- Inertie en marchant : l'arme glisse a l'oppose du mouvement
        -- (cm par cm/s) puis revient, lissee.
        balancement = 0.006, lissage = 8,
        -- Inclinaison quand le regard monte ou descend : degres par degre/s,
        -- bornee a inclinaison_max.
        inclinaison = 0.02, inclinaison_max = 3,
        -- Distance a plat (cm) au-dela de laquelle une mesure de la camera n'est
        -- pas celle de la premiere personne et n'ancre pas l'arme.
        ancrage_max = 60,
    },

    -- Musique du duel : volume (0-1) et fondus en secondes.
    duel_musique = { volume = 0.22, fondu_entree = 3, fondu_sortie = 3.5 },

    -- Trainee d'un tir de duel : longueur du trait (cm), ecart depuis le canon,
    -- epaisseur (echelle du cube de 100 cm), opacite, vitesse d'avance (cm/s).
    duel_trainee = { longueur = 140, ecart = 60, epaisseur = 0.006, opacite = 0.45, vitesse = 30000 },

    -- Contour au sol des arenes de duel (Client/duel/contour.lua) : des
    -- decalques projetes vers le bas depuis `hauteur` cm au-dessus du sol de
    -- l'arene, sur `profondeur` cm, pour epouser les dunes. La doc Decal ne
    -- dit pas si la taille est une demi-taille : a regler en jeu.
    duel_contour = {
        largeur = 14, hauteur = 250, profondeur = 600, pas = 180,
        couleur = { r = 0.72, g = 0.52, b = 0.16 },
        materiau = "nanos-world::M_Default_Translucent_Lit_Decal",
        duree = 86400,
    },

    interaction = {
        -- Portee de la visee, en centimetres. Plus longue que la portee serveur :
        -- on peut lire l'invite d'un peu plus loin qu'on ne peut agir.
        reach = 400.0,
        -- Quand la trace ne touche rien d'interactif, l'objet connu le plus
        -- proche de l'axe du regard dans ce demi-angle, en degres.
        cone_degrees = 10.0,
        -- Periode du balayage. Viser n'a pas besoin de 60 traces par seconde.
        scan_interval_ms = 150,
        key = "E",
    },

    -- HUD provisoire de Liar's Bar (Client/liars_bar/). Noms de touches de la
    -- doc Input. Pas Enter pour poser : il risque de servir au chat.
    liars_hud = {
        journal_lines = 8,
        -- Miroir du plafond serveur (games/liars_bar/data/config.lua), qui
        -- seul fait foi : ici il ne sert qu'a ne pas proposer l'impossible.
        max_play = 3,
        -- Miroirs du serveur eux aussi, pour l'affichage seulement : cartes
        -- recues a chaque donne, et chambres du barillet.
        hand_size = 5,
        chambers  = 6,
        keys = {
            -- Une liste de noms par carte, le premier sert d'etiquette dans le
            -- HUD. Des lettres plutot que des chiffres : Unreal nomme une touche
            -- d'apres le caractere qu'elle tape, et en AZERTY la touche 1 tape
            -- "&". Une lettre porte le meme nom sur tous les claviers.
            select = { { "W" }, { "X" }, { "C" }, { "V" }, { "B" } },
            -- E pose les cartes choisies, R accuse le joueur precedent (26/09 :
            -- une seule touche pour les deux prenait l'un pour l'autre).
            play   = "E",
            accuse = "R",
        },
        -- Tangage de la camera au-dela duquel son propre barillet s'affiche en
        -- haut de l'ecran.
        tangage_barillet = 14,
        -- Revolver de celui qui doit tirer (liars_bar/surbrillance.lua) :
        -- couleur laiton, intensite (x5 et plus : ca brille, doc Client), slot.
        surbrillance = { couleur = { r = 1.0, g = 0.72, b = 0.25 }, intensite = 3, index = 1 },
        -- Coup fatal (liars_bar/mort.lua) : secousse (s, degres), bascule de la
        -- camera vers la gauche (s, degres ; roulis negatif : penche a gauche),
        -- voile noir tenu jusqu'a la fin de la partie (0 a 1).
        mort = {
            secousse = { duree = 0.45, amplitude = 7 },
            bascule = { duree = 0.9, tangage = -22, lacet = -18, roulis = -28 },
            voile = 0.35,
        },
    },

    -- Sons de Liar's Bar (Client/liars_bar/sons.lua), fichiers de
    -- Client/Sounds/ (hors depot). menteur : crie a chaque accusation ; vide
    -- tant que le fichier n'est pas la (un mp3 se convertit en ogg).
    -- musique : jouee en boucle tant qu'on est assis a la table (salon et
    -- partie), tres bas, en fondu (secondes).
    -- Cycle jour/nuit accelere hors loup-garou (Client/loup_garou/ciel.lua),
    -- le meme pour tous : secondes de jour (6h a 20h) et de nuit (20h a 6h).
    cycle = { jour = 600, nuit = 300, decalage = 0 },

    -- Chutes (Server/domain/chutes.lua) : vitesse de chute a l'arrivee (cm/s)
    -- qui fait encaisser durement, puis s'ecraser au sol. 750 cm/s, c'est
    -- ~3,2 m de chute ; 1400, ~11 m. Duree en secondes (immobilise pendant),
    -- fondu de sortie = le relevement. actif = false tant que les animations
    -- ne sont pas cuites (scripts/unreal/import_chutes.py).
    chutes = {
        actif = true,     -- animations cuites le 27/09
        seuil_dure = 750,         -- ~3,2 m (900 le 27/09 : trop haut)
        seuil_sol = 1400,
        dure = { anim = "my-asset-pack::ANIM_Chute_Reception", duree = 1.93, fondu_sortie = 0.3 },
        sol = { anim = "my-asset-pack::ANIM_Chute_Au_Sol", duree = 2.77, fondu_sortie = 0.9 },
    },

    -- Bruits du corps et musique de la place (Client/bruits.lua) : pas, cri au
    -- saut, reception apres une chute, musique hors des jeux. Volumes de 0 a
    -- 1 ; musique = false la coupe.
    bruits = {
        musique = "musique_place",
        -- Pas discrets : trop forts et trop rapproches le 27/09.
        volumes = { marche = 0.07, course = 0.11, cri = 0.15, reception = 0.25, musique = 0.06 },
        foulee_marche = 85, foulee_course = 170,   -- cm entre deux pas
        seuil_saut = 330,                          -- cm/s, le saut part a 400
        seuil_cri = 350,                           -- cm de vide sous les pieds pour crier
    },

    liars_sons = {
        menteur = "", volume_menteur = 0.9,
        musique = "musique_liars.ogg", volume_musique = 0.08,
        fondu_entree = 4, fondu_sortie = 3,
    },

    -- HUD du Loup-Garou (Client/loup_garou/hud.lua) : portee des marques
    -- au-dessus des tetes (cm) et demi-angle de visee pour designer (degres).
    loup_garou = {
        portee = 1500, cone = 10,
        -- Cartes de role au sol (Client/loup_garou/cartes.lua), en cm ; tourner :
        -- degres a ajouter si le dessin apparait de travers.
        -- modele3d : la carte a coins arrondis et epaisseur (SM_WW_RoleCard),
        -- a passer a true une fois importee et cuite ; sinon une carte plate.
        cartes = { largeur = 32, hauteur = 48, tourner = 0, modele3d = true },   -- 60 x 90 : trop grandes
        -- Sons (Client/loup_garou/sons.lua, fichiers dans Client/Sounds/loup_garou/).
        sons = { volumes = { ambiance = 0.18, lg_jour = 0.04, sons = 0.6, coeur = 0.35 } },
    },

    -- Pseudos au-dessus des personnages (Client/pseudos.lua) : portee (cm),
    -- hauteur au-dessus de la tete (cm), delai entre deux verifications de mur
    -- (ms). Taille de l'ecriture : Client/ui/pseudo.lua.
    pseudos = { portee = 1500, au_dessus = 30, verif_vue_ms = 200 },

    -- Petites marches (Client/marche.lua) : hauteur la plus haute montee sans
    -- sauter (cm), temps du glissement sur la marche (s), delai entre deux
    -- (s), portee du rebord devant le bord de la capsule (cm), marges du
    -- glissement au-dessus de la marche et au-dela du rebord (cm).
    -- Glissement tres court et presque sans marge en hauteur : plus long ou plus
    -- haut, l'animation de marche repartait a zero a chaque marche (27/09).
    -- Reduit fortement le 27/09 : sur les petits objets, le glissement donnait
    -- des retours en arriere et des deplacements bizarres.
    marche = { hauteur_max = 25, glisse = 0.03, glisse_max = 0.06, delai = 0.2, portee = 12,
        anticipation = 0.05, marge_haut = 2, marge_avant = 5 },

    -- Roue d'emotes (Client/emotes.lua, Server/domain/emotes.lua). T ouvre la
    -- roue, puis 1 a 7 choisit une danse sur QWERTY, AZERTY ou pave numerique.
    -- Les apercus sont dans Client/emotes/img/, hors depot.
    emotes = {
        touche = "T",
        chiffres = {
            { "One", "Ampersand", "NumPadOne" },
            { "Two", "E_AccentAigu", "NumPadTwo" },
            { "Three", "Quote", "NumPadThree" },
            { "Four", "Apostrophe", "NumPadFour" },
            { "Five", "LeftParantheses", "NumPadFive" },
            { "Six", "Hyphen", "NumPadSix" },
            { "Seven", "E_AccentGrave", "NumPadSeven" },
        },
        fenetre = 4,   -- secondes avant que la roue se referme seule
        liste = {
            { titre = "Step Hip Hop", anim = "my-asset-pack::ANIM_Dance_StepHipHop", apercu = "step", boucle = true },
            { titre = "Chicken",      anim = "my-asset-pack::ANIM_Dance_Chicken", apercu = "chicken", boucle = true },
            { titre = "Wave Hip Hop", anim = "my-asset-pack::ANIM_Dance_WaveHipHop", apercu = "wave", boucle = true },
            { titre = "Tut Hip Hop",  anim = "my-asset-pack::ANIM_Dance_TutHipHop", apercu = "tut", boucle = true },
            { titre = "Booty Hip Hop",anim = "my-asset-pack::ANIM_Dance_BootyHipHop", apercu = "booty", boucle = true },
            { titre = "Salsa",        anim = "my-asset-pack::ANIM_Dance_Salsa", apercu = "salsa", boucle = true },
            { titre = "Jazz",         anim = "my-asset-pack::ANIM_Dance_Jazz", apercu = "jazz", boucle = true },
        },
    },

    -- Mouvement de la tete des joueurs assis (Client/vue_assise.lua,
    -- Client/regard_assis.lua, borne aussi par le serveur) : bornes en degres,
    -- gain (la tete tourne un peu plus que la camera, pour se lire de loin)
    -- et part du cou et de la tete.
    -- Poses du loup-garou : degres ajoutes au regard, par animation (positif :
    -- la tete se releve), chaque pose penchant la tete a sa facon ;
    -- decalage_loup_garou pour une pose absente de la liste. Valeurs estimees,
    -- a regler en jeu avec /lg regard <degres> (mode dev).
    regard_assis = { lacet_max = 70, tangage_max = 35, gain = 1.3, cou = 0.4, tete = 0.6,
        decalage_loup_garou = 0,
        marge_poses = 50,    -- degres de plus permis au-dela de tangage_max pour ces decalages
        poses_loup_garou = {
            ["my-asset-pack::ANIM_WW_Sitting_Idle"] = 20,
            ["my-asset-pack::ANIM_WW_Sitting_Idle_Mirror"] = 20,  -- miroir de la precedente
            ["my-asset-pack::ANIM_WW_Sitting_Idle_Glance"] = 20,
            ["my-asset-pack::ANIM_WW_Sitting_Dazed"] = 30,        -- tete tres basse
            ["my-asset-pack::ANIM_WW_Sitting_Idle_Lazy"] = -40,   -- adosse, tete en arriere
            ["my-asset-pack::ANIM_WW_Sitting_Idle_Shift"] = -40,  -- meme pose adossee
        },
    },

    -- Cartes 3D de Liar's Bar (Client/liars_bar/rendu.lua). L'echelle et les
    -- axes du FBX des cartes sont inconnus : tout se regle en jeu avec /fan,
    -- ces valeurs ne sont que des points de depart. Rotations en degres,
    -- { p = tangage, y = lacet, r = roulis }, distances en cm.
    liars_cards = {
        pack       = "my-asset-pack",
        -- Le jeu de 52 n'a pas de Joker : le Valet, qui ne sert pas ici, le
        -- remplace sans confusion possible.
        joker_mesh = "my-asset-pack::Jack_of_Spades1",
        -- Le dos est le meme pour toutes les cartes : n'importe laquelle,
        -- retournee, fait une carte face cachee sans rien reveler.
        back_mesh  = "my-asset-pack::Ace_of_Spades1",
        -- Support invisible de l'eventail et de chaque fente.
        pivot_mesh = "nanos-world::SM_Cube",
        -- Os qui tient l'eventail : squelette Creative, puis mannequin nanos.
        -- Pas RightHandProp / LeftHandProp : ces os ne suivent pas les
        -- animations, les cartes flottaient. /fan os <nom> pour essayer.
        bone_simple    = "LeftHand",
        bone_mannequin = "hand_r",
        -- Garder la main en texte dans le HUD tant que l'eventail n'est pas
        -- valide en jeu.
        -- La main s'affiche en HUD (liars_bar/hud.lua), avec les images des
        -- cartes rangees en fichiers dans le pack d'assets : 14 jpg du jeu de
        -- 52, copies dans Assets/my-asset-pack/HUD/Cartes (hors depot).
        images = "assets://my-asset-pack/HUD/Cartes",
        -- Cartes 3D dans les mains, rallumees le 26/09 sur l'os de la main.
        en_main = true,

        -- Bordure blanche des cartes choisies en main (rendu.lua) : largeur du
        -- liseré autour de la carte (cm) et materiau (sans eclairage : blanc pur).
        contour_choisie = { marge = 0.35, materiau = "nanos-world::M_Default_Masked_Unlit" },

        -- Cartes plates : nos dessins (scripts/cartes/cartes.html, copies dans
        -- Client/liars_bar/cartes/) sur deux SM_Plane dos a dos, a la place des
        -- modeles du jeu de 52. rot, rot_dos : les plaques face et dos dans le
        -- repere de la carte (face traversee par Y, hauteur Z). Reglees en jeu
        -- le 26/09 : face r -90 (normale -Y, vers le porteur) et p 180 (le
        -- dessin etait a l'envers), dos r 90. Le materiau est a deux faces : le
        -- dos est pose juste derriere la face (rendu.lua). /fan plaque face|dos p y r,
        -- /fan plaque retourner (echange les cotes), /fan plaque taille l h.
        plates = {
            actif     = true,
            images    = "package://fate-games/Client/liars_bar/cartes/",
            materiau  = "nanos-world::M_Default_Masked_Lit",
            largeur   = 5.9, hauteur = 8.9,   -- cm, comme les anciens modeles
            rot       = { p = 180, y = 0, r = -90 },
            rot_dos   = { p = 0, y = 0, r = 90 },
            retourner = false,
        },

        -- Mouvements des cartes (Client/liars_bar/rendu.lua), en secondes et cm :
        -- duree d'un vol, hauteur de l'arc, ecart entre deux cartes d'une meme
        -- donne, pose ou revelation, et fenetre ou une main qui se remplit fait
        -- venir ses cartes du centre.
        anim = {
            duree = 0.45, arc = 18,
            ecart_donne = 0.09, ecart_pose = 0.07, ecart_revelation = 0.12,
            fenetre_donne = 1.5,
            -- Pose : les cartes suivent la main dans ANIM_Seated_Card_Play (30
            -- images a 30 i/s, main sur la table des images 15 a 18), puis la
            -- quittent a `lacher` secondes et tombent sur le tas.
            lacher = 0.5, duree_lacher = 0.22, arc_lacher = 3, ecart_lacher = 0.04,
        },

        -- Centre de chaque carte par rapport a son pivot, en unites du FBX (le
        -- pivot est reste celui du fichier de 52 cartes : loin de la carte, et
        -- un y different pour chacune, l'empilement du paquet d'origine).
        -- Mesure dans l'ADK par scripts/unreal/export_cartes.py le 26/09 (les 52).
        -- Compense dans l'eventail et les vols, sinon chaque carte tourne
        -- autour d'un point a 32 cm d'elle.
        pivot_defaut = { x = -926.85, y = -50, z = 405.6 },
        pivots = {   -- les 13 modeles du jeu (As, Rois, Dames, Valet de pique = Joker)
            ["Ace_of_Clubs1"]      = { x = -926.85, y = -34.97, z = 405.6 },
            ["Ace_of_Diamonds1"]   = { x = -926.85, y = -36.34, z = 405.6 },
            ["Ace_of_Hearts1"]     = { x = -926.85, y = -37.70, z = 405.6 },
            ["Ace_of_Spades1"]     = { x = -926.85, y = -39.06, z = 405.6 },
            ["Jack_of_Spades1"]    = { x = -926.85, y = -60.22, z = 405.6 },
            ["King_of_Clubs1"]     = { x = -926.85, y = -61.68, z = 405.6 },
            ["King_of_Diamonds1"]  = { x = -926.85, y = -63.04, z = 405.6 },
            ["King_of_Hearts1"]    = { x = -926.85, y = -64.31, z = 405.6 },
            ["King_of_Spades1"]    = { x = -926.85, y = -65.58, z = 405.6 },
            ["Queen_of_Clubs1"]    = { x = -926.85, y = -72.36, z = 405.6 },
            ["Queen_of_Diamonds1"] = { x = -926.85, y = -73.64, z = 405.6 },
            ["Queen_of_Hearts1"]   = { x = -926.85, y = -75.09, z = 405.6 },
            ["Queen_of_Spades1"]   = { x = -926.85, y = -76.36, z = 405.6 },
        },

        fan = {
            -- Reglees en jeu le 26/09 sur les quatre chaises (/fan demo).
            pos        = { x = 3.7, y = -17.6, z = 9.0 },   -- carte du milieu, depuis l'os de la main
            rot        = { p = 32, y = 140, r = 26 },
            carte      = { p = 0, y = 0, r = 0 },   -- carte, dans sa fente
            axe        = "y",   -- la face est traversee par Y (epaisseur 0,6 sur 142 x 254)
            coin       = -2.2,  -- pivot pres du bord gauche (demi-largeur d'une carte : 2,5)
            sens       = -1,    -- sens de rotation, valide en jeu le 26/09 (/fan sens)
            empilement = 1,     -- quelle carte passe devant (/fan empilement)
            ecart      = 20,    -- degres entre deux cartes, dans leur plan (12 : trop serre)
            rayon      = 5,     -- du pivot (bas commun) au centre d'une carte :
                                -- la moitie de sa hauteur, les bases se touchent
            taille     = 0.035, -- le FBX est en pouces : 254 cm de haut, ramene a ~9 cm
            levee      = 4.5,   -- carte choisie (3 : pas assez, 26/09)
            curseur    = 1.5,   -- carte sous le curseur
            profondeur = 0.15,  -- empilement le long de la face, contre le scintillement
        },

        table = {
            decalage   = { x = 20, y = 0, z = 0.5 }, -- tas, depuis le centre du plateau
            -- La face est traversee par Y : un roulis de 90 couche la carte a
            -- plat. Si le tas montre ses faces, inverser : /fan dos 0 0 90 et
            -- /fan face 0 0 -90.
            dos        = { p = 0, y = 0, r = -90 },   -- carte face cachee
            face       = { p = 0, y = 0, r = 90 },    -- carte revelee
            echelle    = 2.1,   -- taille des cartes posees, par rapport a la main (1,8 : un peu petit)
            epaisseur  = 0.3,   -- entre deux cartes du tas
            dispersion = 7,     -- desordre autour du tas
            ecart_revelation = 14, -- entre deux cartes revelees (une carte fait 5,9 cm x echelle)
        },
    },

    scheduler = {
        -- duree d'un tour de roue : chaque entite inscrite est traitee une fois par tour
        wheel_seconds = 60,
        -- periode d'un tick ; le plus court utile est le tick rate serveur, ~33 ms
        tick_ms       = 1000,
    },
}
