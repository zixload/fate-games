"""Bake one seated left-hand card placement gesture for 1, 2 or 3 cards.

The game attaches its card fan to LeftHand. This clip briefly takes that hand
toward the centre of the table, releases the cards and returns to the idle
seated pose. Card count is visualised by the existing card props, not by the
skeleton, so a single animation serves every legal count.
"""

from pathlib import Path

import bpy
from math import radians
from mathutils import Matrix, Vector


ROOT = Path("C:/Users/ingam/OneDrive/Documents/fate-games")
OUT = ROOT / "art/animations"
bpy.ops.wm.open_mainfile(filepath=str(OUT / "seated_revolver.blend"))
scene = bpy.context.scene
body = next(obj for obj in scene.objects if obj.type == "ARMATURE")
bones = body.pose.bones
scene.render.fps = 30
scene.frame_set(1)

action = body.animation_data.action.copy()
action.name = "ANIM_Seated_Card_Play"
body.animation_data.action = action
body.animation_data.action_slot = action.slots[0]
bag = action.layers[0].strips[0].channelbag(action.slots[0])
for curve in bag.fcurves:
    for index in range(len(curve.keyframe_points) - 1, -1, -1):
        if curve.keyframe_points[index].co.x > 1:
            curve.keyframe_points.remove(curve.keyframe_points[index])
    curve.update()

world = body.matrix_world.copy()


def at(name, tail=False):
    bone = bones[name]
    return world @ (bone.tail if tail else bone.head)


wrist = at("LeftHand")
shoulder = at("LeftArm")
# A restrained reach toward the table, without dragging the whole body into
# it. Keep a generous clearance for the
# fingers and attached cards, which extend below the wrist in game.
table = wrist + Vector((-0.13, -0.38, 0.25))
reach = wrist.lerp(table, 0.58) + Vector((0, 0, 0.055))
pole_location = shoulder + Vector((0.30, 0.07, -0.18))

target = bpy.data.objects.new("Cards_LeftWrist_Target", None)
pole = bpy.data.objects.new("Cards_LeftElbow_Pole", None)
scene.collection.objects.link(target)
scene.collection.objects.link(pole)
for frame, point in ((1, wrist), (5, wrist), (10, reach), (15, table),
                     (18, table), (23, reach), (30, wrist)):
    target.location = point
    target.keyframe_insert("location", frame=frame)
for frame in (1, 30):
    pole.location = pole_location
    pole.keyframe_insert("location", frame=frame)


def ease(start, end, frame):
    t = max(0.0, min(1.0, (frame - start) / (end - start)))
    return t * t * (3 - 2 * t)


ik = bones["LeftForeArm"].constraints.new("IK")
ik.target, ik.pole_target = target, pole
ik.chain_count, ik.use_stretch = 2, False
scene.frame_set(15)
best = None
for angle in (-180, -135, -90, -45, 0, 45, 90, 135):
    ik.pole_angle = __import__("math").radians(angle)
    bpy.context.view_layer.update()
    distance = (at("LeftForeArm") - pole_location).length
    if best is None or distance < best[1]:
        best = (angle, distance)
ik.pole_angle = __import__("math").radians(best[0])

bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.mode_set(mode="POSE")
bpy.ops.nla.bake(frame_start=1, frame_end=30, step=1, only_selected=False,
                 visual_keying=True, clear_constraints=True,
                 use_current_action=False, bake_types={"POSE"})
bpy.ops.object.mode_set(mode="OBJECT")
for obj in (target, pole):
    bpy.data.objects.remove(obj, do_unlink=True)

body.animation_data.action.name = "ANIM_Seated_Card_Play"

# Near full extension, the IK elbow can turn abruptly even with a smooth
# wrist target. Blend neighboring baked rotations to keep the elbow moving.
for name in ("LeftArm", "LeftForeArm"):
    rotations = []
    for frame in range(1, 31):
        scene.frame_set(frame)
        rotations.append(bones[name].rotation_quaternion.copy())
    for _ in range(2):
        softened = []
        for index, center in enumerate(rotations):
            if index < 5 or index >= 29:
                softened.append(center.copy())
                continue
            neighbors = ((max(0, index - 2), 1), (index - 1, 4),
                         (index, 6), (min(29, index + 1), 4),
                         (min(29, index + 2), 1))
            components = [0.0] * 4
            for other, weight in neighbors:
                q = rotations[other]
                sign = 1 if center.dot(q) >= 0 else -1
                for axis in range(4):
                    components[axis] += q[axis] * weight * sign
            softened.append(type(center)(components).normalized())
        rotations = softened
    for frame, rotation in enumerate(rotations, start=1):
        scene.frame_set(frame)
        bones[name].rotation_quaternion = rotation
        bones[name].keyframe_insert("rotation_quaternion", frame=frame)

# The bake keys every frame, so the small forward dip must also be keyed on
# every frame. Sparse keys left neutral frames in between and made the hand
# jump down and back up at release. Pelvis and legs stay planted.
for frame in range(1, 31):
    lean = 8 * ease(7, 15, frame) * (1 - ease(18, 30, frame))
    scene.frame_set(frame)
    bone = bones["Spine1"]
    original = bone.matrix.copy()
    tilt = Matrix.Rotation(radians(lean), 3, "X")
    rotated = (world.to_3x3().inverted() @ tilt @ world.to_3x3()
               @ original.to_3x3()).normalized()
    bone.matrix = Matrix.Translation(original.translation) @ rotated.to_4x4()
    bpy.context.view_layer.update()
    bone.keyframe_insert("rotation_quaternion", frame=frame)

scene.frame_start, scene.frame_end = 1, 30
scene.frame_set(15)
print("CARD_REACH", tuple(round(v, 3) for v in at("LeftHand")),
      "target", tuple(round(v, 3) for v in table))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "seated_card_play.blend"))

bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
bpy.context.view_layer.objects.active = body
fbx = OUT / "seated_card_play.fbx"
bpy.ops.export_scene.fbx(
    filepath=str(fbx), use_selection=True, object_types={"ARMATURE"},
    add_leaf_bones=False, bake_anim=True, bake_anim_use_all_bones=True,
    bake_anim_use_nla_strips=False, bake_anim_use_all_actions=False,
    bake_anim_step=1.0,
)
print("CARD_EXPORT", fbx, "frames 1-30, duration 0.97s")
