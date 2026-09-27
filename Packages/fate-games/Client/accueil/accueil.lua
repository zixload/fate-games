-- Ecran d'accueil (Server/domain/accueil.lua) : la page par-dessus la vue de
-- la carte, la camera qui glisse de A a B en boucle, n'importe quelle touche
-- ou un clic pour jouer. La page ne prend pas le focus : les touches sont
-- lues ici (Input KeyDown / MouseDown), bloquees tant que l'accueil est ouvert.

return function(config)
    config = config or {}
    local page = WebUI("accueil", "file://accueil/accueil.html", WidgetVisibility.Hidden)
    local ouvert, parti = false, false
    local minuteur = nil
    local pret, attente = false, {}

    local function vers_page(evenement, ...)
        if pret then page:CallEvent(evenement, ...) else attente[#attente + 1] = { evenement, { ... } } end
    end
    page:Subscribe("pret", function()
        pret = true
        for _, a in ipairs(attente) do page:CallEvent(a[1], table.unpack(a[2])) end
        attente = {}
    end)

    local function lieu(p) return Vector(p.x, p.y, p.z) end
    local function angle(p) return Rotator(p.pitch or 0, p.yaw or 0, p.roll or 0) end

    -- A, puis de A vers B et retour, sur `duree` secondes chaque trajet.
    local function travelling(a, b, duree)
        local moi = Client.GetLocalPlayer()
        moi:SetCameraLocation(lieu(a))
        moi:SetCameraRotation(angle(a))
        if not b then return end
        local cible, autre = b, a
        local function trajet()
            local j = Client.GetLocalPlayer()
            j:TranslateCameraTo(lieu(cible), duree)
            j:RotateCameraTo(angle(cible), duree)
            cible, autre = autre, cible
        end
        trajet()
        minuteur = Timer.SetInterval(trajet, math.floor(duree * 1000))
    end

    local function fermer()
        if minuteur then Timer.ClearInterval(minuteur); minuteur = nil end
        if not ouvert then return end
        ouvert = false
        page:SetVisibility(WidgetVisibility.Hidden)
    end

    local function jouer()
        if not ouvert or parti then return end
        parti = true
        -- Arreter net le trajet en cours (27/09 : le RotateCameraTo de 40 s
        -- continuait apres l'apparition et bloquait le viseur quelques secondes).
        local moi = Client.GetLocalPlayer()
        moi:TranslateCameraTo(moi:GetCameraLocation(), 0.01)
        moi:RotateCameraTo(moi:GetCameraRotation(), 0.01)
        fermer()
        Events.CallRemote("accueil:jouer", Reliability.Reliable)
    end

    Events.SubscribeRemote("accueil:ouvrir", function(d)
        ouvert, parti = true, false
        page:SetVisibility(WidgetVisibility.Visible)
        page:BringToFront()
        vers_page("accueil:ouvrir", d, config.astuces or {})
        if d and d.plans and d.plans.a then travelling(d.plans.a, d.plans.b, d.traversee or 40) end
    end)
    Events.SubscribeRemote("accueil:parties", function(r) vers_page("accueil:parties", r) end)
    Events.SubscribeRemote("accueil:gain", function(g) vers_page("accueil:gain", g) end)
    Events.SubscribeRemote("accueil:stats", function(s) vers_page("accueil:stats", s) end)
    Events.SubscribeRemote("accueil:fermer", fermer)

    -- /accueil a|b (dev) : le serveur demande la camera, on la lui renvoie.
    Events.SubscribeRemote("accueil:mesurer", function(lettre)
        local moi = Client.GetLocalPlayer()
        Events.CallRemote("accueil:mesure", Reliability.Reliable, lettre, moi:GetCameraLocation(), moi:GetCameraRotation())
    end)

    Input.Subscribe("KeyDown", function()
        if ouvert then jouer(); return false end
    end)
    Input.Subscribe("MouseDown", function()
        if ouvert then jouer(); return false end
    end)
end
