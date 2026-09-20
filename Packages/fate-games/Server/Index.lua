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

local Accounts      = Package.Require("domain/accounts.lua")(Log, DB, Ids, ServerConfig)
local Characters    = Package.Require("domain/characters.lua")(Log, DB, Ids, Scheduler, Accounts, ServerConfig)
local Interactables = Package.Require("domain/interactables.lua")(Log, Intents, Characters, ServerConfig)

-- Liar's Bar. Le cablage est explicite et a plat : chaque module recoit ses
-- dependances, aucune globale ne circule entre eux (R5).
local LiarsConfig    = Package.Require("games/liars_bar/data/config.lua")
local Appearances    = Package.Require("Shared/appearances.lua")
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
end

-- Atelier (panneau admin et dev, depot a part), s'il est charge : le jeu se
-- nomme, ce qui range ses enregistrements. Deux appels, pour ne pas dependre
-- de l'ordre de chargement des packages.
local function declarer_atelier()
    Events.Call("atelier:declarer", "fate-games", {})
end
Events.Subscribe("atelier:pret", declarer_atelier)
declarer_atelier()

Player.Subscribe("Ready", function(player)
    Characters.OnPlayerReady(player)
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
