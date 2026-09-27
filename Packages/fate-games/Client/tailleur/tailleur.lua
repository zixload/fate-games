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

    -- La camera voulue par le serveur, rapprochee si un mur ou un decor se
    -- trouve entre elle et le joueur (le rayon ne se lance que cote client,
    -- doc Trace). Sur la droite joueur -> camera, il garde sa place a l'ecran.
    local function cadrer(c)
        if not (c and c.perso and c.camera) then return end
        local tete = c.perso + Vector(0, 0, 50)
        local vers = c.camera - tete
        local longueur = vers:Size()
        if longueur < 1 then return end
        local dir = vers * (1 / longueur)
        local ok, ret = pcall(Trace.LineSingle, tete, c.camera,
            CollisionChannel.WorldStatic | CollisionChannel.WorldDynamic)
        local pos = c.camera
        if ok and ret and ret.Success and ret.Location then
            local libre = (ret.Location - tete):Size()
            pos = tete + dir * math.max(60, libre - 30)
        end
        local moi = Client.GetLocalPlayer()
        moi:SetCameraLocation(pos)
        if c.rotation then moi:SetCameraRotation(c.rotation) end
    end

    Events.SubscribeRemote("tailleur:ouvrir", function(vue, cadrage)
        cadrer(cadrage)
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
    page:Subscribe("essayer", function(emplacement, id)
        Events.CallRemote("tailleur:essayer", Reliability.Reliable, emplacement, id)
    end)
    page:Subscribe("porter", function(emplacement, id)
        Events.CallRemote("tailleur:porter", Reliability.Reliable, emplacement, id)
    end)
    page:Subscribe("fermer", function()
        Events.CallRemote("tailleur:fermer", Reliability.Reliable)
        fermer_ici()
    end)
end
