-- Point d'entree serveur.
--
-- Seul endroit ou l'ordre de chargement et les dependances sont decides (R5 : injection
-- explicite, aucune globale entre modules). Les dependances de chaque module se lisent
-- donc ici, en une seule fois.
--
-- Convention : un module de donnees retourne une table ; un module de comportement
-- retourne une fonction qui recoit ses dependances et retourne sa table publique.

local SharedConfig = Package.Require("Shared/config.lua")
local ServerConfig = Package.Require("core/config.lua")

local Log       = Package.Require("core/log.lua")(ServerConfig)
local Scheduler = Package.Require("core/scheduler.lua")(Log, SharedConfig)
local DB        = Package.Require("db/init.lua")(Log, ServerConfig)
local Ids       = Package.Require("core/ids.lua")(Log, DB)
local Intents   = Package.Require("intents/init.lua")(Log)

local Appearances   = Package.Require("Shared/appearances.lua")
local Catalogue     = Package.Require("Shared/catalogue.lua")

local Accounts      = Package.Require("domain/accounts.lua")(Log, DB, Ids, ServerConfig)
local Characters    = Package.Require("domain/characters.lua")(Log, DB, Ids, Scheduler, Accounts, ServerConfig, Appearances)
local Interactables = Package.Require("domain/interactables.lua")(Log, Intents, Characters, ServerConfig)
local Boutique      = Package.Require("domain/boutique.lua")(Log, DB, Ids, Catalogue, ServerConfig)

-- Liar's Bar. Le cablage est explicite et a plat : chaque module recoit ses
-- dependances, aucune globale ne circule entre eux (R5).
local LiarsConfig    = Package.Require("games/liars_bar/data/config.lua")
local LiarsDeck      = Package.Require("games/liars_bar/data/deck.lua")(LiarsConfig)
local LiarsRevolver  = Package.Require("games/liars_bar/revolver.lua")(LiarsConfig)
local LiarsChallenge = Package.Require("games/liars_bar/challenge.lua")(LiarsDeck)
local LiarsRound     = Package.Require("games/liars_bar/round.lua")(LiarsConfig, LiarsDeck)
local LiarsMatch     = Package.Require("games/liars_bar/match.lua")(LiarsConfig, Appearances, LiarsRevolver)
local LiarsEffects   = Package.Require("games/liars_bar/effects.lua")()

local LiarsEngine = Package.Require("games/liars_bar/engine.lua")(
    LiarsConfig, LiarsDeck, LiarsRevolver, LiarsChallenge,
    LiarsRound, LiarsMatch, LiarsEffects)

local LiarsBots = Package.Require("games/liars_bar/bots.lua")(LiarsConfig)

-- Duel : regles pures (logic.lua) et branchement au monde (adapter.lua).
local DuelConfig = Package.Require("games/duel/data/config.lua")
local DuelLogic  = Package.Require("games/duel/logic.lua")(DuelConfig)
local DuelJeu    = Package.Require("games/duel/adapter.lua")(
    Log, Characters, Boutique, Catalogue, DuelLogic, DuelConfig,
    Package.Require("games/duel/data/arenes.lua"))

local LiarsBar = Package.Require("games/liars_bar/adapter.lua")(
    Log, DB, Ids, Characters, Interactables, Intents,
    LiarsEngine, LiarsBots, Appearances, LiarsConfig, ServerConfig.spawn)

-- Les chaines de log restent en ASCII : la console Windows les reaffiche selon sa page
-- de codes locale, et tout caractere accentue y ressort en "?".
Log.Info("boot", "=== Fate Games - demarrage ===")

-- Version de la VM Lua du moteur. Elle determine quel interpreteur autonome peut faire
-- tourner le banc de test hors-jeu : LuaJIT parle 5.1, Lua 5.4 non.
Log.Info("boot", ("VM %s%s"):format(_VERSION, jit and (" / " .. jit.version) or ""))

DB.Connect()

if not DB.Migrate() then
    Log.Error("boot", "migrations echouees : initialisation interrompue")
    return
end

if not Ids.Seed({ "accounts", "characters", "ledger", "liars_matches" }) then
    Log.Error("boot", "amorcage des identifiants echoue : initialisation interrompue")
    return
end

-- A partir d'ici, plus aucune requete bloquante n'est autorisee (R2).
DB.EndStartup()

Scheduler.Start()

LiarsBar.Init()
DuelJeu.Init()

