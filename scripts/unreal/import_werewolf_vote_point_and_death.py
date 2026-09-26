"""Reimport only the revised Werewolf elimination and final-vote gestures.

Execute in the Python console of the ADK editor that is already open. Save
and cook my-asset-pack afterward. No level or Werewolf Lua is changed.
"""

from pathlib import Path

import unreal


SOURCE = (Path("C:/Users/ingam/OneDrive/Documents/fate-games")
          / "art/werewolf")
DEST = "/Game/MyAssetPack/Creative_Characters_FREE/Animations"
SKELETON = ("/Game/MyAssetPack/Creative_Characters_FREE/"
            "Skeleton_Meshes/SKEL_Animations_Skeleton")
CLIPS = (
    "ANIM_WW_Seated_Death",
    "ANIM_WW_Seated_Dead_Idle",
    "ANIM_WW_Seated_Vote_Point",
)

library = unreal.EditorAssetLibrary
tools = unreal.AssetToolsHelpers.get_asset_tools()
skeleton = library.load_asset(SKELETON)
if not skeleton:
    raise RuntimeError("Creative skeleton missing: " + SKELETON)

for name in CLIPS:
    source = SOURCE / (name + ".fbx")
    if not source.is_file():
        raise FileNotFoundError(source)
    options = unreal.FbxImportUI()
    options.automated_import_should_detect_type = False
    options.mesh_type_to_import = unreal.FBXImportType.FBXIT_ANIMATION
    options.import_as_skeletal = True
    options.import_mesh = False
    options.import_animations = True
    options.skeleton = skeleton

    task = unreal.AssetImportTask()
    task.filename = str(source)
    task.destination_path = DEST
    task.destination_name = name
    task.automated = True
    task.save = True
    task.replace_existing = True
    task.options = options
    task.factory = unreal.FbxFactory()
    tools.import_asset_tasks([task])
    if not task.imported_object_paths:
        raise RuntimeError("Animation import failed: " + str(source))

    sequence = library.load_asset(DEST + "/" + name)
    if not isinstance(sequence, unreal.AnimSequence):
        raise RuntimeError("Imported asset is not an AnimSequence: " + name)
    if sequence.get_skeleton() != skeleton:
        raise RuntimeError("Wrong Creative skeleton: " + name)
    sequence.set_editor_property("enable_root_motion", False)
    if not library.save_loaded_asset(sequence):
        raise RuntimeError("Could not save imported animation: " + name)
    print("WW_UPDATED", name, "seconds",
          round(sequence.get_play_length(), 4))

print("WW_DEATH_AND_POINT_IMPORT_COMPLETE", len(CLIPS))
