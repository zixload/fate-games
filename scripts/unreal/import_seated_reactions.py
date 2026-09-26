"""Import the new seated card and fatal animations into MyAssetPack.

In the ADK editor Python console:
    exec(open("C:/Users/ingam/OneDrive/Documents/fate-games/scripts/unreal/import_seated_reactions.py", encoding="utf-8").read())

Imports and saves the two Animation Sequences. Cooking remains an editor step.
"""

from pathlib import Path

import unreal


source = Path("C:/Users/ingam/OneDrive/Documents/fate-games/art/animations")
skeleton_path = "/Game/MyAssetPack/Creative_Characters_FREE/Skeleton_Meshes/SKEL_Animations_Skeleton"
destination = "/Game/MyAssetPack/Creative_Characters_FREE/Animations"
skeleton = unreal.EditorAssetLibrary.load_asset(skeleton_path)
if not skeleton:
    raise RuntimeError(f"Creative skeleton missing: {skeleton_path}")

for filename, asset_name, minimum, maximum in (
    ("seated_revolver_fatal.fbx", "ANIM_Seated_Revolver_Fatal", 0.75, 0.9),
    ("seated_card_play.fbx", "ANIM_Seated_Card_Play", 0.9, 1.1),
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
        raise RuntimeError(f"Animation import failed: {asset_name}")
    for path in task.imported_object_paths:
        asset = unreal.EditorAssetLibrary.load_asset(path)
        if not asset or asset.get_skeleton() != skeleton:
            raise RuntimeError(f"Wrong Creative skeleton: {path}")
        duration = asset.get_play_length()
        if not minimum <= duration <= maximum:
            raise RuntimeError(f"Unexpected animation duration: {path} ({duration:.3f}s)")
        unreal.log(f"Seated reaction imported: {path}, {duration:.3f}s")
