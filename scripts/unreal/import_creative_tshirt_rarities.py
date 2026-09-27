"""Import the four new Creative T-shirt tiers in the *open* Nanos ADK.

Execute in Unreal's Python console. The existing SK_T_Shirt_009 is the common
tier and is not reimported. This script saves only its own content assets;
it never edits the map, Lua, or starts a cook.
"""

from pathlib import Path

import unreal


ROOT = Path("C:/Users/ingam/OneDrive/Documents/fate-games")
SOURCE = ROOT / "art/cosmetics/tshirts"
DEST = "/Game/MyAssetPack/Cosmetics/TShirts"
SKELETON_PATH = ("/Game/MyAssetPack/Creative_Characters_FREE/"
                 "Skeleton_Meshes/SKEL_Animations_Skeleton")
TIERS = (
    "Uncommon_Frayed", "Rare_Compass", "Epic_Eclipse", "Legendary_Sun",
)
LIB = unreal.EditorAssetLibrary
TOOLS = unreal.AssetToolsHelpers.get_asset_tools()
MATERIALS = unreal.MaterialEditingLibrary
PROP = unreal.MaterialProperty

skeleton = LIB.load_asset(SKELETON_PATH)
if not isinstance(skeleton, unreal.Skeleton):
    raise RuntimeError("Creative skeleton missing: " + SKELETON_PATH)
LIB.make_directory(DEST)


def import_asset(filename, name, options=None):
    if not filename.is_file():
        raise FileNotFoundError(filename)
    task = unreal.AssetImportTask()
    task.filename = str(filename)
    task.destination_path = DEST
    task.destination_name = name
    task.automated = True
    task.save = True
    task.replace_existing = True
    if options:
        task.options = options
        task.factory = unreal.FbxFactory()
    TOOLS.import_asset_tasks([task])
    if not task.imported_object_paths:
        raise RuntimeError("Import failed: " + str(filename))
    asset = LIB.load_asset(DEST + "/" + name)
    if not asset:
        raise RuntimeError("Imported asset missing: " + name)
    return asset


def create_material(name, texture=None, color=None):
    asset_path = DEST + "/" + name
    material = LIB.load_asset(asset_path)
    if not material:
        material = TOOLS.create_asset(name, DEST, unreal.Material,
                                      unreal.MaterialFactoryNew())
    if not isinstance(material, unreal.Material):
        raise RuntimeError("Could not create material: " + asset_path)
    MATERIALS.delete_all_material_expressions(material)
    if texture:
        node = MATERIALS.create_material_expression(
            material, unreal.MaterialExpressionTextureSample, -400, 0)
        node.set_editor_property("texture", texture)
        MATERIALS.connect_material_property(node, "RGB", PROP.MP_BASE_COLOR)
    else:
        node = MATERIALS.create_material_expression(
            material, unreal.MaterialExpressionConstant3Vector, -400, 0)
        node.set_editor_property("constant", unreal.LinearColor(
            color[0], color[1], color[2], 1))
        MATERIALS.connect_material_property(node, "", PROP.MP_BASE_COLOR)
    rough = MATERIALS.create_material_expression(
        material, unreal.MaterialExpressionConstant, -400, 220)
    rough.set_editor_property("r", .88)
    MATERIALS.connect_material_property(rough, "", PROP.MP_ROUGHNESS)
    MATERIALS.recompile_material(material)
    if not LIB.save_loaded_asset(material):
        raise RuntimeError("Could not save material: " + name)
    return material


frayed_materials = (
    create_material("M_COS_TShirt_Frayed_Blue", color=(.055, .22, .34)),
    create_material("M_COS_TShirt_Frayed_Cream", color=(.78, .73, .58)),
)

for tier in TIERS:
    name = "SK_COS_TShirt_" + tier
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
    mesh = import_asset(SOURCE / (name + ".fbx"), name, options)
    if not isinstance(mesh, unreal.SkeletalMesh):
        raise RuntimeError("Expected SkeletalMesh: " + name)
    if mesh.get_editor_property("skeleton") != skeleton:
        raise RuntimeError("Wrong skeleton: " + name)

    if tier == "Uncommon_Frayed":
        materials = frayed_materials
    else:
        texture_name = "T_COS_TShirt_" + tier
        texture = import_asset(SOURCE / (texture_name + ".png"), texture_name)
        if not isinstance(texture, unreal.Texture2D):
            raise RuntimeError("Expected Texture2D: " + texture_name)
        materials = (create_material("M_COS_TShirt_" + tier, texture=texture),)
    slots = list(mesh.get_editor_property("materials"))
    if len(slots) != len(materials):
        raise RuntimeError(f"{name}: {len(slots)} slots, expected {len(materials)}")
    for slot, material in zip(slots, materials):
        slot.set_editor_property("material_interface", material)
    mesh.set_editor_property("materials", slots)
    if not LIB.save_loaded_asset(mesh):
        raise RuntimeError("Could not save mesh: " + name)
    print("TSHIRT_IMPORTED", name, "slots", len(slots), "skeleton", SKELETON_PATH)

print("TSHIRT_IMPORT_COMPLETE", len(TIERS))
