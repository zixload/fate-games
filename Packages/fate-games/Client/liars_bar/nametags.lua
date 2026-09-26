-- Superposition de Liar's Bar, rendue par WebUI pour des contours nets :
--   - un petit barillet au-dessus de chaque joueur (aucun pseudo ni chance
--     chiffree) ; le sien, en haut de l'ecran, quand on leve la tete ;
--   - au-dessus du joueur precedent, a mon tour, quand je le regarde :
--     l'invite "Menteur !" (E l'accuse, hud.lua lit journal.vise_menteur) ;
--   - au-dessus du tas : la derniere pose (+2), la carte de table, le total ;
--   - les consignes, en bas, a mon tour.
-- Les positions suivent l'os de la tete : le centre de la capsule assise
-- n'est pas un repere fiable pour placer un HUD.

return function(journal, config)
    local tireur = nil
    local pret = false
    local erreur_signalee = false
    local CHAMBRES = 6
    local PORTEE = 1200
    local HAUTEUR_AU_DESSUS_TETE = 58
    local reglage = config or {}
    local cone_menteur = math.cos(math.rad(reglage.cone_menteur or 12))
    local tangage_barillet = reglage.tangage_barillet or 14
    local touches = reglage.keys or {}

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
    local function projeter(point, camera, forward, screen_size)
        local dx, dy, dz = point.X - camera.X, point.Y - camera.Y, point.Z - camera.Z
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
        if distance < 80 or distance > PORTEE then return end
        if dx * forward.X + dy * forward.Y + dz * forward.Z <= 0 then return end
        local projected = Viewport.ProjectWorldToScreen(point)
        if not projected or type(projected.X) ~= "number" or type(projected.Y) ~= "number" then return end
        if projected.X < 35 or projected.X > screen_size.X - 35
            or projected.Y < 70 or projected.Y > screen_size.Y - 35 then return end
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

    local function ajouter(markers, character, chair, camera, forward, screen_size, precedent)
        local fired = character:GetValue("liars_fired", nil)
        if type(fired) ~= "number" or character:GetValue("liars_alive", false) ~= true then return end
        local point, tete = position_tete(character)
        local projected, distance = projeter(point, camera, forward, screen_size)
        if not projected then return end
        local menteur = precedent == chair and vise(tete, camera, forward)
        if menteur then journal.vise_menteur = chair end
        markers[#markers + 1] = {
            id = character:GetID(),
            x = projected.X,
            y = projected.Y,
            fired = math.max(0, math.min(CHAMBRES, math.floor(fired))),
            active = (tireur or journal.turn) == chair,
            menteur = menteur,
            scale = math.max(0.80, math.min(1, 700 / distance)),
        }
    end

    local function angle(degres)
        return (degres + 180) % 360 - 180
    end

    -- Le sien, en haut au centre, quand on leve les yeux.
    local function le_mien(markers, character, rotation, screen_size)
        if not character or character:GetValue("liars_chair", 0) == 0 then return end
        local fired = character:GetValue("liars_fired", nil)
        if type(fired) ~= "number" or character:GetValue("liars_alive", false) ~= true then return end
        if angle(rotation.Pitch) < tangage_barillet then return end
        markers[#markers + 1] = {
            id = "moi",
            x = screen_size.X / 2,
            y = screen_size.Y * 0.2,
            fired = math.max(0, math.min(CHAMBRES, math.floor(fired))),
            active = (tireur or journal.turn) == journal.my_chair,
            scale = 1.15,
        }
    end

    local function carton_du_tas(camera, forward, screen_size)
        local lieu = journal.lieu_tas
        if not (lieu and journal.table_rank) then return nil end
        local projected, distance = projeter(Vector(lieu.X, lieu.Y, lieu.Z + 26), camera, forward, screen_size)
        if not projected then return nil end
        local total = 0
        for _, pose in ipairs(journal.pile) do total = total + pose.count end
        local derniere = journal.pile[#journal.pile]
        return {
            x = projected.X, y = projected.Y,
            plus = derniere and derniere.count or 0,
            rang = journal.table_rank,
            total = total,
            poses = #journal.pile,
            scale = math.max(0.80, math.min(1, 500 / distance)),
        }
    end

    local function aide()
        if not journal:IsMyTurn() or journal.designated ~= nil or #journal.hand == 0 then return "" end
        local texte = ("molette : parcourir · clic : choisir · [%s] poser"):format(touches.play or "E")
        if accusable() then
            texte = texte .. " · regarde le joueur précédent + [" .. (touches.play or "E") .. "] : menteur"
        end
        return texte
    end

    local photo = Package.Require("photo.lua")

    local function rafraichir()
        journal.vise_menteur = nil
        if not pret then return end
        local player = Client.GetLocalPlayer()
        if not player then return end
        local my_character = player:GetControlledCharacter()
        local my_id = my_character and my_character:GetID()
        local camera = player:GetCameraLocation()
        local rotation = player:GetCameraRotation()
        local screen_size = Viewport.GetViewportSize()
        if not (camera and rotation and screen_size) then return end

        local forward = rotation:GetForwardVector()
        local precedent = accusable()
        local markers = {}
        for _, class in ipairs({ CharacterSimple, Character }) do
            for _, character in pairs(class.GetAll()) do
                if character:IsValid() and character:GetID() ~= my_id then
                    local chair = character:GetValue("liars_chair", 0)
                    if type(chair) == "number" and chair > 0 then
                        ajouter(markers, character, chair, camera, forward, screen_size, precedent)
                    end
                end
            end
        end
        le_mien(markers, my_character, rotation, screen_size)
        page:CallEvent("barillet:maj", {
            width = screen_size.X, height = screen_size.Y, markers = markers,
            tas = carton_du_tas(camera, forward, screen_size),
            -- Mode capture (F1) : pas de consignes a l'ecran.
            aide = photo.cache and "" or aide(),
        })
    end

    -- La projection doit suivre la camera a chaque image. Un timer de 66 ms
    -- donnait un retard visible pendant les mouvements de souris.
    Client.Subscribe("Tick", function()
        local ok, err = pcall(rafraichir)
        if not ok and not erreur_signalee then
            Console.Error("[barillet HUD] " .. tostring(err))
            erreur_signalee = true
        elseif ok then
            erreur_signalee = false
        end
    end)
end
