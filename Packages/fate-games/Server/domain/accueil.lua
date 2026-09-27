-- Ecran d'accueil : a la connexion, le personnage attend cache hors carte
-- (Characters.OuvrirVestiaire) pendant que le client montre la carte, le titre
-- et l'activite (Client/accueil). Une touche : accueil:jouer, il apparait.
--
-- Plans A et B de la camera dans accueil.json, a la racine du serveur (doc
-- File), poses en jeu par /accueil a et /accueil b (mode dev) : la camera du
-- developpeur, que seul son client connait (accueil:mesurer).

return function(Log, Characters, Boutique, Activite, config, dev_pour)
    local Accueil = {}
    local FICHIER = config.fichier or "accueil.json"
    local plans = {}        -- { a = plan, b = plan }, plan = { x, y, z, pitch, yaw, roll }
    local presents = {}     -- player_id -> Player, sur l'accueil
    local look_de = nil     -- fonction(etat) -> tenue resolue (Server/Index.lua)

    local function lire()
        if not File.Exists(FICHIER) then return {} end
        local f = File(FICHIER)
        local texte = f:Read(0)
        f:Close()
        local ok, t = pcall(JSON.parse, texte)
        return (ok and type(t) == "table") and t or {}
    end

    local function ecrire()
        local f = File(FICHIER, true)
        f:Write(JSON.stringify(plans))
        f:Close()
    end

    -- Sans plan pose : au-dessus du point d'apparition, un peu en retrait.
    local function plan_defaut()
        local s = config.spawn
        return { x = s.x, y = s.y - 900, z = s.z + 450, pitch = -18, yaw = 90, roll = 0 }
    end

    local function en_ligne()
        local n = 0
        for _ in pairs(Player.GetPairs()) do n = n + 1 end
        return n
    end

    local function a_tous(evenement, donnee)
        for id, p in pairs(presents) do
            if p:IsValid() then
                Events.CallRemote(evenement, p, Reliability.Reliable, donnee)
            else
                presents[id] = nil
            end
        end
    end

    function Accueil.Ouvrir(session, transform, etat)
        Characters.OuvrirVestiaire(session, transform, look_de(etat))
        Characters.MontrerAuVestiaire(session.player_id, false)
        presents[session.player_id] = session.player
        Events.CallRemote("accueil:ouvrir", session.player, Reliability.Reliable, {
            solde = etat.solde,
            plans = { a = plans.a or plan_defaut(), b = plans.b },
            parties = Activite.Resume(en_ligne()),
            gains = Activite.Gains(),
            traversee = config.traversee or 40,
        })
    end

    function Accueil.Gain(g)
        a_tous("accueil:gain", g)
    end

    function Accueil.Init(fonction_look)
        look_de = fonction_look
        plans = lire()

        -- Une touche : il apparait (une seule fois, et seulement depuis l'accueil).
        Events.SubscribeRemote("accueil:jouer", function(player)
            local id = player:GetID()
            if not presents[id] then return end
            presents[id] = nil
            if not Characters.AuVestiaire(id) then return end
            local session = Characters.SessionByPlayer(id)
            local etat = session and session.account and Boutique.Etat(session.account)
            if etat then Characters.Habiller(id, look_de(etat)) end
            Characters.QuitterVestiaire(id)
            Events.CallRemote("accueil:fermer", player, Reliability.Reliable)
        end)

        -- /accueil a|b : le client du developpeur renvoie sa camera.
        Chat.Subscribe("PlayerSubmit", function(message, player)
            local lettre = tostring(message):match("^/accueil%s+([abAB])%s*$")
            if not lettre then return end
            if not dev_pour(player) then return end
            Events.CallRemote("accueil:mesurer", player, Reliability.Reliable, lettre:lower())
            return false
        end)
        Events.SubscribeRemote("accueil:mesure", function(player, lettre, l, r)
            if not dev_pour(player) or (lettre ~= "a" and lettre ~= "b") then return end
            if not (l and r and l.X and r.Yaw) then return end
            plans[lettre] = { x = l.X, y = l.Y, z = l.Z, pitch = r.Pitch, yaw = r.Yaw, roll = r.Roll }
            ecrire()
            Chat.SendMessage(player, ("Plan %s de l'accueil enregistre."):format(lettre:upper()))
        end)

        -- Toutes les 2 s : le resume des jeux, envoye seulement s'il a change.
        Timer.SetInterval(function()
            if not next(presents) then return end
            local r = Activite.Changement(en_ligne())
            if r then a_tous("accueil:parties", r) end
        end, 2000)

        Player.Subscribe("Destroy", function(player) presents[player:GetID()] = nil end)
        Log.Info("accueil", "pret" .. (plans.a and " (plan A pose)" or " (plan par defaut)"))
    end

    return Accueil
end
