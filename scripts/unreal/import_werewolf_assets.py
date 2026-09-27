"""Import the licensed Werewolf carpet, seven aged zabutons, and seated clips.

Execute in the NanosWorldADK Unreal Python console or with -ExecutePythonScript.
Source media is in ignored art/werewolf/source and Downloads. Never commit it.
This does not place assets in the game map or cook the pack.
"""

from pathlib import Path
import unreal

ROOT = Path("C:/Users/ingam/OneDrive/Documents/fate-games")
SOURCE = ROOT / "art/werewolf"
ZAB = SOURCE / "source/zabuton_7col_v22_2608_en/Textures"
CAR = SOURCE / "source/carpet/textures"
DEST = "/Game/MyAssetPack/Werewolf"
ANIM_DEST = "/Game/MyAssetPack/Creative_Characters_FREE/Animations"
SKELETON_PATH = ("/Game/MyAssetPack/Creative_Characters_FREE/"
                 "Skeleton_Meshes/SKEL_Animations_Skeleton")
COLORS = ("Blue", "Brown", "Green", "Purple", "Red", "White", "Yellow")
ANIMATIONS = ("ANIM_WW_Sitting_Idle", "ANIM_WW_Sitting_Idle_Lazy",
              "ANIM_WW_Sitting_Dazed")
TOOLS = unreal.AssetToolsHelpers.get_asset_tools()
LIB = unreal.EditorAssetLibrary
LIB.make_directory(DEST)


# 27/09 : chaque lancement reimportait tout et ecrasait les reglages faits a
# la main (taille, materiaux). Un asset deja present est garde tel quel ;
# mettre son nom dans FORCER pour le reimporter, ex. FORCER = ["SM_WW_Carpet"].
FORCER = []


def import_file(filename, name, folder, options=None):
    if LIB.does_asset_exist(f"{folder}/{name}") and name not in FORCER:
        print("WW_ASSET_GARDE", name)
        return LIB.load_asset(f"{folder}/{name}")
    if not filename.is_file():
        raise FileNotFoundError(filename)
    task = unreal.AssetImportTask()
    task.filename = str(filename)
    task.destination_path = folder
    task.destination_name = name
    task.automated = True
    task.save = True
    task.replace_existing = True
    if options is not None:
        task.options = options
        task.factory = unreal.FbxFactory()
    TOOLS.import_asset_tasks([task])
    if not task.imported_object_paths:
        raise RuntimeError(f"Import failed: {filename} -> {folder}/{name}")
    asset = LIB.load_asset(f"{folder}/{name}")
    if not asset:
        raise RuntimeError(f"Imported asset missing: {folder}/{name}")
    return asset


def texture(source, name, normal=False, roughness=False):
    obj = import_file(source, name, DEST)
    if not isinstance(obj, unreal.Texture2D):
        raise RuntimeError(f"Imported texture is not Texture2D: {name}")
    if normal:
        obj.set_editor_property("compression_settings", unreal.TextureCompressionSettings.TC_NORMALMAP)
        obj.set_editor_property("srgb", False)
        # Both source normal maps are OpenGL/Y+; Unreal expects DirectX/Y-.
        obj.set_editor_property("flip_green_channel", True)
    elif roughness:
        obj.set_editor_property("compression_settings", unreal.TextureCompressionSettings.TC_MASKS)
        obj.set_editor_property("srgb", False)
    LIB.save_loaded_asset(obj)
    return obj


def material(name, base_color, normal_map, roughness_map=None):
    path = f"{DEST}/{name}"
    obj = LIB.load_asset(path)
    if not obj:
        obj = TOOLS.create_asset(name, DEST, unreal.Material,
                                 unreal.MaterialFactoryNew())
    if not obj:
        raise RuntimeError(f"Cannot create material: {path}")
    unreal.MaterialEditingLibrary.delete_all_material_expressions(obj)

    def sample(tex, x, y, prop, output="RGB"):
        expr = unreal.MaterialEditingLibrary.create_material_expression(
            obj, unreal.MaterialExpressionTextureSample, x, y)
        expr.set_editor_property("texture", tex)
        unreal.MaterialEditingLibrary.connect_material_property(expr, output, prop)

    sample(base_color, -520, -120, unreal.MaterialProperty.MP_BASE_COLOR)
    sample(normal_map, -520, 120, unreal.MaterialProperty.MP_NORMAL)
    if roughness_map:
        sample(roughness_map, -520, 360, unreal.MaterialProperty.MP_ROUGHNESS,
               "R")
    else:
        constant = unreal.MaterialEditingLibrary.create_material_expression(
            obj, unreal.MaterialExpressionConstant, -520, 360)
        constant.set_editor_property("r", .88)
        unreal.MaterialEditingLibrary.connect_material_property(
            constant, "", unreal.MaterialProperty.MP_ROUGHNESS)
    unreal.MaterialEditingLibrary.recompile_material(obj)
    LIB.save_loaded_asset(obj)
    return obj


