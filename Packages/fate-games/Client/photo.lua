-- Mode capture : F1 cache tout l'affichage superpose du jeu (journal, main,
-- invite, barillets, duel), pour des captures d'ecran propres. F1 le ramene.
-- Package.Require garde le resultat en cache : tous les modules lisent la
-- meme table, et ceux qui ont une WebUI ecoutent "zix:photo".

local etat = { cache = false }

Input.Subscribe("KeyPress", function(touche)
    if touche ~= "F1" then return end
    etat.cache = not etat.cache
    Events.Call("zix:photo", etat.cache)
end)

return etat
