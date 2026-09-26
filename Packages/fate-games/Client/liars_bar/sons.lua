-- Sons courts 3D, joues localement chez chaque spectateur du tir.
-- Les OGG vivent dans le package : aucun recook d'asset pack n'est requis.

return function(disposition)
    local erreur_signalee = false

    local function position_revolver(chaise)
        for _, prop in pairs(Prop.GetPairs()) do
            if prop:IsValid() and prop:GetValue("liars_revolver_chair", nil) == chaise then
                return prop:GetLocation()
            end
        end
        local centre = disposition.revolver_home
        return Vector(centre.x, centre.y, centre.z)
    end

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
