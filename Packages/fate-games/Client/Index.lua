-- Point d'entree client.
--
-- Le client ne fait que de la presentation : UI, effets, camera, surbrillance. Aucune
-- decision de jeu ici (R1) — il envoie une intention et attend le verdict du serveur.

local SharedConfig = Package.Require("Shared/config.lua")

-- Cote client : CallRemote(evenement, fiabilite, ...). La fiabilite est un
-- parametre positionnel — l'omettre y fait glisser le nom de l'intention.
local function send_intent(name, payload)
    Events.CallRemote("zix:intent", Reliability.Reliable, name, payload)
end

Events.SubscribeRemote("zix:intent_result", function(name, ok, detail)
    if not ok then
        Console.Log(("intention refusee : %s (%s)"):format(tostring(name), tostring(detail)))
    end
end)

local Interaction = Package.Require("interaction/init.lua")(SharedConfig.interaction)
Interaction.Start()
-- En partie de Liar's Bar, seule son arme se vise, et seulement pour tirer.
Package.Require("liars_bar/invite_partie.lua")(Interaction)
local ok_invite, err_invite = pcall(function()
    Package.Require("interaction/invite.lua")(Interaction)
end)
if not ok_invite then Console.Error("[interaction] invite impossible : " .. tostring(err_invite)) end

-- Posture assise des personnages d'essai, publiee par le serveur.
Package.Require("posture.lua")
Package.Require("vue_assise.lua")
Package.Require("regard_assis.lua")

-- F1 : cacher les logs en haut a gauche, pour les captures d'ecran.
Package.Require("photo.lua")

-- Marcher par defaut, Maj pour courir.
Package.Require("course.lua")
-- Espace pour quitter sa chaise hors partie.
Package.Require("se_lever.lua")

-- Vestiaire d'arrivee : cartes des personnages et des armes, boutique.
local ok_vestiaire, err_vestiaire = pcall(function()
    Package.Require("vestiaire/vestiaire.lua")(SharedConfig)
end)
if not ok_vestiaire then Console.Error("[vestiaire] chargement impossible : " .. tostring(err_vestiaire)) end

-- Duel : HUD, touches et tir dans l'arene.
local ok_duel, err_duel = pcall(function()
    Package.Require("duel/duel.lua")(SharedConfig)
end)
if not ok_duel then Console.Error("[duel] chargement impossible : " .. tostring(err_duel)) end

-- HUD provisoire de Liar's Bar : le journal et la main, au clavier.
local LiarsJournal = Package.Require("liars_bar/journal.lua")(SharedConfig.liars_hud)
local liars_journal = Package.Require("liars_bar/hud.lua")(
    SharedConfig.liars_hud, LiarsJournal, send_intent, SharedConfig.liars_cards)
local ok_tags, err_tags = pcall(function()
    Package.Require("liars_bar/nametags.lua")(liars_journal)
end)
if not ok_tags then Console.Error("[etiquettes] chargement impossible : " .. tostring(err_tags)) end

local ok_sons, err_sons = pcall(function()
    Package.Require("liars_bar/sons.lua")(Package.Require("Shared/liars_table.lua"))
end)
if not ok_sons then Console.Error("[sons] chargement impossible : " .. tostring(err_sons)) end

-- Cartes en 3D, a regler en jeu (/fan). Sous garde : pas encore valide en
-- jeu, un echec ici ne doit pas emporter le reste du client.
local ok_cartes, err_cartes = pcall(function()
    local LiarsCartes = Package.Require("liars_bar/cartes.lua")(SharedConfig.liars_cards)
    local disposition = Package.Require("Shared/liars_table.lua")
    local rendu = Package.Require("liars_bar/rendu.lua")(
        SharedConfig.liars_cards, LiarsCartes, liars_journal, disposition)
    Package.Require("liars_bar/reglages.lua")(SharedConfig.liars_cards, rendu)
    Package.Require("liars_bar/atelier.lua")(SharedConfig.liars_cards, rendu)
end)
if not ok_cartes then
    Console.Error("[cartes] chargement impossible : " .. tostring(err_cartes))
end

Console.Log("[INFO][boot] Fate Games - client pret")

return {
    SendIntent = send_intent,
    Interaction = Interaction,
}
