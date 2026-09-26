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
    -- La vraie carte (coins arrondis, epaisseur : scripts/blender/create_carte_role.py,
    -- importee par scripts/unreal/import_decor_loup_garou.py), une fois cuite.
    -- Elle mesure 10 x 15 cm, le dessin court le long de X : quart de tour.
    local MODELE = config.modele3d and "my-asset-pack::SM_WW_RoleCard" or nil
    local IMG = "package://fate-games/Client/loup_garou/img/"
    local IMAGES = { wolf = "loup", white_wolf = "loup_blanc", villager = "villageois", seer = "voyante",
        hunter = "chasseur", guard = "gardien", cupid = "cupidon", witch = "sorciere" }

    local cartes = {}   -- n -> { objet, image }

    local function texture(objet, image)
        pcall(function()
            -- La vraie carte a ses materiaux (face avec un parametre Texture).
            if not MODELE then objet:SetMaterial("nanos-world::M_Default_Masked_Lit") end
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
            if MODELE then
                -- Taille mesuree plutot que supposee : l'import a pu lire les
                -- metres du FBX comme des centimetres (carte de 1,5 mm).
                local o = StaticMesh(Vector(c.x, c.y, c.z - 0.3), Rotator(0, 0, 0), MODELE, CollisionType.NoCollision)
                local k = LARGEUR / 10
                local ok_b, b = pcall(function() return o:GetBounds() end)
                local e = ok_b and b and b.BoxExtent
                if e and math.max(e.X, e.Y) > 0.0001 then k = HAUTEUR / (2 * math.max(e.X, e.Y)) end
                o:SetScale(Vector(k, k, k))
                o:SetRotation(Rotator(0, (c.yaw or 0) + TOURNER + 90, 0))
                return o
            end
            local o = StaticMesh(Vector(c.x, c.y, c.z), Rotator(0, (c.yaw or 0) + TOURNER, 0),
                "nanos-world::SM_Plane", CollisionType.NoCollision)
            -- Le dessin court en largeur le long de X et en hauteur le long de Y
            -- (UV du SM_Plane) : l'inverse l'etirait et le couchait.
            o:SetScale(Vector(LARGEUR / 100, HAUTEUR / 100, 1))
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
