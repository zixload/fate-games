-- Ciel jour/nuit du loup-garou (Sky de nanos, Ultra Dynamic Sky).
--
-- Tout le serveur est sous le ciel de nanos : Sky.Spawn remplace le soleil,
-- le ciel et le brouillard de la map des l'arrivee du joueur. Hors partie,
-- l'heure suit un cycle accelere commun a tous (horloge du monde, plus bas).
-- Seuls les joueurs de la partie recoivent les phases (ww:phase) : chez eux,
-- la nuit tombe et le jour se leve ; a la fin, retour a l'heure du monde.
--
-- Horloge du monde : calculee depuis l'heure Unix, la meme chez chaque
-- client, sans rien envoyer du serveur. Un cycle = `jour` secondes de 6h a
-- 20h puis `nuit` secondes de 20h a 6h (Shared/config.lua, cycle).
--
-- Chaque phase fait passer l'heure par des points (part de la phase ecoulee,
-- heure), a vitesse constante entre deux points. L'aube, le plus beau moment,
-- dure : de 6h, elle court jusqu'a la moitie du debat (chrono a 1:30), puis
-- la journee defile. Si l'heure est loin du premier point, elle y court
-- d'abord (quelques secondes, toujours vers l'avant). L'heure est tenue ici,
-- a la minute, et poussee au ciel par petits pas : relire le ciel pendant
-- une transition donnait des retours en arriere.
--
-- Apercu sans partie : /lg ciel jour | nuit | aube | soir | <heure>[:<minutes>]

