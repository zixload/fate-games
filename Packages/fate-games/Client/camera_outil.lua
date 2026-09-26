-- Camera pendant un outil de l'atelier (panneau dev, F2, package separe).
--
-- L'atelier dit quelle vue il veut ("atelier:vue") : "premiere" (premiere
-- personne, tete cachee chez soi), "epaule" (troisieme personne decalee
-- au-dessus de l'epaule droite) ou "jeu" (la camera du jeu, publiee par le
-- serveur dans la valeur synchronisee "camera_jeu"). SetSpringArmSettings est
-- permis au client (annotations : [Client/Server]) : seule la vue de ce
-- joueur change.
--
-- Constate en jeu le 19/09 : le decalage (socket_offset) passe a
-- SetSpringArmSettings reste sans effet, et le changement de longueur du bras
-- est interpole, donc lent. Le decalage passe donc par la camera du joueur
-- (Player:SetCameraSocketOffset), et la longueur y est forcee sans
-- interpolation (Player:SetCameraArmLength(longueur, true)), les deux
-- [Client/Server] d'apres la doc Player.
--
-- Les distances se reglent en direct dans F2 > Reglages ("Camera des
-- outils"). Valeurs reglees en jeu le 19/09 ; le pivot se mesure depuis le
-- bas du personnage, a son echelle.

local reglage = {
    premiere = { avant = 10, cote = 0, hauteur = 155 },
    epaule   = { hauteur = 140, bras = 150, cote = 60, dessus = 15 },
}

local vue = "jeu"

local function mien()
    local player = Client.GetLocalPlayer()
    local c = player and player:GetControlledCharacter()
    if c and c:IsValid() and c:IsA(CharacterSimple) then return c end
    return nil
end

local function tete(c, visible)
    -- Assis, la tete reste cachee : posture.lua s'en occupe.
    if visible and c:GetValue("assis", false) then return end
    if visible then
        c:UnHideBone("Head")
        c:UnHideBone("Neck")
    else
        c:HideBone("Head")
        c:HideBone("Neck")
    end
end

local function appliquer()
    local c = mien()
    local player = Client.GetLocalPlayer()
    if not (c and player) then return end
    -- Longueur du bras sans interpolation, decalage par la camera du joueur.
    local function bras(longueur, decalage)
        player:SetCameraArmLength(longueur, true)
        player:SetCameraSocketOffset(decalage or Vector(0, 0, 0))
    end
    local ok, err = pcall(function()
        if vue == "premiere" then
            local p = reglage.premiere
            -- Sans retard de camera : on vise au pixel.
            c:SetSpringArmSettings(Vector(p.avant, p.cote, p.hauteur), 0, Vector(0, 0, 0), false)
            bras(0)
            c:SetVisibility(false)
            tete(c, false)
        elseif vue == "epaule" then
            local e = reglage.epaule
            c:SetSpringArmSettings(Vector(0, 0, e.hauteur), e.bras, Vector(0, 0, 0), false)
            bras(e.bras, Vector(0, e.cote, e.dessus))
            c:SetVisibility(true)
            tete(c, true)
        else
            local j = c:GetValue("camera_jeu", nil)
            if type(j) == "table" then
                c:SetSpringArmSettings(Vector(j.x, j.y, j.z), j.bras, Vector(0, 0, 0), j.retard ~= false)
                bras(j.bras)
            end
            c:SetVisibility(true)
            tete(c, true)
        end
    end)
    if not ok then Console.Error("[camera outil] " .. tostring(err)) end
end

Events.Subscribe("atelier:vue", function(mode)
    if mode ~= "premiere" and mode ~= "epaule" then mode = "jeu" end
    vue = mode
    appliquer()
end)

-- Le serveur a change la camera du jeu (assis, debout) pendant un outil :
-- la vue de l'outil reprend la main.
CharacterSimple.Subscribe("ValueChange", function(self, key)
    if key ~= "camera_jeu" or vue == "jeu" then return end
    local c = mien()
    if c and c:GetID() == self:GetID() then appliquer() end
end)

---------------------------------------------------------------- reglage a l'atelier

local function champ(chemin, label, pas) return { chemin = chemin, label = label, pas = pas } end

local DECLARATION = {
    {
        id = "outils.camera", label = "Caméra des outils", valeurs = reglage,
        champs = {
            champ("premiere.hauteur", "1re personne : hauteur", 5),
            champ("premiere.avant", "1re personne : avant", 1),
            champ("premiere.cote", "1re personne : côté", 1),
            champ("epaule.hauteur", "Épaule : hauteur", 5),
            champ("epaule.bras", "Épaule : recul", 5),
            champ("epaule.cote", "Épaule : décalage à droite", 5),
            champ("epaule.dessus", "Épaule : au-dessus", 5),
        },
    },
}

-- Recopie les seuls nombres deja presents.
local function recopier(cible, source)
    for cle, valeur in pairs(source or {}) do
        local actuel = cible[cle]
        if type(actuel) == "number" and type(valeur) == "number" then
            cible[cle] = valeur
        elseif type(actuel) == "table" and type(valeur) == "table" then
            recopier(actuel, valeur)
        end
    end
end

Events.Subscribe("atelier:reglage_change", function(id, valeurs)
    if id ~= "outils.camera" then return end
    recopier(reglage, valeurs)
    if vue ~= "jeu" then appliquer() end
end)

local function declarer() Events.Call("atelier:declarer_reglages", DECLARATION) end
Events.Subscribe("atelier:pret", declarer)
declarer()
