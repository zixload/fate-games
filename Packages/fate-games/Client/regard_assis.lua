-- Anime le regard des autres joueurs assis. Le serveur publie un angle borne
-- dix fois par seconde ; chaque client interpole localement pour eviter les
-- saccades. Le joueur local suit directement sa camera dans vue_assise.lua.

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
    if type(regard) ~= "table" then return end
    local yaw, pitch = tonumber(regard.yaw), tonumber(regard.pitch)
    if not (yaw and pitch) then return end
    cibles[character] = {
        yaw = math.max(-50, math.min(50, yaw)),
        pitch = math.max(-25, math.min(25, pitch)),
    }
end

local function appliquer(character, yaw, pitch)
    character:SetAnimationBlueprintPropertyValue("LookNeck",
        Rotator(pitch * 0.35, yaw * 0.35, 0))
    character:SetAnimationBlueprintPropertyValue("LookHead",
        Rotator(pitch * 0.65, yaw * 0.65, 0))
end

CharacterSimple.Subscribe("ValueChange", function(self, key, value)
    if key == "liars_look" then
        cible(self, value)
    elseif key == "assis" and value == false then
        cibles[self] = nil
        courants[self] = nil
        pcall(appliquer, self, 0, 0)
    end
end)

CharacterSimple.Subscribe("Spawn", function(self)
    if self:GetValue("assis", false) then
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
