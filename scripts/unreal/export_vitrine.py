"""Export the Creative character pieces, their texture and a few poses for Blender.

Used by the showcase renders (store page) and the character card portraits.
Read-only on the project: nothing is saved, no map is opened.

Run it inside the open ADK editor: Output Log, switch the input from Cmd to
Python, then type
    exec(open(r"C:/Users/ingam/OneDrive/Documents/fate-games/scripts/unreal/export_vitrine.py").read())
The FBXs land in Saved/Vitrine, outside the repo (Fab assets, not ours to publish).
"""

from pathlib import Path
import unreal


ROOT = "/Game/MyAssetPack/Creative_Characters_FREE"
output = Path("C:/nanos-adk/Saved/Vitrine")
(output / "pieces").mkdir(parents=True, exist_ok=True)
(output / "poses").mkdir(parents=True, exist_ok=True)

POSES = ["ANIM_Idle_Relaxed", "ANIM_Idle_Look_Around", "ANIM_Idle_Breathing",
         "ANIM_Run_Forward", "ANIM_Jump_Loop", "ANIM_Sitting_Idle",
         "Walking_While_Texting"]


def export(asset_path, filename):
    asset = unreal.EditorAssetLibrary.load_asset(asset_path)
    if not asset:
        unreal.log_warning(f"Vitrine: missing {asset_path}")
        return False
    task = unreal.AssetExportTask()
    task.object = asset
    task.filename = str(filename)
    task.automated = True
    task.prompt = False
    task.replace_identical = True
    ok = unreal.Exporter.run_asset_export_task(task)
    if not ok:
        unreal.log_warning(f"Vitrine: export failed {asset_path}: {list(task.errors)}")
    return ok


done = 0
for path in unreal.EditorAssetLibrary.list_assets(f"{ROOT}/Skeleton_Meshes", recursive=False):
    name = path.split(".")[-1]
    if name.startswith("SK_") and name != "SK_Animations":
        done += export(path.split(".")[0], output / "pieces" / f"{name}.fbx")

for name in POSES:
    done += export(f"{ROOT}/Animations/{name}", output / "poses" / f"{name}.fbx")

texture = f"{ROOT}/Textures/T_Textures"
done += export(texture, output / "T_Textures.png") or export(texture, output / "T_Textures.tga")

unreal.log(f"Vitrine: {done} files written to {output}")
