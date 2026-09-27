r"""Importe les vetements et accessoires (T-shirts, manches longues, pantalons,
shorts, coiffures, chapeaux, lunettes) dans my-asset-pack.

A executer dans la console Python de l'editeur ADK deja ouvert :

    exec(open(r"C:\Users\ingam\OneDrive\Documents\fate-games\scripts\unreal\import_cosmetiques.py", encoding="utf-8").read())

Une piece squelettique par coupe (T-shirts de ChatGPT, pantalons et short de
scripts/blender/create_pantalons.py), sur le squelette Creative. Une texture
et un materiau (instance de M_COS_Base) par motif : en jeu, on accroche la
coupe puis on lui pose le materiau du motif (SetMaterial avec l'identifiant de
la piece accrochee, doc Paintable). Tout dans /Game/MyAssetPack/Cosmetiques.
Save All puis cuire my-asset-pack ensuite. Relancer remplace l'existant.
"""

import json
from pathlib import Path

import unreal

ROOT = Path("C:/Users/ingam/OneDrive/Documents/fate-games")
ART = ROOT / "art/cosmetics"
DEST = "/Game/MyAssetPack/Cosmetiques"
SKELETON = ("/Game/MyAssetPack/Creative_Characters_FREE/"
            "Skeleton_Meshes/SKEL_Animations_Skeleton")

lib = unreal.EditorAssetLibrary
tools = unreal.AssetToolsHelpers.get_asset_tools()
mel = unreal.MaterialEditingLibrary
skeleton = lib.load_asset(SKELETON)
if not skeleton:
    raise RuntimeError("Squelette Creative introuvable : " + SKELETON)


def importer(fichier, dossier, nom, options=None):
    t = unreal.AssetImportTask()
    t.filename = str(fichier)
    t.destination_path = dossier
    t.destination_name = nom
    t.automated = True
    t.save = True
    t.replace_existing = True
    if options:
        t.options = options
        t.factory = unreal.FbxFactory()
    tools.import_asset_tasks([t])
    if not t.imported_object_paths:
        raise RuntimeError("Import rate : " + str(fichier))
    return lib.load_asset(dossier + "/" + nom)


def options_piece(avec_materiaux):
    o = unreal.FbxImportUI()
    o.automated_import_should_detect_type = False
    o.mesh_type_to_import = unreal.FBXImportType.FBXIT_SKELETAL_MESH
    o.import_mesh = True
    o.import_as_skeletal = True
    o.import_animations = False
    o.import_materials = avec_materiaux
    o.import_textures = False
    o.skeleton = skeleton
    return o


# ---------------------------------------------------------------- ce qu'on importe

pieces = {}       # nom d'asset -> fichier FBX
textures = {}     # nom de texture -> fichier PNG

for nom in ("SK_COS_TShirt_Rare_Compass", "SK_COS_TShirt_Epic_Eclipse",
            "SK_COS_TShirt_Legendary_Sun", "SK_COS_TShirt_Uncommon_Frayed"):
    pieces[nom] = ART / "tshirts" / (nom + ".fbx")
for nom in ("T_COS_TShirt_Rare_Compass", "T_COS_TShirt_Epic_Eclipse", "T_COS_TShirt_Legendary_Sun"):
    textures[nom] = ART / "tshirts" / (nom + ".png")
for m in json.loads((ART / "tshirts_motifs/manifeste.json").read_text(encoding="utf-8")):
    textures[m["texture"]] = ART / "tshirts_motifs" / (m["texture"] + ".png")
for m in json.loads((ART / "pantalons/manifeste.json").read_text(encoding="utf-8")):
    pieces[m["piece"]] = ART / "pantalons" / (m["piece"] + ".fbx")
    textures[m["texture"]] = ART / "pantalons" / (m["texture"] + ".png")

# Manches longues tartan (scripts/blender/create_manches_longues.py) : une
# piece, un motif par tartan.
for m in json.loads((ART / "manches_longues/manifeste.json").read_text(encoding="utf-8")):
    pieces[m["piece"]] = ART / "manches_longues" / (m["piece"] + ".fbx")
    textures[m["texture"]] = ART / "manches_longues" / (m["texture"] + ".png")

# Chapeaux et lunettes telecharges (scripts/blender/create_accessoires.py) :
# une texture cuite par piece.
for m in json.loads((ART / "accessoires/manifeste.json").read_text(encoding="utf-8")):
    pieces[m["piece"]] = ART / "accessoires" / (m["piece"] + ".fbx")
    textures[m["texture"]] = ART / "accessoires" / (m["texture"] + ".png")

# Tenues des PNJ (scripts/blender/create_pnj_tenues.py) : une texture cuite
# par piece, portee par le PNJ avec son materiau (Shared/config.lua, pnj.types).
_pnj = ART / "pnj/manifeste.json"
if _pnj.is_file():
    for m in json.loads(_pnj.read_text(encoding="utf-8")):
        pieces[m["piece"]] = ART / "pnj" / (m["piece"] + ".fbx")
        textures[m["texture"]] = ART / "pnj" / (m["texture"] + ".png")

