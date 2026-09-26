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
