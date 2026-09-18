-- Posture assise des personnages d'essai (CharacterSimple).
--
-- Le serveur ne peut pas toucher l'Animation Blueprint :
-- SetAnimationBlueprintPropertyValue est reserve au client (annotations
-- officielles). Il publie donc une valeur synchronisee "assis" sur le
-- personnage, et chaque client la recopie dans la variable "Assis" de
-- ABP_Creative, pour tous les personnages qu'il voit, le sien compris.

local function appliquer(character, assis)
    local ok, err = pcall(function()
        character:SetAnimationBlueprintPropertyValue("Assis", assis == true)
    end)
    if not ok then
        Console.Error("[posture] Assis impossible : " .. tostring(err))
    end
end

CharacterSimple.Subscribe("ValueChange", function(self, key, value)
    if key == "assis" then appliquer(self, value) end
end)

-- Un joueur qui arrive voit les gens deja assis : la valeur est la des
-- l'apparition du personnage chez lui, sans changement a signaler.
CharacterSimple.Subscribe("Spawn", function(self)
    if self:GetValue("assis", false) then appliquer(self, true) end
end)
