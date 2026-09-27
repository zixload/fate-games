"""Import Creative NPC idles, the bound flute and modular footwear in the open ADK.

Execute in the existing Unreal Python console. The script does not edit a map,
Lua files or gameplay assets, and does not start an editor or cook a pack.
"""

import json
from pathlib import Path

import unreal


ROOT = Path("C:/Users/ingam/OneDrive/Documents/fate-games")
NPC = ROOT / "art/animations/npc"
FEET = ROOT / "art/cosmetics/footwear"
ANIM_DEST = "/Game/MyAssetPack/Creative_Characters_FREE/Animations"
PROP_DEST = "/Game/MyAssetPack/NPC/Props"
FEET_DEST = "/Game/MyAssetPack/Cosmetics/Footwear"
SKELETON_PATH = ("/Game/MyAssetPack/Creative_Characters_FREE/"
                 "Skeleton_Meshes/SKEL_Animations_Skeleton")
NAMES = (
    "ANIM_NPC_Tailor_Idle",
    "ANIM_NPC_Armorer_Idle",
    "ANIM_NPC_Showman_Idle",
    "ANIM_NPC_Musician_Flute_Idle",
)
SOCKS = ("Ivory", "Charcoal", "BlackStripe")
FLUTE_COLORS = (
    (.6445, .1144, .0194), (.8796, .8148, .5520),
    (.1812, .0704, .0242), (.0343, .1301, .1221),
    (.1878, .1046, .4287), (.3968, .3467, .3372),
    (.0203, .3467, .4179), (.4287, .3712, .0037),
    (.2705, .5089, .0284),
)
GETA_COLORS = ((.47, .245, .105), (.28, .13, .065), (.095, .12, .14))

LIB = unreal.EditorAssetLibrary
TOOLS = unreal.AssetToolsHelpers.get_asset_tools()
MATS = unreal.MaterialEditingLibrary
PROP = unreal.MaterialProperty
skeleton = LIB.load_asset(SKELETON_PATH)
if not isinstance(skeleton, unreal.Skeleton):
    raise RuntimeError("Creative skeleton missing: " + SKELETON_PATH)
for directory in (ANIM_DEST, PROP_DEST, FEET_DEST):
    LIB.make_directory(directory)


def import_file(path, destination, name, options):
    if not path.is_file():
        raise FileNotFoundError(path)
    task = unreal.AssetImportTask()
    task.filename = str(path)
    task.destination_path = destination
    task.destination_name = name
    task.automated = True
    task.save = True
    task.replace_existing = True
    if options is not None:
        task.options = options
    if path.suffix.lower() == ".fbx":
        task.factory = unreal.FbxFactory()
    TOOLS.import_asset_tasks([task])
    if not task.imported_object_paths:
        raise RuntimeError("Import failed: " + str(path))
    result = LIB.load_asset(destination + "/" + name)
    if not result:
        raise RuntimeError("Imported asset missing: " + name)
    return result


def flat_material(destination, name, color):
    path = destination + "/" + name
    material = LIB.load_asset(path) if LIB.does_asset_exist(path) else None
    if not material:
        material = TOOLS.create_asset(name, destination, unreal.Material,
                                      unreal.MaterialFactoryNew())
    if not isinstance(material, unreal.Material):
        raise RuntimeError("Cannot create material: " + path)
    MATS.delete_all_material_expressions(material)
    # Pose sur un maillage squelettique (geta, chaussettes) : sans cet usage
    # enregistre, le jeu cuit affiche un damier gris. L'editeur ne le coche
    # qu'en memoire, apres la sauvegarde (27/09).
    material.set_editor_property("used_with_skeletal_mesh", True)
    base = MATS.create_material_expression(
        material, unreal.MaterialExpressionConstant3Vector, -400, 0)
    base.set_editor_property("constant", unreal.LinearColor(*color, 1))
    MATS.connect_material_property(base, "", PROP.MP_BASE_COLOR)
    rough = MATS.create_material_expression(
        material, unreal.MaterialExpressionConstant, -400, 220)
    rough.set_editor_property("r", .82)
    MATS.connect_material_property(rough, "", PROP.MP_ROUGHNESS)
    MATS.recompile_material(material)
    if not LIB.save_loaded_asset(material):
        raise RuntimeError("Could not save: " + path)
    return material


def textured_material(destination, name, texture):
    material = flat_material(destination, name, (.8, .8, .8))
    MATS.delete_all_material_expressions(material)
    base = MATS.create_material_expression(
        material, unreal.MaterialExpressionTextureSample, -400, 0)
    base.set_editor_property("texture", texture)
    MATS.connect_material_property(base, "RGB", PROP.MP_BASE_COLOR)
    rough = MATS.create_material_expression(
        material, unreal.MaterialExpressionConstant, -400, 220)
    rough.set_editor_property("r", .9)
    MATS.connect_material_property(rough, "", PROP.MP_ROUGHNESS)
    MATS.recompile_material(material)
    if not LIB.save_loaded_asset(material):
        raise RuntimeError("Could not save textile material: " + name)
    return material


