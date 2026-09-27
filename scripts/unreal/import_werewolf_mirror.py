"""Importe la pose assise en miroir du loup-garou (ANIM_WW_Sitting_Idle_Mirror).

A executer dans la console Python de l'editeur ADK deja ouvert :

    exec(open(r"C:\Users\ingam\OneDrive\Documents\fate-games\scripts\unreal\import_werewolf_mirror.py", encoding="utf-8").read())

Le FBX vient de scripts/blender/create_werewolf_mirror.py (art/werewolf/, hors
depot). Memes reglages que les autres poses : squelette Creative, pas de root
motion. Save All puis cuire my-asset-pack ensuite.
"""

from pathlib import Path

import unreal

SOURCE = Path("C:/Users/ingam/OneDrive/Documents/fate-games") / "art/werewolf"
DEST = "/Game/MyAssetPack/Creative_Characters_FREE/Animations"
SKELETON = ("/Game/MyAssetPack/Creative_Characters_FREE/"
            "Skeleton_Meshes/SKEL_Animations_Skeleton")
NAME = "ANIM_WW_Sitting_Idle_Mirror"

library = unreal.EditorAssetLibrary
tools = unreal.AssetToolsHelpers.get_asset_tools()
skeleton = library.load_asset(SKELETON)
if not skeleton:
    raise RuntimeError("Squelette Creative introuvable : " + SKELETON)

source = SOURCE / (NAME + ".fbx")
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
task.destination_name = NAME
task.automated = True
task.save = True
task.replace_existing = True
task.options = options
task.factory = unreal.FbxFactory()
tools.import_asset_tasks([task])
if not task.imported_object_paths:
    raise RuntimeError("Import rate : " + str(source))

sequence = library.load_asset(DEST + "/" + NAME)
if not isinstance(sequence, unreal.AnimSequence):
    raise RuntimeError("Ce n'est pas une AnimSequence : " + NAME)
if sequence.get_skeleton() != skeleton:
    raise RuntimeError("Mauvais squelette : " + NAME)
sequence.set_editor_property("enable_root_motion", False)
if not library.save_loaded_asset(sequence):
    raise RuntimeError("Sauvegarde impossible : " + NAME)
print("WW_MIRROR_IMPORT_COMPLETE", NAME, "secondes", round(sequence.get_play_length(), 4))
