-- HUD du mannequin d'essayage (Server/domain/mannequin.lua), mode dev :
-- fleches gauche/droite pour le haut, haut/bas pour le bas. Le HUD affiche le
-- nom, la rarete, le rang dans le catalogue, la piece et le materiau : un
-- vetement en damier se reconnait tout de suite.

return function()
    local Cosmetiques = Package.Require("Shared/cosmetiques.lua")
    local page = WebUI("mannequin", "file://mannequin/mannequin.html", WidgetVisibility.Hidden)
    local actif = false
    local choix = { haut = 1, bas = 1 }
    local chat_ouvert = false
    local mannequin_id = nil
    local PORTEE = 300   -- cm : plus loin, le HUD se ferme

    local function fermer()
        actif = false
        page:SetVisibility(WidgetVisibility.Hidden)
    end

    local function vue(emplacement)
        local liste = Cosmetiques.par_emplacement[emplacement] or {}
        local c = liste[choix[emplacement]]
        if not c then return { rang = 0, total = #liste } end
        return { rang = choix[emplacement], total = #liste, nom = c.nom, rarete = c.rarete,
                 piece = c.piece, materiau = c.materiau or "(materiau de la piece)" }
    end

    local function afficher()
        page:CallEvent("mannequin:maj", vue("haut"), vue("bas"))
    end

    Events.SubscribeRemote("mannequin:ouvrir", function(haut, bas, id, basculer)
        -- E sur le mannequin, HUD deja ouvert : on le ferme.
        if basculer and actif then return fermer() end
        actif = true
        mannequin_id = id
        choix.haut, choix.bas = tonumber(haut) or 1, tonumber(bas) or 1
        page:SetVisibility(WidgetVisibility.VisibleNotHitTestable)
        afficher()
    end)

    Events.SubscribeRemote("mannequin:fermer", fermer)

    -- S'eloigner du mannequin ferme le HUD (E dessus le rouvre).
    Timer.SetInterval(function()
        if not actif then return end
        local p = Client.GetLocalPlayer()
        local moi = p and p:GetControlledCharacter()
        local m
        for _, c in pairs(CharacterSimple.GetAll()) do
            if c:IsValid() and c:GetID() == mannequin_id then m = c break end
        end
        if not (moi and m) or (moi:GetLocation() - m:GetLocation()):Size() > PORTEE then fermer() end
    end, 250)

    Chat.Subscribe("Open", function() chat_ouvert = true end)
    Chat.Subscribe("Close", function() chat_ouvert = false end)

    local TOUCHES = { Left = { "haut", -1 }, Right = { "haut", 1 }, Up = { "bas", -1 }, Down = { "bas", 1 } }
    Input.Subscribe("KeyPress", function(touche)
        if not actif or chat_ouvert then return end
        local t = TOUCHES[touche]
        if not t then return end
        local emplacement, sens = t[1], t[2]
        local total = #(Cosmetiques.par_emplacement[emplacement] or {})
        if total == 0 then return false end
        choix[emplacement] = (choix[emplacement] - 1 + sens) % total + 1
        Events.CallRemote("mannequin:choix", Reliability.Reliable, emplacement, choix[emplacement])
        afficher()
        return false
    end)
end
