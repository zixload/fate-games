-- Salon de Liar's Bar, cote client : le panneau d'attente (salon.html) et
-- ses touches, comme l'attente du duel. R : pret / pas pret ; fleches : la
-- mise, pour le createur. Le serveur tranche tout (games/liars_bar/salon.lua).

return function()
    local etat = nil
    local pret_page = false
    local chat_ouvert = false

    local page = WebUI("liars-salon", "file://liars_bar/salon.html",
        WidgetVisibility.VisibleNotHitTestable, true, true)

    local function ma_chaise()
        local player = Client.GetLocalPlayer()
        local perso = player and player:GetControlledCharacter()
        local c = perso and perso:GetValue("liars_chair", 0) or 0
        return c > 0 and c or nil
    end

    local function dessiner()
        if pret_page then page:CallEvent("salon:maj", etat, ma_chaise()) end
    end

    page:Subscribe("Ready", function() pret_page = true dessiner() end)
    page:Subscribe("pret", function() pret_page = true dessiner() end)

    -- Ma chaise arrive par une valeur du personnage, parfois apres le salon.
    CharacterSimple.Subscribe("ValueChange", function(_, cle)
        if cle == "liars_chair" and etat then dessiner() end
    end)

    Events.SubscribeRemote("liars:salon", function(vue)
        etat = vue
        dessiner()
    end)
    -- La partie part : le panneau se ferme sans attendre le serveur.
    Events.SubscribeRemote("liars:started", function()
        etat = nil
        dessiner()
    end)

    Chat.Subscribe("Open", function() chat_ouvert = true end)
    Chat.Subscribe("Close", function() chat_ouvert = false end)

    local function moi_pret()
        local c = ma_chaise()
        for _, p in ipairs(etat and etat.places or {}) do
            if p.chair == c then return p.pret == true end
        end
        return false
    end

    Input.Subscribe("KeyPress", function(touche)
        if chat_ouvert or not etat then return end
        if touche == "R" then
            Events.CallRemote("liars:pret", Reliability.Reliable, not moi_pret())
            return false
        end
        if (touche == "Right" or touche == "Left") and etat.createur == ma_chaise() and not etat.avec_bots then
            local paliers = etat.paliers or { 0 }
            local i = 1
            for k, v in ipairs(paliers) do if v == etat.mise then i = k end end
            i = math.max(1, math.min(#paliers, i + (touche == "Right" and 1 or -1)))
            Events.CallRemote("liars:mise", Reliability.Reliable, paliers[i])
            return false
        end
    end)
end
