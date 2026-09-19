-- L'outil de l'atelier en cours (panneau dev, F2, package separe).
--
-- Tant qu'un outil autre que Poings est actif, E, la molette et les clics
-- lui appartiennent : l'interaction et le HUD de Liar's Bar se taisent. Sans
-- atelier, l'evenement n'arrive jamais et rien ne change. Package.Require
-- garde le resultat en cache : tous les modules lisent la meme table.

local etat = { actif = false }

Events.Subscribe("atelier:outil", function(nom)
    etat.actif = nom ~= nil and nom ~= "poings"
end)

return etat
