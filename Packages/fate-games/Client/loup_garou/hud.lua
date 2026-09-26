-- HUD du Loup-Garou, cote client (maquettes : scripts/affiche/hud_loup_garou.html).
--
-- Le moteur (Server/games/werewolf/) envoie les evenements ci-dessous ; /lg demo
-- les joue sur place, sans partie, pour voir le HUD. Pour jouer : /lg entrer
-- (et /lg bots N en dev), traites par le serveur.
--
--   ww:salon    (vue | nil)       panneau d'attente : joueurs, pret, reglages
--                                 { joueurs = { { nom, pret, moi } }, max,
--                                   compo = { [role] = n }, debat, createur }
--   ww:role     (role, allies)    prive : revelation puis rappel ; allies :
--                                 { { id, nom } } (les autres loups)
--   ww:phase    (id, duree)       bandeau et minuteur ; id : voir PHASES
--   ww:votes    (compte)          { [id de personnage] = voix } du vote en cours
--   ww:vision   (nom, role)       resultat de la voyante, dans son rappel
--   ww:amoureux (id, nom)         prive : lie par Cupidon a ce joueur
--   ww:annonce  (texte)           message transitoire
--   ww:mort     ()                on est mort : plus de designation
--   ww:fin      ()                fin de partie : tout se range
--
-- Vers le serveur : ww:designer (id), ww:pret, ww:reglage (cle, +1 | -1).
--
-- Fixe a l'ecran : page WebUI (hud.html). Au-dessus des tetes (invites,
-- compteurs de voix, loups allies, amoureux) : Canvas, sans retard.

