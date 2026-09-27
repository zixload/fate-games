-- Sons du loup-garou (assets de my-asset-pack, voir Client/son.lua) :
-- ambiance de jour et de nuit en boucle, en fondu ; sons des moments de la
-- partie ; battement de coeur tant qu'on est le plus vise. Ecoute les memes
-- evenements que le HUD (loup_garou/hud.lua), joue en 2D chez chacun.
--
-- Le volume passe a la creation du son et FadeIn monte jusqu'a 1 : le niveau
-- de FadeIn multiplie le volume du son (doc Sound).

return function(config)
    local Dev = Package.Require("dev.lua")
    config = config or {}
    local VOLUMES = config.volumes or { ambiance = 0.18, lg_jour = 0.04, sons = 0.6, coeur = 0.35 }
    local chemin = Package.Require("son.lua")

    local ambiance, ambiance_nom = nil, nil
    local coeur = nil
    local tictac_prevu = nil
    local etat = { phase = nil, role = nil, votes_sur_moi = 0, total_votes = 0, revelees = 0 }

    -- Chaque son joue ou refuse laisse une ligne dans la console du client :
    -- un echec ne doit plus etre muet.
    local function jouer(nom, volume)
        local ok, err = pcall(function()
            Sound(Vector(), chemin(nom), true, true, SoundType.SFX, volume or VOLUMES.sons, 1)
        end)
        if ok then Console.Log("[loup-garou sons] " .. nom) else Console.Error("[loup-garou sons] " .. nom .. " : " .. tostring(err)) end
    end

    local function boucle(nom, volume, fondu)
        local ok, son = pcall(function()
            local s = Sound(Vector(), chemin(nom), true, false, SoundType.Ambient, volume, 1,
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
        -- Une ambiance peut avoir son propre volume (VOLUMES.lg_jour...).
        if nom then ambiance = boucle(nom, VOLUMES[nom] or VOLUMES.ambiance, 3) end
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
    -- Au debut du tour d'un role, tout le monde l'entend : on sait qui joue.
    local SONS_DE_ROLE = { night_cupid = "lg_cupidon", night_guard = "lg_gardien", night_witch = "lg_potion",
        night_seer = "lg_voyante" }

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
            local premiere = not NUIT[avant or ""]
            if premiere then jouer("lg_hurlement") end
            if SONS_DE_ROLE[id] then
                -- Apres le hurlement de la tombee de la nuit, pas par-dessus.
                local nom = SONS_DE_ROLE[id]
                Timer.SetTimeout(function() if etat.phase == id then jouer(nom) end end, premiere and 2500 or 300)
            end
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

    -- Chaque vote s'entend, meme un changement d'avis ; contre moi, autre son.
    Events.SubscribeRemote("ww:pointe", function(_, cible)
        if not cible then return end
        if cible == mon_id() then jouer("lg_vote_contre_toi") else jouer("lg_vote", 0.45) end
    end)

    -- En tete des votes contre moi : le coeur bat.
    Events.SubscribeRemote("ww:votes", function(compte)
        local moi = mon_id()
        local sur_moi, total, max = 0, 0, 0
        for cid, n in pairs(compte or {}) do
            total = total + n
            if n > max then max = n end
            if cid == moi then sur_moi = n end
        end
        etat.votes_sur_moi, etat.total_votes = sur_moi, total
        battre(sur_moi > 0 and sur_moi == max and etat.phase ~= "day_mayor")
    end)

    -- Cupidon vient de me lier a quelqu'un.
    Events.SubscribeRemote("ww:amoureux", function() jouer("lg_cupidon") end)
    -- Un son demande par le serveur (le coup de feu du chasseur...).
    Events.SubscribeRemote("ww:son", function(nom) if type(nom) == "string" then jouer(nom) end end)
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

    -- /lg son <nom> [3d] [volume] : jouer un son a la main et afficher dans le
    -- chat ce que le moteur en dit (duree lue, en train de jouer ou non).
    -- 3d : pose le son a la camera au lieu d'un son 2D.
    -- Le journal du client n'est ecrit qu'a la fermeture (et se perd parfois) :
    -- le diagnostic va aussi dans Packages/.transient/diag_sons.txt, lisible
    -- pendant la partie.
    local journal = nil
    local function noter(texte)
        Chat.AddMessage(texte)
        Console.Log("[loup-garou sons] " .. texte)
        pcall(function()
            journal = journal or File("diag_sons.txt", true)
            journal:Write(os.date("%H:%M:%S") .. " " .. texte .. "\n")
            journal:Flush()
        end)
    end

    local function diagnostiquer(nom, en3d, volume)
        local ok, son = pcall(function()
            if en3d then
                local p = Client.GetLocalPlayer()
                return Sound(p:GetCameraLocation(), chemin(nom), false, false, SoundType.SFX,
                    volume, 1, 400, 3600)
            end
            return Sound(Vector(), chemin(nom), true, false, SoundType.SFX, volume, 1)
        end)
        if not ok then return noter("son " .. nom .. " : erreur " .. tostring(son)) end
        local function etat_son(quand)
            if not son:IsValid() then return noter("son " .. nom .. " " .. quand .. " : detruit") end
            noter("son " .. nom .. (en3d and " 3d" or " 2d") .. " vol " .. volume .. " " .. quand
                .. " : duree " .. tostring(son:GetDuration()) .. " joue " .. tostring(son:IsPlaying()))
        end
        etat_son("0 ms")
        Timer.SetTimeout(function() etat_son("500 ms") end, 500)
        Timer.SetTimeout(function() if son:IsValid() then son:Destroy() end end, 15000)
    end

    -- /lg son tout : chaque son du loup-garou, un toutes les 4 secondes.
    local function tout_jouer()
        local fichiers = { "lg_cloche", "lg_coeur", "lg_cupidon", "lg_gardien", "lg_hurlement", "lg_jour", "lg_loups",
            "lg_maire", "lg_mort", "lg_nuit", "lg_potion", "lg_role", "lg_tictac", "lg_victoire", "lg_vote",
            "lg_vote_contre_toi", "lg_voyante" }
        noter("son tout : " .. #fichiers .. " fichiers")
        for i, nom in ipairs(fichiers) do
            Timer.SetTimeout(function() diagnostiquer(nom, false, VOLUMES.sons) end, (i - 1) * 4000)
        end
    end

    Chat.Subscribe("PlayerSubmit", function(message)
        local nom, reste = tostring(message):match("^/lg son%s+(%S+)%s*(.*)$")
        if not nom then return end
        if not Dev.actif then return end
        if nom == "tout" then
            tout_jouer()
            return false
        end
        local en3d = reste:find("3d") ~= nil
        local volume = tonumber(reste:match("([%d%.]+)%s*$")) or VOLUMES.sons
        diagnostiquer(nom, en3d, volume)
        return false
    end)

    Events.SubscribeRemote("ww:fin", function()
        if tictac_prevu then Timer.ClearTimeout(tictac_prevu) tictac_prevu = nil end
        battre(false)
        mettre_ambiance(nil)
        etat = { phase = nil, role = nil, votes_sur_moi = 0, total_votes = 0, revelees = 0 }
    end)
end
