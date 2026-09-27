r"""Repare les vetements en damier gris : coche l'usage "maillage squelettique"
de M_COS_Base et pose un materiau par defaut sur chaque piece SK_COS_*.

A executer une fois dans la console Python de l'ADK :

    exec(open(r"C:\Users\ingam\OneDrive\Documents\fate-games\scripts\unreal\reparer_materiau_cosmetiques.py", encoding="utf-8").read())

Puis Save All et cuire my-asset-pack. (import_cosmetiques.py le fait aussi
desormais ; ce script evite de tout reimporter.)
"""

import json
from pathlib import Path

import unreal

ART = Path("C:/Users/ingam/OneDrive/Documents/fate-games/art/cosmetics")
DEST = "/Game/MyAssetPack/Cosmetiques"
lib = unreal.EditorAssetLibrary
mel = unreal.MaterialEditingLibrary

base = lib.load_asset(DEST + "/M_COS_Base")
if not base:
    raise RuntimeError("M_COS_Base introuvable : lancer d'abord import_cosmetiques.py")
base.set_editor_property("used_with_skeletal_mesh", True)
mel.recompile_material(base)
lib.save_loaded_asset(base)
print("COS_BASE_SQUELETTIQUE", base.get_editor_property("used_with_skeletal_mesh"))

defauts = {
    "SK_COS_TShirt_Rare_Compass": "MI_COS_TShirt_Rare_Compass",
    "SK_COS_TShirt_Epic_Eclipse": "MI_COS_TShirt_Epic_Eclipse",
    "SK_COS_TShirt_Legendary_Sun": "MI_COS_TShirt_Legendary_Sun",
}
for m in json.loads((ART / "pantalons/manifeste.json").read_text(encoding="utf-8")):
    defauts.setdefault(m["piece"], "MI_" + m["texture"][2:])

for piece, mi_nom in sorted(defauts.items()):
    sk = lib.load_asset(DEST + "/" + piece)
    mi = lib.load_asset(DEST + "/Materiaux/" + mi_nom)
    if not (sk and mi):
        print("COS_MANQUE", piece, mi_nom)
        continue
    mats = sk.get_editor_property("materials")
    for m in mats:
        m.set_editor_property("material_interface", mi)
    sk.set_editor_property("materials", mats)
    lib.save_loaded_asset(sk)
    print("COS_PIECE_MATERIAU", piece, mi_nom)
lib.save_directory(DEST)
print("COS_REPARATION_COMPLETE")
