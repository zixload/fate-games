-- Superposition de Liar's Bar :
--   - au-dessus de chaque joueur, son pseudo et un petit barillet (aucune
--     chance chiffree) ; le sien, en haut de l'ecran, quand on leve la tete ;
--   - au-dessus du joueur precedent, a mon tour, quand je le regarde :
--     l'invite "Menteur !" (E l'accuse, hud.lua lit journal.vise_menteur) ;
--   - au-dessus du tas : la derniere pose (+2), la carte de table, le total ;
--   - les consignes, en bas, a mon tour.
-- Ce qui suit la camera est dessine par le Canvas natif, dans la meme image
-- que la camera : une page WebUI se peint a part et trainait une image ou
-- deux derriere les mouvements de souris. Les dessins sont des PNG dans le
-- style croquis (scripts/hud/sprites.html, rendus par scripts/hud/rendre.sh).
-- Seules les consignes, fixes a l'ecran, restent dans la page WebUI.
-- Les positions suivent l'os de la tete : le centre de la capsule assise
-- n'est pas un repere fiable pour placer un HUD.

return function(journal, config)
    local tireur = nil
    local pret = false
    local erreur_signalee = false
    local CHAMBRES = 6
    local PORTEE = 1200
    local HAUTEUR_AU_DESSUS_TETE = 34   -- 58 : trop haut (26/09)
    local reglage = config or {}
    local cone_menteur = math.cos(math.rad(reglage.cone_menteur or 12))
    local tangage_barillet = reglage.tangage_barillet or 14
    local touches = reglage.keys or {}
    local IMG = "package://fate-games/Client/liars_bar/hud/"
    -- Pseudos : ecriture partagee avec ceux de la map (ui/pseudo.lua).
    local Pseudo = Package.Require("ui/pseudo.lua")
    local RANGS = { king = "roi", queen = "dame", ace = "as", joker = "joker" }

    local page = WebUI("liars-barillet", "file://liars_bar/barillet.html",
        WidgetVisibility.VisibleNotHitTestable, true, true)
    page:Subscribe("Ready", function()
        pret = true
        page:BringToFront()
    end)
    page:Subscribe("pret", function() pret = true end)
    page:Subscribe("Fail", function(_, code, message)
        Console.Error(("[barillet HUD] chargement WebUI impossible (%s) : %s")
            :format(tostring(code), tostring(message)))
    end)

    Events.SubscribeRemote("liars:designated", function(chair) tireur = chair end)
    Events.SubscribeRemote("liars:shoot", function() tireur = nil end)
    Events.SubscribeRemote("liars:round_ended", function() tireur = nil end)
    Events.SubscribeRemote("liars:match_ended", function() tireur = nil end)

    local function position_tete(character)
        local origin = character:GetLocation()
        local bones = character:IsA(CharacterSimple) and { "Head" } or { "head", "Head" }
        for _, bone in ipairs(bones) do
            local ok, transform = pcall(function()
                return character:GetSocketTransform(bone)
            end)
            local location = ok and transform and transform.Location
            if location and location.X and location.Y and location.Z then
                local dx = location.X - origin.X
                local dy = location.Y - origin.Y
                local dz = location.Z - origin.Z
                local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
                if distance > 35 and distance < 250 then
                    return Vector(location.X, location.Y, location.Z + HAUTEUR_AU_DESSUS_TETE),
                        Vector(location.X, location.Y, location.Z)
                end
            end
        end
        -- Un personnage sans cet os (ou un bot nanos) garde un repere bas.
        return Vector(origin.X, origin.Y, origin.Z + 143), Vector(origin.X, origin.Y, origin.Z + 85)
    end

    -- Point du monde vers l'ecran, ou nil s'il est derriere, trop pres, trop
    -- loin ou hors du cadre.
    local function projeter(point, camera, forward, largeur, hauteur)
        local dx, dy, dz = point.X - camera.X, point.Y - camera.Y, point.Z - camera.Z
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
        if distance < 80 or distance > PORTEE then return end
        if dx * forward.X + dy * forward.Y + dz * forward.Z <= 0 then return end
        local projected = Viewport.ProjectWorldToScreen(point)
        if not projected or type(projected.X) ~= "number" or type(projected.Y) ~= "number" then return end
        if projected.X < 35 or projected.X > largeur - 35
            or projected.Y < 70 or projected.Y > hauteur - 35 then return end
        return projected, distance
    end

    -- Le regard passe-t-il sur ce point, a cone_menteur pres ?
    local function vise(point, camera, forward)
        local dx, dy, dz = point.X - camera.X, point.Y - camera.Y, point.Z - camera.Z
        local d = math.sqrt(dx * dx + dy * dy + dz * dz)
        if d < 1 then return false end
        return (dx * forward.X + dy * forward.Y + dz * forward.Z) / d >= cone_menteur
    end

    -- Je peux accuser : mon tour, personne ne tire, et quelqu'un d'autre vient
    -- de poser. Rend sa chaise.
    local function accusable()
        if not journal:IsMyTurn() or journal.designated ~= nil then return nil end
        local derniere = journal.pile[#journal.pile]
        if not derniere or derniere.chair == journal.my_chair then return nil end
        return derniere.chair
    end

    local function angle(degres)
        return (degres + 180) % 360 - 180
    end

    ---------------------------------------------------------------- dessin

    -- Un sprite centre en (x, y). l, h : sa taille a l'echelle 1 (celle de la
    -- fenetre de rendu ; le PNG est rendu au double pour rester net).
    local function sprite(c, nom, x, y, l, h, s)
        local w, hh = l * s, h * s
        c:DrawTexture(IMG .. nom .. ".png", Vector2D(x - w / 2, y - hh / 2), Vector2D(w, hh),
            Vector2D(0, 0), Vector2D(1, 1), Color.WHITE, BlendMode.AlphaBlend, 0, Vector2D(0.5, 0.5))
    end

    local function pseudo(c, texte, x, y, s)
        return Pseudo.Dessiner(c, texte, x, y, s)
    end

    -- Barillet pose sur le point (x, y) : son bas y touche, comme avant.
    -- Fleche rouge dessous pour qui joue ou tire ; au-dessus, le pseudo puis
    -- l'invite "Menteur !".
    local function barillet(c, x, y, fired, actif, menteur, s, nom)
        local n = math.max(0, math.min(CHAMBRES, math.floor(fired)))
        sprite(c, "barillet_" .. n, x, y - 24 * s, 64, 64, s)
        if actif then sprite(c, "fleche", x, y + 12 * s, 28, 24, s) end
        local dessus = y - 48 * s - 4 * s
        if nom and nom ~= "" then dessus = dessus - pseudo(c, nom, x, dessus, s) - 2 * s end
        if menteur then sprite(c, "menteur", x, dessus - 2 * s - 25 * s, 186, 66, s) end
    end

    local function les_autres(c, camera, forward, largeur, hauteur, mon_id)
        local precedent = accusable()
        for _, class in ipairs({ CharacterSimple, Character }) do
            for _, character in pairs(class.GetAll()) do
                if character:IsValid() and character:GetID() ~= mon_id then
                    local chair = character:GetValue("liars_chair", 0)
                    local fired = character:GetValue("liars_fired", nil)
                    if type(chair) == "number" and chair > 0 and type(fired) == "number"
                        and character:GetValue("liars_alive", false) == true then
                        local point, tete = position_tete(character)
                        local p, distance = projeter(point, camera, forward, largeur, hauteur)
                        if p then
                            local menteur = precedent == chair and vise(tete, camera, forward)
                            if menteur then journal.vise_menteur = chair end
                            barillet(c, p.X, p.Y, fired, (tireur or journal.turn) == chair, menteur,
                                math.max(0.80, math.min(1, 700 / distance)), journal.names[chair])
                        end
                    end
                end
            end
        end
    end

    -- Le sien, en haut au centre, quand on leve les yeux.
    local function le_mien(c, character, rotation, largeur, hauteur)
        if not character or character:GetValue("liars_chair", 0) == 0 then return end
        local fired = character:GetValue("liars_fired", nil)
        if type(fired) ~= "number" or character:GetValue("liars_alive", false) ~= true then return end
        if angle(rotation.Pitch) < tangage_barillet then return end
        barillet(c, largeur / 2, hauteur * 0.2, fired, (tireur or journal.turn) == journal.my_chair, false, 1.15)
    end

    -- Le carton au-dessus du tas : +N, la carte de table, le total.
    local function carton(c, camera, forward, largeur, hauteur)
        local lieu = journal.lieu_tas
        if not (lieu and journal.table_rank) then return end
        local p, distance = projeter(Vector(lieu.X, lieu.Y, lieu.Z + 26), camera, forward, largeur, hauteur)
        if not p then return end
        local s = math.max(0.80, math.min(1, 500 / distance))
        local total = 0
        for _, pose in ipairs(journal.pile) do total = total + pose.count end
        local derniere = journal.pile[#journal.pile]
        local haut = p.Y - 76 * s          -- haut du papier, dont le bas touche le point
        sprite(c, "carton", p.X, p.Y - 38 * s, 132, 98, s)
        local rang = RANGS[journal.table_rank]
        if derniere and derniere.count >= 1 and derniere.count <= 3 then
            sprite(c, "plus_" .. derniere.count, p.X, haut + 21 * s, 60, 34, s)
            if rang then sprite(c, "table_" .. rang, p.X, haut + 46 * s, 110, 22, s) end
            if total >= 1 and total <= 20 then sprite(c, "tas_" .. total, p.X, haut + 63 * s, 90, 16, s) end
        else
            if rang then sprite(c, "table_" .. rang, p.X, haut + 32 * s, 110, 22, s) end
            if total >= 1 and total <= 20 then sprite(c, "tas_" .. total, p.X, haut + 52 * s, 90, 16, s) end
        end
    end

    local function dessiner(c, largeur, hauteur)
        journal.vise_menteur = nil
        local player = Client.GetLocalPlayer()
        if not player then return end
        local mon_perso = player:GetControlledCharacter()
        local camera = player:GetCameraLocation()
        local rotation = player:GetCameraRotation()
        if not (camera and rotation) then return end
        local forward = rotation:GetForwardVector()
        carton(c, camera, forward, largeur, hauteur)
        les_autres(c, camera, forward, largeur, hauteur, mon_perso and mon_perso:GetID())
        le_mien(c, mon_perso, rotation, largeur, hauteur)
    end

    -- Taux 0 : redessine a chaque image (doc Canvas:SetAutoRepaintRate).
    local canvas = Canvas(true, Color.TRANSPARENT, 0, true, true)
    canvas:Subscribe("Update", function(self, largeur, hauteur)
        local ok, err = pcall(dessiner, self, largeur, hauteur)
        if not ok and not erreur_signalee then
            Console.Error("[barillet HUD] " .. tostring(err))
            erreur_signalee = true
        elseif ok then
            erreur_signalee = false
        end
    end)

    ---------------------------------------------------------------- consignes

    local function aide()
        if not journal:IsMyTurn() or journal.designated ~= nil or #journal.hand == 0 then return "" end
        local texte = ("molette : parcourir · clic : choisir · [%s] poser"):format(touches.play or "E")
        if accusable() then
            texte = texte .. " · regarde le joueur précédent + [" .. (touches.play or "E") .. "] : menteur"
        end
        return texte
    end

    -- Les consignes ne bougent pas avec la camera : la page ne recoit que
    -- leurs changements.
    local derniere_aide = nil
    Timer.SetInterval(function()
        if not pret then return end
        local ok, texte = pcall(aide)
        texte = ok and texte or ""
        if texte == derniere_aide then return end
        derniere_aide = texte
        page:CallEvent("barillet:maj", { width = 1, height = 1, markers = {}, aide = texte })
    end, 150)
end