-- Poser l'arene du duel sous ses pieds : "/arene [rayon]", en mode dev.
if ServerConfig.dev and ServerConfig.dev.liars_bots then
    Chat.Subscribe("PlayerSubmit", function(message, player)
        local texte = tostring(message)
        if not texte:match("^/arene") then return end
        local rayon = tonumber(texte:match("^/arene%s+(%d+)"))
        local ligne, err = DuelJeu.PoserArene(player, rayon)
        Chat.SendMessage(player, ligne and (ligne .. " (disparait au redemarrage)")
            or ("arene : " .. tostring(err)))
        if ligne then Log.Info("duel", ligne) end
        return false
    end)

    -- Un adversaire de test pour jouer seul : "/botduel", debout dans l'arene.
    Chat.Subscribe("PlayerSubmit", function(message, player)
        if not tostring(message):match("^/botduel") then return end
        local nom, err = DuelJeu.AjouterBot(player)
        Chat.SendMessage(player, nom and (nom .. " rejoint le duel, pret. R pour lancer.") or ("botduel : " .. tostring(err)))
        return false
    end)
end

-- Bots de test : "/bots N" dans le chat, en mode dev seulement. Retourner
-- false retient le message (doc Chat, PlayerSubmit).
if ServerConfig.dev and ServerConfig.dev.liars_bots then
    Chat.Subscribe("PlayerSubmit", function(message, player)
        local n = tostring(message):match("^/bots%s+(%d+)%s*$")
        if not n then return end

        local ok, detail = LiarsBar.SetBots(tonumber(n))
        if ok then
            Chat.SendMessage(player, ("%d bot(s) a la table"):format(detail))
        else
            Chat.SendMessage(player, "bots refuses : " .. tostring(detail))
        end
        return false
    end)
    Log.Info("liars", "bots de test actifs : /bots N dans le chat")

    -- Mannequin de reglage, hors partie : /posebot [chaise] puis /posebot stop.
    Chat.Subscribe("PlayerSubmit", function(message, player)
        local texte = tostring(message)
        if texte ~= "/posebot" and not texte:match("^/posebot%s+") then return end
        local argument = texte:match("^/posebot%s+(%S+)%s*$")
        if argument == "stop" then
            LiarsBar.StopPoseBot()
            Chat.SendMessage(player, "mannequin de prise retire")
            return false
        end
        local regard_yaw, regard_pitch = texte:match("^/posebot%s+regard%s+([%+%-]?[%d%.]+)%s+([%+%-]?[%d%.]+)%s*$")
        if regard_yaw and tonumber(regard_yaw) and tonumber(regard_pitch) then
            local ok = LiarsBar.PoseBotLook(tonumber(regard_yaw), tonumber(regard_pitch))
            Chat.SendMessage(player, ok and "regard du mannequin regle" or "lance /posebot d'abord")
            return false
        end
        if argument and not tonumber(argument) then
            Chat.SendMessage(player, "usage : /posebot [chaise 1-4|stop|regard yaw pitch]")
            return false
        end
        local chaise = argument and tonumber(argument) or nil
        if chaise and (chaise % 1 ~= 0 or chaise < 1 or chaise > 4) then
            Chat.SendMessage(player, "chaise attendue : 1 a 4")
            return false
        end
        local ok, detail = LiarsBar.PoseBot(player, chaise)
        Chat.SendMessage(player, ok and ("pose figee sur chaise " .. detail .. " ; /prise pour les valeurs")
            or ("posebot : " .. tostring(detail)))
        return false
    end)

    -- /prise affiche les valeurs ; /prise z -2 les ajuste ; six nombres
    -- remplacent les valeurs. L'arme du mannequin bouge sans rejouer la pose.
    Chat.Subscribe("PlayerSubmit", function(message, player)
        local texte = tostring(message)
        if texte ~= "/prise" and not texte:match("^/prise%s+") then return end
        local v = {}
        for token in texte:gmatch("%S+") do v[#v + 1] = token end
        local prise
        if #v == 1 then
            prise = LiarsBar.GetPrise()
        elseif #v == 3 then
            prise = LiarsBar.AdjustPrise(v[2], tonumber(v[3]))
        elseif #v == 7 then
            local values = {}
            local tous_valides = true
            for i = 2, 7 do
                values[i - 1] = tonumber(v[i])
                if not values[i - 1] then tous_valides = false end
            end
            if tous_valides then
                prise = LiarsBar.SetPrise({ x = values[1], y = values[2], z = values[3],
                    p = values[4], ya = values[5], r = values[6] })
            end
        end
        if prise then
            Chat.SendMessage(player, ("prise : %g %g %g | %g %g %g"):format(
                prise.x, prise.y, prise.z, prise.p, prise.ya, prise.r))
        else
            Chat.SendMessage(player, "usage : /prise [axe x,y,z,p,ya,r decalage | x y z p ya r]")
        end
        return false
    end)
end

-- ESSAI : regler la camera assise en direct, "/cam <avant> <haut> [cote]"
-- en cm (cote positif = vers la droite),
-- tant que le personnage d'essai est actif. Les bonnes valeurs vont ensuite
-- dans dev.creative_character.seated_camera.
local essai = ServerConfig.dev and ServerConfig.dev.creative_character
if essai and essai.enabled then
    Chat.Subscribe("PlayerSubmit", function(message, player)
        local texte = tostring(message)
        local avant, haut, cote = texte:match("^/cam%s+(%-?[%d%.]+)%s+(%-?[%d%.]+)%s+(%-?[%d%.]+)%s*$")
        if not avant then
            avant, haut = texte:match("^/cam%s+(%-?[%d%.]+)%s+(%-?[%d%.]+)%s*$")
        end
        if not avant then return end

        if Characters.SetSeatedCamera(player:GetID(), tonumber(avant), tonumber(haut), tonumber(cote or 0)) then
            Chat.SendMessage(player, ("camera assise : avant %s, haut %s, cote %s"):format(avant, haut, cote or 0))
        else
            Chat.SendMessage(player, "pas de personnage d'essai a regler")
        end
        return false
    end)

    -- ESSAI : regler les vitesses en direct, "/vitesse <marche> [course]" en
    -- cm/s, pour trouver celle qui ne fait pas glisser les pieds.
    Chat.Subscribe("PlayerSubmit", function(message, player)
        local texte = tostring(message)
        -- "/vitesse arriere <marche> [course]" regle le recul.
        local arriere = texte:match("^/vitesse%s+arriere%s+") ~= nil
        local motif = arriere and "^/vitesse%s+arriere%s+" or "^/vitesse%s+"
        local marche, course = texte:match(motif .. "([%d%.]+)%s+([%d%.]+)%s*$")
        if not marche then
            marche = texte:match(motif .. "([%d%.]+)%s*$")
        end
        if not marche then return end

        local regler = arriere and Characters.SetVitessesArriere or Characters.SetVitesses
        if regler(player:GetID(), tonumber(marche), tonumber(course)) then
            Chat.SendMessage(player, ("vitesses %s : marche %s, course %s"):format(
                arriere and "en arriere" or "en avant", marche,
                course or (arriere and essai.run_back_speed or essai.run_speed)))
        else
            Chat.SendMessage(player, "pas de personnage d'essai a regler")
        end
        return false
    end)

    -- ESSAI : regler le saut en direct, "/saut <impulsion> [pesanteur]".
    -- Le temps en l'air doit correspondre a l'animation de chute.
    Chat.Subscribe("PlayerSubmit", function(message, player)
        local texte = tostring(message)
        local z, pesanteur = texte:match("^/saut%s+([%d%.]+)%s+([%d%.]+)%s*$")
        if not z then z = texte:match("^/saut%s+([%d%.]+)%s*$") end
        if not z then return end

        if Characters.SetSaut(player:GetID(), tonumber(z), tonumber(pesanteur)) then
            local p = tonumber(pesanteur) or essai.gravity_scale
            Chat.SendMessage(player, ("saut : impulsion %s, pesanteur %s, environ %.2f s en l'air")
                :format(z, tostring(p), 2 * tonumber(z) / (981 * p)))
        else
            Chat.SendMessage(player, "pas de personnage d'essai a regler")
        end
        return false
    end)

    -- Maj pour courir. Hors du pipeline des intentions : un reglage de
    -- vitesse sans enjeu de jeu ne merite pas une ligne d'audit par appui.
    Events.SubscribeRemote("zix:course", function(player, course)
        Characters.SetRunning(player:GetID(), course == true)
    end)

    -- Le client a vu qu'il recule : on ralentit, meme raison.
    Events.SubscribeRemote("zix:recul", function(player, recul)
        Characters.SetArriere(player:GetID(), recul == true)
    end)

    -- Le regard est purement visuel : seuls les joueurs assis peuvent publier
    -- leur angle, a une cadence bornee. La valeur synchronisee anime le cou et
    -- la tete sur les autres clients sans toucher au verdict du jeu.
    local dernier_regard = {}
    Events.SubscribeRemote("zix:regard_assis", function(player, yaw, pitch)
        local session = Characters.SessionByPlayer(player:GetID())
        local character = session and session.character
        if not (session and session.assis and character and character:IsValid()
            and character:IsA(CharacterSimple)) then return end
        if type(yaw) ~= "number" or type(pitch) ~= "number"
            or yaw ~= yaw or pitch ~= pitch then return end
        local maintenant = Server.GetTime()
        local id = player:GetID()
        if maintenant - (dernier_regard[id] or 0) < 80 then return end
        dernier_regard[id] = maintenant
        character:SetValue("liars_look", {
            yaw = math.max(-30, math.min(30, yaw)),
            pitch = math.max(-15, math.min(15, pitch)),
        }, true)
    end)
end

-- Atelier (panneau admin et dev, depot a part), s'il est charge : le jeu se
-- nomme, ce qui range ses enregistrements. Deux appels, pour ne pas dependre
-- de l'ordre de chargement des packages.
local function declarer_atelier()
    Events.Call("atelier:declarer", "fate-games", {})
end
Events.Subscribe("atelier:pret", declarer_atelier)
declarer_atelier()

-- Vestiaire d'arrivee et boutique. Le client ne fait que demander : chaque
-- achat, choix et entree est revalide ici contre le catalogue du serveur.
do
    local function envoyer(player, etat, refus)
        Events.CallRemote("vestiaire:etat", player, Reliability.Reliable, Boutique.Vue(etat), refus)
    end

    -- La session et son etat de boutique, si le joueur est bien au vestiaire.
    local function au_vestiaire(player)
        local session = Characters.SessionByPlayer(player:GetID())
        if not (session and session.account and Characters.AuVestiaire(player:GetID())) then return nil end
        local etat = Boutique.Etat(session.account)
        if not etat then return nil end
        return session, etat
    end

    Characters.SurArrivee(function(session, transform)
        Boutique.Charger(session.account, function(etat)
            if not Characters.SessionByPlayer(session.player_id) then return end
            -- Base en panne : on entre quand meme, avec la tenue par defaut.
            if not etat then
                return Characters.Apparaitre(session, transform, ServerConfig.boutique.perso_defaut)
            end
            if not (ServerConfig.vestiaire and ServerConfig.vestiaire.enabled) then
                return Characters.Apparaitre(session, transform, etat.perso)
            end
            Characters.OuvrirVestiaire(session, transform, etat.perso)
            Events.CallRemote("vestiaire:ouvrir", session.player, Reliability.Reliable, Boutique.Vue(etat))
        end)
    end)

    -- Apercu : la tenue change sur le personnage du vestiaire, achetee ou non.
    Events.SubscribeRemote("vestiaire:apercu", function(player, look_id)
        if not au_vestiaire(player) then return end
        if type(look_id) ~= "string" or not Catalogue.article("persos", look_id) then return end
        Characters.Habiller(player:GetID(), look_id)
    end)

    -- Rayon des armes : le personnage s'efface derriere l'arme montree.
    Events.SubscribeRemote("vestiaire:vitrine", function(player, id)
        if not au_vestiaire(player) then return end
        Characters.MontrerAuVestiaire(player:GetID(), type(id) ~= "string" or id == "")
    end)

    Events.SubscribeRemote("vestiaire:acheter", function(player, rayon, id)
        local session, etat = au_vestiaire(player)
        if not session then return end
        if rayon ~= "persos" and rayon ~= "armes" then return end
        if type(id) ~= "string" then return end
        Boutique.Acheter(session.account, rayon, id, nil, function(ok, raison)
            envoyer(player, etat, not ok and raison or nil)
        end)
    end)

    Events.SubscribeRemote("vestiaire:equiper", function(player, id)
        local session, etat = au_vestiaire(player)
        if not session or type(id) ~= "string" then return end
        Boutique.Equiper(session.account, "armes", id, function(ok, raison)
            envoyer(player, etat, not ok and raison or nil)
        end)
    end)

    -- Entrer : la tenue choisie doit etre possedee. Elle est gardee pour la
    -- prochaine connexion, puis le personnage descend dans le monde.
    Events.SubscribeRemote("vestiaire:entrer", function(player, look_id)
        local session, etat = au_vestiaire(player)
        if not session or type(look_id) ~= "string" then return end
        if not Boutique.Possede(etat, "persos", look_id) then
            return envoyer(player, etat, "non_possede")
        end
        Boutique.Equiper(session.account, "persos", look_id, function(ok)
            if not ok then return envoyer(player, etat, "base") end
            if not Characters.AuVestiaire(player:GetID()) then return end
            Characters.Habiller(player:GetID(), look_id)
            Characters.QuitterVestiaire(player:GetID())
            Events.CallRemote("vestiaire:fermer", player, Reliability.Reliable)
        end)
    end)

    -- Remonter au vestiaire en jeu (touche I du client), debout seulement.
    Events.SubscribeRemote("vestiaire:retour", function(player)
        if not (ServerConfig.vestiaire and ServerConfig.vestiaire.enabled) then return end
        local session = Characters.SessionByPlayer(player:GetID())
        if not (session and session.account) then return end
        Boutique.Charger(session.account, function(etat)
            if not etat then return end
            local ok, raison = Characters.RetournerVestiaire(player:GetID(), etat.perso)
            if not ok then
                Log.Debug("vestiaire", "retour refuse : " .. tostring(raison))
                return
            end
            Events.CallRemote("vestiaire:ouvrir", player, Reliability.Reliable, Boutique.Vue(etat))
        end)
    end)

    -- Argent de test : "/argent <n>" dans le chat, en mode dev seulement.
    if ServerConfig.dev and ServerConfig.dev.liars_bots then
        Chat.Subscribe("PlayerSubmit", function(message, player)
            local n = tostring(message):match("^/argent%s+(%d+)%s*$")
            if not n then return end
            local session = Characters.SessionByPlayer(player:GetID())
            if not (session and session.account and Boutique.Etat(session.account)) then return false end
            Boutique.Crediter(session.account, tonumber(n), "dev", nil, function(ok)
                local etat = Boutique.Etat(session.account)
                Chat.SendMessage(player, ok and ("solde : %d"):format(etat.solde) or "credit refuse")
                if ok and Characters.AuVestiaire(player:GetID()) then envoyer(player, etat) end
            end)
            return false
        end)
    end
end

-- Demo de reglage des cartes (/fan demo, cote client) : bots sur toutes les
-- chaises, en mode dev seulement.
if ServerConfig.dev and ServerConfig.dev.liars_bots then
    Events.SubscribeRemote("liars:fan_demo", function(player, actif)
        local ok, detail = LiarsBar.DemoCartes(actif == true)
        Chat.SendMessage(player, ok and (actif and ("demo : %d bot(s) assis"):format(detail) or "demo : bots partis")
            or ("demo impossible : " .. tostring(detail)))
    end)
end

-- Se lever de sa chaise hors partie, par la touche du client. Le verdict
-- (refus en partie) reste a Liar's Bar.
Events.SubscribeRemote("liars:lever", function(player)
    LiarsBar.Lever(player)
end)

Player.Subscribe("Ready", function(player)
    Characters.OnPlayerReady(player)
    local ok_duel, err_duel = pcall(DuelJeu.OnPlayerReady, player)
    if not ok_duel then Log.Warn("duel", "arenes non envoyees : " .. tostring(err_duel)) end
    -- Voix de proximite native : le son suit le personnage en 3D, donc sa
    -- direction se percoit en stereo autour de la table. Pas de canal global
    -- en parallele, qui ferait entendre deux fois la meme personne.
    local ok_voix, err_voix = pcall(function()
        player:SetVOIPGlobalAllChannelsSetting(VOIPSetting.None)
        player:SetVOIPLocalMaxDistance(ServerConfig.voice.max_distance)
        player:SetVOIPLocalVolume(ServerConfig.voice.volume)
        player:SetVOIPLocalSetting(VOIPSetting.Both)
    end)
    if not ok_voix then Log.Warn("voix", "VOIP locale indisponible : " .. tostring(err_voix)) end
    -- Le joueur doit connaitre ce qui est deja interactif dans le monde.
    Interactables.SendSnapshotTo(player)
end)

Player.Subscribe("Destroy", function(player)
    -- Prevenir le jeu AVANT que la session du personnage soit fermee, sinon la
    -- place n'est plus retrouvable. Sous pcall parce qu'une levee ici sauterait
    -- le vidage de position et la destruction du Character.
    local ok, err = pcall(LiarsBar.OnPlayerLeave, player)
    if not ok then
        Log.Error("liars", "OnPlayerLeave a leve : " .. tostring(err))
    end
    local ok_duel, err_duel = pcall(DuelJeu.OnPlayerLeave, player)
    if not ok_duel then
        Log.Error("duel", "OnPlayerLeave a leve : " .. tostring(err_duel))
    end

    local session = Characters.SessionByPlayer(player:GetID())
    if session then Boutique.Oublier(session.account) end

    Characters.OnPlayerLeave(player)
end)

if ServerConfig.dev and ServerConfig.dev.smoke_test then
    Package.Require("dev/smoke.lua")(Log, DB, Characters).Run()
end

Package.Subscribe("Unload", function()
    -- Ecrire avant de fermer : sinon on perd la derniere tranche de la roue.
    Characters.FlushAll()
    Scheduler.Stop()
    DB.Close()
    Log.Info("boot", "package decharge proprement")
end)

Log.Info("boot", "initialisation terminee")
