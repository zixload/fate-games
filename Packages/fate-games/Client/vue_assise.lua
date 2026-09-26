-- Limite la vue vers le bas quand le joueur est assis. La camera reste libre
-- lateralement et vers le haut ; le bas du champ montre le buste et les jambes
-- sans pouvoir rentrer dans le costume ou regarder a travers la chaise.

local vue = "jeu"
local PITCH_MIN = -55 -- assez bas pour voir les jambes, sans basculer sous le corps
local erreur_signalee = false
local place_initialisee = nil
local dernier_envoi = 0
local dernier_yaw = nil
local dernier_pitch = nil

local function angle(degres)
    return (degres + 180) % 360 - 180
end

Events.Subscribe("atelier:vue", function(mode)
    vue = (mode == "epaule" or mode == "premiere") and mode or "jeu"
end)

Timer.SetInterval(function()
    if vue ~= "jeu" then
        place_initialisee = nil
        dernier_yaw = nil
        return
    end
    local player = Client.GetLocalPlayer()
    local perso = player and player:GetControlledCharacter()
    if not (perso and perso:IsValid() and perso:IsA(CharacterSimple)
        and perso:GetValue("assis", false)) then
        place_initialisee = nil
        dernier_yaw = nil
        return
    end

    local ok, err = pcall(function()
        local rotation = player:GetCameraRotation()
        if not rotation then return end
        local identifiant = perso:GetID()
        if place_initialisee ~= identifiant then
            local yaw = perso:GetValue("seat_yaw", nil)
            if type(yaw) ~= "number" then return end
            local depart = Rotator(0, yaw, 0)
            perso:SetControlRotation(depart)
            player:SetCameraRotation(depart)
            place_initialisee = identifiant
            dernier_yaw = nil
            return
        end
        local pitch = angle(rotation.Pitch)
        if pitch < PITCH_MIN then
            rotation = Rotator(PITCH_MIN, rotation.Yaw, rotation.Roll)
            perso:SetControlRotation(rotation)
            player:SetCameraRotation(rotation)
            pitch = PITCH_MIN
        end

        local orientation_chaise = perso:GetValue("seat_yaw", rotation.Yaw)
        local yaw = math.max(-30, math.min(30, angle(rotation.Yaw - orientation_chaise)))
        local regard_pitch = math.max(-15, math.min(15, pitch))
        -- La rotation du regard est repartie entre cou et tete dans le rig.
        perso:SetAnimationBlueprintPropertyValue("LookNeck",
            Rotator(yaw * 0.35, 0, regard_pitch * 0.35))
        perso:SetAnimationBlueprintPropertyValue("LookHead",
            Rotator(yaw * 0.65, 0, regard_pitch * 0.65))

        local maintenant = Client.GetTime()
        if maintenant - dernier_envoi >= 100 and (dernier_yaw == nil
            or math.abs(yaw - dernier_yaw) >= 1
            or math.abs(regard_pitch - dernier_pitch) >= 1) then
            Events.CallRemote("zix:regard_assis", Reliability.Unreliable, yaw, regard_pitch)
            dernier_envoi = maintenant
            dernier_yaw, dernier_pitch = yaw, regard_pitch
        end
    end)
    if not ok and not erreur_signalee then
        Console.Error("[vue assise] limitation de la camera : " .. tostring(err))
        erreur_signalee = true
    elseif ok then
        erreur_signalee = false
    end
end, 33)
