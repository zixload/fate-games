-- Les elimines du loup-garou deviennent des ombres : un voile gris pose sur
-- le corps (surbrillance, seulement quand on le voit, pas a travers les murs)
-- et un contour d'encre noire. Slot 0 des deux : la surbrillance 1 sert au
-- revolver du Liar's Bar, le contour 1 a la cible du loup-garou, le 2 aux
-- cartes (doc Actor, doc Client).
--
-- Reglage en direct : /lg ombre <voile 0-1> <epaisseur du contour>

return function()
    local Dev = Package.Require("dev.lua")
    local SLOT = 0
    local reglage = { voile = 0.35, epaisseur = 2 }
    local ombres = setmetatable({}, { __mode = "k" })   -- personnage -> true

    local function couleurs()
        local v = reglage.voile
        pcall(function()
            Client.SetHighlightColor(Color(v, v, v * 1.1), SLOT, HighlightMode.OnlyVisible)
            Client.SetOutlineColor(Color(0, 0, 0), SLOT, reglage.epaisseur)
        end)
    end
    couleurs()

    local function ombre(ch, oui)
        pcall(function()
            ch:SetHighlightEnabled(oui, SLOT)
            ch:SetOutlineEnabled(oui, SLOT)
        end)
        ombres[ch] = oui or nil
    end

    Timer.SetInterval(function()
        local vus = {}
        for _, class in ipairs({ CharacterSimple, Character }) do
            for _, ch in pairs(class.GetAll()) do
                if ch:IsValid() and ch:GetValue("ww_joueur", false) == true and ch:GetValue("ww_mort", false) == true then
                    vus[ch] = true
                    if not ombres[ch] then ombre(ch, true) end
                end
            end
        end
        for ch in pairs(ombres) do
            if not vus[ch] then
                if ch:IsValid() then ombre(ch, false) else ombres[ch] = nil end
            end
        end
    end, 400)

    Chat.Subscribe("PlayerSubmit", function(message)
        local v, e = tostring(message):match("^/lg ombre%s*([%d%.]*)%s*([%d%.]*)")
        if not v then return end
        if not Dev.actif then return end
        reglage.voile = tonumber(v) or reglage.voile
        reglage.epaisseur = tonumber(e) or reglage.epaisseur
        couleurs()
        Chat.AddMessage(("ombre : voile %s | contour %s"):format(reglage.voile, reglage.epaisseur))
        return false
    end)
end
