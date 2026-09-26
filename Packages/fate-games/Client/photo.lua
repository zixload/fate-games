-- Mode capture : F1 cache les logs de Liar's Bar en haut a gauche (l'etat de
-- la table et le journal), pour des captures d'ecran propres. F1 les ramene.
-- Package.Require garde le resultat en cache : liars_bar/hud.lua lit la meme
-- table.

local etat = { cache = false }

Input.Subscribe("KeyPress", function(touche)
    if touche ~= "F1" then return end
    etat.cache = not etat.cache
end)

return etat
