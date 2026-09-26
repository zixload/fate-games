"""Import the two Blender clips on the already-cooked Creative skeleton.

In the ADK editor Python console:
    py "C:/Users/ingam/OneDrive/Documents/fate-games/scripts/unreal/import_revolver_segments.py"
Save the assets and let the user cook my-asset-pack in the editor.
"""

from pathlib import Path
import unreal


source = Path("C:/Users/ingam/OneDrive/Documents/fate-games/art/animations")
skeleton_path = "/Game/MyAssetPack/Creative_Characters_FREE/Skeleton_Meshes/SKEL_Animations_Skeleton"
destination = "/Game/MyAssetPack/Creative_Characters_FREE/Animations"
skeleton = unreal.EditorAssetLibrary.load_asset(skeleton_path)
if not skeleton:
    raise RuntimeError(f"Creative skeleton missing: {skeleton_path}")

for filename, asset_name in (
    ("seated_revolver_take.fbx", "ANIM_Seated_Revolver_Take"),
    ("seated_revolver_fire.fbx", "ANIM_Seated_Revolver_Fire"),
):
    fbx = source / filename
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
    task.destination_name = asset_name
    task.automated = True
    task.save = True
    task.replace_existing = True
    task.options = options
    task.factory = unreal.FbxFactory()

    unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([task])
    if not task.imported_object_paths:
        raise RuntimeError(f"FBX animation import returned no asset: {asset_name}")
    for path in task.imported_object_paths:
        asset = unreal.EditorAssetLibrary.load_asset(path)
        if not asset or asset.get_skeleton() != skeleton:
            raise RuntimeError(f"Wrong Creative skeleton after import: {path}")
        duration = asset.get_play_length()
        low, high = (0.75, 0.95) if asset_name.endswith("Take") else (0.65, 0.85)
        if not low <= duration <= high:
            raise RuntimeError(f"Unexpected animation duration for {path}: {duration:.3f}s")
        unreal.log(f"Revolver segment imported {path}: {asset.get_class().get_name()}")
