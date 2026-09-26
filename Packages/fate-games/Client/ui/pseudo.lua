-- Dessin d'un pseudo au Canvas natif, en Lilita One papier cerne d'encre : la
-- police bitmap de scripts/hud/rendre_police.py (planche police.png et ses
-- avances dans liars_bar/police.lua), le Canvas n'ayant pas cette police.
-- Partage par les pseudos de la map (pseudos.lua) et ceux de la table de
-- Liar's Bar (liars_bar/nametags.lua).

local Police = Package.Require("liars_bar/police.lua")
local PLANCHE = "package://fate-games/Client/liars_bar/hud/police.png"
local TAILLE, MAX, ESPACE = 0.42, 16, 2   -- taille par rapport a la planche

-- Les glyphes d'un texte (UTF-8 : les accents font plusieurs octets). Un
-- caractere absent de la planche devient "?".
local function glyphes(texte)
    local out = {}
    local ok = pcall(function()
        for _, cp in utf8.codes(texte) do
            out[#out + 1] = Police.glyphes[utf8.char(cp)] or Police.glyphes["?"]
            if #out >= MAX then break end
        end
    end)
    if not ok then
        out = {}
        for ch in texte:gmatch(".") do out[#out + 1] = Police.glyphes[ch] or Police.glyphes["?"] end
    end
    return out
end

local Pseudo = {}

-- Un pseudo centre sur x, pose sur la ligne y (son bas), a l'echelle s.
-- Rend sa hauteur a l'ecran.
function Pseudo.Dessiner(c, texte, x, y, s)
    local gs = glyphes(tostring(texte or ""))
    if #gs == 0 then return 0 end
    local k = TAILLE * (s or 1)
    local largeur = 0
    for _, g in ipairs(gs) do largeur = largeur + (g.a + ESPACE) * k end
    local cx = x - largeur / 2
    local haut = y - (Police.base + 10) * k
    local ul, uh = Police.case_l / Police.largeur, Police.case_h / Police.hauteur
    for _, g in ipairs(gs) do
        local col, lig = g.i % Police.colonnes, math.floor(g.i / Police.colonnes)
        c:DrawTexture(PLANCHE, Vector2D(cx - Police.marge * k, haut),
            Vector2D(Police.case_l * k, Police.case_h * k),
            Vector2D(col * ul, lig * uh), Vector2D(ul, uh),
            Color.WHITE, BlendMode.AlphaBlend, 0, Vector2D(0.5, 0.5))
        cx = cx + (g.a + ESPACE) * k
    end
    return (Police.base + 10) * k
end

return Pseudo
