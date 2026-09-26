-- Mourir au Liar's Bar se sent : au coup fatal, flash rouge, secousse de la
-- camera, puis elle bascule vers la gauche avec la chute du personnage
-- (ANIM_Seated_Revolver_Fatal) et l'ecran reste voile jusqu'a la fin de la
-- partie. nanos n'a pas de secousse de camera toute faite : on la joue ici,
-- image par image, avec SetCameraRotation (doc Player). Les fondus sont
-- StartCameraFade / StopCameraFade.

return function(journal, reglage)
    local r = reglage or {}
    local SECOUSSE = r.secousse or { duree = 0.45, amplitude = 7 }
    local BASCULE = r.bascule or { duree = 0.9, tangage = -22, lacet = -18, roulis = -28 }
    local VOILE = r.voile or 0.35

    local anim = nil    -- { t, base } pendant la secousse et la bascule
    local mort = false

    local function lisse(k) return k * k * (3 - 2 * k) end

    local function joueur() return Client.GetLocalPlayer() end

    local function mourir()
        local p = joueur()
        local base = p and p:GetCameraRotation()
        if not base then return end
        mort = true
        anim = { t = 0, base = Rotator(base.Pitch, base.Yaw, 0) }
        pcall(function()
            p:StartCameraFade(0.6, 0, 0.8, Color(0.5, 0.03, 0.03), false, false)
        end)
        Timer.SetTimeout(function()
            if not mort then return end
            local pj = joueur()
            if pj then pcall(function() pj:StartCameraFade(0, VOILE, 1.2, Color(0, 0, 0), false, true) end) end
        end, 800)
    end

    -- Fin de partie ou relevee : la camera se redresse, le voile s'en va.
    local function revivre()
        if not mort then return end
        mort, anim = false, nil
        local p = joueur()
        if not p then return end
        pcall(function() p:StopCameraFade() end)
        local rot = p:GetCameraRotation()
        if rot then pcall(function() p:SetCameraRotation(Rotator(rot.Pitch, rot.Yaw, 0)) end) end
    end

    Client.Subscribe("Tick", function(delta)
        if not anim then return end
        local p = joueur()
        if not p then anim = nil return end
        anim.t = anim.t + delta
        local b = anim.base
        local k = lisse(math.min(1, anim.t / BASCULE.duree))
        local pitch = b.Pitch + BASCULE.tangage * k
        local yaw = b.Yaw + BASCULE.lacet * k
        local roll = BASCULE.roulis * k
        -- Secousse : un tremblement qui s'eteint, par-dessus la bascule.
        if anim.t < SECOUSSE.duree then
            local a = SECOUSSE.amplitude * (1 - anim.t / SECOUSSE.duree)
            pitch = pitch + (math.random() * 2 - 1) * a
            yaw = yaw + (math.random() * 2 - 1) * a
            roll = roll + (math.random() * 2 - 1) * a * 0.6
        end
        pcall(function() p:SetCameraRotation(Rotator(pitch, yaw, roll)) end)
        if anim.t >= math.max(SECOUSSE.duree, BASCULE.duree) then anim = nil end
    end)

    Events.SubscribeRemote("liars:shoot", function(chaise, _, fatal)
        if fatal and chaise ~= nil and chaise == journal.my_chair then mourir() end
    end)
    Events.SubscribeRemote("liars:match_ended", revivre)
    Events.SubscribeRemote("liars:unseated", function(chaise)
        if chaise ~= nil and chaise == journal.my_chair then revivre() end
    end)
end
