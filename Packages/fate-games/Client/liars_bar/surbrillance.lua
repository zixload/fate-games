-- Le revolver de celui qui doit tirer s'allume chez tout le monde, de sa
-- designation jusqu'au coup (ou la fin de la manche). La designation part a
-- tous les clients (effects.lua, audience "all") : chacun allume le meme
-- revolver de son cote. SetHighlightEnabled et Client.SetHighlightColor
-- sont cote client (doc Actor, doc Client).

return function(reglage)
    reglage = reglage or {}
    local INDEX = reglage.index or 1
    local allume = nil

    local c = reglage.couleur or { r = 1.0, g = 0.72, b = 0.25 }
    local k = reglage.intensite or 3
    pcall(function()
        Client.SetHighlightColor(Color(c.r * k, c.g * k, c.b * k), INDEX, HighlightMode.Always)
    end)

    local function revolver_de(chaise)
        for _, prop in pairs(Prop.GetPairs()) do
            if prop:IsValid() and prop:GetValue("liars_revolver_chair", nil) == chaise then
                return prop
            end
        end
    end

    local function eteindre()
        if allume and allume:IsValid() then
            pcall(function() allume:SetHighlightEnabled(false, INDEX) end)
        end
        allume = nil
    end

    Events.SubscribeRemote("liars:designated", function(chaise)
        eteindre()
        local r = chaise and revolver_de(chaise)
        if r then
            local ok = pcall(function() r:SetHighlightEnabled(true, INDEX) end)
            if ok then allume = r end
        end
    end)
    for _, evenement in ipairs({ "liars:shoot", "liars:gun_cancelled", "liars:round_ended", "liars:match_ended" }) do
        Events.SubscribeRemote(evenement, eteindre)
    end
end