return function(config)
    config = config or {}
    local PORTEE = config.portee or 1500
    local CONE = math.cos(math.rad(config.cone or 10))
    local IMG = "package://fate-games/Client/loup_garou/hud/"

    -- Roles : identifiant du moteur, image de la carte, nom affiche.
    local ROLES = {
        wolf       = { image = "loup",       nom = "Loup-Garou", article = "" },
        white_wolf = { image = "loup_blanc", nom = "Loup Blanc", article = "le " },
        villager   = { image = "villageois", nom = "Villageois", article = "" },
        seer       = { image = "voyante",    nom = "Voyante",    article = "la " },
        hunter     = { image = "chasseur",   nom = "Chasseur",   article = "le " },
        guard      = { image = "gardien",    nom = "Gardien",    article = "le " },
        cupid      = { image = "cupidon",    nom = "Cupidon",    article = "" },
    }
    local ALIAS = { loup = "wolf", loup_blanc = "white_wolf", villageois = "villager", voyante = "seer",
        chasseur = "hunter", gardien = "guard", cupidon = "cupid" }
    local function role_id(r) return ROLES[r] and r or ALIAS[r] end

    -- Phases : bandeau, qui peut designer, invite et consigne.
    local PHASES = {
        night_cupid      = { texte = "Nuit · Cupidon lie deux amoureux", icone = "lune", qui = { cupid = true },
            invite = "lg_lier", consigne = "Regarde deux joueurs et appuie sur [E] pour les lier" },
        night_guard      = { texte = "Nuit · Le gardien veille", icone = "lune", qui = { guard = true },
            invite = "lg_proteger", consigne = "Regarde un joueur et appuie sur [E] pour le protéger cette nuit" },
        night_wolves     = { texte = "Nuit · Les loups choisissent", icone = "lune", qui = { wolf = true, white_wolf = true },
            invite = "lg_designer", consigne = "Regarde un joueur et appuie sur [E] pour le désigner" },
        night_white_wolf = { texte = "Nuit · Le loup blanc rôde", icone = "lune", qui = { white_wolf = true },
            invite = "lg_designer", consigne = "Tu peux dévorer un loup : regarde-le et appuie sur [E]" },
        night_seer       = { texte = "Nuit · La voyante sonde", icone = "lune", qui = { seer = true },
            invite = "lg_sonder", consigne = "Regarde un joueur et appuie sur [E] pour découvrir son rôle" },
        dawn             = { texte = "Aube", icone = "soleil" },
        hunter_shot      = { texte = "Le chasseur tire", icone = "soleil", qui = { hunter = true },
            invite = "lg_tirer", consigne = "Tu es mort : regarde un joueur et appuie sur [E] pour l'emporter avec toi" },
        day_debate       = { texte = "Jour · Débat", icone = "soleil" },
        day_vote         = { texte = "Jour · Le village vote", icone = "soleil", qui = "tous",
            invite = "lg_voter", consigne = "Regarde un joueur et appuie sur [E] pour voter contre lui" },
        execution        = { texte = "Jour · Exécution", icone = "soleil" },
    }
    local LARGEUR_INVITE = { lg_designer = 196, lg_voter = 170, lg_proteger = 192, lg_lier = 150, lg_tirer = 158, lg_sonder = 176 }

    -- Reglages du salon, dans l'ordre du panneau : cle, nom, bornes, pas.
    local REGLAGES = {
        { cle = "max",        nom = "Joueurs",     min = 4, max = 12, pas = 1 },
        { cle = "wolf",       nom = "Loups-Garous", min = 1, max = 4,  pas = 1, image = "loup" },
        { cle = "white_wolf", nom = "Loup Blanc",  min = 0, max = 1,  pas = 1, image = "loup_blanc" },
        { cle = "seer",       nom = "Voyante",     min = 0, max = 1,  pas = 1, image = "voyante" },
        { cle = "hunter",     nom = "Chasseur",    min = 0, max = 1,  pas = 1, image = "chasseur" },
        { cle = "guard",      nom = "Gardien",     min = 0, max = 1,  pas = 1, image = "gardien" },
        { cle = "cupid",      nom = "Cupidon",     min = 0, max = 1,  pas = 1, image = "cupidon" },
        { cle = "debat",      nom = "Débat",       min = 60, max = 300, pas = 30 },
    }

    local pret_page = false
    local file = {}
    local function neuf()
        return { role = nil, allies = {}, phase = nil, votes = {}, mort = false, salon = nil,
            vise = nil, amoureux = nil, ligne = 1, demo = false }
    end
    local etat = neuf()
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
        if not (ph and ph.qui) then return false end
        -- Le chasseur tire une fois mort ; les autres, vivants seulement.
        if etat.mort and etat.phase ~= "hunter_shot" then return false end
        return ph.qui == "tous" or ph.qui[etat.role] == true
    end

    -- Le panneau du salon : la vue du serveur, plus les lignes de reglage.
    local function dessiner_salon()
        local v = etat.salon
        if not v then return appeler("lg:salon", nil) end
        local compo, speciaux = v.compo or {}, 0
        local lignes = {}
        for i, r in ipairs(REGLAGES) do
            local valeur = r.cle == "max" and v.max or (r.cle == "debat" and v.debat or compo[r.cle] or 0)
            if r.image then speciaux = speciaux + (compo[r.cle] or 0) end
            lignes[i] = { nom = r.nom, image = r.image,
                valeur = r.cle == "debat" and (("%d:%02d"):format(valeur // 60, valeur % 60)) or tostring(valeur),
                choisie = v.createur and i == etat.ligne or false }
        end
        appeler("lg:salon", { joueurs = v.joueurs, max = v.max, createur = v.createur, lignes = lignes,
            villageois = math.max(0, #(v.joueurs or {}) - speciaux) })
    end

    local H = {}

    function H.salon(vue)
        etat.salon = vue
        dessiner_salon()
    end

    function H.role(role, allies)
        local id = role_id(role)
        local r = ROLES[id]
        if not r then return end
        etat.role = id
        etat.allies = {}
        local noms = {}
        for _, a in ipairs(allies or {}) do
            etat.allies[a.id] = true
            noms[#noms + 1] = a.nom
        end
        local texte_allies = #noms > 0 and ((#noms > 1 and "Tes alliés : " or "Ton allié : ") .. table.concat(noms, ", ")) or ""
        etat.salon = nil
        appeler("lg:salon", nil)
        appeler("lg:revelation", { image = r.image, nom = r.nom, article = r.article, allies = texte_allies,
            petit = #noms > 0 and ("avec " .. table.concat(noms, ", ")) or "" })
    end

    function H.phase(id, duree)
        etat.phase = id
        etat.votes = {}
        local ph = PHASES[id]
        appeler("lg:phase", ph and { texte = ph.texte, icone = ph.icone, duree = duree } or nil)
        appeler("lg:message", peut_designer() and ph.consigne or "", 6)
    end

    function H.votes(compte) etat.votes = compte or {} end

    local function rappel(petit)
        local moi = etat.role and ROLES[etat.role]
        if moi then appeler("lg:rappel", { image = moi.image, nom = moi.nom, petit = petit }) end
    end

    function H.vision(nom, role)
        local r = ROLES[role_id(role) or ""]
        if r then rappel(("%s est %s"):format(tostring(nom), r.nom)) end
    end

    function H.amoureux(id, nom)
        etat.amoureux = id
        rappel("Amoureux de " .. tostring(nom))
        appeler("lg:message", ("Cupidon t'a lié à %s : si l'un meurt, l'autre aussi."):format(tostring(nom)), 6)
    end

    function H.annonce(texte) appeler("lg:message", texte, 5) end

    function H.mort()
        etat.mort = true
        if etat.role ~= "hunter" then appeler("lg:message", "Tu es mort. Tu peux encore regarder la partie.", 6) end
    end

    function H.fin()
        etat = neuf()
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
        if not etat.phase and not next(etat.allies) and not etat.amoureux then return end
        local player = Client.GetLocalPlayer()
        if not player then return end
        local moi = player:GetControlledCharacter()
        local mon_id = moi and moi:GetID()
        local camera, rotation = player:GetCameraLocation(), player:GetCameraRotation()
        if not (camera and rotation) then return end
        local avant = rotation:GetForwardVector()
        local designer = peut_designer()
        local ph = etat.phase and PHASES[etat.phase]

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
        local vise_id = meilleur and meilleur:GetID()

        for _, e in ipairs(poses) do
            local id, y = e.ch:GetID(), e.y
            local n = etat.votes[id]
            if n and n > 0 then
                sprite(c, ("voix_%d%s"):format(math.min(12, n), n == max and "_tete" or ""), e.x, y - 14 * e.s, 96, 56, e.s)
                y = y - 40 * e.s
            end
            if etat.allies[id] or etat.amoureux == id then
                local x = e.x
                if etat.allies[id] and etat.amoureux == id then
                    sprite(c, "lg_allie", x - 28 * e.s, y - 24 * e.s, 62, 62, e.s)
                    sprite(c, "lg_coeur", x + 28 * e.s, y - 22 * e.s, 56, 52, e.s)
                elseif etat.allies[id] then
                    sprite(c, "lg_allie", x, y - 24 * e.s, 62, 62, e.s)
                else
                    sprite(c, "lg_coeur", x, y - 22 * e.s, 56, 52, e.s)
                end
                y = y - 50 * e.s
            end
            if id == vise_id and ph and ph.invite then
                sprite(c, ph.invite, e.x, y - 22 * e.s, LARGEUR_INVITE[ph.invite] or 190, 62, e.s)
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

    -- Hors moteur (demo), les reglages s'appliquent sur place, dans leurs bornes.
    local function regler_localement(r, sens)
        local v = etat.salon
        if r.cle == "max" then
            v.max = math.max(r.min, math.min(r.max, v.max + sens * r.pas))
        elseif r.cle == "debat" then
            v.debat = math.max(r.min, math.min(r.max, v.debat + sens * r.pas))
        else
            v.compo[r.cle] = math.max(r.min, math.min(r.max, (v.compo[r.cle] or 0) + sens * r.pas))
        end
    end

    Chat.Subscribe("Open", function() chat_ouvert = true end)
    Chat.Subscribe("Close", function() chat_ouvert = false end)

    Input.Subscribe("KeyPress", function(touche)
        if chat_ouvert then return end
        if touche == "E" and etat.vise and peut_designer() and etat.vise:IsValid() then
            Events.CallRemote("ww:designer", Reliability.Reliable, etat.vise:GetID())
            return false
        end
        local v = etat.salon
        if not v then return end
        if touche == "R" then
            if etat.demo then
                for _, j in ipairs(v.joueurs) do if j.moi then j.pret = not j.pret end end
                dessiner_salon()
            else
                Events.CallRemote("ww:pret", Reliability.Reliable)
            end
            return false
        end
        if not v.createur then return end
        if touche == "Up" or touche == "Down" then
            etat.ligne = (etat.ligne - 1 + (touche == "Down" and 1 or -1)) % #REGLAGES + 1
            dessiner_salon()
            return false
        elseif touche == "Left" or touche == "Right" then
            local r, sens = REGLAGES[etat.ligne], touche == "Right" and 1 or -1
            if etat.demo then
                regler_localement(r, sens)
                dessiner_salon()
            else
                Events.CallRemote("ww:reglage", Reliability.Reliable, r.cle, sens)
            end
            return false
        end
    end)

    ---------------------------------------------------------------- /lg demo : le HUD sans partie

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

    local function allie_demo()
        local v = voisins()
        return v[1] and { { id = v[1]:GetID(), nom = nom_de(v[1], 1) } } or {}
    end

    local function devenir(role)
        etat.mort = false
        H.role(role, (role == "wolf" or role == "white_wolf") and allie_demo() or {})
    end

    local DEMO = {
        salon = function()
            local joueurs = { { nom = "Toi", pret = true, moi = true } }
            for i, ch in ipairs(voisins()) do
                if #joueurs >= 8 then break end
                joueurs[#joueurs + 1] = { nom = nom_de(ch, i), pret = i % 2 == 1 }
            end
            while #joueurs < 6 do joueurs[#joueurs + 1] = { nom = "Invité " .. #joueurs, pret = false } end
            etat.demo, etat.ligne = true, 1
            H.salon({ joueurs = joueurs, max = 10, createur = true, debat = 180,
                compo = { wolf = 2, white_wolf = 0, seer = 1, hunter = 1, guard = 0, cupid = 0 } })
        end,
        role = function(r) devenir(role_id(r or "wolf") or "wolf") end,
        nuit = function()
            local v = voisins()
            H.salon(nil)
            if etat.role ~= "wolf" and etat.role ~= "white_wolf" then devenir("wolf") end
            H.phase("night_wolves", 45)
            if v[2] then H.votes({ [v[2]:GetID()] = 1 }) end
        end,
        gardien = function() H.salon(nil); devenir("guard"); H.phase("night_guard", 20) end,
        cupidon = function() H.salon(nil); devenir("cupid"); H.phase("night_cupid", 25) end,
        voyante = function() H.salon(nil); devenir("seer"); H.phase("night_seer", 20) end,
        amoureux = function()
            local v = voisins()
            if not etat.role then devenir("villager") end
            if v[1] then H.amoureux(v[1]:GetID(), nom_de(v[1], 1)) end
        end,
        chasseur = function()
            H.salon(nil); devenir("hunter"); H.mort(); H.phase("hunter_shot", 15)
        end,
        jour = function()
            local v = voisins()
            H.salon(nil)
            if not etat.role then devenir("villager") end
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
        -- /lg entrer, /lg sortir, /lg bots : pour le serveur, on laisse passer.
        if mots[1] ~= "/lg" or mots[2] ~= "demo" then return end
        local f = DEMO[mots[3] or ""]
        if f then
            f(mots[4])
        else
            Chat.AddMessage("/lg demo salon | role [loup|loup_blanc|voyante|chasseur|gardien|cupidon|villageois]")
            Chat.AddMessage("/lg demo nuit | gardien | cupidon | voyante | chasseur | amoureux | jour | stop")
        end
        return false
    end)
end
