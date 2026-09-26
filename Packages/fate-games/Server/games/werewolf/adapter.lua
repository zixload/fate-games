-- Adaptateur du loup-garou : le seul fichier du jeu qui connait nanos world.
-- Il tient le salon, fait avancer le moteur (engine.lua), traduit ses effets
-- en evenements du HUD (Client/loup_garou/hud.lua) et fait jouer les bots de
-- test. La logique du jeu n'est pas ici.
--
-- En attendant la cloche du decor : /lg entrer, /lg sortir, /lg bots N (dev).
-- Hors de cette version : lumiere du jour et de la nuit, bras tendus, corps au
-- sol (effets recus, ignores).
--
-- Le resultat d'une partie terminee s'ecrit en base (werewolf_matches et
-- werewolf_participants, migration 5), sauf avec des bots.
--
-- Decor (docs/WEREWOLF-ASSETS-IMPORT.md) : le serveur pose le tapis et un
-- zabuton par joueur sur un cercle autour du centre, symetriques par calcul ;
-- rien n'est place a la main dans la map. /lg centre (dev) enregistre le centre
-- a ses pieds dans loup_garou.json, a cote de l'executable du serveur.

return function(Log, DB, Ids, Characters, Engine, Roles, Match, config)
    local A = {}
    config = config or {}
    local TICK = config.tick or 0.25
    local RAYON = config.rayon or 212     -- cercle des places (docs/WEREWOLF-ASSETS-IMPORT.md)

    local NOMS_ROLES = { wolf = "Loup-Garou", white_wolf = "Loup Blanc", villager = "Villageois",
        seer = "Voyante", hunter = "Chasseur", guard = "Gardien", cupid = "Cupidon", witch = "Sorcière" }
    local GAGNANTS = { village = "Le village gagne !", wolves = "Les loups-garous gagnent !",
        white_wolf = "Le loup blanc gagne seul !", lovers = "Les amoureux gagnent !",
        none = "Partie terminée sans vainqueur." }

    ---------------------------------------------------------------- voix

    -- La voix d'une partie passe par trois canaux globaux (doc Player :
    -- SetVOIPGlobalChannelSetting, 1 a 63) ; la voix de proximite est coupee
    -- pendant la partie. Un reglage par situation (effet voice_channel) :
    --   sleep    la nuit, qui n'est pas loup : ni parler ni entendre
    --   wolves   la nuit, les loups entre eux
    --   village  le jour, tout le monde, a volume egal quelle que soit la distance
    --   dead     les morts entre eux ; ils ecoutent les vivants sans leur parler
    --   normal   hors partie : la proximite, comme partout sur la map
    local CANAUX = config.canaux or { village = 10, wolves = 11, dead = 12 }
    local N, E, D = VOIPSetting.None, VOIPSetting.ListenOnly, VOIPSetting.Both
    local VOIX = {
        sleep   = { locale = N, village = N, wolves = N, dead = N },
        wolves  = { locale = N, village = N, wolves = D, dead = N },
        village = { locale = N, village = D, wolves = N, dead = N },
        dead    = { locale = N, village = E, wolves = E, dead = D },
        normal  = { locale = D, village = N, wolves = N, dead = N },
    }
    local MESSAGES_VOIX = {
        sleep  = "Tu dors : personne ne t'entend.",
        wolves = "Seuls les loups t'entendent.",
        dead   = "Seuls les morts t'entendent. Tu écoutes encore les vivants.",
    }
    local voix_actuelle = {}   -- id -> situation

    local function regler_voix(id, situation)
        if not id or id < 0 then return end   -- les bots n'ont pas de voix
        local p
        for _, pl in pairs(Player.GetPairs()) do
            if pl:IsValid() and pl:GetID() == id then p = pl break end
        end
        local v = VOIX[situation]
        if not (p and v) then return end
        local ok, err = pcall(function()
            p:SetVOIPLocalSetting(v.locale)
            for canal, numero in pairs(CANAUX) do p:SetVOIPGlobalChannelSetting(numero, v[canal]) end
            if config.volume then p:SetVOIPGlobalVolume(config.volume) end
        end)
        if not ok then Log.Warn("werewolf", "voix : " .. tostring(err)) return end
        if voix_actuelle[id] ~= situation then
            voix_actuelle[id] = situation
            if MESSAGES_VOIX[situation] then
                Events.CallRemote("ww:annonce", p, Reliability.Reliable, MESSAGES_VOIX[situation])
            end
        end
    end

    local s = Engine.nouveau()
    local salon = { ordre = {}, pret = {}, createur = nil, max = 10, debat = 180,
        compo = Roles.par_defaut(6), centre = nil }
    local bots = {}          -- id negatif -> { nom, corps }
    local decor = { centre = nil, objets = {}, places = {} }   -- places : id -> { x, y, yaw }
    local memoires = {}      -- id de bot -> ce qu'il retient (bots.lua)
    local prochain_bot = -1

    local function rng(k) return math.random(k) end

    ---------------------------------------------------------------- joueurs et personnages

    local function membre(id)
        for _, m in ipairs(salon.ordre) do if m == id then return true end end
        return false
    end

    local function joueur(id)
        if not id or id < 0 then return nil end
        for _, p in pairs(Player.GetPairs()) do
            if p:IsValid() and p:GetID() == id then return p end
        end
    end

    local function personnage(id)
        if bots[id] then return bots[id].corps end
        local session = Characters.SessionByPlayer(id)
        return session and session.character or nil
    end

    local function nom(id)
        if bots[id] then return bots[id].nom end
        local p = joueur(id)
        return p and p:GetName() or ("Joueur " .. tostring(id))
    end

    local function id_personnage(id)
        local c = personnage(id)
        return c and c:IsValid() and c:GetID() or nil
    end

    local function par_personnage(cid)
        for _, id in ipairs(salon.ordre) do
            if id_personnage(id) == cid then return id end
        end
    end

    local function envoyer(id, evenement, ...)
        local p = joueur(id)
        if p then Events.CallRemote(evenement, p, Reliability.Reliable, ...) end
    end

    local function diffuser(evenement, ...)
        for _, id in ipairs(salon.ordre) do envoyer(id, evenement, ...) end
    end

    local function dire(player, texte)
        if player then Chat.SendMessage(player, texte) end
    end

    ---------------------------------------------------------------- decor et places

    local D = config.decor or {}
    local FICHIER = D.fichier or "loup_garou.json"
    local COUSSINS = D.coussins or { "Red", "Blue", "Yellow", "Green", "Purple", "White", "Brown" }
    local POSES = D.poses or {
        -- Hauteur du pivot du personnage au-dessus du sol sous le tapis (cm),
        -- mesuree par l'import (echelle 0,8).
        { anim = "my-asset-pack::ANIM_WW_Sitting_Idle", z = 11.0 },
        { anim = "my-asset-pack::ANIM_WW_Sitting_Idle_Lazy", z = 12.8 },
    }
    local MORT = D.mort or { anim = "my-asset-pack::ANIM_WW_Sitting_Dazed", z = 11.6 }
    local TAPIS = D.tapis or "my-asset-pack::SM_WW_Carpet"
    local EPAISSEUR_TAPIS = D.epaisseur_tapis or 0.8
    local AJUSTEMENT = D.ajustement_z or 0      -- retouche en jeu si les vetements depassent

    local function lire_centre()
        if not File.Exists(FICHIER) then return nil end
        local f = File(FICHIER)
        local texte = f:Read(0)
        f:Close()
        local ok, c = pcall(JSON.parse, texte)
        return ok and type(c) == "table" and c.x and c or nil
    end

    local function ecrire_centre(c)
        local f = File(FICHIER, true)
        f:Write(JSON.stringify(c))
        f:Close()
    end

    local function effacer_decor()
        for _, o in ipairs(decor.objets) do
            if o and o:IsValid() then o:Destroy() end
        end
        decor.objets = {}
    end

    -- Le tapis au centre, puis n zabutons a intervalles egaux sur le cercle,
    -- tournes vers le feu. Les places suivent l'ordre d'arrivee du salon.
    local function poser_decor()
        effacer_decor()
        decor.places = {}
        local c = decor.centre
        if not c then return end
        local ok, err = pcall(function()
            local tapis = StaticMesh(Vector(c.x, c.y, c.sol), Rotator(0, c.yaw or 0, 0), TAPIS, CollisionType.NoCollision)
            decor.objets[#decor.objets + 1] = tapis
            local n = math.max(#salon.ordre, Roles.MIN_JOUEURS)
            for i = 1, n do
                local angle = (c.yaw or 0) + 360 * (i - 1) / n
                local r = math.rad(angle)
                local x, y = c.x + RAYON * math.cos(r), c.y + RAYON * math.sin(r)
                local coussin = StaticMesh(Vector(x, y, c.sol + EPAISSEUR_TAPIS), Rotator(0, angle + 180, 0),
                    "my-asset-pack::SM_WW_Zabuton_" .. COUSSINS[(i - 1) % #COUSSINS + 1], CollisionType.NoCollision)
                decor.objets[#decor.objets + 1] = coussin
                local id = salon.ordre[i]
                if id then decor.places[id] = { x = x, y = y, yaw = angle + 180 } end
            end
        end)
        if not ok then Log.Error("werewolf", "decor : " .. tostring(err)) end
    end

    -- /lg centre : le centre du cercle sous les pieds du joueur. On garde la
    -- hauteur du personnage debout et celle du sol (capsule a l'echelle).
    function A.PoserCentre(player)
        local c = personnage(player:GetID())
        if not (c and c:IsValid()) then return dire(player, "Pas de personnage.") end
        local l, r = c:GetLocation(), c:GetRotation()
        local demi = 90
        pcall(function() demi = c:GetCapsuleSize().HalfHeight * c:GetScale().Z end)
        decor.centre = { x = l.X, y = l.Y, debout = l.Z, sol = l.Z - demi, yaw = math.floor(r.Yaw + 0.5) }
        local ok, err = pcall(ecrire_centre, decor.centre)
        if not ok then Log.Error("werewolf", "centre non enregistre : " .. tostring(err)) end
        if s.statut ~= "partie" then poser_decor() end
        dire(player, ("Centre du loup-garou enregistre (%d, %d, %d)."):format(l.X, l.Y, l.Z))
    end

    -- Assoit un joueur (ou un bot) sur sa place, avec une pose ; nil : debout.
    local function asseoir(id, pose)
        local p = decor.places[id]
        local c = personnage(id)
        if not (p and c and c:IsValid() and decor.centre) then return end
        local z = decor.centre.debout + pose.z + AJUSTEMENT
        if id > 0 then
            Characters.Sit(id, p.x, p.y, p.yaw, z)
        else
            c:SetLocation(Vector(p.x, p.y, z))
            c:SetRotation(Rotator(0, p.yaw, 0))
            pcall(function() c:SetGravityEnabled(false) end)
        end
        pcall(function() c:PlayAnimation(pose.anim, "DefaultSlot", true, 0.15, 0.15, 1.0, true) end)
        c:SetValue("ww_pose", pose.anim, true)
    end

    local function relever(id)
        local c = personnage(id)
        if c and c:IsValid() then
            local anim = c:GetValue("ww_pose", nil)
            if anim then pcall(function() c:StopAnimation(anim) end) end
            c:SetValue("ww_pose", nil, true)
            if id < 0 then pcall(function() c:SetGravityEnabled(true) end) end
        end
        if id > 0 then pcall(Characters.Stand, id) end
    end

    local function asseoir_tout_le_monde()
        if not decor.centre then return end
        poser_decor()
        for i, id in ipairs(salon.ordre) do asseoir(id, POSES[(i - 1) % #POSES + 1]) end
    end

    ---------------------------------------------------------------- salon

    local function envoyer_salon()
        if s.statut == "partie" then return end
        if decor.centre and #decor.objets ~= math.max(#salon.ordre, Roles.MIN_JOUEURS) + 1 then poser_decor() end
        local joueurs = {}
        for _, id in ipairs(salon.ordre) do joueurs[#joueurs + 1] = { nom = nom(id), pret = salon.pret[id] == true } end
        for i, id in ipairs(salon.ordre) do
            local vue = { joueurs = {}, max = salon.max, compo = salon.compo, debat = salon.debat,
                createur = id == salon.createur }
            for k, j in ipairs(joueurs) do vue.joueurs[k] = { nom = j.nom, pret = j.pret, moi = k == i } end
            envoyer(id, "ww:salon", vue)
        end
    end

    local function lancer()
        local ids = {}
        for _, id in ipairs(salon.ordre) do ids[#ids + 1] = id end
        if #ids > salon.max then return diffuser("ww:annonce", "Trop de joueurs pour cette partie.") end
        s = Engine.nouveau({ debat = salon.debat })
        memoires = {}
        s.debut = os.date("!%Y-%m-%dT%H:%M:%SZ")
        local fx, raison = Engine.demarrer(s, ids, salon.compo, rng)
        if not fx then
            salon.pret = {}
            for id in pairs(bots) do salon.pret[id] = true end
            envoyer_salon()
            return diffuser("ww:annonce", "Impossible de lancer : " .. tostring(raison))
        end
        Log.Info("werewolf", ("partie lancee a %d joueurs"):format(#ids))
        diffuser("ww:salon", nil)
        asseoir_tout_le_monde()
        A.Appliquer(fx)
    end

    local function tous_prets()
        if #salon.ordre < Roles.MIN_JOUEURS then return false end
        for _, id in ipairs(salon.ordre) do if not salon.pret[id] then return false end end
        return true
    end

    function A.Rejoindre(player)
        local id = player:GetID()
        if s.statut == "partie" then return dire(player, "Une partie est en cours.") end
        if membre(id) then return end
        if #salon.ordre >= Roles.MAX_JOUEURS then return dire(player, "Le salon est plein.") end
        salon.ordre[#salon.ordre + 1] = id
        salon.createur = salon.createur or id
        if not salon.centre then
            local c = personnage(id)
            salon.centre = c and c:GetLocation() or Vector(0, 0, 0)
        end
        envoyer_salon()
    end

    local function retirer(id)
        for i, m in ipairs(salon.ordre) do
            if m == id then table.remove(salon.ordre, i) break end
        end
        salon.pret[id] = nil
        if salon.createur == id then
            salon.createur = nil
            for _, m in ipairs(salon.ordre) do if m > 0 then salon.createur = m break end end
        end
    end

    function A.Quitter(player)
        local id = player:GetID()
        if not membre(id) then return end
        if s.statut == "partie" then A.Appliquer(Engine.depart(s, id)) end
        regler_voix(id, "normal")
        voix_actuelle[id] = nil
        relever(id)
        retirer(id)
        envoyer(id, "ww:fin")
        envoyer_salon()
    end

    function A.Pret(player)
        local id = player:GetID()
        if s.statut == "partie" or not membre(id) then return end
        salon.pret[id] = not salon.pret[id] or nil
        envoyer_salon()
        if tous_prets() then lancer() end
    end

    local BORNES_SALON = { max = { Roles.MIN_JOUEURS, Roles.MAX_JOUEURS, 1 }, debat = { 60, 300, 30 } }

    function A.Reglage(player, cle, sens)
        if s.statut == "partie" or player:GetID() ~= salon.createur then return end
        sens = (tonumber(sens) or 0) > 0 and 1 or -1
        local b = BORNES_SALON[cle]
        if b then
            salon[cle] = math.max(b[1], math.min(b[2], salon[cle] + sens * b[3]))
        elseif Roles.bornes[cle] then
            local r = Roles.bornes[cle]
            salon.compo[cle] = math.max(r[1], math.min(r[2], (salon.compo[cle] or 0) + sens))
        else
            return
        end
        -- Changer les regles remet les humains en "pas pret".
        for id in pairs(salon.pret) do if id > 0 then salon.pret[id] = nil end end
        envoyer_salon()
    end

    function A.AjouterBots(player, n)
        if s.statut == "partie" then return dire(player, "Une partie est en cours.") end
        A.Rejoindre(player)
        local c0 = decor.centre and Vector(decor.centre.x, decor.centre.y, decor.centre.debout)
            or salon.centre or Vector(0, 0, 0)
        for _ = 1, math.max(0, math.min(tonumber(n) or 0, Roles.MAX_JOUEURS - #salon.ordre)) do
            local id = prochain_bot
            prochain_bot = prochain_bot - 1
            local angle = math.rad(360 * (#salon.ordre) / Roles.MAX_JOUEURS)
            local x, y = c0.X + RAYON * math.cos(angle), c0.Y + RAYON * math.sin(angle)
            local ok, corps = pcall(Characters.CorpsDebout, x, y, c0.Z, math.deg(angle) + 180)
            bots[id] = { nom = "Bot " .. (-id), corps = ok and corps or nil }
            salon.ordre[#salon.ordre + 1] = id
            salon.pret[id] = true
        end
        envoyer_salon()
    end

    ---------------------------------------------------------------- bots de test

    -- Les bots jouent avec bots.lua (le meme cerveau que les parties simulees
    -- des tests), quelques secondes apres le debut de chaque phase.
    local Bots = Package.Require("games/werewolf/bots.lua")(Match)

    local function faire_jouer_bots(phase)
        for id in pairs(bots) do
            for coup = 1, Bots.coups(s, id) do
                Timer.SetTimeout(function()
                    if s.statut ~= "partie" or Engine.phase(s) ~= phase then return end
                    memoires[id] = memoires[id] or {}
                    local cible = Bots.choisir(s, id, rng, memoires[id])
                    if not cible then return end
                    local fx = Engine.designer(s, id, cible)
                    if fx then A.Appliquer(fx) end
                end, math.random(2000, 6000) + coup * 900)
            end
        end
    end

    ---------------------------------------------------------------- effets

    local function destinataires(audience)
        if type(audience) == "number" then return { audience } end
        local out = {}
        for _, id in ipairs(salon.ordre) do
            local ok = audience == "all"
                or (audience == "wolves" and Match.est_loup(s.match, id))
                or (audience == "dead" and not Match.vivant(s.match, id))
            if ok then out[#out + 1] = id end
        end
        return out
    end

    local function liste_noms(ids)
        local t = {}
        for _, id in ipairs(ids or {}) do t[#t + 1] = nom(id) end
        return table.concat(t, ", ")
    end

    local ANNONCES = {
        aube_morts = function(a) return "Au lever du jour, on découvre : " .. liste_noms(a.morts) .. "." end,
        aube_personne = function() return "Personne n'est mort cette nuit." end,
        execution = function(a) return ("Le village élimine %s. C'était : %s."):format(nom(a.joueur), NOMS_ROLES[a.role] or "?") end,
        egalite = function() return "Égalité : le village ne tranche pas." end,
        chasseur = function(a) return ("%s tire en mourant et emporte %s."):format(nom(a.tireur), nom(a.joueur)) end,
        depart = function(a) return nom(a.joueur) .. " a quitté la partie." end,
        maire = function(a) return nom(a.joueur) .. " est élu maire : sa voix compte double." end,
        successeur = function(a) return nom(a.joueur) .. " devient maire." end,
    }

    local TRADUIRE = {}

    TRADUIRE.assign_role = function(e)
        local allies = {}
        for _, a in ipairs(e.allies) do allies[#allies + 1] = { id = id_personnage(a), nom = nom(a) } end
        envoyer(e.player, "ww:role", e.role, allies)
    end
    TRADUIRE.phase = function(e)
        diffuser("ww:phase", e.id, e.duree)
        faire_jouer_bots(e.id)
    end
    TRADUIRE.votes = function(e)
        local compte = {}
        for cible, n in pairs(e.compte) do
            local cid = id_personnage(cible)
            if cid then compte[cid] = n end
        end
        for _, id in ipairs(destinataires(e.audience)) do envoyer(id, "ww:votes", compte) end
    end
    TRADUIRE.reveal = function(e) envoyer(e.viewer, "ww:vision", nom(e.target), e.role) end
    TRADUIRE.lovers = function(e) envoyer(e.player, "ww:amoureux", id_personnage(e.partner), nom(e.partner)) end
    TRADUIRE.kill = function(e)
        envoyer(e.player, "ww:mort")
        local c = personnage(e.player)
        if c and c:IsValid() then c:SetValue("ww_mort", true, true) end
        -- Les morts restent assis, hebetes (ANIM_WW_Sitting_Dazed).
        if decor.places[e.player] then
            local ancienne = c and c:IsValid() and c:GetValue("ww_pose", nil)
            if ancienne then pcall(function() c:StopAnimation(ancienne) end) end
            asseoir(e.player, MORT)
        end
    end
    TRADUIRE.voice_channel = function(e) regler_voix(e.player, e.channel) end
    TRADUIRE.mayor = function(e) diffuser("ww:maire", id_personnage(e.player), nom(e.player)) end
    TRADUIRE.victim = function(e) envoyer(e.player, "ww:victime", id_personnage(e.target), nom(e.target)) end
    TRADUIRE.potions = function(e) envoyer(e.player, "ww:potions", e.vie, e.mort) end
    TRADUIRE.announce = function(e)
        local f = ANNONCES[e.key]
        if f then diffuser("ww:annonce", f(e.args)) end
    end
    -- Gagne-t-il ? Selon son camp, ou pour les amoureux leur lien.
    local function a_gagne(gagnant, id, role, amoureux)
        if gagnant == "lovers" then return amoureux ~= nil and (amoureux[1] == id or amoureux[2] == id) end
        local camp = Roles.roles[role] and Roles.roles[role].camp
        return (gagnant == "village" and camp == "village") or (gagnant == "wolves" and camp == "wolves")
            or (gagnant == "white_wolf" and role == "white_wolf")
    end

    -- Le resultat d'une partie terminee : donnee transactionnelle, ecrite tout
    -- de suite (R3). Une partie avec des bots ne compte pas.
    local function enregistrer(gagnant, resume)
        if next(bots) then return Log.Info("werewolf", "partie avec bots : resultat non enregistre") end
        local id_partie = Ids.Next("werewolf_matches")
        local fin = os.date("!%Y-%m-%dT%H:%M:%SZ")
        DB.Execute([[INSERT INTO werewolf_matches (id, started_at, ended_at, nights, winner)
                     VALUES (:0, :1, :2, :3, :4)]],
            function(_, err) if err then Log.Error("werewolf", "resultat non ecrit : " .. tostring(err)) end end,
            id_partie, s.debut or fin, fin, resume.nuits or 0, tostring(gagnant))
        for id, role in pairs(resume.roles or {}) do
            local session = Characters.SessionByPlayer(id)
            DB.Execute([[INSERT INTO werewolf_participants (match_id, character_id, role, survived, won)
                         VALUES (:0, :1, :2, :3, :4)]],
                function(_, err) if err then Log.Error("werewolf", "participant non ecrit : " .. tostring(err)) end end,
                id_partie, session and session.character_id or 0, role,
                resume.vivants and resume.vivants[id] and 1 or 0,
                a_gagne(gagnant, id, role, resume.amoureux) and 1 or 0)
        end
    end

    TRADUIRE.match_ended = function(e)
        local texte = GAGNANTS[e.winner] or GAGNANTS.none
        diffuser("ww:annonce", texte)
        Log.Info("werewolf", "partie terminee : " .. tostring(e.winner))
        local ok, err = pcall(enregistrer, e.winner, e.summary or {})
        if not ok then Log.Error("werewolf", "resultat : " .. tostring(err)) end
        Timer.SetTimeout(function()
            diffuser("ww:fin")
            for _, id in ipairs(salon.ordre) do regler_voix(id, "normal") end
            for _, id in ipairs(salon.ordre) do relever(id) end
            voix_actuelle = {}
            for _, id in ipairs(salon.ordre) do
                local c = personnage(id)
                if c and c:IsValid() then c:SetValue("ww_mort", false, true) end
            end
            s = Engine.nouveau({ debat = salon.debat })
            salon.pret = {}
            for id in pairs(bots) do salon.pret[id] = true end
            envoyer_salon()
        end, 8000)
    end

    function A.Appliquer(fx)
        for _, e in ipairs(fx or {}) do
            local f = TRADUIRE[e.kind]
            if f then
                local ok, err = pcall(f, e)
                if not ok then Log.Error("werewolf", ("effet %s : %s"):format(e.kind, tostring(err))) end
            end
        end
    end

    ---------------------------------------------------------------- entrees

    function A.Designer(player, cid)
        if s.statut ~= "partie" then return end
        local cible = par_personnage(tonumber(cid))
        if not cible then return end
        local fx = Engine.designer(s, player:GetID(), cible)
        if fx then A.Appliquer(fx) end
    end

    function A.OnPlayerLeave(player)
        local id = player:GetID()
        voix_actuelle[id] = nil
        if not membre(id) then return end
        if s.statut == "partie" then A.Appliquer(Engine.depart(s, id)) end
        retirer(id)
        envoyer_salon()
    end

    function A.Init()
        local ok, c = pcall(lire_centre)
        decor.centre = ok and c or nil
        if decor.centre then Log.Info("werewolf", "centre du loup-garou relu dans " .. FICHIER) end
        Timer.SetInterval(function()
            if s.statut ~= "partie" then return end
            local ok, err = pcall(function() A.Appliquer(Engine.avancer(s, TICK)) end)
            if not ok then Log.Error("werewolf", "horloge : " .. tostring(err)) end
        end, math.floor(TICK * 1000))

        Events.SubscribeRemote("ww:designer", function(p, cid) A.Designer(p, cid) end)
        Events.SubscribeRemote("ww:pret", function(p) A.Pret(p) end)
        Events.SubscribeRemote("ww:reglage", function(p, cle, sens) A.Reglage(p, cle, sens) end)

        Chat.Subscribe("PlayerSubmit", function(message, player)
            local mots = {}
            for m in tostring(message):gmatch("%S+") do mots[#mots + 1] = m end
            if mots[1] ~= "/lg" then return end
            if mots[2] == "entrer" then A.Rejoindre(player)
            elseif mots[2] == "sortir" then A.Quitter(player)
            elseif mots[2] == "bots" and config.bots then A.AjouterBots(player, mots[3])
            elseif mots[2] == "centre" and config.bots then A.PoserCentre(player)
            else return end
            return false
        end)
        Log.Info("werewolf", "loup-garou pret : /lg entrer")
    end

    return A
end
