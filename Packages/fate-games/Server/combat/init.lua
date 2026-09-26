-- Point d'entree du systeme de combat (docs/COMBAT.md) :
--
--     local Combat = Package.Require("combat/init.lua")
--     local w = Combat.nouveau({ a_terre = { actif = true } })
--
-- Tout le dossier combat/ est du Lua pur : pour Qin RP, le copier tel quel
-- et adapter seulement ce chargement si les chemins different.

local R = Package.Require("combat/regles.lua")
local A = Package.Require("combat/armes.lua")
local S = Package.Require("combat/sorts.lua")
local G = Package.Require("combat/geometrie.lua")

local Combat = Package.Require("combat/moteur.lua")(R, A, S, G)
Combat.regles, Combat.armes, Combat.sorts, Combat.geometrie = R, A, S, G
Combat.ia = Package.Require("combat/ia.lua")
return Combat
