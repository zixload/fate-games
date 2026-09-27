-- Mannequin d'essayage (mode dev) : le corps Creative nu, sans tete, pour
-- tester un a un les vetements du catalogue (Shared/cosmetiques.lua). Il
-- servira ensuite au tailleur.
--
--   /mannequin           le pose devant moi (ou le replace) et ouvre le HUD
--   /mannequin retirer   l'enleve et ferme le HUD
--
-- Le client choisit haut et bas (fleches, Client/mannequin.lua) ; le serveur
-- habille le mannequin : piece accrochee puis materiau du motif. Un vetement
-- dont le materiau ne prend pas reste en damier, avec son nom affiche.

return function(Log, Characters, dev_pour)
    local Mannequin = {}
    local Apparences = Package.Require("Shared/appearances.lua")
    local Cosmetiques = Package.Require("Shared/cosmetiques.lua")
    local corps = nil
    local choix = { haut = 1, bas = 1 }

    local function habiller()
        if not (corps and corps:IsValid()) then return end
        local worn, materiaux = {}, {}
        for _, emplacement in ipairs({ "haut", "bas" }) do
            local c = (Cosmetiques.par_emplacement[emplacement] or {})[choix[emplacement]]
            if c then
                worn[#worn + 1] = c.piece_chemin
                materiaux[#worn] = c.materiau_chemin
            end
        end
        local ok, err = pcall(Cosmetiques.Habiller, corps,
            { body = Apparences.body, head = {}, worn = worn, materiaux = materiaux }, "mannequin")
        if not ok then Log.Warn("mannequin", tostring(err)) end
    end

    local function retirer()
        if corps and corps:IsValid() then pcall(function() corps:Destroy() end) end
        corps = nil
    end

    local function poser(player)
        local c = player:GetControlledCharacter()
        if not c then return false end
        retirer()
        local l, yaw = c:GetLocation(), c:GetRotation().Yaw
        local r = math.rad(yaw)
        local x, y = l.X + math.cos(r) * 180, l.Y + math.sin(r) * 180
        corps = Characters.CorpsDebout(x, y, l.Z, yaw + 180)
        if not corps then return false end
        corps:SetValue("mannequin", true, true)
        habiller()
        return true
    end

    function Mannequin.Init()
        Chat.Subscribe("PlayerSubmit", function(message, player)
            local mots = {}
            for m in tostring(message):gmatch("%S+") do mots[#mots + 1] = m end
            if mots[1] ~= "/mannequin" then return end
            if not dev_pour(player) then return end
            if mots[2] == "retirer" then
                retirer()
                Events.CallRemote("mannequin:fermer", player, Reliability.Reliable)
            elseif poser(player) then
                Events.CallRemote("mannequin:ouvrir", player, Reliability.Reliable, choix.haut, choix.bas)
            else
                Chat.SendMessage(player, "Mannequin impossible ici.")
            end
            return false
        end)

        Events.SubscribeRemote("mannequin:choix", function(player, emplacement, index)
            if not dev_pour(player) then return end
            local liste = Cosmetiques.par_emplacement[emplacement]
            index = tonumber(index)
            if not (liste and index and liste[math.floor(index)]) then return end
            choix[emplacement] = math.floor(index)
            habiller()
        end)

        -- Il tourne lentement : devant, dos, profils.
        Timer.SetInterval(function()
            if corps and corps:IsValid() then
                local r = corps:GetRotation()
                corps:SetRotation(Rotator(0, r.Yaw + 1.2, 0))
            end
        end, 50)
    end

    return Mannequin
end
