"""Export the exact Creative skeleton, seated idle and Nagant for Blender.

Run with UnrealEditor-Cmd -run=pythonscript -script=<this file>.
The FBXs under Saved/CodexAnimation are intermediates; the Blender project and
imported animation assets are the deliverables.
"""

from pathlib import Path
import unreal


output = Path("C:/nanos-adk/Saved/CodexAnimation")
output.mkdir(parents=True, exist_ok=True)

assets = {
    "creative_skeleton.fbx": "/Game/MyAssetPack/Creative_Characters_FREE/Skeleton_Meshes/SK_Animations",
    "sitting_idle.fbx": "/Game/MyAssetPack/Creative_Characters_FREE/Animations/ANIM_Sitting_Idle",
    "sitting_with_mesh.fbx": "/Game/MyAssetPack/Creative_Characters_FREE/Animations/ANIM_Sitting_Idle",
    "nagant.fbx": "/Game/MyAssetPack/Revolver/SM_Nagant_M1895",
}

for filename, asset_path in assets.items():
    asset = unreal.EditorAssetLibrary.load_asset(asset_path)
    if not asset:
        raise RuntimeError(f"Missing asset: {asset_path}")
    task = unreal.AssetExportTask()
    task.object = asset
    task.filename = str(output / filename)
    task.automated = True
    task.prompt = False
    task.replace_identical = True
    if filename == "sitting_with_mesh.fbx":
        options = unreal.FbxExportOption()
        options.export_preview_mesh = True
        task.options = options
    ok = unreal.Exporter.run_asset_export_task(task)
    if not ok:
        raise RuntimeError(f"Export failed: {asset_path}: {list(task.errors)}")
    unreal.log(f"CodexAnimation exported {task.filename}")
