"""Verify that the cooked gesture targets the seated Creative skeleton."""

import unreal

base = '/Game/MyAssetPack/Creative_Characters_FREE'
sequence = unreal.load_asset(base + '/Animations/ANIM_Seated_Revolver')
body = unreal.load_asset(base + '/Skeleton_Meshes/SK_Body_010')
blueprint = unreal.load_asset(base + '/Animations/ABP_Creative')
if not (sequence and body and blueprint):
    raise RuntimeError('Creative animation assets are incomplete')

length = sequence.get_play_length()
animation_skeleton = sequence.get_skeleton()
body_skeleton = body.get_editor_property('skeleton')
graph = unreal.BlueprintEditorLibrary.find_graph(blueprint, 'AnimGraph')
slots = graph.get_graph_nodes_of_class(unreal.AnimGraphNode_Slot)
print('CODEX_VERIFY length_s', length)
print('CODEX_VERIFY sequence_skeleton', animation_skeleton.get_path_name())
print('CODEX_VERIFY body_skeleton', body_skeleton.get_path_name())
print('CODEX_VERIFY slot_count', len(slots))
if not (1.4 <= length <= 1.8 and animation_skeleton == body_skeleton and len(slots) == 1):
    raise RuntimeError('Creative gesture has an invalid duration, rig, or montage slot')
