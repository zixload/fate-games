-- HUD du Loup-Garou, cote client (maquettes : scripts/affiche/hud_loup_garou.html).
--
-- Le moteur (docs/superpowers/specs/2026-09-15-loup-garou-design.md) n'est pas
-- encore ecrit : ce fichier fixe les evenements qu'il enverra, et /lg les joue
-- pour voir le HUD en jeu sans lui.
--
--   ww:salon   (vue | nil)        panneau d'attente : joueurs, pret, composition
--   ww:role    (role, allies)     prive : revelation puis rappel ; allies :
--                                  { { id, nom } } (les autres loups)
--   ww:phase   (id, duree)        bandeau et minuteur ; id d'une phase de la spec
--   ww:votes   (compte)           { [id de personnage] = voix } du vote en cours
--   ww:vision  (nom, role)        resultat de la voyante, dans son rappel
--   ww:annonce (texte)            message transitoire
--   ww:mort    ()                 on est mort : plus de designation
--   ww:fin     ()                 fin de partie : tout se range
--
-- Fixe a l'ecran : page WebUI (hud.html). Au-dessus des tetes (invite
-- Designer / Voter, compteurs de voix, loups allies) : Canvas, comme les
-- barillets de Liar's Bar, pour suivre la camera sans retard.

return function(config)
    config = config or {}
    local PORTEE = config.portee or 1500
    local CONE = math.cos(math.rad(config.cone or 10))
    local IMG = "package://fate-games/Client/loup_garou/hud/"

    local ROLES = {
        wolf     = { image = "loup",       nom = "Loup-Garou", article = "" },
        villager = { image = "villageois", nom = "Villageois", article = "" },
        seer     = { image = "voyante",    nom = "Voyante",    article = "la " },
    }
    ROLES.loup, ROLES.villageois, ROLES.voyante = ROLES.wolf, ROLES.villager, ROLES.seer

    local PHASES = {
        night_wolves = { texte = "Nuit · Les loups choisissent", icone = "lune", designe = "wolf" },
        night_seer   = { texte = "Nuit · La voyante sonde",      icone = "lune", designe = "seer" },
        dawn         = { texte = "Aube",                          icone = "soleil" },
        day_debate   = { texte = "Jour · Débat",                  icone = "soleil" },
        day_vote     = { texte = "Jour · Le village vote",        icone = "soleil", designe = "tous" },
        execution    = { texte = "Jour · Exécution",              icone = "soleil" },
    }

    local pret_page = false
    local file = {}   -- appels en attente du chargement de la page
    local etat = { role = nil, allies = {}, phase = nil, votes = {}, mort = false, salon = nil, vise = nil }
    local chat_ouvert = false

    local page = WebUI("loup-garou", "file://loup_garou/hud.html",
        WidgetVisibility.VisibleNotHitTestable, true, true)
    local function appeler(evenement, ...)
        if pret_page then return page:CallEvent(evenement, ...) end
        file[#file + 1] = { evenement, table.pack(...) }
    end
    local function prete()
        if pret_page then return end
        pret_page = true
        for _, a in ipairs(file) do page:CallEvent(a[1], table.unpack(a[2], 1, a[2].n)) end
        file = {}
    end
    page:Subscribe("Ready", prete)
    page:Subscribe("pret", prete)

    ---------------------------------------------------------------- etat

    local function peut_designer()
        local ph = etat.phase and PHASES[etat.phase]
        if etat.mort or not (ph and ph.designe) then return false end
        return ph.designe == "tous" or ph.designe == etat.role
    end

    local function consigne()
        local ph = etat.phase and PHASES[etat.phase]
        if not peut_designer() then return "" end
        if ph.designe == "wolf" then return "Regarde un joueur et appuie sur [E] pour le désigner" end
        if ph.designe == "seer" then return "Regarde un joueur et appuie sur [E] pour découvrir son rôle" end
        return "Regarde un joueur et appuie sur [E] pour voter contre lui"
    end

    local H = {}

    function H.salon(vue)
        etat.salon = vue
        appeler("lg:salon", vue)
    end

    function H.role(role, allies)
        local r = ROLES[role]
        if not r then return end
        etat.role = ROLES[role] == ROLES.wolf and "wolf" or (ROLES[role] == ROLES.seer and "seer" or "villager")
        etat.allies = {}
        local noms = {}
        for _, a in ipairs(allies or {}) do
            etat.allies[a.id] = true
            noms[#noms + 1] = a.nom
        end
        local texte_allies = #noms > 0 and ((#noms > 1 and "Tes alliés : " or "Ton allié : ") .. table.concat(noms, ", ")) or ""
        appeler("lg:salon", nil)
        appeler("lg:revelation", { image = r.image, nom = r.nom, article = r.article, allies = texte_allies,
            petit = #noms > 0 and ("avec " .. table.concat(noms, ", ")) or "" })
    end

    function H.phase(id, duree)
        etat.phase = id
        etat.votes = {}
        local ph = PHASES[id]
        appeler("lg:phase", ph and { texte = ph.texte, icone = ph.icone, duree = duree } or nil)
        appeler("lg:message", consigne(), 6)
    end

    function H.votes(compte)
        etat.votes = compte or {}
    end

    function H.vision(nom, role)
        local r = ROLES[role]
        if not (r and etat.role) then return end
        local moi = ROLES[etat.role]
        appeler("lg:rappel", { image = moi.image, nom = moi.nom, petit = ("%s est %s"):format(tostring(nom), r.nom) })
    end

    function H.annonce(texte) appeler("lg:message", texte, 5) end

    function H.mort()
        etat.mort = true
        appeler("lg:message", "Tu es mort. Tu peux encore regarder la partie.", 6)
    end

    function H.fin()
        etat = { role = nil, allies = {}, phase = nil, votes = {}, mort = false, salon = nil, vise = nil }
        appeler("lg:cacher")
    end

    for nom, f in pairs(H) do
        Events.SubscribeRemote("ww:" .. nom, f)
    end

    ---------------------------------------------------------------- au-dessus des tetes

    local function tete(character)
        local ok, tr = pcall(function() return character:GetSocketTransform("Head") end)
        local l = ok and tr and tr.Location
        local o = character:GetLocation()
        if l and l.X and math.abs(l.Z - o.Z) < 250 then return Vector(l.X, l.Y, l.Z) end
        return Vector(o.X, o.Y, o.Z + 85)
    end

    local function sprite(c, nom, x, y, l, h, s)
        local w, hh = l * s, h * s
        c:DrawTexture(IMG .. nom .. ".png", Vector2D(x - w / 2, y - hh / 2), Vector2D(w, hh),
            Vector2D(0, 0), Vector2D(1, 1), Color.WHITE, BlendMode.AlphaBlend, 0, Vector2D(0.5, 0.5))
    end

    local function dessiner(c, largeur, hauteur)
        etat.vise = nil
        if not etat.phase and not next(etat.allies) then return end
        local player = Client.GetLocalPlayer()
        if not player then return end
        local moi = player:GetControlledCharacter()
        local mon_id = moi and moi:GetID()
        local camera, rotation = player:GetCameraLocation(), player:GetCameraRotation()
        if not (camera and rotation) then return end
        local avant = rotation:GetForwardVector()
        local designer = peut_designer()
        local ph = etat.phase and PHASES[etat.phase]

        -- Le compteur le plus haut, cerne de rouge.
        local max = 0
        for _, n in pairs(etat.votes) do if n > max then max = n end end

        local meilleur, meilleur_cos = nil, CONE
        local poses = {}
        for _, class in ipairs({ CharacterSimple, Character }) do
            for _, ch in pairs(class.GetAll()) do
                if ch:IsValid() and ch:GetID() ~= mon_id then
                    local t = tete(ch)
                    local dx, dy, dz = t.X - camera.X, t.Y - camera.Y, t.Z - camera.Z
                    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
                    local cosinus = d > 1 and (dx * avant.X + dy * avant.Y + dz * avant.Z) / d or -1
                    if d < PORTEE and cosinus > 0 then
                        local p = Viewport.ProjectWorldToScreen(Vector(t.X, t.Y, t.Z + 58))
                        if p and type(p.X) == "number" and p.X > 0 and p.X < largeur and p.Y > 0 and p.Y < hauteur then
                            poses[#poses + 1] = { ch = ch, x = p.X, y = p.Y, s = math.max(0.75, math.min(1, 700 / d)) }
                            if designer and cosinus > meilleur_cos then meilleur, meilleur_cos = ch, cosinus end
                        end
                    end
                end
            end
        end
        etat.vise = meilleur

        for _, e in ipairs(poses) do
            local id, y = e.ch:GetID(), e.y
            local n = etat.votes[id]
            if n and n > 0 then
                sprite(c, ("voix_%d%s"):format(math.min(12, n), n == max and "_tete" or ""), e.x, y - 14 * e.s, 96, 56, e.s)
                y = y - 40 * e.s
            end
            if etat.allies[id] then
                sprite(c, "lg_allie", e.x, y - 24 * e.s, 62, 62, e.s)
                y = y - 50 * e.s
            end
            if meilleur and id == meilleur:GetID() then
                local invite = ph and ph.designe == "tous" and "lg_voter" or "lg_designer"
                sprite(c, invite, e.x, y - 22 * e.s, invite == "lg_voter" and 170 or 196, 62, e.s)
            end
        end
    end

    local canvas = Canvas(true, Color.TRANSPARENT, 0, true, true)
    local erreur_signalee = false
    canvas:Subscribe("Update", function(self, largeur, hauteur)
        local ok, err = pcall(dessiner, self, largeur, hauteur)
        if not ok and not erreur_signalee then
            Console.Error("[loup-garou HUD] " .. tostring(err))
            erreur_signalee = true
        elseif ok then
            erreur_signalee = false
        end
    end)

    ---------------------------------------------------------------- touches

    Chat.Subscribe("Open", function() chat_ouvert = true end)
    Chat.Subscribe("Close", function() chat_ouvert = false end)

    Input.Subscribe("KeyPress", function(touche)
        if chat_ouvert then return end
        if touche == "E" and etat.vise and peut_designer() and etat.vise:IsValid() then
            Events.CallRemote("ww:designer", Reliability.Reliable, etat.vise:GetID())
            return false
        end
        if etat.salon then
            if touche == "R" then
                Events.CallRemote("ww:pret", Reliability.Reliable)
                return false
            elseif touche == "Left" or touche == "Right" then
                Events.CallRemote("ww:debat", Reliability.Reliable, touche == "Right" and 1 or -1)
                return false
            end
        end
    end)

    ---------------------------------------------------------------- /lg : demonstration sans moteur

    -- Les personnages autour de soi, pour peupler la demo.
    local function voisins()
        local out = {}
        local player = Client.GetLocalPlayer()
        local moi = player and player:GetControlledCharacter()
        local mon_id = moi and moi:GetID()
        for _, class in ipairs({ CharacterSimple, Character }) do
            for _, ch in pairs(class.GetAll()) do
                if ch:IsValid() and ch:GetID() ~= mon_id then out[#out + 1] = ch end
            end
        end
        return out
    end

    local function nom_de(ch, i)
        local p = ch:GetPlayer()
        return p and p:GetName() or ("Joueur " .. i)
    end

    local DEMO = {
        salon = function()
            local joueurs = { { nom = "Toi", pret = true, moi = true } }
            for i, ch in ipairs(voisins()) do
                if #joueurs >= 8 then break end
                joueurs[#joueurs + 1] = { nom = nom_de(ch, i), pret = i % 2 == 1 }
            end
            while #joueurs < 5 do joueurs[#joueurs + 1] = { nom = "Invité " .. #joueurs, pret = false } end
            H.salon({ joueurs = joueurs, max = 12, compo = { loups = 2, voyante = 1, villageois = #joueurs - 3 }, debat = 180 })
        end,
        role = function()
            local v = voisins()
            H.role("wolf", v[1] and { { id = v[1]:GetID(), nom = nom_de(v[1], 1) } } or {})
        end,
        voyante = function() H.role("seer", {}) end,
        nuit = function()
            local v = voisins()
            H.salon(nil)
            if not etat.role then H.role("wolf", v[1] and { { id = v[1]:GetID(), nom = nom_de(v[1], 1) } } or {}) end
            H.phase("night_wolves", 45)
            if v[2] then H.votes({ [v[2]:GetID()] = 1 }) end
        end,
        jour = function()
            local v = voisins()
            H.salon(nil)
            H.phase("day_vote", 45)
            local compte = {}
            for i, ch in ipairs(v) do compte[ch:GetID()] = ({ 2, 1, 0 })[i] or 0 end
            H.votes(compte)
            if v[1] then H.annonce(("%s vote contre %s"):format("Ana", nom_de(v[1], 1))) end
        end,
        stop = function() H.fin() end,
    }

    Chat.Subscribe("PlayerSubmit", function(message)
        local mots = {}
        for m in tostring(message):gmatch("%S+") do mots[#mots + 1] = m end
        if mots[1] ~= "/lg" then return end
        local f = DEMO[mots[2] or ""]
        if f then
            f()
        else
            Chat.AddMessage("/lg salon | role | voyante | nuit | jour | stop  (démo du HUD, sans moteur)")
        end
        return false
    end)
end
