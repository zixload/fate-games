-- Le musicien (Server/Index.lua, PnjActions.musicien) : E sur lui, il demande
-- si l'on aime sa musique. Une bulle avec Oui / Non ; un oui rapporte un
-- pourboire, une fois par jour. La bulle affiche aussi sa reponse.

return function()
    local page = WebUI("musicien", "file://musicien/musicien.html", WidgetVisibility.Hidden)
    local ouverte, question = false, false
    local minuteur = nil

    local function fermer()
        if minuteur then Timer.ClearTimeout(minuteur); minuteur = nil end
        if not ouverte then return end
        ouverte, question = false, false
        page:SetVisibility(WidgetVisibility.Hidden)
        page:RemoveFocus()
        Input.SetMouseEnabled(false)
    end

    local function montrer(texte, avec_question, pourboire)
        if minuteur then Timer.ClearTimeout(minuteur); minuteur = nil end
        ouverte, question = true, avec_question
        page:SetVisibility(WidgetVisibility.Visible)
        page:BringToFront()
        page:CallEvent("musicien:bulle", texte, avec_question, pourboire or 0)
        if avec_question then
            page:SetFocus()
            Input.SetMouseEnabled(true)
        else
            page:RemoveFocus()
            Input.SetMouseEnabled(false)
            minuteur = Timer.SetTimeout(fermer, 3500)
        end
    end

    page:Subscribe("repondre", function(oui)
        if not question then return end
        question = false
        Events.CallRemote("musicien:reponse", Reliability.Reliable, oui == true)
        Input.SetMouseEnabled(false)
        page:RemoveFocus()
    end)

    Events.SubscribeRemote("musicien:question", function(pourboire)
        montrer("Est-ce que tu aimes bien la musique ?", true, pourboire)
    end)
    Events.SubscribeRemote("musicien:merci", function(montant)
        if montant and montant > 0 then
            montrer(("Ça me fait plaisir ! Tiens, pour toi : %d pièces."):format(montant), false)
        else
            montrer("Ah… ma bourse est vide aujourd'hui, désolé.", false)
        end
    end)
    Events.SubscribeRemote("musicien:bof", function()
        montrer("Tant pis… je continue quand même.", false)
    end)
    Events.SubscribeRemote("musicien:deja", function()
        montrer("Merci d'être repassé ! Reviens demain pour une autre chanson.", false)
    end)
end
