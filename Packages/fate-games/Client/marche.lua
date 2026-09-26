-- Monter les petites marches sans sauter. nanos n'expose pas la hauteur de
-- marche du personnage (aucune fonction step height dans l'API Character,
-- CharacterSimple ni Pawn) : quand on avance contre un rebord bas, on mesure
-- l'obstacle et on donne au personnage la petite poussee qui le pose dessus.
-- AddImpulse est permis a qui a l'autorite reseau (doc Actor) : le joueur sur
-- son propre personnage, donc sans aller-retour serveur. Trace est cote
-- client (doc Trace).

return function(config)
    config = config or {}
    local HAUTEUR_MAX = config.hauteur_max or 45   -- cm : au-dela, on saute
    local POUSSEE = config.poussee or 140          -- cm/s vers l'avant
    local DELAI = (config.delai or 0.35) * 1000    -- ms entre deux marches
    local enfoncees = {}
    local chat_ouvert = false
    local dernier = 0

    -- Z/Q en AZERTY, W/A en QWERTY : Unreal nomme la touche par sa lettre.
    local AVANT = { Z = true, W = true }
    local ARRIERE = { S = true }
    local GAUCHE = { Q = true, A = true }
    local DROITE = { D = true }

    Input.Subscribe("KeyPress", function(k) enfoncees[k] = true end)
    Input.Subscribe("KeyUp", function(k) enfoncees[k] = nil end)
    Chat.Subscribe("Open", function() chat_ouvert = true enfoncees = {} end)
    Chat.Subscribe("Close", function() chat_ouvert = false end)

    local function une(t)
        for k in pairs(t) do if enfoncees[k] then return true end end
        return false
    end

    -- Direction voulue, d'apres les touches et le lacet de la camera.
    local function direction(player)
        local av = (une(AVANT) and 1 or 0) - (une(ARRIERE) and 1 or 0)
        local dr = (une(DROITE) and 1 or 0) - (une(GAUCHE) and 1 or 0)
        if av == 0 and dr == 0 then return nil end
        local r = player:GetCameraRotation()
        if not r then return nil end
        local yaw = math.rad(r.Yaw)
        local fx, fy = math.cos(yaw), math.sin(yaw)
        local x, y = fx * av - fy * dr, fy * av + fx * dr
        local n = math.sqrt(x * x + y * y)
        return Vector(x / n, y / n, 0)
    end

    local function touche(de, a, perso)
        return Trace.LineSingle(de, a, CollisionChannel.WorldStatic, 0, { perso })
    end

    Timer.SetInterval(function()
        if chat_ouvert then return end
        local maintenant = Client.GetTime() * 1000
        if maintenant - dernier < DELAI then return end
        local player = Client.GetLocalPlayer()
        local perso = player and player:GetControlledCharacter()
        if not (perso and perso:IsValid()) or perso:GetValue("assis", false) then return end
        local dir = direction(player)
        if not dir then return end

        -- Bloque : on appuie mais on n'avance presque pas, et on est au sol.
        local v = perso:GetVelocity()
        if math.abs(v.Z) > 20 or math.sqrt(v.X * v.X + v.Y * v.Y) > 60 then return end

        local ok, err = pcall(function()
            local l = perso:GetLocation()
            local sol = touche(l, Vector(l.X, l.Y, l.Z - 250), perso)
            if not sol.Success then return end
            local pied = sol.Location.Z
            -- Un obstacle a hauteur de cheville, rien a hauteur de marche maxi.
            local bas = Vector(l.X, l.Y, pied + 6)
            if not touche(bas, bas + dir * 45, perso).Success then return end
            local haut = Vector(l.X, l.Y, pied + HAUTEUR_MAX + 5)
            if touche(haut, haut + dir * 45, perso).Success then return end
            -- Le dessus de la marche, juste devant.
            local au_dessus = Vector(l.X, l.Y, pied + HAUTEUR_MAX + 10) + dir * 38
            local dessus = touche(au_dessus, Vector(au_dessus.X, au_dessus.Y, pied - 5), perso)
            if not dessus.Success then return end
            local h = dessus.Location.Z - pied
            if h < 3 or h > HAUTEUR_MAX then return end
            -- Juste ce qu'il faut pour passer le rebord : v = racine(2 g h).
            local g = 980 * (perso:GetGravityScale() or 1)
            local vz = math.sqrt(2 * g * (h + 8))
            perso:AddImpulse(Vector(dir.X * POUSSEE, dir.Y * POUSSEE, vz), true)
            dernier = maintenant
        end)
        if not ok then Console.Error("[marche] " .. tostring(err)) end
    end, 50)
end
