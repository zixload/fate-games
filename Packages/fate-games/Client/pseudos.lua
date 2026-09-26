-- Pseudos au-dessus des personnages, partout sur la map, dans l'ecriture des
-- HUD (ui/pseudo.lua), dessines au Canvas : pas de retard sur la camera.
--   - portee limitee, et caches derriere un mur ;
--   - jamais le sien ;
--   - en duel, ceux des adversaires sont caches (seuls les coequipiers) ;
--   - a la table de Liar's Bar, en partie, liars_bar/nametags.lua les pose
--     au-dessus des barillets : on ne les double pas.
-- Un personnage sans joueur (bot) prend le nom de sa chaise de Liar's Bar.

return function(journal, config)
    config = config or {}
    local PORTEE = config.portee or 1500          -- cm
    local AU_DESSUS = config.au_dessus or 30      -- cm au-dessus de la tete
    local VUE_MS = config.verif_vue_ms or 200     -- entre deux verifications de mur
    local Pseudo = Package.Require("ui/pseudo.lua")
    local vus = setmetatable({}, { __mode = "k" })    -- personnage -> { t, visible }
    local erreur_signalee = false

    local function tete(character)
        local ok, tr = pcall(function() return character:GetSocketTransform("Head") end)
        local l = ok and tr and tr.Location
        local o = character:GetLocation()
        if l and l.X and math.abs(l.Z - o.Z) < 250 then return Vector(l.X, l.Y, l.Z) end
        return Vector(o.X, o.Y, o.Z + 85)
    end

    local function nom_de(character)
        local p = character:GetPlayer()
        if p then return p:GetName() end
        local chaise = character:GetValue("liars_chair", 0)
        if type(chaise) == "number" and chaise > 0 then return journal.names[chaise] end
    end

    -- Deja pose par nametags.lua (assis a la table, partie en cours, vivant).
    local function a_la_table(character)
        local chaise = character:GetValue("liars_chair", 0)
        return type(chaise) == "number" and chaise > 0
            and type(character:GetValue("liars_fired", nil)) == "number"
            and character:GetValue("liars_alive", false) == true
    end

    -- En duel, les adversaires ne montrent pas leur nom.
    local function adversaire(character, moi)
        local d = character:GetValue("duel", nil)
        if type(d) ~= "table" or not d.combat then return false end
        local m = moi and moi:GetValue("duel", nil)
        return not (type(m) == "table" and m.camp == d.camp)
    end

    -- Un mur entre la camera et la tete ? Verifie de temps en temps : une
    -- trace par personnage et par image serait du gaspillage.
    local function visible(character, camera, point, moi)
        local v = vus[character]
        local maintenant = Client.GetTime() * 1000
        if v and maintenant - v.t < VUE_MS then return v.visible end
        local ignores = { character }
        if moi then ignores[2] = moi end
        local hit = Trace.LineSingle(camera, point, CollisionChannel.WorldStatic, 0, ignores)
        v = { t = maintenant, visible = not (hit and hit.Success) }
        vus[character] = v
        return v.visible
    end

    local function dessiner(c, largeur, hauteur)
        local player = Client.GetLocalPlayer()
        if not player then return end
        local moi = player:GetControlledCharacter()
        local mon_id = moi and moi:GetID()
        local camera = player:GetCameraLocation()
        local rotation = player:GetCameraRotation()
        if not (camera and rotation) then return end
        local avant = rotation:GetForwardVector()
        for _, class in ipairs({ CharacterSimple, Character }) do
            for _, character in pairs(class.GetAll()) do
                if character:IsValid() and character:GetID() ~= mon_id and not a_la_table(character)
                    and not adversaire(character, moi) then
                    local nom = nom_de(character)
                    if nom and nom ~= "" then
                        local t = tete(character)
                        local point = Vector(t.X, t.Y, t.Z + AU_DESSUS)
                        local dx, dy, dz = point.X - camera.X, point.Y - camera.Y, point.Z - camera.Z
                        local d = math.sqrt(dx * dx + dy * dy + dz * dz)
                        if d > 60 and d < PORTEE and dx * avant.X + dy * avant.Y + dz * avant.Z > 0
                            and visible(character, camera, t, moi) then
                            local e = Viewport.ProjectWorldToScreen(point)
                            if e and type(e.X) == "number" and e.X > 0 and e.X < largeur
                                and e.Y > 0 and e.Y < hauteur then
                                Pseudo.Dessiner(c, nom, e.X, e.Y, math.max(0.7, math.min(1, 700 / d)))
                            end
                        end
                    end
                end
            end
        end
    end

    local canvas = Canvas(true, Color.TRANSPARENT, 0, true, true)
    canvas:Subscribe("Update", function(self, largeur, hauteur)
        local ok, err = pcall(dessiner, self, largeur, hauteur)
        if not ok and not erreur_signalee then
            Console.Error("[pseudos] " .. tostring(err))
            erreur_signalee = true
        elseif ok then
            erreur_signalee = false
        end
    end)
end
