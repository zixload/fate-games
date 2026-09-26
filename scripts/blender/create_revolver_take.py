"""Build a seated revolver gesture on the Creative character with Blender.

Inputs are the FBX exports from export_creative_reference.py. The idle FBX's
armature object carries an extra scale/rotation animation, so only its bone
curves are copied onto the skeletal mesh's reference armature before posing.
"""

from pathlib import Path
import bpy
from mathutils import Vector


SOURCE = Path("C:/nanos-adk/Saved/CodexAnimation")
OUTPUT = Path("C:/Users/ingam/OneDrive/Documents/fate-games/art/animations")
OUTPUT.mkdir(parents=True, exist_ok=True)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

bpy.ops.import_scene.fbx(filepath=str(SOURCE / "creative_skeleton.fbx"))
body = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
bpy.ops.import_scene.fbx(filepath=str(SOURCE / "sitting_idle.fbx"))
idle = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE" and o != body)

action = idle.animation_data.action.copy()
action.name = "Source_Sitting_Bones"
slot = action.slots[0]
bag = action.layers[0].strips[0].channelbag(slot)
for curve in list(bag.fcurves):
    if not curve.data_path.startswith("pose.bones["):
        bag.fcurves.remove(curve)
body.animation_data_create()
body.animation_data.action = action
body.animation_data.action_slot = slot
bpy.data.objects.remove(idle, do_unlink=True)

scene = bpy.context.scene
scene.render.fps = 30
scene.frame_start = 1
scene.frame_end = 48
scene.frame_set(1)

wrist_bone = body.pose.bones["RightForeArm"]
rest_wrist = body.matrix_world @ wrist_bone.tail
print("REST_WRIST", tuple(round(x, 3) for x in rest_wrist))

target = bpy.data.objects.new("RightHand_IK_Target", None)
bpy.context.collection.objects.link(target)
poses = (
    (1, rest_wrist),
    (5, Vector((-0.22, -0.44, 0.88))),
    (10, Vector((-0.24, -0.45, 0.88))),
    (16, Vector((-0.22, -0.32, 1.12))),
    (23, Vector((-0.17, -0.24, 1.43))),
    (26, Vector((-0.17, -0.24, 1.43))),
    (28, Vector((-0.21, -0.21, 1.39))),
    (31, Vector((-0.17, -0.24, 1.43))),
    (41, Vector((-0.22, -0.44, 0.88))),
    (48, rest_wrist),
)
for frame, location in poses:
    target.location = location
    target.keyframe_insert(data_path="location", frame=frame)

ik = wrist_bone.constraints.new("IK")
ik.name = "Take_Revolver"
ik.target = target
ik.chain_count = 2
ik.use_stretch = False

# Bake the IK into regular bone keys so Unreal does not depend on Blender IK.
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.mode_set(mode="POSE")
bpy.ops.nla.bake(
    frame_start=1,
    frame_end=48,
    step=1,
    only_selected=False,
    visual_keying=True,
    clear_constraints=True,
    use_current_action=False,
    bake_types={"POSE"},
)
bpy.ops.object.mode_set(mode="OBJECT")
baked = body.animation_data.action
baked.name = "ANIM_Seated_Revolver"
print("BAKED_ACTION", baked.name, tuple(baked.frame_range))

scene.frame_set(23)
print("AIM_WRIST", tuple(round(x, 3) for x in body.matrix_world @ body.pose.bones["RightForeArm"].tail))
scene.frame_set(1)

# Keep the mesh, rig and editable action as the source project. Intermediates
# stay in the ADK Saved folder and the FBX is the importable game animation.
bpy.data.objects.remove(target, do_unlink=True)
body.name = "Root"  # The Creative skeleton expects this wrapper as its root track.
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / "seated_revolver.blend"))

bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.export_scene.fbx(
    filepath=str(OUTPUT / "seated_revolver.fbx"),
    use_selection=True,
    object_types={"ARMATURE"},
    add_leaf_bones=False,
    bake_anim=True,
    bake_anim_use_all_bones=True,
    bake_anim_use_nla_strips=False,
    bake_anim_use_all_actions=False,
    bake_anim_step=1.0,
)
print("EXPORTED", OUTPUT / "seated_revolver.fbx")
