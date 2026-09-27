"""Bake additional seated Creative animations for the Werewolf game.

Uses the fitted idle and gesture clips in ignored art/werewolf/. Outputs stay
there. The elimination reaction ends at the first frame of Dead_Idle. The
character reclines behind the cushion while the actor root stays fixed.
"""

import os
from math import pi, radians, sin
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art/werewolf"
FPS = 30


def open_clip(name):
    bpy.ops.wm.open_mainfile(filepath=str(OUT / f"{name}.blend"))
    scene = bpy.context.scene
    scene.render.fps = FPS
    return scene, bpy.data.objects["Root"]


def point(rig, name):
    return rig.matrix_world @ rig.pose.bones[name].head


def turn(rig, name, axis, angle, frame=None):
    bone = rig.pose.bones[name]
    original = bone.matrix.copy()
    rotation = Matrix.Rotation(radians(angle), 3, axis)
    basis = (rig.matrix_world.to_3x3().inverted() @ rotation
             @ rig.matrix_world.to_3x3() @ original.to_3x3()).normalized()
    bone.matrix = Matrix.Translation(original.translation) @ basis.to_4x4()
    bpy.context.view_layer.update()
    if frame is not None:
        bone.keyframe_insert("rotation_quaternion", frame=frame)


def move_hips_back(rig, metres, frame=None):
    bone = rig.pose.bones["Hips"]
    delta = rig.matrix_world.to_3x3().inverted() @ Vector((0, metres, 0))
    matrix = bone.matrix.copy()
    matrix.translation += delta
    bone.matrix = matrix
    bpy.context.view_layer.update()
    if frame is not None:
        bone.keyframe_insert("location", frame=frame)


def export(scene, rig, name):
    scene.frame_set(scene.frame_start)
    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / f"{name}.blend"))
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.fbx(
        filepath=str(OUT / f"{name}.fbx"), use_selection=True,
        object_types={"ARMATURE"}, add_leaf_bones=False, bake_anim=True,
        bake_anim_use_all_bones=True, bake_anim_use_nla_strips=False,
        bake_anim_use_all_actions=False, bake_anim_step=1.0,
    )
    print("WW_EXTRA", name, "frames", scene.frame_start, scene.frame_end,
          "seconds", round((scene.frame_end - scene.frame_start) / FPS, 4))


def loop_variant(source, name, moves):
    scene, rig = open_clip(source)
    first, last = scene.frame_start, scene.frame_end
    action = rig.animation_data.action.copy()
    action.name = name
    rig.animation_data.action = action
    rig.animation_data.action_slot = action.slots[0]
    for frame in range(first, last + 1):
        scene.frame_set(frame)
        phase = 2 * pi * (frame - first) / (last - first)
        for bone, axis, angle in moves(phase):
            turn(rig, bone, axis, angle, frame)
    scene.frame_set(first)
    begin = {n: point(rig, n).copy() for n in
             ("Hips", "LeftFoot", "RightFoot", "Head")}
    scene.frame_set(last)
    seam = max((point(rig, n) - begin[n]).length for n in begin) * 100
    if seam > .1:
        raise RuntimeError(f"{name} loop seam {seam:.3f} cm")
    print("WW_LOOP_SEAM_CM", name, round(seam, 5))
    export(scene, rig, name)


