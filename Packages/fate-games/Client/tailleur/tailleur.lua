-- Boutique du tailleur (Server/Index.lua, PnjActions.vestiaire) : la grille des
-- pieces a droite, la camera sur le tailleur a gauche. La page ne decide rien :
-- achats et tenue sont revalides par le serveur, qui renvoie l'etat.

return function()
    local Cosmetiques = Package.Require("Shared/cosmetiques.lua")
    local page = WebUI("tailleur", "file://tailleur/tailleur.html", WidgetVisibility.Hidden)
    local ouvert = false

    local function fermer_ici()
        if not ouvert then return end
        ouvert = false
        page:SetVisibility(WidgetVisibility.Hidden)
        page:RemoveFocus()
        Input.SetMouseEnabled(false)
        Input.SetInputEnabled(true)
    end

    Events.SubscribeRemote("tailleur:ouvrir", function(vue)
        ouvert = true
        page:SetVisibility(WidgetVisibility.Visible)
        page:BringToFront()
        page:SetFocus()
        Input.SetMouseEnabled(true)
        Input.SetInputEnabled(false)
        page:CallEvent("tailleur:ouvrir", vue, Cosmetiques.emplacements)
    end)

    Events.SubscribeRemote("tailleur:etat", function(vue, refus)
        page:CallEvent("tailleur:etat", vue, refus)
    end)

    Events.SubscribeRemote("tailleur:fermer", fermer_ici)

    page:Subscribe("acheter", function(ids)
        Events.CallRemote("tailleur:acheter", Reliability.Reliable, ids)
    end)
    page:Subscribe("porter", function(emplacement, id)
        Events.CallRemote("tailleur:porter", Reliability.Reliable, emplacement, id)
    end)
    page:Subscribe("fermer", function()
        Events.CallRemote("tailleur:fermer", Reliability.Reliable)
        fermer_ici()
    end)
end
