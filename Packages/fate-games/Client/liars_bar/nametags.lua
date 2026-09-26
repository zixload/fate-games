-- Petit barillet au-dessus des joueurs, rendu par WebUI pour des contours nets.
-- La position suit l'os de la tete : le centre de la capsule assise n'est pas
-- un repere fiable pour placer un HUD. Aucun pseudo ni chance chiffree.

return function(journal)
    local tireur = nil
    local pret = false
    local erreur_signalee = false
    local CHAMBRES = 6
    local PORTEE = 1200
    local HAUTEUR_AU_DESSUS_TETE = 58

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
                    return Vector(location.X, location.Y, location.Z + HAUTEUR_AU_DESSUS_TETE)
                end
            end
        end
        -- Un personnage sans cet os (ou un bot nanos) garde un repere bas.
        return Vector(origin.X, origin.Y, origin.Z + 143)
    end

    local function ajouter(markers, character, chair, camera, forward, screen_size)
        local fired = character:GetValue("liars_fired", nil)
        if type(fired) ~= "number" or character:GetValue("liars_alive", false) ~= true then return end
        local point = position_tete(character)
        local dx, dy, dz = point.X - camera.X, point.Y - camera.Y, point.Z - camera.Z
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
        if distance < 80 or distance > PORTEE then return end
        if dx * forward.X + dy * forward.Y + dz * forward.Z <= 0 then return end

        local projected = Viewport.ProjectWorldToScreen(point)
        if not projected or type(projected.X) ~= "number" or type(projected.Y) ~= "number" then return end
        if projected.X < 35 or projected.X > screen_size.X - 35
            or projected.Y < 70 or projected.Y > screen_size.Y - 35 then return end

        markers[#markers + 1] = {
            id = character:GetID(),
            x = projected.X,
            y = projected.Y,
            fired = math.max(0, math.min(CHAMBRES, math.floor(fired))),
            active = (tireur or journal.turn) == chair,
            scale = math.max(0.80, math.min(1, 700 / distance)),
        }
    end

    local function rafraichir()
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
        local markers = {}
        for _, class in ipairs({ CharacterSimple, Character }) do
            for _, character in pairs(class.GetAll()) do
                if character:IsValid() and character:GetID() ~= my_id then
                    local chair = character:GetValue("liars_chair", 0)
                    if type(chair) == "number" and chair > 0 then
                        ajouter(markers, character, chair, camera, forward, screen_size)
                    end
                end
            end
        end
        page:CallEvent("barillet:maj", {
            width = screen_size.X, height = screen_size.Y, markers = markers,
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
