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

    -- Comme dans une vraie main : les cartes tournent dans leur plan autour
    -- d'un point commun pres du coin bas gauche, chacune un peu plus que la
    -- precedente et posee devant elle, si bien que le bord gauche de chaque
    -- carte (et son indice) reste visible.
    --
    -- Dans le plan de la carte : u le long de sa largeur, v de sa hauteur,
    -- d le long de son epaisseur. fan.coin : ou est le pivot en largeur (cm
    -- depuis le centre, negatif = a gauche) ; fan.rayon : du pivot au centre
    -- en hauteur. fan.sens et fan.empilement (1 ou -1) : sens de rotation et
    -- quelle carte passe devant, selon la face du modele tournee vers soi.
    -- La carte du milieu reste a l'origine du support : /fan pos la place.
    --
    -- L'axe qui traverse la face depend du FBX (fan.axe, /fan axe) :
    --   axe  pivote autour de   hauteur le long de   largeur le long de
    --   y    Y (tangage)        Z                    X
    --   z    Z (lacet)          X                    Y
    --   zy   Z (lacet)          Y                    X
    --   x    X (roulis)         Z                    Y
    local AXES = {
        -- (u, v, d, angle) -> x, y, z, tangage, lacet, roulis
        y  = function(u, v, d, a) return u, d, v, a, 0, 0 end,
        z  = function(u, v, d, a) return v, -u, d, 0, a, 0 end,
        zy = function(u, v, d, a) return u, v, d, 0, a, 0 end,
        x  = function(u, v, d, a) return d, u, v, 0, 0, a end,
    }

    function Cartes.Fente(n, i, fan, levee)
        local rel   = i - (n + 1) / 2
        local angle = rel * fan.ecart * (fan.sens or 1)
        local rad   = math.rad(angle)
        local cu    = fan.coin or 0
        local r     = fan.rayon + (levee or 0)
        -- Centre de la carte : pivot (cu, -rayon) + la rotation de (-cu, r).
        local u = cu + (-cu) * math.cos(rad) - r * math.sin(rad)
        local v = -fan.rayon + (-cu) * math.sin(rad) + r * math.cos(rad)
        local d = rel * fan.profondeur * (fan.empilement or 1)
        local x, y, z, p, ya, ro = (AXES[fan.axe or "y"] or AXES.y)(u, v, d, angle)
        return { x = x, y = y, z = z, p = p, yaw = ya, r = ro }
    end

    -- Du pivot au centre de la carte, a l'echelle du jeu (cm, repere de la
    -- carte). Le nom du modele sans le pack : "my-asset-pack::King_of_Hearts1".
    function Cartes.Centre(modele)
        local nom = tostring(modele):match("::(.+)$") or tostring(modele)
        local o = (config.pivots and config.pivots[nom]) or config.pivot_defaut or { x = 0, y = 0, z = 0 }
        local t = config.fan and config.fan.taille or 1
        return { x = o.x * t, y = o.y * t, z = o.z * t }
    end

    function Cartes.Axes()
        return { "z", "zy", "y", "x" }
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
