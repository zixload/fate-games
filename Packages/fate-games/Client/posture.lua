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

-- Assis, la tete est bridee : on ne se retourne pas sur sa chaise, et on ne
-- voit plus son propre visage. L'API nanos n'a aucune limite de camera : on
-- ramene le regard dans l'angle a chaque image, pour le seul joueur local.
local LIMITE = 100   -- degres de part et d'autre de l'axe du corps

-- Angle signe pour aller de b a a, ramene dans [-180, 180].
local function ecart(a, b)
    local d = (a - b) % 360
    if d > 180 then d = d - 360 end
    return d
end

Client.Subscribe("Tick", function()
    local player = Client.GetLocalPlayer()
    if not player then return end
    local character = player:GetControlledCharacter()
    if not character or not character:GetValue("assis", false) then return end

    local corps  = character:GetRotation().Yaw
    local regard = player:GetCameraRotation()
    local d = ecart(regard.Yaw, corps)
    if d > LIMITE or d < -LIMITE then
        local borne = corps + (d > 0 and LIMITE or -LIMITE)
        player:SetCameraRotation(Rotator(regard.Pitch, borne, 0))
    end
end)
