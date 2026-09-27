r"""Retire l'asset physique des pieces portees (vetements, chaussures, coiffures).

A executer dans la console Python de l'editeur (NanosWorldADK) :

    exec(open(r"C:\Users\ingam\OneDrive\Documents\fate-games\scripts\unreal\retirer_physique_vetements.py", encoding="utf-8").read())

Pourquoi : chaque piece du kit Creative arrive avec un asset physique (des
corps de collision). Accrochee au personnage, une piece garde ces corps ; des
chaussons qui depassent sous le pied pourraient accrocher le bord des marches
(27/09 : moins de blocages dans les escaliers avec les baskets). Une piece
portee n'a pas besoin de physique. Le corps du personnage (SK_Animations,
SK_Body...) garde la sienne : elle sert aux touches.

APPLIQUER = False : n'affiche que ce qui serait change. Relancer ne refait rien.
Save All puis cuire my-asset-pack ensuite.
"""

import unreal

APPLIQUER = True
RACINES = ["/Game/MyAssetPack/Creative_Characters_FREE", "/Game/MyAssetPack/Cosmetiques",
           "/Game/MyAssetPack/Cosmetics"]
GARDER = ("SK_Animations", "SK_Body", "SKEL_")      # corps : physique gardee

lib = unreal.EditorAssetLibrary
changes = 0
for racine in RACINES:
    if not lib.does_directory_exist(racine):
        continue
    for chemin in lib.list_assets(racine, recursive=True):
        nom = chemin.split(".")[-1]
        if not nom.startswith("SK_") or any(nom.startswith(g) for g in GARDER):
            continue
        asset = lib.load_asset(chemin)
        if not isinstance(asset, unreal.SkeletalMesh):
            continue
        if asset.get_editor_property("physics_asset") is None:
            continue
        print("PHYSIQUE_RETIREE" if APPLIQUER else "PHYSIQUE_A_RETIRER", nom)
        if APPLIQUER:
            asset.set_editor_property("physics_asset", None)
            lib.save_loaded_asset(asset)
        changes += 1
print("PHYSIQUE_VETEMENTS_COMPLETE", changes, "pieces")
