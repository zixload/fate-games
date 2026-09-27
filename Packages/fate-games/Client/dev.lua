-- Le mode dev, annonce par le serveur a l'arrivee ([custom_settings] dev =
-- true dans son Config.toml). Hors mode dev, les commandes de reglage du
-- client (/fan, /lg demo, /lg ciel...) ne repondent pas (docs/SORTIE.md).

local Dev = { actif = false }
Events.SubscribeRemote("fg:dev", function(actif) Dev.actif = actif == true end)
return Dev
