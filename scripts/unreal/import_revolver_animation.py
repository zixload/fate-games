"""Import Blender's seated revolver take onto the Creative skeleton in ADK."""

from pathlib import Path
import unreal


fbx = Path("C:/Users/ingam/OneDrive/Documents/fate-games/art/animations/seated_revolver.fbx")
skeleton_path = "/Game/MyAssetPack/Creative_Characters_FREE/Skeleton_Meshes/SKEL_Animations_Skeleton"
destination = "/Game/MyAssetPack/Creative_Characters_FREE/Animations"

skeleton = unreal.EditorAssetLibrary.load_asset(skeleton_path)
if not skeleton:
    raise RuntimeError(f"Creative skeleton missing: {skeleton_path}")
if not fbx.is_file():
    raise RuntimeError(f"Blender animation missing: {fbx}")

options = unreal.FbxImportUI()
options.automated_import_should_detect_type = False
options.mesh_type_to_import = unreal.FBXImportType.FBXIT_ANIMATION
options.import_as_skeletal = True
options.import_mesh = False
options.import_animations = True
options.skeleton = skeleton

task = unreal.AssetImportTask()
task.filename = str(fbx)
task.destination_path = destination
task.destination_name = "ANIM_Seated_Revolver"
task.automated = True
task.save = True
task.replace_existing = True
task.options = options
task.factory = unreal.FbxFactory()

unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([task])
paths = list(task.imported_object_paths)
if not paths:
    raise RuntimeError("FBX animation import returned no asset")
for path in paths:
    asset = unreal.EditorAssetLibrary.load_asset(path)
    unreal.log(f"CodexAnimation imported {path}: {asset.get_class().get_name()}")
