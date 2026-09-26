-- Sons du loup-garou (fichiers dans Client/Sounds/loup_garou/, hors depot) :
-- ambiance de jour et de nuit en boucle, en fondu ; sons des moments de la
-- partie ; battement de coeur tant qu'on est le plus vise. Ecoute les memes
-- evenements que le HUD (loup_garou/hud.lua), joue en 2D chez chacun.
--
-- Le volume passe a la creation du son et FadeIn monte jusqu'a 1 : le niveau
-- de FadeIn multiplie le volume du son (doc Sound).

return function(config)
    config = config or {}
    local VOLUMES = config.volumes or { ambiance = 0.18, sons = 0.6, coeur = 0.35 }
    local DOSSIER = "package://fate-games/Client/Sounds/loup_garou/"

    local ambiance, ambiance_nom = nil, nil
    local coeur = nil
    local tictac_prevu = nil
    local etat = { phase = nil, role = nil, votes_sur_moi = 0, total_votes = 0, revelees = 0 }

    -- Chaque son joue ou refuse laisse une ligne dans la console du client :
    -- un echec ne doit plus etre muet.
    local function jouer(nom, volume)
        local ok, err = pcall(function()
            Sound(Vector(), DOSSIER .. nom .. ".ogg", true, true, SoundType.SFX, volume or VOLUMES.sons, 1)
        end)
        if ok then Console.Log("[loup-garou sons] " .. nom) else Console.Error("[loup-garou sons] " .. nom .. " : " .. tostring(err)) end
    end

    local function boucle(nom, volume, fondu)
        local ok, son = pcall(function()
            local s = Sound(Vector(), DOSSIER .. nom .. ".ogg", true, false, SoundType.Ambient, volume, 1,
                400, 3600, AttenuationFunction.Linear, true, SoundLoopMode.Forever, false)
            s:FadeIn(fondu or 2, 1)
            return s
        end)
        if ok then Console.Log("[loup-garou sons] boucle " .. nom) else Console.Error("[loup-garou sons] boucle " .. nom .. " : " .. tostring(son)) end
        return ok and son or nil
    end

    local function arreter(son, fondu)
        if son and son:IsValid() then pcall(function() son:FadeOut(fondu or 2, 0, true) end) end
    end

    -- Jour ou nuit : une seule ambiance a la fois, en fondu enchaine.
    local function mettre_ambiance(nom)
        if ambiance_nom == nom then return end
        arreter(ambiance, 3)
        ambiance, ambiance_nom = nil, nom
        if nom then ambiance = boucle(nom, VOLUMES.ambiance, 3) end
    end

    local function battre(oui)
        if oui and not coeur then
            coeur = boucle("lg_coeur", VOLUMES.coeur, 1)
        elseif not oui and coeur then
            arreter(coeur, 1)
            coeur = nil
        end
    end

    local function mon_id()
        local p = Client.GetLocalPlayer()
        local c = p and p:GetControlledCharacter()
        return c and c:GetID()
    end

    local NUIT = { night_cupid = true, night_guard = true, night_wolves = true, night_white_wolf = true,
        night_witch = true, night_seer = true }
    local VOTES = { day_debate = true, day_vote = true, day_mayor = true, night_wolves = true }

    Events.SubscribeRemote("ww:role", function(role)
        etat.role = role
        jouer("lg_role")
    end)

    Events.SubscribeRemote("ww:phase", function(id, duree)
        local avant = etat.phase
        etat.phase = id
        if tictac_prevu then Timer.ClearTimeout(tictac_prevu) tictac_prevu = nil end
        if not (id == "day_vote" and avant == "day_debate") then
            etat.votes_sur_moi, etat.total_votes = 0, 0
            battre(false)
        end

        if NUIT[id] then
            if not NUIT[avant or ""] then jouer("lg_hurlement") end
            mettre_ambiance("lg_nuit")
            if id == "night_wolves" and (etat.role == "wolf" or etat.role == "white_wolf") then jouer("lg_loups", 0.5) end
        elseif id == "dawn" then
            mettre_ambiance("lg_jour")
            jouer("lg_cloche")
        elseif id then
            mettre_ambiance("lg_jour")
        end

        -- Les dix dernieres secondes d'un vote : tic-tac.
        if VOTES[id] and id ~= "day_debate" and duree and duree > 10 then
            tictac_prevu = Timer.SetTimeout(function()
                tictac_prevu = nil
                if etat.phase == id then jouer("lg_tictac", 0.5) end
            end, math.floor((duree - 10) * 1000))
        end
    end)

    -- Tout le monde a vote : il reste 10 secondes.
    Events.SubscribeRemote("ww:chrono", function()
        if tictac_prevu then Timer.ClearTimeout(tictac_prevu) tictac_prevu = nil end
        jouer("lg_tictac", 0.5)
    end)

    -- Un vote tombe ; contre moi, ca se sent ; en tete, le coeur bat.
    Events.SubscribeRemote("ww:votes", function(compte)
        local moi = mon_id()
        local sur_moi, total, max = 0, 0, 0
        for cid, n in pairs(compte or {}) do
            total = total + n
            if n > max then max = n end
            if cid == moi then sur_moi = n end
        end
        if sur_moi > etat.votes_sur_moi then
            jouer("lg_vote_contre_toi")
        elseif total ~= etat.total_votes then
            jouer("lg_vote", 0.45)
        end
        etat.votes_sur_moi, etat.total_votes = sur_moi, total
        battre(sur_moi > 0 and sur_moi == max and etat.phase ~= "day_mayor")
    end)

    Events.SubscribeRemote("ww:vision", function() jouer("lg_voyante") end)
    Events.SubscribeRemote("ww:potions", function(vie, mort)
        -- Au debut de sa phase la sorciere recoit ses potions ; ensuite, chaque
        -- potion utilisee en renvoie l'etat : c'est la qu'on l'entend.
        if etat.potions and (etat.potions.vie ~= vie or etat.potions.mort ~= mort) then jouer("lg_potion") end
        etat.potions = { vie = vie, mort = mort }
    end)
    Events.SubscribeRemote("ww:action", function(phase)
        if phase == "night_guard" then jouer("lg_gardien") end
    end)
    Events.SubscribeRemote("ww:maire", function() jouer("lg_maire") end)

    -- Une carte se retourne : quelqu'un vient de mourir.
    Events.SubscribeRemote("ww:cartes", function(liste)
        local revelees = 0
        for _, c in ipairs(liste or {}) do if c.role then revelees = revelees + 1 end end
        if revelees > etat.revelees and etat.phase then jouer("lg_mort") end
        etat.revelees = revelees
    end)

    Events.SubscribeRemote("ww:victoire", function(gagnant)
        battre(false)
        etat.phase = nil   -- les cartes qui se retournent a la fin ne sont pas des morts
        if gagnant == "wolves" or gagnant == "white_wolf" then jouer("lg_hurlement") else jouer("lg_victoire") end
    end)

    -- /lg son <nom> : jouer un son a la main, pour verifier (ex. /lg son lg_cloche).
    Chat.Subscribe("PlayerSubmit", function(message)
        local nom = tostring(message):match("^/lg son%s+(%S+)")
        if not nom then return end
        jouer(nom)
        return false
    end)

    Events.SubscribeRemote("ww:fin", function()
        if tictac_prevu then Timer.ClearTimeout(tictac_prevu) tictac_prevu = nil end
        battre(false)
        mettre_ambiance(nil)
        etat = { phase = nil, role = nil, votes_sur_moi = 0, total_votes = 0, revelees = 0 }
    end)
end
