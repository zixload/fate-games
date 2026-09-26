-- Roue d'emotes : T l'ouvre, puis 1, 2 ou 3 joue l'emote (et referme la
-- roue). T ou Echap referment ; elle se referme seule apres config.fenetre
-- secondes. Bouger arrete l'emote en cours. Le serveur joue l'animation
-- (Server/domain/emotes.lua).

return function(config)
    local ouverte = false
    local danse = false
    local chat_ouvert = false
    local pret = false
    local minuterie = nil
    local outil_atelier = Package.Require("outil_atelier.lua")

    local page = WebUI("emotes", "file://emotes/emotes.html",
        WidgetVisibility.VisibleNotHitTestable, true, true)

    -- Ce que la page affiche : titre, apercu, et si l'emplacement a son
    -- animation.
    local function liste()
        local out = {}
        for i, e in ipairs(config.liste) do
            out[i] = { titre = e.titre, apercu = e.apercu, pret = e.anim ~= "" }
        end
        return out
    end

    local function montrer(oui)
        ouverte = oui
        if minuterie then Timer.ClearTimeout(minuterie) minuterie = nil end
        if oui then
            minuterie = Timer.SetTimeout(function()
                minuterie = nil
                montrer(false)
            end, math.floor((config.fenetre or 4) * 1000))
        end
        if pret then page:CallEvent("emotes:montrer", oui, liste()) end
    end

    page:Subscribe("Ready", function() pret = true end)
    page:Subscribe("pret", function() pret = true end)

    Chat.Subscribe("Open", function() chat_ouvert = true if ouverte then montrer(false) end end)
    Chat.Subscribe("Close", function() chat_ouvert = false end)

    local function emplacement(touche)
        for i, noms in ipairs(config.chiffres) do
            for _, n in ipairs(noms) do
                if n == touche then return i end
            end
        end
    end

    local BOUGER = { W = true, A = true, S = true, D = true, Z = true, Q = true, SpaceBar = true }

    Input.Subscribe("KeyPress", function(touche)
        if chat_ouvert or outil_atelier.actif then return end
        if danse and BOUGER[touche] then
            danse = false
            Events.CallRemote("emote:stop", Reliability.Reliable)
        end
        if touche == config.touche then
            montrer(not ouverte)
            return false
        end
        if not ouverte then return end
        if touche == "Escape" then
            montrer(false)
            return false
        end
        local i = emplacement(touche)
        if i then
            if config.liste[i] and config.liste[i].anim ~= "" then
                Events.CallRemote("emote:jouer", Reliability.Reliable, i)
                danse = true
            end
            if pret then page:CallEvent("emotes:choix", i) end
            Timer.SetTimeout(function() montrer(false) end, 180)
            return false
        end
    end)
end
