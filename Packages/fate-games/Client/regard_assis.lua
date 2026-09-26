-- Anime le regard des autres joueurs assis. Le serveur publie un angle borne
-- dix fois par seconde ; chaque client interpole localement pour eviter les
-- saccades. Le joueur local suit directement sa camera dans vue_assise.lua.

local R = Package.Require("Shared/config.lua").regard_assis
local cibles = setmetatable({}, { __mode = "k" })
local courants = setmetatable({}, { __mode = "k" })
local erreur_signalee = false

local function est_local(character)
    local player = Client.GetLocalPlayer()
    local mien = player and player:GetControlledCharacter()
    return mien and mien:GetID() == character:GetID()
end

local function cible(character, regard)
    if est_local(character) then return end
    if character:GetValue("liars_dead", false) then return end
    if type(regard) ~= "table" then return end
    local yaw, pitch = tonumber(regard.yaw), tonumber(regard.pitch)
    if not (yaw and pitch) then return end
    cibles[character] = {
        yaw = math.max(-R.lacet_max, math.min(R.lacet_max, yaw)),
        pitch = math.max(-R.tangage_max, math.min(R.tangage_max, pitch)),
    }
end

-- pitch suit la camera (positif : vers le haut) ; dans le rig un tangage
-- positif baisse la tete, d'ou le signe moins (26/09 : regarder en l'air
-- faisait regarder en bas chez les autres, et les bots regardaient le ciel
-- au lieu de leurs cartes).
local function appliquer(character, yaw, pitch)
    -- Neck/Head ont leur axe vertical local sur Y. Envoyer le regard lateral
    -- dans Yaw (axe Z) tordait la tete sur le cote au lieu de la tourner.
    character:SetAnimationBlueprintPropertyValue("LookNeck",
        Rotator(yaw * R.cou, 0, -pitch * R.cou))
    character:SetAnimationBlueprintPropertyValue("LookHead",
        Rotator(yaw * R.tete, 0, -pitch * R.tete))
end

CharacterSimple.Subscribe("ValueChange", function(self, key, value)
    if key == "liars_look" then
        cible(self, value)
    elseif key == "liars_dead" and value == true then
        cibles[self] = nil
        courants[self] = nil
        pcall(appliquer, self, 0, 0)
    elseif key == "assis" and value == false then
        cibles[self] = nil
        courants[self] = nil
        pcall(appliquer, self, 0, 0)
    end
end)

CharacterSimple.Subscribe("Spawn", function(self)
    if self:GetValue("assis", false) and not self:GetValue("liars_dead", false) then
        cible(self, self:GetValue("liars_look", nil))
    end
end)

Timer.SetInterval(function()
    for character, wanted in pairs(cibles) do
        if not character:IsValid() or not character:GetValue("assis", false) then
            cibles[character] = nil
            courants[character] = nil
        else
            local current = courants[character] or { yaw = 0, pitch = 0 }
            current.yaw = current.yaw + (wanted.yaw - current.yaw) * 0.3
            current.pitch = current.pitch + (wanted.pitch - current.pitch) * 0.3
            courants[character] = current
            local ok, err = pcall(appliquer, character, current.yaw, current.pitch)
            if not ok and not erreur_signalee then
                Console.Error("[regard assis] animation : " .. tostring(err))
                erreur_signalee = true
            elseif ok then
                erreur_signalee = false
            end
        end
    end
end, 33)
