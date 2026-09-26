-- Ciel jour/nuit du loup-garou (Sky de nanos, Ultra Dynamic Sky).
--
-- Seuls les joueurs de la partie recoivent les phases (ww:phase) : le ciel ne
-- change que chez eux, les autres gardent l'eclairage de la map. Sky.Spawn
-- remplace le soleil, le ciel et le brouillard de la map et nanos n'a rien
-- pour les rendre : pose au debut de la premiere partie, le ciel reste
-- jusqu'a la reconnexion (en plein jour une fois la partie finie).
--
-- Les transitions font defiler le temps vers l'avant, vite : le soleil se
-- couche, la nuit tombe, l'aube se leve.
--
-- Apercu sans partie : /lg ciel jour | nuit | aube | soir | <heure>[:<minutes>]

return function()
    -- Heure visee a chaque phase : { heure, minutes, secondes de defilement }.
    local NUIT = { 23, 0, 8 }
    local PHASES = {
        night_cupid = NUIT, night_guard = NUIT, night_wolves = NUIT, night_white_wolf = NUIT,
        night_witch = NUIT, night_seer = NUIT,
        dawn = { 6, 0, 7 },
        day_mayor = { 11, 0, 20 }, day_debate = { 13, 0, 30 },
        day_vote = { 17, 0, 20 }, execution = { 19, 30, 6 },
    }
    local FIN = { 12, 0, 6 }
    local MOMENTS = { jour = { 12, 0 }, aube = { 6, 0 }, soir = { 19, 30 }, nuit = { 23, 0 } }
    local APERCU = 6   -- secondes de defilement pour /lg ciel

    local pret = false
    local generation = 0      -- une nouvelle transition annule la precedente
    local visee = nil         -- "hh:mm" en cours, pour ne pas relancer la meme

    local function preparer()
        if pret then return true end
        local ok, trouve = pcall(Sky.Spawn, false, true)
        if not ok then
            Console.Error("[loup-garou ciel] Sky.Spawn : " .. tostring(trouve))
            return false
        end
        pcall(Sky.SetAnimateTimeOfDay, false)
        pcall(Sky.SetMoonPhase, 15)          -- pleine lune (0 a 30)
        pcall(Sky.SetTimeOfDay, 12, 0, 0)    -- la premiere nuit tombe depuis midi
        pret = true
        return true
    end

    local function maintenant()
        local ok, h, m = pcall(Sky.GetTimeOfDay)
        if ok and type(h) == "number" then return h * 60 + (m or 0) end
        return 12 * 60
    end

    -- Fait avancer l'heure jusqu'a h:m en `duree` secondes, toujours vers
    -- l'avant. Chaque etape reste avant minuit (l'interpolation ne sait pas
    -- que 23h precede 0h) ; minuit se passe d'un saut instantane 23:59 -> 0:00.
    local function avancer(h, m, duree)
        if not preparer() then return end
        generation = generation + 1
        local ma_generation = generation
        visee = ("%02d:%02d"):format(h, m)
        local depart, cible = maintenant(), h * 60 + m
        local ecart = (cible - depart) % 1440
        if ecart == 0 then return end
        local etapes = {}
        if depart + ecart >= 1440 then
            etapes[#etapes + 1] = { 1439, 1439 - depart }
            etapes[#etapes + 1] = { 0, 0, true }
            if cible > 0 then etapes[#etapes + 1] = { cible, cible } end
        else
            etapes[#etapes + 1] = { cible, ecart }
        end
        local i = 0
        local function suivante()
            if ma_generation ~= generation then return end
            i = i + 1
            local e = etapes[i]
            if not e then return end
            local secondes = e[3] and 0 or math.max(0.1, duree * e[2] / ecart)
            pcall(Sky.SetTimeOfDay, math.floor(e[1] / 60), e[1] % 60, secondes)
            Timer.SetTimeout(suivante, math.floor(secondes * 1000) + 50)
        end
        suivante()
    end

    local function viser(v)
        if not v then return end
        local cle = ("%02d:%02d"):format(v[1], v[2])
        if cle == visee then return end
        avancer(v[1], v[2], v[3])
    end

    Events.SubscribeRemote("ww:phase", function(id) viser(PHASES[id]) end)
    Events.SubscribeRemote("ww:fin", function() if pret then viser(FIN) end end)

    Chat.Subscribe("PlayerSubmit", function(message)
        local arg = tostring(message):match("^/lg ciel%s*(%S*)")
        if not arg then return end
        local h, m
        if MOMENTS[arg] then
            h, m = MOMENTS[arg][1], MOMENTS[arg][2]
        else
            h, m = arg:match("^(%d+):?(%d*)$")
            h, m = tonumber(h), tonumber(m) or 0
        end
        if not (h and h >= 0 and h <= 23 and m >= 0 and m <= 59) then
            Chat.AddMessage("/lg ciel jour | nuit | aube | soir | <heure>[:<minutes>]")
            return false
        end
        avancer(h, m, APERCU)
        Chat.AddMessage(("ciel : vers %02d:%02d"):format(h, m))
        return false
    end)
end