def make_mayor():
    scene, rig = open_clip("ANIM_WW_Sitting_Idle")
    first, last = 1, 75
    scene.frame_set(first)
    wrist = point(rig, "RightHand").copy()
    shoulder = point(rig, "RightArm").copy()
    goal = shoulder + Vector((-.16, -.17, .40))
    target = bpy.data.objects.new("WW_Mayor_Wrist", None)
    pole = bpy.data.objects.new("WW_Mayor_Elbow", None)
    scene.collection.objects.link(target)
    scene.collection.objects.link(pole)
    for frame, where in ((1, wrist), (7, wrist), (21, goal),
                         (42, goal), (65, wrist), (last, wrist)):
        target.location = where
        target.keyframe_insert("location", frame=frame)
    pole.location = point(rig, "RightForeArm") + Vector((-.27, .08, -.06))
    ik = rig.pose.bones["RightForeArm"].constraints.new("IK")
    ik.target = target
    ik.pole_target = pole
    ik.chain_count = 2
    ik.use_stretch = False
    scene.frame_set(21)
    candidates = []
    for degrees in range(-180, 180, 15):
        ik.pole_angle = radians(degrees)
        bpy.context.view_layer.update()
        candidates.append(((point(rig, "RightForeArm") - pole.location).length,
                           degrees))
    ik.pole_angle = radians(min(candidates)[1])
    scene.frame_start, scene.frame_end = first, last
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.nla.bake(frame_start=first, frame_end=last, step=1,
                     only_selected=False, visual_keying=True,
                     clear_constraints=True, use_current_action=False,
                     bake_types={"POSE"})
    bpy.ops.object.mode_set(mode="OBJECT")
    for obj in (target, pole):
        bpy.data.objects.remove(obj, do_unlink=True)
    rig.animation_data.action.name = "ANIM_WW_Seated_Mayor_Cheer"

    # A compact fist reads as a celebratory gesture from across the circle.
    scene.frame_set(1)
    hand = point(rig, "RightHand")
    index = point(rig, "RightHandIndex1") - hand
    pinky = point(rig, "RightHandPinky1") - hand
    normal = index.cross(pinky).normalized()
    palm = (normal if normal.dot(point(rig, "RightHandThumb2") - hand) > 0
            else -normal)
    axes = {}
    for finger in ("Index", "Middle", "Ring", "Pinky", "Thumb"):
        bone = rig.pose.bones[f"RightHand{finger}1"]
        base = bone.rotation_quaternion.copy()
        before = point(rig, f"RightHand{finger}2")
        best = None
        for axis in ((1, 0, 0), (0, 1, 0), (0, 0, 1)):
            bone.rotation_quaternion = base @ Quaternion(axis, radians(25))
            bpy.context.view_layer.update()
            score = (point(rig, f"RightHand{finger}2") - before).dot(palm)
            if best is None or abs(score) > abs(best[1]):
                best = (axis, score)
        bone.rotation_quaternion = base
        axes[finger] = Vector(best[0]) * (1 if best[1] > 0 else -1)

    for frame in range(first, last + 1):
        scene.frame_set(frame)
        strength = min(1, max(0, (frame - 7) / 14),
                       max(0, (last - frame) / 12))
        for finger in axes:
            for segment, degrees in ((1, 65), (2, 65)):
                bone = rig.pose.bones[f"RightHand{finger}{segment}"]
                base = bone.rotation_quaternion.copy()
                bone.rotation_quaternion = (base @ Quaternion(
                    axes[finger], radians(degrees * strength)))
                bone.keyframe_insert("rotation_quaternion", frame=frame)
    for frame in (1, 21, last):
        scene.frame_set(frame)
        print("WW_MAYOR_WRIST", frame, tuple(round(v, 3) for v in point(rig, "RightHand")))
    export(scene, rig, "ANIM_WW_Seated_Mayor_Cheer")


def snapshot(rig):
    return {bone.name: (bone.location.copy(), bone.rotation_quaternion.copy(),
                        bone.scale.copy()) for bone in rig.pose.bones}


def apply_snapshot(rig, pose):
    for name, (loc, rot, scale) in pose.items():
        bone = rig.pose.bones[name]
        bone.location = loc.copy()
        bone.rotation_quaternion = rot.copy()
        bone.scale = scale.copy()
    bpy.context.view_layer.update()


def interpolate(a, b, fraction):
    return {name: (loc.lerp(b[name][0], fraction),
                   rot.slerp(b[name][1], fraction),
                   scale.lerp(b[name][2], fraction))
            for name, (loc, rot, scale) in a.items()}


