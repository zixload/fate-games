-- Cartes 3D de Liar's Bar : quel modele, et ou le poser.
--
-- Pur : aucune globale nanos, donc testable hors jeu. rendu.lua s'en sert
-- pour creer et placer les objets. Les positions sont exprimees dans le
-- repere du support (pivot de l'eventail, centre du plateau) : c'est le
-- moteur qui compose ensuite les reperes par l'accrochage.

return function(config)
    local Cartes = {}

    local COULEURS = { "Clubs", "Diamonds", "Hearts", "Spades" }
    local VALEURS  = { king = "King", queen = "Queen", ace = "Ace" }

    -- Le modele d'une carte vue de face. Le Joker a son remplacant ; une
    -- valeur inconnue montre un dos, jamais une face au hasard.
    function Cartes.Mesh(rank, couleur)
        if rank == "joker" then return config.joker_mesh end
        local valeur = VALEURS[rank]
        if not valeur then return config.back_mesh end
        return ("%s::%s_of_%s1"):format(config.pack, valeur, COULEURS[couleur] or "Spades")
    end

    -- L'image d'une carte pour le HUD : un fichier du pack d'assets, lu par
    -- le Canvas (chemin "assets://", doc Basic Types > SpecialPath). Memes
    -- regles que Mesh : le Joker a son remplacant, l'inconnu montre un dos.
    function Cartes.Image(rank, couleur)
        local dossier = config.images
        if rank == "joker" then return dossier .. "/Jack_of_Spades.jpg" end
        local valeur = VALEURS[rank]
        if not valeur then return dossier .. "/Card_Back.jpg" end
        return ("%s/%s_of_%s.jpg"):format(dossier, valeur, COULEURS[couleur] or "Spades")
    end

    -- Carte i sur n de la main a l'ecran, en eventail : x du bas de la carte
    -- (centre), decalage vers le haut et angle en degres. hud : { largeur
    -- (d'une carte), ecart (fraction de largeur entre deux cartes), angle
    -- (degres entre deux cartes), courbure (pixels, pour la carte du bord) }.
    function Cartes.Main2D(n, i, hud)
        local rel = i - (n + 1) / 2
        local bord = math.max(1, (n - 1) / 2)
        return {
            x     = rel * hud.largeur * hud.ecart,
            y     = hud.courbure * (rel / bord) ^ 2,
            angle = rel * hud.angle,
        }
    end

    -- Une couleur par carte, pour le decor seulement : la regle ne connait
    -- que la valeur.
    function Cartes.Couleurs(n, rng)
        local out = {}
        for i = 1, n do out[i] = rng(#COULEURS) end
        return out
    end

    -- Fente i sur n de l'eventail, dans le repere du pivot. Une carte du FBX
    -- est a plat dans son plan XY, face vers +Z (posee sans rotation sur la
    -- table, elle montre sa face), sa hauteur le long de X. Comme dans une
    -- vraie main, les cartes tournent donc dans leur plan (lacet, autour de
    -- Z) autour d'un point commun, le pivot, et s'empilent le long de Z sans
    -- se traverser. rayon : du pivot au centre de la carte ; a la moitie de
    -- sa hauteur, les bases se rejoignent. La levee eloigne la carte du pivot.
    -- La carte du milieu reste a l'origine du support : le reglage de
    -- position (/fan pos) la place, l'eventail s'ouvre autour d'elle.
    function Cartes.Fente(n, i, fan, levee)
        local angle = (i - (n + 1) / 2) * fan.ecart
        local rad   = math.rad(angle)
        local r     = fan.rayon + (levee or 0)
        return {
            x   = math.cos(rad) * r - fan.rayon,
            y   = math.sin(rad) * r,
            z   = (i - 1) * fan.profondeur,
            yaw = angle,
        }
    end

    -- Carte k du tas du centre, relative au centre du plateau. Le desordre
    -- est tire du rang de la carte, pas du hasard : chaque client dessine le
    -- meme tas.
    function Cartes.Tas(k, tbl)
        local jx  = (((k * 37) % 11) - 5) / 5 * tbl.dispersion
        local jy  = (((k * 53) % 13) - 6) / 6 * tbl.dispersion
        local yaw = ((k * 71) % 60) - 30
        return {
            x   = tbl.decalage.x + jx,
            y   = tbl.decalage.y + jy,
            z   = tbl.decalage.z + (k - 1) * tbl.epaisseur,
            yaw = yaw,
        }
    end

    -- Carte revelee i sur n : alignees cote a cote, a cote du tas.
    function Cartes.Revelee(n, i, tbl)
        return {
            x   = tbl.decalage.x - 3 * tbl.ecart_revelation,
            y   = tbl.decalage.y + (i - (n + 1) / 2) * tbl.ecart_revelation,
            z   = tbl.decalage.z,
            yaw = 0,
        }
    end

    return Cartes
end
