-- Sons courts 3D, joues localement chez chaque spectateur du tir.
-- Les OGG vivent dans le package : aucun recook d'asset pack n'est requis.

return function(disposition, reglage)
    local erreur_signalee = false
    reglage = reglage or {}

    local function position_revolver(chaise)
        for _, prop in pairs(Prop.GetPairs()) do
            if prop:IsValid() and prop:GetValue("liars_revolver_chair", nil) == chaise then
                return prop:GetLocation()
            end
        end
        local centre = disposition.revolver_home
        return Vector(centre.x, centre.y, centre.z)
    end

    -- Musique de table (Jazz Music #1) : tant que mon personnage est assis a
    -- une chaise de Liar's Bar. Meme reglage de Sound que la musique du duel.
    local musique = nil

    local function musique_on()
        if musique and musique:IsValid() then return end
        local ok, err = pcall(function()
            local boucle = SoundLoopMode and (SoundLoopMode.Forever or SoundLoopMode.Default) or nil
            musique = Sound(Vector(), "package://fate-games/Client/Sounds/" .. reglage.musique, true, false,
                SoundType.Music, 0, 1, 400, 3600, AttenuationFunction and AttenuationFunction.Linear or nil,
                true, boucle, false)
            musique:FadeIn(reglage.fondu_entree or 4, reglage.volume_musique or 0.08)
        end)
        if not ok then
            musique = nil
            Console.Error("[liars] musique : " .. tostring(err))
        end
    end

    local function musique_off()
        if not (musique and musique:IsValid()) then musique = nil return end
        local m = musique
        musique = nil
        pcall(function() m:FadeOut(reglage.fondu_sortie or 3, 0, true) end)
    end

    if (reglage.musique or "") ~= "" then
        Timer.SetInterval(function()
            local player = Client.GetLocalPlayer()
            local perso = player and player:GetControlledCharacter()
            local chaise = perso and perso:IsValid() and perso:GetValue("liars_chair", 0) or 0
            if type(chaise) == "number" and chaise > 0 then musique_on() else musique_off() end
        end, 500)
    end

    -- "Menteur !" crie depuis la chaise qui accuse, si le fichier est la.
    Events.SubscribeRemote("liars:accuse", function(accusateur)
        if (reglage.menteur or "") == "" then return end
        pcall(function()
            local lieu = disposition.chairs and disposition.chairs[accusateur]
            local l = lieu and lieu.location or disposition.revolver_home
            Sound(Vector(l.x, l.y, l.z + 120),
                "package://fate-games/Client/Sounds/" .. reglage.menteur,
                false, true, SoundType.SFX, reglage.volume_menteur or 0.9, 1.0, 250, 2500)
        end)
    end)

    Events.SubscribeRemote("liars:shoot", function(chaise, _, fatal)
        local ok, err = pcall(function()
            local fichier = fatal and "gunshot.ogg" or "dryfire.ogg"
            Sound(position_revolver(chaise),
                "package://fate-games/Client/Sounds/" .. fichier,
                false, true, SoundType.SFX,
                fatal and 0.82 or 0.62, 1.0, 180, 1800)
        end)
        if not ok and not erreur_signalee then
            Console.Error("[liars] son du tir : " .. tostring(err))
            erreur_signalee = true
        elseif ok then
            erreur_signalee = false
        end
    end)
end
