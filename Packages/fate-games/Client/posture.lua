-- Posture assise des personnages d'essai (CharacterSimple).
--
-- Le serveur ne peut pas toucher l'Animation Blueprint :
-- SetAnimationBlueprintPropertyValue est reserve au client (annotations
-- officielles). Il publie donc une valeur synchronisee "assis" sur le
-- personnage, et chaque client la recopie dans la variable "Assis" de
-- ABP_Creative, pour tous les personnages qu'il voit, le sien compris.

-- Le personnage que ce client controle ?
local function est_le_mien(character)
    local player = Client.GetLocalPlayer()
    local mien = player and player:GetControlledCharacter()
    return mien ~= nil and mien:GetID() == character:GetID()
end

local function appliquer(character, assis)
    local ok, err = pcall(function()
        character:SetAnimationBlueprintPropertyValue("Assis", assis == true)

        -- Assis, la camera est dans la tete : on la cache, chez soi seulement.
        -- HideBone appele cote client ne vaut que pour ce client, les autres
        -- joueurs voient toujours la tete. Visage et nez suivent l'os.
        if est_le_mien(character) then
            if assis then
                character:HideBone("Head")
            else
                character:UnHideBone("Head")
            end
        end
    end)
    if not ok then
        Console.Error("[posture] Assis impossible : " .. tostring(err))
    end
end

-- Pose « cartes en main » pendant une partie : meme principe, variable
-- "Cartes" de ABP_Creative. Si elle n'existe pas encore, rien ne se passe.
local function tenir_cartes(character, en_main)
    local ok, err = pcall(function()
        character:SetAnimationBlueprintPropertyValue("Cartes", en_main == true)
    end)
    if not ok then
        Console.Error("[posture] Cartes impossible : " .. tostring(err))
    end
end

CharacterSimple.Subscribe("ValueChange", function(self, key, value)
    if key == "assis" then appliquer(self, value) end
    if key == "cartes" then tenir_cartes(self, value) end
end)

-- Un joueur qui arrive voit les gens deja assis : la valeur est la des
-- l'apparition du personnage chez lui, sans changement a signaler.
CharacterSimple.Subscribe("Spawn", function(self)
    if self:GetValue("assis", false) then appliquer(self, true) end
    if self:GetValue("cartes", false) then tenir_cartes(self, true) end
end)
