-- Monter les petites marches sans sauter. nanos n'expose pas la hauteur de
-- marche du personnage (aucune fonction step height dans l'API Character,
-- CharacterSimple ni Pawn) : quand on avance vers un rebord bas, on mesure
-- l'obstacle et on fait glisser le personnage dessus, en un dixieme de
-- seconde (TranslateTo). Une poussee (AddImpulse) le faisait decoller : il
-- passait en chute et ca ressemblait a un saut (27/09). TranslateTo est permis
-- a qui a l'autorite reseau (doc Actor) : le joueur qui possede son
-- personnage l'a (doc Authority Concepts), donc sans aller-retour serveur.
-- Trace est cote client (doc Trace).
--
-- On n'attend plus d'etre arrete contre la marche : des que le rebord est a
-- portee du bord de la capsule, on pousse. Les traces visent le decor fixe et
-- le decor mobile (une marche peut etre l'un ou l'autre selon la map).
--
-- L'obstacle se cherche a plusieurs hauteurs, pas seulement a la cheville :
-- l'escalier de la place est fait de planches epaisses avec un creux dessous,
-- le rayon a 5 cm passait sous la planche ("rien a la cheville", 27/09).
-- Bloque contre une marche, on cherche aussi son dessus meme sans obstacle vu.
--
-- Journal : quand on appuie pour avancer mais qu'on reste bloque au sol, la
-- raison du refus s'ecrit dans la console (F1), une fois par seconde au plus.

return function(config)
    config = config or {}
    local HAUTEUR_MAX = config.hauteur_max or 45   -- cm : au-dela, on saute
    local GLISSE = config.glisse or 0.09           -- s pour monter une marche
    local DELAI = config.delai or 0.12             -- s entre deux marches
    local PORTEE = config.portee or 14             -- cm devant le bord de la capsule
    local MARGE_HAUT = config.marge_haut or 7      -- cm au-dessus de la marche
    local MARGE_AVANT = config.marge_avant or 16   -- cm au-dela du rebord
    local enfoncees = {}
    local chat_ouvert = false
    local dernier = -math.huge
    local dernier_journal = -math.huge

    local CANAUX = CollisionChannel.WorldStatic | CollisionChannel.WorldDynamic

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
        return Trace.LineSingle(de, a, CANAUX, 0, { perso })
    end

    -- Rayon reel de la capsule, echelle comprise (le personnage est a 0.8).
    local function rayon(perso)
        local ok, r = pcall(function()
            local taille = perso:GetCapsuleSize()
            local echelle = perso:GetScale()
            return taille.Radius * (echelle and echelle.X or 1)
        end)
        return (ok and type(r) == "number" and r > 0) and r or 30
    end

    local function journal(bloque, maintenant, texte)
        if not bloque or maintenant - dernier_journal < 1 then return end
        dernier_journal = maintenant
        Console.Log("[marche] " .. texte)
    end

    Timer.SetInterval(function()
        if chat_ouvert then return end
        local maintenant = Client.GetTime() / 1000
        if maintenant - dernier < DELAI then return end
        local player = Client.GetLocalPlayer()
        local perso = player and player:GetControlledCharacter()
        if not (perso and perso:IsValid()) or perso:GetValue("assis", false) then return end
        local dir = direction(player)
        if not dir then return end

        local v = perso:GetVelocity()
        if math.abs(v.Z) > 40 then return end   -- en l'air : rien a monter
        -- Bloque, ou presque : sur certaines marches on glisse de cote contre le rebord.
        local bloque = math.sqrt(v.X * v.X + v.Y * v.Y) < 60

        local ok, err = pcall(function()
            local l = perso:GetLocation()
            local sol = touche(l, Vector(l.X, l.Y, l.Z - 250), perso)
            if not sol.Success then return journal(bloque, maintenant, "pas de sol sous les pieds") end
            local pied = sol.Location.Z
            local r = rayon(perso)
            local loin = r + PORTEE
            -- Un obstacle entre la cheville et la hauteur de marche maxi.
            local obstacle, a_distance = false, nil
            for z = 3, HAUTEUR_MAX - 3, 7 do
                local de = Vector(l.X, l.Y, pied + z)
                local t = touche(de, de + dir * loin, perso)
                if t.Success then
                    obstacle = true
                    local d = math.sqrt((t.Location.X - l.X) ^ 2 + (t.Location.Y - l.Y) ^ 2)
                    a_distance = math.min(a_distance or d, d)
                end
            end
            if not obstacle and not bloque then return end
            -- Rien a hauteur de marche maxi : sinon c'est un mur.
            local haut = Vector(l.X, l.Y, pied + HAUTEUR_MAX + 5)
            if touche(haut, haut + dir * loin, perso).Success then
                return journal(bloque, maintenant, ("obstacle plus haut que %d cm"):format(HAUTEUR_MAX))
            end
            -- Le dessus de la marche, juste apres son rebord : le premier
            -- dessus assez haut, de plus pres a plus loin.
            local h
            for _, d in ipairs({ r + 2, r + 7, r + 12, r + 18, r + 25, r + 32, loin + 6 }) do
                local au_dessus = Vector(l.X, l.Y, pied + HAUTEUR_MAX + 10) + dir * d
                local dessus = touche(au_dessus, Vector(au_dessus.X, au_dessus.Y, pied - 5), perso)
                local hd = dessus.Success and (dessus.Location.Z - pied) or nil
                if hd and hd >= 3 and hd <= HAUTEUR_MAX then h = hd break end
            end
            -- Sans obstacle vu, rien a dire : on demarre juste (vitesse encore basse).
            if not h then
                if obstacle then journal(bloque, maintenant, "obstacle mais pas de dessus de marche a portee") end
                return
            end
            -- Monter de la hauteur de la marche, avec de la marge, et avancer assez
            -- pour que le bord de la capsule soit bien au-dessus (marges
            -- relevees le 27/09 : certaines marches accrochaient encore).
            local avance = math.max(0, (a_distance or r) - r) + MARGE_AVANT
            local cible = Vector(l.X + dir.X * avance, l.Y + dir.Y * avance, l.Z + h + MARGE_HAUT)
            perso:TranslateTo(cible, GLISSE, 0)
            dernier = maintenant
        end)
        if not ok then Console.Error("[marche] " .. tostring(err)) end
    end, 30)
end
