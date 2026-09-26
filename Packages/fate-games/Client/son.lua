-- Chemin d'un son du jeu. Les sons sont des assets de my-asset-pack, importes
-- depuis art/sons/ par scripts/unreal/import_sons.py (nom A_<fichier>) puis
-- cuits avec le reste. Les .ogg bruts lus par package:// se chargeaient au
-- hasard : duree 0, jamais joues, sauf un ou deux par session.

return function(nom)
    return "my-asset-pack::A_" .. (tostring(nom):gsub("%.ogg$", ""))
end