return function(cycle)
    local Dev = Package.Require("dev.lua")
    local function hm(h, m) return h * 60 + (m or 0) end
    cycle = cycle or {}
    local DUREE_JOUR = cycle.jour or 600     -- s de 6h a 20h
    local DUREE_NUIT = cycle.nuit or 300     -- s de 20h a 6h
    local DECALAGE = cycle.decalage or 0     -- s, pour choisir l'heure d'un instant donne

    -- Par phase : points { part de la phase (0 a 1), heure }. Sans entree,
    -- l'heure ne bouge pas (tir du chasseur, succession du maire).
    local NUIT = { { 0, hm(23) }, { 1, hm(23, 20) } }
    local PHASES = {
        night_cupid = NUIT, night_guard = NUIT, night_wolves = NUIT, night_white_wolf = NUIT,
        night_witch = NUIT, night_seer = NUIT,
        dawn = { { 0, hm(6) }, { 1, hm(6, 15) } },
        day_mayor = { { 0, hm(6, 15) }, { 1, hm(6, 35) } },
        day_debate = { { 0, hm(6, 35) }, { 0.5, hm(7, 15) }, { 1, hm(15) } },
        day_vote = { { 0, hm(15) }, { 1, hm(18) } },
        execution = { { 0, hm(18) }, { 1, hm(19, 30) } },
    }
    local JOUR = hm(12)          -- l'heure du serveur hors partie
    local MOMENTS = { jour = hm(12), aube = hm(6), soir = hm(19, 30), nuit = hm(23) }
    local COURSE = 4             -- secondes pour rejoindre le debut d'une phase
    local ECART_MIN = 30         -- en dessous (minutes), pas de course : on part d'ou l'on est
    local PAS = 0.2              -- secondes entre deux pas pousses au ciel

    local pret = false
    local courant = JOUR         -- minutes depuis minuit, tenues ici
    local segments = nil         -- { { de, a, t0, duree }, ... } en minutes continues
    local visee = nil

    local function pousser(minutes, transition)
        local m = math.floor(minutes + 0.5) % 1440
        pcall(Sky.SetTimeOfDay, math.floor(m / 60), m % 60, transition)
    end

    local function preparer()
        if pret then return true end
        local ok, err = pcall(Sky.Spawn, false, true)
        if not ok then
            Console.Error("[loup-garou ciel] Sky.Spawn : " .. tostring(err))
            return false
        end
        pcall(Sky.SetAnimateTimeOfDay, false)
        pcall(Sky.SetMoonPhase, 15)          -- pleine lune (0 a 30)
        pousser(courant, 0)
        pret = true
        return true
    end

    local function secondes() return Client.GetTime() / 1000 end

    -- L'heure du monde (minutes depuis minuit), identique chez tous.
    local function heure_monde(avance)
        local t = (secondes() + (avance or 0) + DECALAGE) % (DUREE_JOUR + DUREE_NUIT)
        if t < DUREE_JOUR then return hm(6) + (hm(20) - hm(6)) * t / DUREE_JOUR end
        return (hm(20) + (hm(30) - hm(20)) * (t - DUREE_JOUR) / DUREE_NUIT) % 1440
    end
    local en_partie = false

    -- Aller de l'heure actuelle au premier point (vite, vers l'avant), puis
    -- d'un point a l'autre sur le reste de `duree` secondes.
    local function programmer(points, duree)
        if not preparer() then return end
        local depart = courant
        local ecart = (points[1][2] - depart) % 1440
        local t = secondes()
        local reste = math.max(duree or 0, 0)
        segments = {}
        -- Loin du premier point : on y court. Tout pres : on part d'ou l'on
        -- est et on rejoint directement les points suivants.
        local heure = depart % 1440
        if ecart >= ECART_MIN and ecart <= 1440 - ECART_MIN then
            local course = math.min(COURSE, math.max(reste * 0.5, 1))
            segments[#segments + 1] = { depart, depart + ecart, t, course }
            t, reste = t + course, reste - course
            depart, heure = depart + ecart, points[1][2]
        end
        local valeur = depart
        for i = 2, #points do
            local avance = (points[i][2] - heure) % 1440
            local duree_i = math.max((points[i][1] - points[i - 1][1]) * reste, 0.1)
            segments[#segments + 1] = { valeur, valeur + avance, t, duree_i }
            t, valeur, heure = t + duree_i, valeur + avance, points[i][2]
        end
        if #segments == 0 then segments[1] = { depart, depart, t, 0.1 } end
    end

    -- L'heure a l'instant t le long des segments, et si l'on est au bout.
    local function heure_a(t)
        for i, s in ipairs(segments) do
            local de, a, t0, duree = s[1], s[2], s[3], s[4]
            if t < t0 + duree or i == #segments then
                local k = math.max(0, math.min(1, (t - t0) / duree))
                return de + (a - de) * k, i == #segments and k >= 1
            end
        end
    end

    Timer.SetInterval(function()
        -- Hors partie et sans programme en cours : l'heure du monde.
        if pret and not segments and not en_partie then
            local minutes = heure_monde()
            local avant = math.floor(courant + 0.5) % 1440
            local apres = math.floor(minutes + 0.5) % 1440
            if apres ~= avant then pousser(minutes, apres < avant and 0 or PAS) end
            courant = minutes
            return
        end
        if not (pret and segments) then return end
        local minutes, fini = heure_a(secondes())
        if not minutes then segments = nil return end
        local avant = math.floor(courant + 0.5) % 1440
        local apres = math.floor(minutes + 0.5) % 1440
        if apres ~= avant then
            -- Passer minuit en douceur ferait reculer le ciel de 24 h : saut net.
            pousser(minutes, apres < avant and 0 or PAS)
        end
        courant = minutes % 1440
        if fini then segments = nil end
    end, math.floor(PAS * 1000))

    local function viser(cle, points, duree)
        if cle == visee then return end
        visee = cle
        programmer(points, duree)
    end

    Events.SubscribeRemote("ww:phase", function(id, duree)
        en_partie = true
        local p = PHASES[id]
        -- Les phases de nuit s'enchainent : une seule nuit, qui dure ce qu'elle dure.
        if p == NUIT then
            viser("nuit", p, 90)
        elseif p then
            viser(id, p, tonumber(duree) or 10)
        end
    end)
    -- Fin de partie : on rejoint l'heure du monde (celle qu'il sera a l'arrivee).
    Events.SubscribeRemote("ww:fin", function()
        en_partie = false
        local arrivee = COURSE + 2
        local cible = heure_monde(arrivee)
        viser("fin", { { 0, cible } }, arrivee)
        visee = nil
    end)

    courant = heure_monde()
    preparer()

    Chat.Subscribe("PlayerSubmit", function(message)
        local arg = tostring(message):match("^/lg ciel%s*(%S*)")
        if not arg then return end
        if not Dev.actif then return end
        local cible = MOMENTS[arg]
        if not cible then
            local h, m = arg:match("^(%d+):?(%d*)$")
            h, m = tonumber(h), tonumber(m) or 0
            if h and h >= 0 and h <= 23 and m >= 0 and m <= 59 then cible = hm(h, m) end
        end
        if not cible then
            Chat.AddMessage("/lg ciel jour | nuit | aube | soir | <heure>[:<minutes>]")
            return false
        end
        visee = nil
        programmer({ { 0, cible } }, 6)
        Chat.AddMessage(("ciel : vers %02d:%02d"):format(math.floor(cible / 60), cible % 60))
        return false
    end)
end
