-- Adaptateur du loup-garou : le seul fichier du jeu qui connait nanos world.
-- Il tient le salon, fait avancer le moteur (engine.lua), traduit ses effets
-- en evenements du HUD (Client/loup_garou/hud.lua) et fait jouer les bots de
-- test. La logique du jeu n'est pas ici.
--
-- En attendant la cloche du decor : /lg entrer, /lg sortir, /lg bots N (dev).
-- Hors de cette version : lumiere du jour et de la nuit, bras tendus, corps au
-- sol, ecriture du resultat en base (effets recus, ignores).

return function(Log, Characters, Engine, Roles, Match, config)
    local A = {}
    config = config or {}
    local TICK = config.tick or 0.25
    local RAYON = config.rayon or 212     -- cercle des places (docs/WEREWOLF-ASSETS-IMPORT.md)

    local NOMS_ROLES = { wolf = "Loup-Garou", white_wolf = "Loup Blanc", villager = "Villageois",
        seer = "Voyante", hunter = "Chasseur", guard = "Gardien", cupid = "Cupidon" }
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

    ---------------------------------------------------------------- salon

    local function envoyer_salon()
        if s.statut == "partie" then return end
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
        local fx, raison = Engine.demarrer(s, ids, salon.compo, rng)
        if not fx then
            salon.pret = {}
            for id in pairs(bots) do salon.pret[id] = true end
            envoyer_salon()
            return diffuser("ww:annonce", "Impossible de lancer : " .. tostring(raison))
        end
        Log.Info("werewolf", ("partie lancee a %d joueurs"):format(#ids))
        diffuser("ww:salon", nil)
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
        local c0 = salon.centre or Vector(0, 0, 0)
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

    -- Un bot qui peut agir dans cette phase designe une cible au hasard,
    -- quelques secondes apres son debut (Cupidon deux fois).
    local function cibles(bot, phase)
        local m = s.match
        local out = {}
        for _, id in ipairs(Match.vivants(m)) do
            local ok = id ~= bot
            if phase == "night_wolves" then ok = ok and not Match.est_loup(m, id) end
            if phase == "night_white_wolf" then ok = ok and Match.est_loup(m, id) end
            if phase == "night_guard" then ok = id ~= s.protege_avant end
            if phase == "night_cupid" then ok = true end
            if ok then out[#out + 1] = id end
        end
        return out
    end

    local QUI = { night_wolves = { wolf = true, white_wolf = true }, night_white_wolf = { white_wolf = true },
        night_guard = { guard = true }, night_seer = { seer = true }, night_cupid = { cupid = true },
        day_vote = "tous", day_mayor = "tous", hunter_shot = { hunter = true }, mayor_succession = "maire" }

    local function faire_jouer_bots(phase)
        local qui = QUI[phase]
        if not qui then return end
        for id in pairs(bots) do
            local role = Match.role(s.match, id)
            local vivant = Match.vivant(s.match, id)
            local actif = (qui == "tous" and vivant) or (qui == "maire" and s.ancien_maire == id)
                or (type(qui) == "table" and qui[role] and (vivant or (phase == "hunter_shot" and s.tireur == id)))
            if actif then
                for coup = 1, phase == "night_cupid" and 2 or 1 do
                    Timer.SetTimeout(function()
                        if s.statut ~= "partie" or Engine.phase(s) ~= phase then return end
                        local c = cibles(id, phase)
                        if #c == 0 then return end
                        local fx = Engine.designer(s, id, c[math.random(#c)])
                        if fx then A.Appliquer(fx) end
                    end, math.random(2000, 6000) + coup * 700)
                end
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
    end
    TRADUIRE.voice_channel = function(e) regler_voix(e.player, e.channel) end
    TRADUIRE.mayor = function(e) diffuser("ww:maire", id_personnage(e.player), nom(e.player)) end
    TRADUIRE.announce = function(e)
        local f = ANNONCES[e.key]
        if f then diffuser("ww:annonce", f(e.args)) end
    end
    TRADUIRE.match_ended = function(e)
        local texte = GAGNANTS[e.winner] or GAGNANTS.none
        diffuser("ww:annonce", texte)
        Log.Info("werewolf", "partie terminee : " .. tostring(e.winner))
        Timer.SetTimeout(function()
            diffuser("ww:fin")
            for _, id in ipairs(salon.ordre) do regler_voix(id, "normal") end
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
            else return end
            return false
        end)
        Log.Info("werewolf", "loup-garou pret : /lg entrer")
    end

    return A
end
