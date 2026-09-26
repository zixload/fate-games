"""Remet la carte de role SM_WW_RoleCard a sa vraie taille (15 x 10 cm).

A executer dans la console Python de l'editeur (NanosWorldADK) :

    exec(open(r"C:\\Users\\ingam\\OneDrive\\Documents\\fate-games\\scripts\\unreal\\echelle_carte_role.py", encoding="utf-8").read())

L'import a lu les metres du FBX comme des centimetres : la carte etait
minuscule. Le script remet le Build Scale a 1, mesure le maillage, calcule
l'echelle qui donne 15 cm au grand cote, l'applique (le maillage est
reconstruit) et enregistre. Cuire my-asset-pack ensuite.
"""

import unreal

CHEMIN = "/Game/MyAssetPack/Werewolf/Decor/RoleCard/SM_WW_RoleCard"
LONGUEUR_CM = 15.0

mesh = unreal.EditorAssetLibrary.load_asset(CHEMIN)
if not mesh:
    raise RuntimeError(f"Introuvable : {CHEMIN}")
editeur = unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem)


def appliquer(echelle):
    reglages = editeur.get_lod_build_settings(mesh, 0)
    reglages.set_editor_property("build_scale3d", unreal.Vector(echelle, echelle, echelle))
    editeur.set_lod_build_settings(mesh, 0, reglages)


def grand_cote():
    boite = mesh.get_bounding_box()
    taille = boite.max - boite.min
    return max(taille.x, taille.y)


appliquer(1.0)
brut = grand_cote()
print("CARTE_TAILLE_BRUTE", brut, "cm")
if brut <= 0:
    raise RuntimeError("Maillage vide ou illisible")
echelle = LONGUEUR_CM / brut
appliquer(echelle)
print("CARTE_BUILD_SCALE", round(echelle, 3), "-> grand cote", round(grand_cote(), 2), "cm")
unreal.EditorAssetLibrary.save_loaded_asset(mesh)
print("CARTE_PRETE : cuire my-asset-pack")
