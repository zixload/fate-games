"""Import the three seated accusation clips into MyAssetPack from Unreal's Python console.

    exec(open("C:/Users/ingam/OneDrive/Documents/fate-games/scripts/unreal/import_seated_accuse.py", encoding="utf-8").read())

Saves only these Animation Sequences. Cook my-asset-pack in the editor afterward.
"""

from pathlib import Path

import unreal


source = Path("C:/Users/ingam/OneDrive/Documents/fate-games/art/animations")
skeleton_path = "/Game/MyAssetPack/Creative_Characters_FREE/Skeleton_Meshes/SKEL_Animations_Skeleton"
destination = "/Game/MyAssetPack/Creative_Characters_FREE/Animations"
skeleton = unreal.EditorAssetLibrary.load_asset(skeleton_path)
if not skeleton:
    raise RuntimeError(f"Creative skeleton missing: {skeleton_path}")

for side in ("Left", "Center", "Right"):
    asset_name = f"ANIM_Seated_Accuse_{side}"
    fbx = source / f"seated_accuse_{side.lower()}.fbx"
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
        raise RuntimeError(f"Accusation import failed: {asset_name}")
    for path in task.imported_object_paths:
        asset = unreal.EditorAssetLibrary.load_asset(path)
        if not asset or asset.get_skeleton() != skeleton:
            raise RuntimeError(f"Wrong Creative skeleton: {path}")
        duration = asset.get_play_length()
        if not 1.25 <= duration <= 1.45:
            raise RuntimeError(f"Unexpected accusation duration: {path} ({duration:.3f}s)")
        unreal.log(f"Seated accusation imported: {path}, {duration:.3f}s")