def ease(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def recline(rig, frame=None):
    """Keep the pelvis on the cushion and let the upper body fall backwards."""
    move_hips_back(rig, .10, frame)
    for bone, axis, angle in (
        ("Spine", "X", -95),
        ("Spine1", "X", -20),
        ("Neck", "X", -20),
        ("RightArm", "X", 50),
        ("RightArm", "Z", -20),
        ("LeftArm", "X", 80),
        ("LeftArm", "Z", 40),
    ):
        turn(rig, bone, axis, angle, frame)


def make_death():
    scene, rig = open_clip("ANIM_WW_Sitting_Idle")
    scene.frame_set(1)
    idle = snapshot(rig)
    # Reuse the tested raised arm from Vote and the curled fingers from Mayor.
    # This makes a short, readable downward fist gesture without a fall.
    with bpy.data.libraries.load(str(OUT / "ANIM_WW_Seated_Vote.blend"),
                                 link=False) as (src, dst):
        dst.actions = ["ANIM_WW_Seated_Vote"]
    vote_action = dst.actions[0]
    with bpy.data.libraries.load(str(OUT / "ANIM_WW_Seated_Mayor_Cheer.blend"),
                                 link=False) as (src, dst):
        dst.actions = ["ANIM_WW_Seated_Mayor_Cheer"]
    mayor_action = dst.actions[0]
    if vote_action is None or mayor_action is None:
        raise RuntimeError("Fitted vote or mayor action unavailable")
    rig.animation_data.action = vote_action
    rig.animation_data.action_slot = vote_action.slots[0]
    scene.frame_set(23)
    vote = snapshot(rig)
    rig.animation_data.action = mayor_action
    rig.animation_data.action_slot = mayor_action.slots[0]
    scene.frame_set(21)
    mayor = snapshot(rig)

    apply_snapshot(rig, idle)
    for name in ("RightArm", "RightForeArm", "RightHand"):
        rig.pose.bones[name].location = vote[name][0].copy()
        rig.pose.bones[name].rotation_quaternion = vote[name][1].copy()
    for name in idle:
        if name.startswith("RightHand") and name != "RightHand":
            rig.pose.bones[name].rotation_quaternion = mayor[name][1].copy()
    turn(rig, "Spine1", "X", 5)
    turn(rig, "Head", "X", 5)
    raised = snapshot(rig)

    apply_snapshot(rig, idle)
    for name in idle:
        if name.startswith("RightHand") and name != "RightHand":
            rig.pose.bones[name].rotation_quaternion = mayor[name][1].copy()
    turn(rig, "Spine1", "X", 9)
    turn(rig, "Neck", "X", 5)
    turn(rig, "Head", "X", 8)
    strike = snapshot(rig)

    apply_snapshot(rig, idle)
    recline(rig)
    reclined = snapshot(rig)

    # Copy the idle action to retain the exact Creative action slot and bones.
    base = bpy.data.actions.get("ANIM_WW_Sitting_Idle")
    action = base.copy()
    action.name = "ANIM_WW_Seated_Death"
    rig.animation_data.action = action
    rig.animation_data.action_slot = action.slots[0]
    bag = action.layers[0].strips[0].channelbag(action.slots[0])
    for curve in bag.fcurves:
        for index in range(len(curve.keyframe_points) - 1, -1, -1):
            curve.keyframe_points.remove(curve.keyframe_points[index])
        curve.update()

    controls = ((1, idle), (6, idle), (14, raised), (17, raised),
                (24, strike), (32, idle), (56, reclined), (61, reclined))
    scene.frame_start, scene.frame_end = 1, 61
    for frame in range(1, 62):
        scene.frame_set(frame)
        for i in range(len(controls) - 1):
            left, a = controls[i]
            right, b = controls[i + 1]
            if left <= frame <= right:
                pose = interpolate(a, b, ease((frame - left) / (right - left)))
                break
        apply_snapshot(rig, pose)
        for bone in rig.pose.bones:
            bone.keyframe_insert("location", frame=frame)
            bone.keyframe_insert("rotation_quaternion", frame=frame)
            bone.keyframe_insert("scale", frame=frame)
    scene.frame_set(61)
    final = {n: point(rig, n).copy() for n in
             ("Hips", "LeftFoot", "RightFoot", "Head")}
    print("WW_DEATH_FINAL", {n: tuple(round(v, 4) for v in p)
                             for n, p in final.items()})
    export(scene, rig, "ANIM_WW_Seated_Death")

    # The reclined pose loops until the eliminated player is reset.
    scene, rig = open_clip("ANIM_WW_Sitting_Idle")
    action = rig.animation_data.action.copy()
    action.name = "ANIM_WW_Seated_Dead_Idle"
    rig.animation_data.action = action
    rig.animation_data.action_slot = action.slots[0]
    for frame in range(scene.frame_start, scene.frame_end + 1):
        scene.frame_set(frame)
        recline(rig, frame)
    scene.frame_set(1)
    start = {n: point(rig, n).copy() for n in final}
    match = max((start[n] - final[n]).length for n in final) * 100
    if match > .1:
        raise RuntimeError(f"Death to dead idle jump: {match:.3f} cm")
    scene.frame_set(scene.frame_end)
    seam = max((point(rig, n) - start[n]).length for n in start) * 100
    if seam > .1:
        raise RuntimeError(f"Dead idle seam: {seam:.3f} cm")
    print("WW_DEAD_MATCH_CM", round(match, 5), "LOOP_SEAM_CM", round(seam, 5))
    export(scene, rig, "ANIM_WW_Seated_Dead_Idle")


if os.environ.get("WW_EXTRA_ONLY") == "death":
    make_death()
else:
    loop_variant("ANIM_WW_Sitting_Idle", "ANIM_WW_Sitting_Idle_Glance",
                 lambda p: (("Spine1", "Z", 1.7 * sin(p)),
                            ("Neck", "Z", 3.0 * sin(p)),
                            ("Head", "Z", 6.0 * sin(p))))
    loop_variant("ANIM_WW_Sitting_Idle_Lazy", "ANIM_WW_Sitting_Idle_Shift",
                 lambda p: (("Spine1", "Y", 2.3 * sin(p)),
                            ("Neck", "Y", -1.5 * sin(p)),
                            ("Head", "Z", 4.0 * sin(p + pi) + 0.0)))
    make_mayor()
    make_death()
