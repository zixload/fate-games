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

local LiarsBar = Package.Require("games/liars_bar/adapter.lua")(
    Log, DB, Ids, Characters, Interactables, Intents,
    LiarsEngine, Appearances, LiarsConfig, ServerConfig.spawn)

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
