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
    },

    -- Trainee d'un tir de duel : longueur du trait (cm), ecart depuis le canon,
    -- epaisseur (echelle du cube de 100 cm), opacite, duree.
    duel_trainee = { longueur = 140, ecart = 60, epaisseur = 0.006, opacite = 0.45, duree_ms = 45 },

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
            play   = "P",
            accuse = "M",
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
        bone_simple    = "RightHandProp",
        bone_mannequin = "hand_r",
        -- Garder la main en texte dans le HUD tant que l'eventail n'est pas
        -- valide en jeu.
        -- La main s'affiche en HUD (liars_bar/hud.lua), avec les images des
        -- cartes rangees en fichiers dans le pack d'assets : 14 jpg du jeu de
        -- 52, copies dans Assets/my-asset-pack/HUD/Cartes (hors depot).
        images = "assets://my-asset-pack/HUD/Cartes",
        -- Cartes 3D dans les mains : coupees pour le moment (19/09), l'os
        -- RightHandProp n'est pas anime. Le tas de la table reste en 3D.
        en_main = false,

        fan = {
            pos        = { x = 0, y = 0, z = 0 },   -- pivot, depuis l'os de la main
            rot        = { p = 0, y = 0, r = 0 },
            carte      = { p = 0, y = 0, r = 0 },   -- carte, dans sa fente
            ecart      = 8,     -- degres entre deux cartes
            rayon      = 10,    -- rayon de l'arc
            taille     = 0.035, -- le FBX est en pouces : 254 cm de haut, ramene a ~9 cm
            levee      = 3,     -- carte choisie
            curseur    = 1.5,   -- carte sous le curseur
            profondeur = 0.2,   -- decalage entre deux cartes, contre le scintillement
        },

        table = {
            decalage   = { x = 20, y = 0, z = 0.5 }, -- tas, depuis le centre du plateau
            dos        = { p = 0, y = 0, r = 180 },   -- carte face cachee
            face       = { p = 0, y = 0, r = 0 },     -- carte revelee
            epaisseur  = 0.3,   -- entre deux cartes du tas
            dispersion = 4,     -- desordre autour du tas
            ecart_revelation = 7,  -- entre deux cartes revelees
        },
    },

    scheduler = {
        -- duree d'un tour de roue : chaque entite inscrite est traitee une fois par tour
        wheel_seconds = 60,
        -- periode d'un tick ; le plus court utile est le tick rate serveur, ~33 ms
        tick_ms       = 1000,
    },
}
