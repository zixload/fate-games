-- Limite la vue vers le bas quand le joueur est assis. La camera reste libre
-- lateralement et vers le haut ; le bas du champ montre le buste et les jambes
-- sans pouvoir rentrer dans le costume ou regarder a travers la chaise.

local R = Package.Require("Shared/config.lua").regard_assis
-- Nuit du loup-garou : qui dort garde la tete baissee (Ecran.baisse).
local Ecran = Package.Require("loup_garou/ecran.lua")
local Dev = Package.Require("dev.lua")
-- Decalage du regard par pose du loup-garou (degres, positif : vers le haut) :
-- chaque animation penche la tete a sa facon. /lg regard <degres> regle en
-- direct la pose sur laquelle on est assis (mode dev), a reporter ensuite
-- dans Shared/config.lua (regard_assis.poses_loup_garou).
local baisse_faite = false
local baisse_depuis = 0
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

-- Butee du bas : corriger la camera apres coup la laissait depasser puis
-- revenir (saccade). A la butee, le mouvement de souris vers le bas est
-- bloque avant d'arriver a la camera. Le sens qui baisse la vue est appris
-- (souris inversee ou non) ; par defaut, descendre la souris baisse la vue.
local sens_bas = 1
local cumul_y = 0
local pitch_precedent = nil

local function assis_en_vue_jeu()
    if vue ~= "jeu" then return nil end
    local player = Client.GetLocalPlayer()
    local perso = player and player:GetControlledCharacter()
    if perso and perso:IsValid() and perso:IsA(CharacterSimple) and perso:GetValue("assis", false) then
        return player
    end
end

Input.Subscribe("MouseMove", function(dx, dy)
    local player = assis_en_vue_jeu()
    if not player then return end
    if Ecran.baisse then return false end
    if not dy or dy == 0 then return end
    local rotation = player:GetCameraRotation()
    if not rotation then return end
    local descend = dy * sens_bas > 0
    -- Un geste surtout horizontal passe : on peut tourner la tete en fixant le sol.
    if descend and angle(rotation.Pitch) <= PITCH_MIN + 1 and math.abs(dy) >= math.abs(dx or 0) then
        return false
    end
    cumul_y = cumul_y + dy
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
        if (Ecran.baisse == true) ~= baisse_faite then
            baisse_faite = Ecran.baisse == true
            if baisse_faite then
                -- Face a sa place, le regard au sol, en une seconde.
                player:RotateCameraTo(Rotator(PITCH_MIN, perso:GetValue("seat_yaw", rotation.Yaw), 0), 1.0)
                baisse_depuis = Client.GetTime()
            end
        elseif baisse_faite and Client.GetTime() - baisse_depuis > 1100 then
            -- La souris est bloquee ; au cas ou la vue bougerait quand meme.
            local voulu = Rotator(PITCH_MIN, perso:GetValue("seat_yaw", rotation.Yaw), 0)
            if math.abs(angle(rotation.Pitch - voulu.Pitch)) > 1 or math.abs(angle(rotation.Yaw - voulu.Yaw)) > 1 then
                perso:SetControlRotation(voulu)
                player:SetCameraRotation(voulu)
                rotation = voulu
            end
        end
        local pitch = angle(rotation.Pitch)
        if pitch_precedent and cumul_y ~= 0 and math.abs(pitch - pitch_precedent) > 0.5 then
            sens_bas = ((pitch < pitch_precedent) == (cumul_y > 0)) and 1 or -1
        end
        pitch_precedent, cumul_y = pitch, 0
        if pitch < PITCH_MIN then
            rotation = Rotator(PITCH_MIN, rotation.Yaw, rotation.Roll)
            perso:SetControlRotation(rotation)
            player:SetCameraRotation(rotation)
            pitch = PITCH_MIN
        end

        local orientation_chaise = perso:GetValue("seat_yaw", rotation.Yaw)
        -- Le gain fait tourner la tete un peu plus que la camera : les autres
        -- lisent le regard de loin. Bornes et gain : Shared/config.lua.
        local yaw = math.max(-R.lacet_max, math.min(R.lacet_max,
            angle(rotation.Yaw - orientation_chaise) * R.gain))
        -- Les poses assises du loup-garou penchent deja la tete : sans ce
        -- decalage, regarder droit devant faisait regarder le sol (27/09).
        local pose = perso:GetValue("ww_pose", nil)
        local decalage = 0
        if pose then
            local par_pose = R.poses_loup_garou or {}
            decalage = par_pose[pose] or R.decalage_loup_garou or 0
        end
        -- Le decalage s'ajoute apres la borne du regard : une pose tres penchee
        -- doit pouvoir etre ramenee au-dela de tangage_max.
        local regard_pitch = math.max(-R.tangage_max, math.min(R.tangage_max, pitch * R.gain)) + decalage
        if not perso:GetValue("liars_dead", false) then
            -- La tete ne doit pas suivre la camera pendant la chute figee.
            -- Tangage inverse : dans le rig, un tangage positif baisse la tete
            -- (regarder en l'air faisait regarder en bas chez les autres).
            perso:SetAnimationBlueprintPropertyValue("LookNeck",
                Rotator(yaw * R.cou, 0, -regard_pitch * R.cou))
            perso:SetAnimationBlueprintPropertyValue("LookHead",
                Rotator(yaw * R.tete, 0, -regard_pitch * R.tete))

            local maintenant = Client.GetTime()
            if maintenant - dernier_envoi >= 100 and (dernier_yaw == nil
                or math.abs(yaw - dernier_yaw) >= 1
                or math.abs(regard_pitch - dernier_pitch) >= 1) then
                Events.CallRemote("zix:regard_assis", Reliability.Unreliable, yaw, regard_pitch)
                dernier_envoi = maintenant
                dernier_yaw, dernier_pitch = yaw, regard_pitch
            end
        end
    end)
    if not ok and not erreur_signalee then
        Console.Error("[vue assise] limitation de la camera : " .. tostring(err))
        erreur_signalee = true
    elseif ok then
        erreur_signalee = false
    end
end, 33)

Chat.Subscribe("PlayerSubmit", function(message)
    local valeur = tostring(message):match("^/lg regard%s*(%-?[%d%.]*)")
    if not valeur then return end
    if not Dev.actif then return end
    local player = Client.GetLocalPlayer()
    local perso = player and player:GetControlledCharacter()
    local pose = perso and perso:GetValue("ww_pose", nil)
    if not pose then Chat.AddMessage("/lg regard : assieds-toi au loup-garou d'abord") return false end
    R.poses_loup_garou = R.poses_loup_garou or {}
    if tonumber(valeur) then R.poses_loup_garou[pose] = tonumber(valeur) end
    Chat.AddMessage(("regard %s : %s degres"):format((pose:gsub("^.*::", "")),
        tostring(R.poses_loup_garou[pose] or R.decalage_loup_garou or 0)))
    return false
end)
