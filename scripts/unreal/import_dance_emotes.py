"""Import seven Creative-skeleton dance emotes into the open Nanos World ADK.

Run from the existing editor's Python console, then Save All and cook
my-asset-pack. This script does not start another editor or change a map.
"""

import json
from pathlib import Path

import unreal


ROOT = Path("C:/Users/ingam/OneDrive/Documents/fate-games")
SOURCE = ROOT / "art/animations/dances"
DEST = "/Game/MyAssetPack/Creative_Characters_FREE/Animations"
SKELETON = ("/Game/MyAssetPack/Creative_Characters_FREE/"
            "Skeleton_Meshes/SKEL_Animations_Skeleton")
NAMES = (
    "ANIM_Dance_StepHipHop",
    "ANIM_Dance_Chicken",
    "ANIM_Dance_WaveHipHop",
    "ANIM_Dance_TutHipHop",
    "ANIM_Dance_BootyHipHop",
    "ANIM_Dance_Salsa",
    "ANIM_Dance_Jazz",
)

library = unreal.EditorAssetLibrary
tools = unreal.AssetToolsHelpers.get_asset_tools()
skeleton = library.load_asset(SKELETON)
if not skeleton:
    raise RuntimeError("Creative skeleton missing: " + SKELETON)
metrics = json.loads((SOURCE / "metrics.json").read_text(encoding="utf-8"))
for name in NAMES:
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
    tools.import_asset_tasks([task])
    if not task.imported_object_paths:
        raise RuntimeError("Dance import failed: " + str(filename))

    sequence = library.load_asset(DEST + "/" + name)
    if not isinstance(sequence, unreal.AnimSequence):
        raise RuntimeError("Imported asset is not an AnimSequence: " + name)
    if sequence.get_skeleton() != skeleton:
        raise RuntimeError("Wrong Creative skeleton: " + name)
    sequence.set_editor_property("enable_root_motion", False)
    if not library.save_loaded_asset(sequence):
        raise RuntimeError("Could not save imported dance: " + name)
    duration = sequence.get_play_length()
    expected = metrics[name]["seconds"]
    if abs(duration - expected) > .15:
        raise RuntimeError(
            f"{name} duration {duration:.3f}s differs from Blender "
            f"{expected:.3f}s")
    print("DANCE_IMPORTED", name, "seconds", round(duration, 3))

print("DANCE_IMPORT_COMPLETE", len(NAMES))
