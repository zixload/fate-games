-- Cartes de role posees sur le tapis du loup-garou, devant chaque joueur de
-- la partie : face cachee au lancement, retournees a la mort du joueur, et
-- toutes a la fin. Grandes, pour que tout le cercle les lise.
--
-- Le serveur publie ww:cartes (liste de { n, x, y, z, yaw, role }) a chaque
-- changement ; role n'y figure qu'une fois la carte retournee : le dessin
-- d'une carte cachee n'arrive jamais chez le client. Chaque client pose les
-- cartes chez lui (un SM_Plane texture, comme les cartes du Liar's Bar).

return function(config)
    config = config or {}
    local LARGEUR, HAUTEUR = config.largeur or 60, config.hauteur or 90
    local TOURNER = config.tourner or 0          -- degres, si le dessin est de travers
    local IMG = "package://fate-games/Client/loup_garou/img/"
    local IMAGES = { wolf = "loup", white_wolf = "loup_blanc", villager = "villageois", seer = "voyante",
        hunter = "chasseur", guard = "gardien", cupid = "cupidon", witch = "sorciere" }

    local cartes = {}   -- n -> { objet, image }

    local function texture(objet, image)
        pcall(function()
            objet:SetMaterial("nanos-world::M_Default_Masked_Lit")
            objet:SetMaterialTextureParameter("Texture", IMG .. image .. ".png")
        end)
    end

    local function poser(c)
        local image = c.role and IMAGES[c.role] or "dos_nuit"
        local actuelle = cartes[c.n]
        if actuelle and actuelle.objet:IsValid() then
            if actuelle.image ~= image then
                texture(actuelle.objet, image)
                actuelle.image = image
            end
            return
        end
        local ok, objet = pcall(function()
            local o = StaticMesh(Vector(c.x, c.y, c.z), Rotator(0, (c.yaw or 0) + TOURNER, 0),
                "nanos-world::SM_Plane", CollisionType.NoCollision)
            o:SetScale(Vector(HAUTEUR / 100, LARGEUR / 100, 1))
            pcall(function() o:SetCastShadow(false) end)
            return o
        end)
        if not ok then return Console.Error("[loup-garou cartes] " .. tostring(objet)) end
        texture(objet, image)
        cartes[c.n] = { objet = objet, image = image }
    end

    Events.SubscribeRemote("ww:cartes", function(liste)
        local vues = {}
        for _, c in ipairs(liste or {}) do
            vues[c.n] = true
            poser(c)
        end
        for n, carte in pairs(cartes) do
            if not vues[n] then
                if carte.objet:IsValid() then carte.objet:Destroy() end
                cartes[n] = nil
            end
        end
    end)
end
