r"""Repare les vetements en damier gris : coche l'usage "maillage squelettique"
de M_COS_Base (sans lui, tout motif pose sur un maillage squelettique
s'affiche en damier en jeu cuit).

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

# Aucun materiau par defaut sur les pieces : un motif qui ne prend pas en jeu
# doit rester visible (damier). Si une version precedente de ce script en a
# pose, on les retire.
for sk_asset in lib.list_assets(DEST, recursive=False):
    nom = sk_asset.split(".")[-1]
    if not nom.startswith("SK_COS_") or nom.endswith("PhysicsAsset") or nom.endswith("Frayed"):
        continue
    sk = lib.load_asset(sk_asset)
    if not isinstance(sk, unreal.SkeletalMesh):
        continue
    mats = sk.get_editor_property("materials")
    for m in mats:
        m.set_editor_property("material_interface", None)
    sk.set_editor_property("materials", mats)
    lib.save_loaded_asset(sk)
    print("COS_PIECE_SANS_DEFAUT", nom)
lib.save_directory(DEST)
print("COS_REPARATION_COMPLETE")