def assign_materials(mesh, materials):
    # StaticMesh (la flute) : "materials" est protege, on passe par
    # static_materials et set_material (27/09, l'import s'arretait la).
    if isinstance(mesh, unreal.StaticMesh):
        count = len(mesh.get_editor_property("static_materials"))
        if count != len(materials):
            raise RuntimeError(f"{mesh.get_name()}: {count} slots, expected {len(materials)}")
        for index, material in enumerate(materials):
            mesh.set_material(index, material)
    else:
        slots = list(mesh.get_editor_property("materials"))
        if len(slots) != len(materials):
            raise RuntimeError(f"{mesh.get_name()}: {len(slots)} slots, expected {len(materials)}")
        for slot, material in zip(slots, materials):
            slot.set_editor_property("material_interface", material)
        mesh.set_editor_property("materials", slots)
    if not LIB.save_loaded_asset(mesh):
        raise RuntimeError("Could not save mesh: " + mesh.get_name())


metrics = json.loads((NPC / "metrics.json").read_text(encoding="utf-8"))
for name in NAMES:
    options = unreal.FbxImportUI()
    options.automated_import_should_detect_type = False
    options.mesh_type_to_import = unreal.FBXImportType.FBXIT_ANIMATION
    options.import_as_skeletal = True
    options.import_mesh = False
    options.import_animations = True
    options.skeleton = skeleton
    sequence = import_file(NPC / (name + ".fbx"), ANIM_DEST, name, options)
    if not isinstance(sequence, unreal.AnimSequence):
        raise RuntimeError("Not an AnimSequence: " + name)
    if sequence.get_skeleton() != skeleton:
        raise RuntimeError("Wrong skeleton: " + name)
    duration = sequence.get_play_length()
    expected = metrics[name]["seconds"]
    # Un ecart de duree (cadence d'image lue autrement a l'export) ne doit plus
    # arreter tout l'import : la flute et les chaussures passaient a la trappe
    # (27/09, musicien lu a 7,2 s au lieu de 6 s). On le signale seulement.
    if abs(duration - expected) > .15:
        unreal.log_warning(f"NPC_ANIM_DUREE {name}: Unreal {duration:.3f}s, Blender {expected:.3f}s")
    sequence.set_editor_property("enable_root_motion", False)
    if not LIB.save_loaded_asset(sequence):
        raise RuntimeError("Could not save animation: " + name)
    print("NPC_ANIM_IMPORTED", name, "seconds", round(duration, 3))


options = unreal.FbxImportUI()
options.automated_import_should_detect_type = False
options.mesh_type_to_import = unreal.FBXImportType.FBXIT_STATIC_MESH
options.import_as_skeletal = False
options.import_mesh = True
options.import_animations = False
options.import_materials = False
options.import_textures = False
options.static_mesh_import_data.combine_meshes = True
flute = import_file(NPC / "SM_NPC_Spirit_Flute.fbx", PROP_DEST,
                    "SM_NPC_Spirit_Flute", options)
if not isinstance(flute, unreal.StaticMesh):
    raise RuntimeError("Flute import is not a StaticMesh")
flute_materials = [flat_material(PROP_DEST, f"M_NPC_Flute_{index:02d}", color)
                   for index, color in enumerate(FLUTE_COLORS)]
assign_materials(flute, flute_materials)
print("NPC_PROP_IMPORTED", flute.get_name(), "materials", len(flute_materials))


for suffix in SOCKS + ("Wood",):
    name = ("SK_COS_Geta_Wood" if suffix == "Wood" else "SK_COS_Socks_" + suffix)
    options = unreal.FbxImportUI()
    options.automated_import_should_detect_type = False
    options.mesh_type_to_import = unreal.FBXImportType.FBXIT_SKELETAL_MESH
    options.import_as_skeletal = True
    options.import_mesh = True
    options.import_animations = False
    options.import_materials = False
    options.import_textures = False
    options.create_physics_asset = False
    options.skeleton = skeleton
    mesh = import_file(FEET / (name + ".fbx"), FEET_DEST, name, options)
    if not isinstance(mesh, unreal.SkeletalMesh):
        raise RuntimeError("Footwear import is not a SkeletalMesh: " + name)
    if mesh.get_editor_property("skeleton") != skeleton:
        raise RuntimeError("Wrong footwear skeleton: " + name)
    if suffix == "Wood":
        materials = [flat_material(FEET_DEST, "M_COS_Geta_%02d" % i, color)
                     for i, color in enumerate(GETA_COLORS)]
    else:
        texture_name = "T_COS_Socks_" + suffix
        texture = import_file(FEET / (texture_name + ".png"), FEET_DEST,
                              texture_name, None)
        if not isinstance(texture, unreal.Texture2D):
            raise RuntimeError("Sock texture did not import: " + texture_name)
        materials = [textured_material(FEET_DEST, "M_COS_Socks_" + suffix, texture)]
    assign_materials(mesh, materials)
    print("NPC_FOOTWEAR_IMPORTED", name, "slots", len(materials))

print("NPC_AND_FOOTWEAR_IMPORT_COMPLETE", len(NAMES), "animations, 1 prop, 4 wearable meshes")