# Pieces de tete et coiffures (create_tete.py, create_cheveux.py) : elles
# utilisent l'atlas du kit Creative, comme ses pieces.
tete = json.loads((ART / "tete/manifeste.json").read_text(encoding="utf-8"))
cheveux = json.loads((ART / "cheveux/manifeste.json").read_text(encoding="utf-8"))
for m in tete:
    pieces[m["piece"]] = ART / "tete" / (m["piece"] + ".fbx")
for m in cheveux:
    pieces[m["piece"]] = ART / "cheveux" / (m["piece"] + ".fbx")
PIECES_ATLAS = {m["piece"] for m in tete + cheveux}

# ---------------------------------------------------------------- textures et materiaux

imp = {}
for nom, fichier in sorted(textures.items()):
    imp[nom] = importer(fichier, DEST + "/Textures", nom)
    print("COS_TEXTURE", nom)

base_chemin = DEST + "/M_COS_Base"
if lib.does_asset_exist(base_chemin):
    base = lib.load_asset(base_chemin)
else:
    base = tools.create_asset("M_COS_Base", DEST, unreal.Material, unreal.MaterialFactoryNew())
    tex = mel.create_material_expression(base, unreal.MaterialExpressionTextureSampleParameter2D, -420, 0)
    tex.set_editor_property("parameter_name", "Base")
    tex.set_editor_property("texture", next(iter(imp.values())))
    mel.connect_material_property(tex, "RGB", unreal.MaterialProperty.MP_BASE_COLOR)
    rugo = mel.create_material_expression(base, unreal.MaterialExpressionConstant, -420, 260)
    rugo.set_editor_property("r", 0.85)
    mel.connect_material_property(rugo, "", unreal.MaterialProperty.MP_ROUGHNESS)
    mel.recompile_material(base)
    lib.save_loaded_asset(base)

# Indispensable en jeu cuit : sans cet usage, un materiau pose sur un maillage
# squelettique s'affiche en damier gris (materiau par defaut). L'editeur ne le
# coche seul que quand on applique le materiau a la main (27/09).
if not base.get_editor_property("used_with_skeletal_mesh"):
    base.set_editor_property("used_with_skeletal_mesh", True)
    mel.recompile_material(base)
    lib.save_loaded_asset(base)

for nom, texture in sorted(imp.items()):
    mi_nom = "MI_" + nom[2:]          # T_COS_... -> MI_COS_...
    chemin = DEST + "/Materiaux/" + mi_nom
    mi = lib.load_asset(chemin) if lib.does_asset_exist(chemin) else tools.create_asset(
        mi_nom, DEST + "/Materiaux", unreal.MaterialInstanceConstant, unreal.MaterialInstanceConstantFactoryNew())
    mel.set_material_instance_parent(mi, base)
    mel.set_material_instance_texture_parameter_value(mi, "Base", texture)
    lib.save_loaded_asset(mi)
    print("COS_MATERIAU", mi_nom)

# ---------------------------------------------------------------- pieces

_atlas = []


def materiau_atlas():
    """Le materiau de l'atlas Creative, pris sur une piece du kit (SK_Hat_010)."""
    if not _atlas:
        chemins = [a for a in lib.list_assets("/Game/MyAssetPack", recursive=True)
                   if a.split(".")[-1] == "SK_Hat_010"]
        if not chemins:
            raise RuntimeError("SK_Hat_010 introuvable : materiau de l'atlas inconnu")
        kit = lib.load_asset(chemins[0])
        _atlas.append(kit.get_editor_property("materials")[0].get_editor_property("material_interface"))
        print("COS_ATLAS", _atlas[0].get_path_name())
    return _atlas[0]


for nom, fichier in sorted(pieces.items()):
    if not fichier.is_file():
        raise FileNotFoundError(fichier)
    sk = importer(fichier, DEST, nom, options_piece(avec_materiaux=nom.endswith("Frayed")))
    if not isinstance(sk, unreal.SkeletalMesh):
        raise RuntimeError("Ce n'est pas un maillage squelettique : " + nom)
    if sk.get_editor_property("skeleton") != skeleton:
        raise RuntimeError("Mauvais squelette : " + nom)
    # Pas de materiau par defaut sur les vetements : si le motif ne prend pas
    # en jeu, la piece reste en damier et on sait laquelle ne marche pas. Les
    # pieces de tete, elles, portent le materiau de l'atlas du kit.
    if nom in PIECES_ATLAS:
        mats = sk.get_editor_property("materials")
        for m in mats:
            m.set_editor_property("material_interface", materiau_atlas())
        sk.set_editor_property("materials", mats)
        lib.save_loaded_asset(sk)
    print("COS_PIECE", nom)

lib.save_directory(DEST)
print("COSMETIQUES_IMPORT_COMPLETE", len(pieces), "pieces", len(imp), "materiaux")
