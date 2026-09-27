-- HUD du mannequin d'essayage (Server/domain/mannequin.lua), mode dev : les
-- categories (Shared/cosmetiques.lua, emplacements), haut/bas pour en
-- choisir une, gauche/droite pour changer de piece dedans (0 : aucune).

return function()
    local Cosmetiques = Package.Require("Shared/cosmetiques.lua")
    local page = WebUI("mannequin", "file://mannequin/mannequin.html", WidgetVisibility.Hidden)
    local actif = false
    local choix = {}
    local ligne = 1
    local chat_ouvert = false
    local mannequin_id = nil
    local PORTEE = 300   -- cm : plus loin, le HUD se ferme

    local function fermer()
        actif = false
        page:SetVisibility(WidgetVisibility.Hidden)
    end

    local function afficher()
        local lignes = {}
        for i, e in ipairs(Cosmetiques.emplacements) do
            local liste = Cosmetiques.par_emplacement[e.id] or {}
            local c = liste[choix[e.id] or 0]
            lignes[i] = { categorie = e.nom, vide = #liste == 0, choisie = i == ligne,
                          nom = c and c.nom or nil, numero = c and c.numero or nil, rarete = c and c.rarete or nil }
        end
        page:CallEvent("mannequin:maj", lignes)
    end

    Events.SubscribeRemote("mannequin:ouvrir", function(etat, id, basculer)
        -- E sur le mannequin, HUD deja ouvert : on le ferme.
        if basculer and actif then return fermer() end
        actif = true
        mannequin_id = id
        choix = type(etat) == "table" and etat or {}
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

    Input.Subscribe("KeyPress", function(touche)
        if not actif or chat_ouvert then return end
        local n = #Cosmetiques.emplacements
        if touche == "Up" or touche == "Down" then
            ligne = (ligne - 1 + (touche == "Down" and 1 or -1)) % n + 1
        elseif touche == "Left" or touche == "Right" then
            local e = Cosmetiques.emplacements[ligne]
            local total = #(Cosmetiques.par_emplacement[e.id] or {})
            if total == 0 then return false end
            -- 0 a total : "aucune" puis chaque piece.
            choix[e.id] = ((choix[e.id] or 0) + (touche == "Right" and 1 or -1)) % (total + 1)
            Events.CallRemote("mannequin:choix", Reliability.Reliable, e.id, choix[e.id])
        else
            return
        end
        afficher()
        return false
    end)
end
