-- Logs de Liar's Bar en haut a gauche (l'etat de la table et le journal) :
-- caches par defaut depuis le 26/09, F1 les montre ou les recache.
-- Package.Require garde le resultat en cache : liars_bar/hud.lua lit la meme
-- table.

local etat = { cache = true }

Input.Subscribe("KeyPress", function(touche)
    if touche ~= "F1" then return end
    etat.cache = not etat.cache
end)

return etat
