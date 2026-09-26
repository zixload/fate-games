"""Make a short, baked seated collapse after the revolver fires.

The gun is at the character's right temple (-X in this Blender scene), so the
head and chest recoil toward +X. Hips and legs stay on the chair. The final
pose is held by PlayAnimation(..., blend_out_time=-1) in the game; no ragdoll or
physics simulation runs on clients.

Run with the Steam Blender executable:
  blender.exe -b --python create_seated_fatal.py
Then import seated_revolver_fatal.fbx on the Creative skeleton in the ADK.
"""

from math import radians
from pathlib import Path

import bpy
from mathutils import Matrix


ROOT = Path("C:/Users/ingam/OneDrive/Documents/fate-games")
OUT = ROOT / "art/animations"
SOURCE = OUT / "seated_revolver.blend"
FIRST, LAST = 28, 52  # 0.8 seconds at 30 fps, including the settled hold

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
body = next(obj for obj in scene.objects if obj.type == "ARMATURE")
assert scene.render.fps == 30
assert body.animation_data and body.animation_data.action
bones = body.pose.bones
world = body.matrix_world.copy()


def sample(frame):
    scene.frame_set(frame)
    bpy.context.view_layer.update()
    return {bone.name: bone.rotation_quaternion.copy() for bone in bones}


idle = sample(1)
shot = sample(FIRST)
action = body.animation_data.action.copy()
action.name = "ANIM_Seated_Revolver_Fatal"
body.animation_data.action = action
body.animation_data.action_slot = action.slots[0]

# Keep the source shot frame, then write only the new reaction. Source fire
# keys after frame 28 would otherwise pull the arm back during the collapse.
bag = action.layers[0].strips[0].channelbag(action.slots[0])
for curve in bag.fcurves:
    for index in range(len(curve.keyframe_points) - 1, -1, -1):
        if curve.keyframe_points[index].co.x > FIRST:
            curve.keyframe_points.remove(curve.keyframe_points[index])
    curve.update()


def turn_world(bone_name, left, back):
    """Add a world-space lean while preserving the seated bone's local pose."""
    bone = bones[bone_name]
    delta = (Matrix.Rotation(radians(left), 3, "Y")
             @ Matrix.Rotation(radians(-back), 3, "X"))
    arm_space = bone.matrix.copy()
    new_rotation = (world.to_3x3().inverted() @ delta @ world.to_3x3()
                    @ arm_space.to_3x3()).normalized()
    bone.matrix = Matrix.Translation(arm_space.translation) @ new_rotation.to_4x4()
    bpy.context.view_layer.update()
    bone.keyframe_insert("rotation_quaternion", frame=scene.frame_current)


arms = [name for name in shot if name.startswith(("RightArm", "RightForeArm", "RightHand",
                                                  "LeftArm", "LeftForeArm", "LeftHand"))]
core = ("Spine", "Spine1", "Neck", "Head")

# frame, torso lean left, lean back, neck flop, head flop, arm relaxation.
# The overshoot and tiny rebound make the hit a little funny without flinging
# the pelvis or the feet off the chair.
poses = (
    (28, 0, 0, 0, 0, 0.00),
    (30, 6, 0, 5, 7, 0.08),
    (33, 17, 4, 12, 15, 0.32),
    (37, 26, 10, 20, 23, 0.78),
    (41, 21, 7, 14, 17, 0.93),
    (46, 24, 11, 19, 21, 1.00),
    (52, 24, 11, 19, 21, 1.00),
)

for frame, left, back, neck, head, relax in poses:
    scene.frame_set(frame)
    # Start each control pose from the same shot frame, so interpolation does
    # not accidentally accumulate the previous world-space rotation.
    for name in core:
        bones[name].rotation_quaternion = shot[name].copy()
    for name in arms:
        bones[name].rotation_quaternion = shot[name].slerp(idle[name], relax)
    bpy.context.view_layer.update()

    turn_world("Spine", left * 0.45, back * 0.45)
    turn_world("Spine1", left * 0.55, back * 0.55)
    turn_world("Neck", neck * 0.40, -neck * 0.10)
    turn_world("Head", head * 0.60, -head * 0.18)
    for name in arms:
        bones[name].keyframe_insert("rotation_quaternion", frame=frame)

scene.frame_start, scene.frame_end = FIRST, LAST
scene.frame_set(LAST)
bpy.context.view_layer.update()
blend = OUT / "seated_revolver_fatal.blend"
bpy.ops.wm.save_as_mainfile(filepath=str(blend))

bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
bpy.context.view_layer.objects.active = body
fbx = OUT / "seated_revolver_fatal.fbx"
bpy.ops.export_scene.fbx(
    filepath=str(fbx), use_selection=True, object_types={"ARMATURE"},
    add_leaf_bones=False, bake_anim=True, bake_anim_use_all_bones=True,
    bake_anim_use_nla_strips=False, bake_anim_use_all_actions=False,
    bake_anim_step=1.0,
)
print("FATAL_EXPORT", fbx, "frames", FIRST, LAST, "duration", (LAST - FIRST) / 30)