normal_zab = texture(ZAB / "Normal.png", "T_WW_Zabuton_Normal", normal=True)
normal_car = texture(CAR / "v2_Normal.png", "T_WW_Carpet_Normal", normal=True)
car_base = texture(CAR / "v2_Base_color.png", "T_WW_Carpet_Base")
car_rough = texture(CAR / "v2_Roughness.png", "T_WW_Carpet_Roughness",
                    roughness=True)
materials = {
    "SM_WW_Carpet": material("M_WW_Carpet", car_base, normal_car, car_rough),
}
for color in COLORS:
    base = texture(ZAB / f"Texture_Aged/T_Col_Aged_{color}.png",
                   f"T_WW_Zabuton_Aged_{color}")
    materials[f"SM_WW_Zabuton_{color}"] = material(
        f"M_WW_Zabuton_{color}", base, normal_zab)

for name, mat in materials.items():
    options = unreal.FbxImportUI()
    options.automated_import_should_detect_type = False
    options.mesh_type_to_import = unreal.FBXImportType.FBXIT_STATIC_MESH
    options.import_as_skeletal = False
    options.import_mesh = True
    options.import_materials = False
    options.import_textures = False
    options.static_mesh_import_data.combine_meshes = True
    options.static_mesh_import_data.auto_generate_collision = True
    mesh = import_file(SOURCE / (name + ".fbx"), name, DEST, options)
    if not isinstance(mesh, unreal.StaticMesh):
        raise RuntimeError(f"Imported asset is not StaticMesh: {name}")
    mesh.set_material(0, mat)
    LIB.save_loaded_asset(mesh)
    extent = mesh.get_bounds().box_extent
    if name == "SM_WW_Carpet":
        if not 265 <= extent.x <= 285 or not 265 <= extent.y <= 285:
            unreal.log_warning(f"WW_TAILLE Carpet ~550 cm attendu : {extent}")
    else:
        if not 30 <= extent.x <= 37 or not 32 <= extent.y <= 39:
            unreal.log_warning(f"WW_TAILLE {name} : {extent}")
    print("WW_MESH", name, "half_extent_cm",
          tuple(round(v, 2) for v in (extent.x, extent.y, extent.z)),
          "material", mat.get_path_name())

skeleton = LIB.load_asset(SKELETON_PATH)
if not skeleton:
    raise RuntimeError(f"Creative skeleton missing: {SKELETON_PATH}")
for name in ANIMATIONS:
    options = unreal.FbxImportUI()
    options.automated_import_should_detect_type = False
    options.mesh_type_to_import = unreal.FBXImportType.FBXIT_ANIMATION
    options.import_as_skeletal = True
    options.import_mesh = False
    options.import_animations = True
    options.skeleton = skeleton
    sequence = import_file(SOURCE / (name + ".fbx"), name, ANIM_DEST, options)
    if not isinstance(sequence, unreal.AnimSequence):
        raise RuntimeError(f"Imported asset is not an AnimSequence: {name}")
    if sequence.get_skeleton() != skeleton:
        raise RuntimeError(f"Wrong skeleton: {name}")
    sequence.set_editor_property("enable_root_motion", False)
    LIB.save_loaded_asset(sequence)
    print("WW_ANIMATION", name, "length_seconds",
          round(sequence.get_play_length(), 4),
          "skeleton", sequence.get_skeleton().get_path_name())

print("WW_IMPORT_COMPLETE", len(materials), "meshes,", len(ANIMATIONS),
      "animations")
