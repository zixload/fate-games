-- Client du systeme de combat (docs/COMBAT.md) : entrees, HUD, indicateurs.
-- Presentation seule : le client dit ce qu'il veut faire, le serveur tranche
-- (Server/games/pvp/adapter.lua). Actif quand le personnage controle porte la
-- valeur "pvp".
--
-- Corps a corps :
--   clic gauche          attaque legere, dans la direction du dernier geste de souris
--   clic molette ou F    attaque lourde
--   clic droit (tenu)    garde ; un geste de souris la change de cote, la camera
--                        se cale sur l'ennemi le plus proche
--   Q                    feinte (pendant l'armement)
--   Alt gauche           esquive (direction : Z Q S D ou W A S D tenues)
-- Arc : clic gauche tenu pour bander, relache pour tirer.
-- Armes a feu : les commandes natives (tir, visee, R pour recharger).
-- Sorts : 1 trait de feu, 2 onde de choc, 3 eclair, 4 gel, 5 soin, 6 barriere, 7 bond.
-- G : relever un allie a terre, achever un ennemi a terre.
-- /pvp inverser : inverse le geste vertical (garde en haut).

return function()
    local Pseudo = Package.Require("ui/pseudo.lua")

    local FAMILLE = { poings = "melee", dague = "melee", epee_courte = "melee", epee_longue = "melee", hache = "melee",
        masse = "melee", lance = "melee", epee_bouclier = "melee", baton = "melee", pistolet = "tir", revolver = "tir",
        fusil = "tir", fusil_pompe = "tir", fusil_precision = "tir", arc = "arc", arbalete = "arc" }
    local SORTS = { One = "trait_de_feu", Two = "onde_de_choc", Three = "eclair", Four = "gel", Five = "soin",
        Six = "barriere", Seven = "bond" }
    local MIROIR = { gauche = "droite", droite = "gauche", haut = "haut" }
    local SYMBOLE = { gauche = "<<", droite = ">>", haut = "^" }
    local ROUGE = { couleur = Color(1, 0.3, 0.25) }
    local JAUNE = { couleur = Color(1, 0.85, 0.3) }
    local GRIS = { couleur = Color(0.75, 0.75, 0.75, 0.85) }
    local BLANC = { couleur = Color(1, 1, 1) }

    local actif, mon_id, arme = false, nil, nil
    local chat_ouvert = false
    local direction, inverser = "droite", false
    local en_garde, bande = false, false
    local mouvements = {}
    local attaques, gardes, a_terre, camps = {}, {}, {}, {}
    local nombres, traits, projectiles = {}, {}, {}
    local touche_jusqua = 0

    local function maintenant() return Client.GetTime() / 1000 end
    local function famille() return FAMILLE[arme or ""] end
    local function V(t) return Vector(t.x, t.y, t.z) end

    -- Personnages par identifiant (GetByIndex prend un rang, pas un id).
    local par_id = {}
    local function perso_de(id)
        if not id then return nil end
        local c = par_id[id]
        if c and c:IsValid() then return c end
        for _, ch in pairs(Character.GetAll()) do
            if ch:IsValid() and ch:GetID() == id then par_id[id] = ch return ch end
        end
    end

    local function envoyer(nom, ...) Events.CallRemote(nom, Reliability.Reliable, ...) end

    ---------------------------------------------------------------- HUD

    local page = WebUI("pvp", "file://pvp/hud.html", WidgetVisibility.Hidden, true, false)
    local pret = false
    local file_page = {}
    local function hud(evenement, ...)
        if pret then return page:CallEvent(evenement, ...) end
        file_page[#file_page + 1] = { evenement, table.pack(...) }
    end
    page:Subscribe("Ready", function()
        pret = true
        for _, a in ipairs(file_page) do page:CallEvent(a[1], table.unpack(a[2], 1, a[2].n)) end
        file_page = {}
    end)

    local function activer(oui)
        if oui == actif then return end
        actif = oui
        page:SetVisibility(oui and WidgetVisibility.VisibleNotHitTestable or WidgetVisibility.Hidden)
        if not oui then en_garde, bande = false, false end
    end

    Timer.SetInterval(function()
        local p = Client.GetLocalPlayer()
        local c = p and p:GetControlledCharacter()
        local oui = c ~= nil and c:IsValid() and c:GetValue("pvp", false) == true
        activer(oui)
        if oui then
            mon_id = c:GetID()
            arme = c:GetValue("pvp_arme", arme)
        end
        -- Les camps des combattants, pour les indicateurs.
        for _, ch in pairs(Character.GetAll()) do
            if ch:IsValid() then camps[ch:GetID()] = ch:GetValue("pvp_camp", nil) end
        end
    end, 200)

    Events.SubscribeRemote("pvp:etat", function(e)
        if type(e) ~= "table" then return end
        -- Armes a feu : c'est l'arme native qui tient le vrai chargeur.
        if famille() == "tir" then
            pcall(function()
                local moi = perso_de(mon_id)
                local w = moi and moi:GetPicked()
                if w and w:IsValid() and w.GetAmmoClip then
                    e.munitions, e.chargeur = w:GetAmmoClip(), w:GetClipCapacity()
                end
            end)
        end
        hud("etat", e, arme)
    end)

    local REFUS = { epuise = "Épuisé", etourdi = "Étourdi", expose = "Exposé", mana = "Plus de mana",
        recharge = "En recharge", occupe = "Occupé", trop_tard = "Trop tard pour feinter", vide = "Chargeur vide" }
    Events.SubscribeRemote("pvp:refus", function(_, raison)
        if REFUS[raison] then hud("refus", REFUS[raison]) end
    end)

    ---------------------------------------------------------------- visuels

    local function son(asset, pos, volume, pitch)
        pcall(function() Sound(pos, asset, false, true, SoundType.SFX, volume or 1, pitch or 1, 200, 3000) end)
    end

    local function etincelles(pos)
        pcall(function() Particle(pos, Rotator(), "nanos-world::P_Sparks", true, true) end)
    end

    -- Un trait lumineux (eclair, tir de bot), qui s'efface vite.
    local function trait(origine, direction, longueur, couleur, duree)
        local ok, o = pcall(function()
            local d = Vector(direction.x, direction.y, direction.z)
            local milieu = V(origine) + d * (longueur / 2)
            local m = StaticMesh(milieu, d:ToOrientationRotator(), "nanos-world::SM_Cube", CollisionType.NoCollision)
            m:SetScale(Vector(longueur / 100, 0.03, 0.03))
            m:SetMaterial("nanos-world::M_Default_Masked_Unlit")
            m:SetMaterialColorParameter("Tint", couleur)
            pcall(function() m:SetCastShadow(false) end)
            return m
        end)
        if ok then traits[#traits + 1] = { objet = o, fin = maintenant() + (duree or 0.15) } end
    end

    local COULEURS_PROJ = { trait_de_feu = Color(1, 0.45, 0.1), gel = Color(0.4, 0.85, 1),
        arc = Color(0.55, 0.4, 0.25), arbalete = Color(0.45, 0.35, 0.25) }
    local function projectile(e)
        local ok, m = pcall(function()
            local o = StaticMesh(V(e.pos), Rotator(), "nanos-world::SM_Sphere", CollisionType.NoCollision)
            local magie = e.quoi == "trait_de_feu" or e.quoi == "gel"
            local k = magie and 0.35 or 0.08
            o:SetScale(Vector(k, k, k))
            o:SetMaterial("nanos-world::M_Default_Masked_Unlit")
            o:SetMaterialColorParameter("Tint", COULEURS_PROJ[e.quoi] or Color.WHITE)
            pcall(function() o:SetCastShadow(false) end)
            return o
        end)
        if not ok then return end
        projectiles[e.pid] = { objet = m, pos = V(e.pos), vitesse = V(e.vitesse), mien = e.id == mon_id,
            gravite = (e.quoi == "arc" and 0.6) or (e.quoi == "arbalete" and 0.35) or 0 }
    end
    local function fin_projectile(pid)
        local p = projectiles[pid]
        if p and p.objet and p.objet:IsValid() then p.objet:Destroy() end
        projectiles[pid] = nil
    end

    ---------------------------------------------------------------- effets du serveur

    Events.SubscribeRemote("pvp:fx", function(liste)
        local t = maintenant()
        for _, e in ipairs(liste or {}) do
            local c = e.id and perso_de(e.id)
            local k = e.kind
            if k == "attaque" then
                attaques[e.id] = { dir = e.dir, force = e.force, debut = t, fin = t + (e.armement or 0.4) }
            elseif k == "frappe" or k == "feinte" or k == "interrompu" or k == "mort" or k == "garde_brisee" then
                attaques[e.id] = nil
                if k == "frappe" and c then son("nanos-world::A_Whoosh", c:GetLocation(), 0.6, 1.1) end
                if k == "garde_brisee" and c then son("nanos-world::A_MetalHeavy_Impact_MS", c:GetLocation(), 1, 0.6) end
                if k == "mort" then a_terre[e.id], gardes[e.id] = nil, nil end
            elseif k == "pare" then
                attaques[e.source] = nil
                if c then
                    son("nanos-world::A_MetalHeavy_Impact_MS", c:GetLocation(), 1, 1.5)
                    etincelles(c:GetLocation() + Vector(0, 0, 50))
                end
                if e.id == mon_id then hud("refus", "Parade !") end
            elseif k == "bloque" then
                if c then
                    son("nanos-world::A_MetalHeavy_Impact_MS", c:GetLocation(), 0.8, 1)
                    etincelles(c:GetLocation() + Vector(0, 0, 40))
                end
            elseif k == "garde" then
                gardes[e.id] = e.dir
            elseif k == "degats" then
                local cible = perso_de(e.cible)
                if cible then
                    if e.type ~= "balistique" then son("nanos-world::A_Punch_Cue", cible:GetLocation(), 0.8, 1) end
                    nombres[#nombres + 1] = { pos = cible:GetLocation() + Vector(0, 0, 100), texte = tostring(math.floor(e.montant + 0.5)),
                        style = e.zone == "tete" and JAUNE or BLANC, debut = t }
                end
                if e.source == mon_id then touche_jusqua = t + 0.15 end
                if e.cible == mon_id then hud("touche", e.montant) end
            elseif k == "a_terre" then
                a_terre[e.id] = true
                attaques[e.id], gardes[e.id] = nil, nil
            elseif k == "releve" or k == "reapparition" then
                a_terre[e.id] = nil
            elseif k == "projectile" then
                projectile(e)
            elseif k == "projectile_impact" or k == "projectile_fin" then
                fin_projectile(e.pid)
                if k == "projectile_impact" then etincelles(V(e.pos)) end
            elseif k == "eclair" then
                trait(e.origine, e.direction, e.portee, Color(0.6, 0.8, 1), 0.2)
            elseif k == "tir" and e.id ~= mon_id then
                trait(e.origine, e.direction, 3000, Color(1, 0.9, 0.6), 0.06)
            elseif k == "incantation" and e.id == mon_id then
                hud("incantation", e.sort, e.duree)
            elseif k == "sort_interrompu" and e.id == mon_id then
                hud("refus", "Sort interrompu")
            end
        end
    end)

    ---------------------------------------------------------------- entrees

    Chat.Subscribe("Open", function() chat_ouvert = true end)
    Chat.Subscribe("Close", function() chat_ouvert = false end)

    -- La direction vient du geste de souris des 150 dernieres millisecondes.
    local SEUIL = 14
    Input.Subscribe("MouseMove", function(dx, dy)
        if not actif or famille() ~= "melee" then return end
        local t = maintenant()
        mouvements[#mouvements + 1] = { t, dx or 0, dy or 0 }
        while #mouvements > 0 and t - mouvements[1][1] > 0.15 do table.remove(mouvements, 1) end
        local sx, sy = 0, 0
        for _, m in ipairs(mouvements) do sx, sy = sx + m[2], sy + m[3] end
        if inverser then sy = -sy end
        if math.abs(sx) + math.abs(sy) > SEUIL then
            local d
            if math.abs(sx) > math.abs(sy) then d = sx < 0 and "gauche" or "droite"
            elseif sy < 0 then d = "haut" end
            if d and d ~= direction then
                direction = d
                mouvements = {}
                if en_garde then envoyer("pvp:garde", d) end
            end
        end
        -- En garde, la souris choisit le cote : la camera, elle, suit l'ennemi.
        if en_garde then return false end
    end)

    local function ennemi_proche(portee, cone)
        local p = Client.GetLocalPlayer()
        local moi = perso_de(mon_id)
        if not (p and moi) then return nil end
        local cam, rot = p:GetCameraLocation(), p:GetCameraRotation()
        local avant = rot:GetForwardVector()
        local meilleur, score
        for _, ch in pairs(Character.GetAll()) do
            if ch:IsValid() and ch:GetID() ~= mon_id and ch:GetValue("pvp", false) and not ch:IsDead()
                and camps[ch:GetID()] ~= camps[mon_id] then
                local d = ch:GetLocation() - moi:GetLocation()
                local dist = d:Size()
                if dist < portee then
                    local cosinus = (ch:GetLocation() - cam):GetSafeNormal():Dot(avant)
                    if cosinus > (cone or 0.3) then
                        local s = dist * (2 - cosinus)
                        if not score or s < score then meilleur, score = ch, s end
                    end
                end
            end
        end
        return meilleur
    end

    local function viser()
        local p = Client.GetLocalPlayer()
        local moi = perso_de(mon_id)
        if not (p and moi) then return nil end
        local cam, rot = p:GetCameraLocation(), p:GetCameraRotation()
        local loin = cam + rot:GetForwardVector() * 20000
        local ok, r = pcall(Trace.LineSingle, cam, loin, CollisionChannel.WorldStatic, 0, { moi })
        local point = (ok and r and r.Success) and r.Location or loin
        local origine = moi:GetLocation() + Vector(0, 0, 62)
        return origine, (point - origine):GetSafeNormal()
    end

    Input.Subscribe("MouseDown", function(touche)
        if not actif or chat_ouvert then return end
        local fam = famille()
        if fam == "melee" then
            if touche == "LeftMouseButton" then envoyer("pvp:attaque", "legere", direction) return false end
            if touche == "MiddleMouseButton" then envoyer("pvp:attaque", "lourde", direction) return false end
            if touche == "RightMouseButton" then
                en_garde = true
                envoyer("pvp:garde", direction)
                return false
            end
        elseif fam == "arc" and touche == "LeftMouseButton" then
            bande = true
            envoyer("pvp:bander")
            return false
        end
    end)

    Input.Subscribe("MouseUp", function(touche)
        if not actif then return end
        local fam = famille()
        if fam == "melee" and touche == "RightMouseButton" and en_garde then
            en_garde = false
            envoyer("pvp:garde", false)
            return false
        elseif fam == "arc" and touche == "LeftMouseButton" and bande then
            bande = false
            local o, d = viser()
            if o then envoyer("pvp:decocher", o, d) end
            return false
        end
    end)

    local function direction_esquive()
        if Input.IsKeyDown("A") or Input.IsKeyDown("Q") then return "gauche" end
        if Input.IsKeyDown("D") then return "droite" end
        if Input.IsKeyDown("W") or Input.IsKeyDown("Z") then return "avant" end
        return "arriere"
    end

    Input.Subscribe("KeyPress", function(touche)
        if not actif or chat_ouvert then return end
        local fam = famille()
        if touche == "F" and fam == "melee" then envoyer("pvp:attaque", "lourde", direction) return false end
        if touche == "Q" and fam == "melee" and not Input.IsKeyDown("LeftAlt") then
            -- Q sert aussi a gauche sur un clavier AZERTY : feinte seulement si
            -- une attaque est en cours chez soi.
            if attaques[mon_id] then envoyer("pvp:feinte") return false end
        end
        if touche == "LeftAlt" then envoyer("pvp:esquive", direction_esquive()) return false end
        if SORTS[touche] then
            local cible = nil
            if SORTS[touche] == "soin" then
                local allie = ennemi_proche(900, 0.9)
                cible = allie and allie:GetID()
            end
            envoyer("pvp:sort", SORTS[touche], cible)
            return false
        end
        if touche == "G" then
            local moi = perso_de(mon_id)
            if not moi then return end
            for id in pairs(a_terre) do
                local c = perso_de(id)
                if c and c:GetLocation():Distance(moi:GetLocation()) < 180 then
                    envoyer(camps[id] == camps[mon_id] and "pvp:relever" or "pvp:achever", id)
                    return false
                end
            end
        end
    end)

    Chat.Subscribe("PlayerSubmit", function(message)
        if tostring(message) == "/pvp inverser" then
            inverser = not inverser
            Chat.AddMessage("Geste vertical " .. (inverser and "inverse" or "normal"))
            return false
        end
    end)

    ---------------------------------------------------------------- chaque image

    Client.Subscribe("Tick", function(dt)
        local t = maintenant()
        -- Projectiles : on les fait voler ; ceux du joueur detectent le decor.
        for pid, p in pairs(projectiles) do
            local suivant = p.pos + p.vitesse * dt
            p.vitesse = p.vitesse - Vector(0, 0, 980 * p.gravite * dt)
            if p.mien then
                local ok, r = pcall(Trace.LineSingle, p.pos, suivant, CollisionChannel.WorldStatic, 0, {})
                if ok and r and r.Success then
                    envoyer("pvp:impact", pid, r.Location)
                    fin_projectile(pid)
                    goto continue
                end
            end
            p.pos = suivant
            if p.objet:IsValid() then p.objet:SetLocation(suivant) end
            ::continue::
        end
        for i = #traits, 1, -1 do
            if t >= traits[i].fin then
                if traits[i].objet:IsValid() then traits[i].objet:Destroy() end
                table.remove(traits, i)
            end
        end
        -- En garde : la camera se cale sur l'ennemi le plus proche.
        if actif and en_garde then
            local e = ennemi_proche(1500, 0.2)
            local p = Client.GetLocalPlayer()
            if e and p then
                local cam = p:GetCameraLocation()
                local voulu = (e:GetLocation() + Vector(0, 0, 40) - cam):ToOrientationRotator()
                local r = p:GetCameraRotation()
                local dyaw = ((voulu.Yaw - r.Yaw + 180) % 360) - 180
                p:SetCameraRotation(Rotator(r.Pitch + (voulu.Pitch - r.Pitch) * 0.25, r.Yaw + dyaw * 0.25, 0))
            end
        end
    end)

    ---------------------------------------------------------------- canvas

    local canvas = Canvas(true, Color.TRANSPARENT, 0, true, true)
    canvas:Subscribe("Update", function(c, largeur, hauteur)
        if not actif then return end
        local t = maintenant()
        -- Au-dessus des ennemis : l'attaque qui arrive, cote a garder, et sa garde.
        for id, a in pairs(attaques) do
            local ch = perso_de(id)
            if ch and id ~= mon_id then
                local e = Viewport.ProjectWorldToScreen(ch:GetLocation() + Vector(0, 0, 120))
                if e and e.X > 0 and e.X < largeur and e.Y > 0 and e.Y < hauteur then
                    local reste = math.max(0, (a.fin - t) / math.max(0.01, a.fin - a.debut))
                    local style = a.force == "lourde" and ROUGE or JAUNE
                    Pseudo.Dessiner(c, SYMBOLE[MIROIR[a.dir]] or "?", e.X, e.Y, 1.6, style)
                    c:DrawLine(Vector2D(e.X - 30, e.Y + 6), Vector2D(e.X - 30 + 60 * reste, e.Y + 6), 5, style.couleur)
                end
            end
        end
        for id, dir in pairs(gardes) do
            local ch = perso_de(id)
            if ch and id ~= mon_id and dir and not attaques[id] then
                local e = Viewport.ProjectWorldToScreen(ch:GetLocation() + Vector(0, 0, 120))
                if e and e.X > 0 and e.X < largeur then
                    Pseudo.Dessiner(c, "[" .. (SYMBOLE[dir] or "") .. "]", e.X, e.Y, 0.9, GRIS)
                end
            end
        end
        -- Sa propre garde, autour du viseur.
        local cx, cy = largeur / 2, hauteur / 2
        if en_garde then
            local pos = { gauche = { cx - 70, cy + 10 }, droite = { cx + 70, cy + 10 }, haut = { cx, cy - 55 } }
            local pz = pos[direction]
            Pseudo.Dessiner(c, SYMBOLE[direction], pz[1], pz[2], 1.2, BLANC)
        end
        if t < touche_jusqua then Pseudo.Dessiner(c, "x", cx, cy + 12, 1.3, ROUGE) end
        -- Degats flottants.
        for i = #nombres, 1, -1 do
            local n = nombres[i]
            local age = t - n.debut
            if age > 1 then
                table.remove(nombres, i)
            else
                local e = Viewport.ProjectWorldToScreen(n.pos + Vector(0, 0, age * 60))
                if e and e.X > 0 and e.X < largeur then Pseudo.Dessiner(c, n.texte, e.X, e.Y, 1.1, n.style) end
            end
        end
        -- Un ennemi a terre : G pour l'achever, un allie : G pour le relever.
        for id in pairs(a_terre) do
            local ch = perso_de(id)
            if ch then
                local e = Viewport.ProjectWorldToScreen(ch:GetLocation() + Vector(0, 0, 60))
                if e and e.X > 0 and e.X < largeur then
                    Pseudo.Dessiner(c, camps[id] == camps[mon_id] and "G relever" or "G achever", e.X, e.Y, 0.8, GRIS)
                end
            end
        end
    end)
end
