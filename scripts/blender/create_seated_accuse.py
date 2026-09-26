"""Bake three seated pointing gestures on the Creative character skeleton.

Run with Steam Blender in background mode. The server selects left, center or
right from the accused player's chair. The raised arm and index finger make
the accusation readable from the other side of the table.
"""

from math import radians
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector


ROOT = Path("C:/Users/ingam/OneDrive/Documents/fate-games")
OUT = ROOT / "art/animations"
SOURCE = OUT / "seated_revolver.blend"
LAST = 42
VARIANTS = {
    # The Creative model faces -Y, and its right arm is on -X.
    "Left": (Vector((0.04, -0.54, 1.23)), Vector((0.50, -0.86, 0.15))),
    "Center": (Vector((-0.16, -0.61, 1.23)), Vector((0.0, -1.0, 0.15))),
    "Right": (Vector((-0.35, -0.53, 1.23)), Vector((-0.50, -0.86, 0.15))),
}


def ease(start, end, frame):
    t = max(0.0, min(1.0, (frame - start) / (end - start)))
    return t * t * (3 - 2 * t)


def amount(frame):
    return ease(7, 18, frame) * (1 - ease(28, LAST, frame))


def make_variant(side, wrist_goal, finger_direction):
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    scene = bpy.context.scene
    scene.render.fps = 30
    scene.frame_set(1)
    body = next(obj for obj in scene.objects if obj.type == "ARMATURE")
    bones = body.pose.bones
    world = body.matrix_world.copy()

    action = body.animation_data.action.copy()
    action.name = f"ANIM_Seated_Accuse_{side}"
    body.animation_data.action = action
    body.animation_data.action_slot = action.slots[0]
    bag = action.layers[0].strips[0].channelbag(action.slots[0])
    for curve in bag.fcurves:
        for index in range(len(curve.keyframe_points) - 1, -1, -1):
            if curve.keyframe_points[index].co.x > 1:
                curve.keyframe_points.remove(curve.keyframe_points[index])
        curve.update()

    def at(name, tail=False):
        bone = bones[name]
        return world @ (bone.tail if tail else bone.head)

    rest_wrist = at("RightHand")
    shoulder = at("RightArm")
    target = bpy.data.objects.new("Accuse_RightWrist_Target", None)
    pole = bpy.data.objects.new("Accuse_RightElbow_Pole", None)
    scene.collection.objects.link(target)
    scene.collection.objects.link(pole)
    for frame, point in ((1, rest_wrist), (7, rest_wrist),
                         (18, wrist_goal), (28, wrist_goal),
                         (LAST, rest_wrist)):
        target.location = point
        target.keyframe_insert("location", frame=frame)
    pole_location = shoulder + Vector((-0.35, 0.10, -0.10))
    for frame in (1, LAST):
        pole.location = pole_location
        pole.keyframe_insert("location", frame=frame)

    ik = bones["RightForeArm"].constraints.new("IK")
    ik.target, ik.pole_target = target, pole
    ik.chain_count, ik.use_stretch = 2, False
    scene.frame_set(18)
    best = None
    for angle in (-180, -135, -90, -45, 0, 45, 90, 135):
        ik.pole_angle = radians(angle)
        bpy.context.view_layer.update()
        distance = (at("RightForeArm") - pole_location).length
        if best is None or distance < best[1]:
            best = (angle, distance)
    ik.pole_angle = radians(best[0])

    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.nla.bake(frame_start=1, frame_end=LAST, step=1,
                     only_selected=False, visual_keying=True,
                     clear_constraints=True, use_current_action=False,
                     bake_types={"POSE"})
    bpy.ops.object.mode_set(mode="OBJECT")
    for obj in (target, pole):
        bpy.data.objects.remove(obj, do_unlink=True)
    body.animation_data.action.name = f"ANIM_Seated_Accuse_{side}"

    # The curled fingers close into a loose fist. The index stays straight.
    # Determine each finger's local curl axis from the actual Creative rig.
    scene.frame_set(1)
    wrist = at("RightHand")
    a = at("RightHandIndex1") - wrist
    b = at("RightHandPinky1") - wrist
    normal = a.cross(b).normalized()
    palm = normal if normal.dot(at("RightHandThumb2") - wrist) > 0 else -normal
    fingers = ("Index", "Middle", "Ring", "Pinky", "Thumb")
    curl_axis, rest_rotation = {}, {}
    for finger in fingers:
        bone = bones[f"RightHand{finger}1"]
        tip = f"RightHand{finger}2"
        base = bone.rotation_quaternion.copy()
        before = at(tip)
        best = None
        for axis in ((1, 0, 0), (0, 1, 0), (0, 0, 1)):
            bone.rotation_quaternion = base @ Quaternion(axis, radians(30))
            bpy.context.view_layer.update()
            score = (at(tip) - before).dot(palm)
            if best is None or abs(score) > abs(best[1]):
                best = (axis, score)
        bone.rotation_quaternion = base
        bpy.context.view_layer.update()
        curl_axis[finger] = Vector(best[0]) * (1 if best[1] > 0 else -1)
        for segment in (1, 2):
            name = f"RightHand{finger}{segment}"
            rest_rotation[name] = bones[name].rotation_quaternion.copy()

    def basis(x, y):
        z = x.cross(y).normalized()
        y = z.cross(x).normalized()
        return Matrix((x, y, z)).transposed()

    curl = {
        "Index": (-12, -28), "Middle": (72, 78), "Ring": (78, 82),
        "Pinky": (72, 78), "Thumb": (48, 52),
    }
    pointing = finger_direction.normalized()
    for frame in range(1, LAST + 1):
        scene.frame_set(frame)
        progress = amount(frame)
        if progress:
            wrist = at("RightHand")
            knuckles = (at("RightHandIndex1") + at("RightHandPinky1")) / 2
            along = (knuckles - wrist).normalized()
            thumb = at("RightHandThumb1") - wrist
            thumb = (thumb - along * thumb.dot(along)).normalized()
            current = basis(along, thumb)
            wanted = basis(pointing, Vector((0, 0, 1)))
            turn = Quaternion().slerp((wanted @ current.inverted()).to_quaternion(), progress)
            bone = bones["RightHand"]
            original = bone.matrix.copy()
            rotation = (world.to_3x3().inverted() @ turn.to_matrix()
                        @ world.to_3x3() @ original.to_3x3()).normalized()
            bone.matrix = Matrix.Translation(original.translation) @ rotation.to_4x4()
            bpy.context.view_layer.update()
        bones["RightHand"].keyframe_insert("rotation_quaternion", frame=frame)
        for finger, (first, second) in curl.items():
            for segment, angle in ((1, first), (2, second)):
                name = f"RightHand{finger}{segment}"
                bone = bones[name]
                bone.rotation_quaternion = (rest_rotation[name]
                                            @ Quaternion(curl_axis[finger], radians(angle * progress)))
                bone.keyframe_insert("rotation_quaternion", frame=frame)

    scene.frame_start, scene.frame_end = 1, LAST
    scene.frame_set(22)
    index_direction = (at("RightHandIndex2", tail=True) - at("RightHandIndex1")).normalized()
    print("ACCUSE_POSE", side, "wrist", tuple(round(v, 3) for v in at("RightHand")),
          "finger_alignment", round(index_direction.dot(pointing), 3))
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / f"seated_accuse_{side.lower()}.blend"))

    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    path = OUT / f"seated_accuse_{side.lower()}.fbx"
    bpy.ops.export_scene.fbx(
        filepath=str(path), use_selection=True, object_types={"ARMATURE"},
        add_leaf_bones=False, bake_anim=True, bake_anim_use_all_bones=True,
        bake_anim_use_nla_strips=False, bake_anim_use_all_actions=False,
        bake_anim_step=1.0,
    )
    print("ACCUSE_EXPORT", path)


for variant, (goal, direction) in VARIANTS.items():
    make_variant(variant, goal, direction)
