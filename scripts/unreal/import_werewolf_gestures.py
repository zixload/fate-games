"""Import only the new Werewolf body gestures into the open NanosWorld ADK.

Execute this file in the editor Python console, then save and cook the pack.
No map, gameplay Lua, carpet, or zabuton asset is changed by this script.
"""

from pathlib import Path

import unreal


ROOT = Path("C:/Users/ingam/OneDrive/Documents/fate-games")
SOURCE = ROOT / "art/werewolf"
DEST = "/Game/MyAssetPack/Creative_Characters_FREE/Animations"
SKELETON_PATH = ("/Game/MyAssetPack/Creative_Characters_FREE/"
                 "Skeleton_Meshes/SKEL_Animations_Skeleton")
ANIMATIONS = ("ANIM_WW_Seated_Vote", "ANIM_WW_Seated_Sleep")
LIB = unreal.EditorAssetLibrary
TOOLS = unreal.AssetToolsHelpers.get_asset_tools()

skeleton = LIB.load_asset(SKELETON_PATH)
if not skeleton:
    raise RuntimeError(f"Creative skeleton missing: {SKELETON_PATH}")

for name in ANIMATIONS:
    filename = SOURCE / (name + ".fbx")
    if not filename.is_file():
        raise FileNotFoundError(filename)
    options = unreal.FbxImportUI()
    options.automated_import_should_detect_type = False
    options.mesh_type_to_import = unreal.FBXImportType.FBXIT_ANIMATION
    options.import_as_skeletal = True
    options.import_mesh = False
    options.import_animations = True
    options.skeleton = skeleton
    task = unreal.AssetImportTask()
    task.filename = str(filename)
    task.destination_path = DEST
    task.destination_name = name
    task.automated = True
    task.save = True
    task.replace_existing = True
    task.options = options
    task.factory = unreal.FbxFactory()
    TOOLS.import_asset_tasks([task])
    if not task.imported_object_paths:
        raise RuntimeError(f"Import failed: {filename}")
    sequence = LIB.load_asset(f"{DEST}/{name}")
    if not isinstance(sequence, unreal.AnimSequence):
        raise RuntimeError(f"Imported asset is not an AnimSequence: {name}")
    if sequence.get_skeleton() != skeleton:
        raise RuntimeError(f"Wrong skeleton: {name}")
    sequence.set_editor_property("enable_root_motion", False)
    LIB.save_loaded_asset(sequence)
    print("WW_GESTURE_IMPORTED", name,
          "length_seconds", round(sequence.get_play_length(), 4))

print("WW_GESTURES_IMPORT_COMPLETE", len(ANIMATIONS))
