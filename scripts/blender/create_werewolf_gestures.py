"""Create seated Werewolf vote and night-rest clips on the Creative rig.

Run with Blender in background mode. The input is the already fitted idle
animation, so the seat and foot contact are inherited. Generated .blend and
.fbx files stay under ignored art/werewolf/. No game map is edited.
"""

from math import pi, radians, sin
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art/werewolf"
SOURCE = OUT / "ANIM_WW_Sitting_Idle.blend"
FPS = 30


def open_idle():
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    scene = bpy.context.scene
    scene.render.fps = FPS
    rig = bpy.data.objects["Root"]
    return scene, rig


def point(rig, bone_name):
    return rig.matrix_world @ rig.pose.bones[bone_name].head


def turn_world(rig, bone_name, angle):
    bone = rig.pose.bones[bone_name]
    original = bone.matrix.copy()
    world_rotation = Matrix.Rotation(radians(angle), 3, "X")
    rig_rotation = (rig.matrix_world.to_3x3().inverted()
                    @ world_rotation @ rig.matrix_world.to_3x3()
                    @ original.to_3x3()).normalized()
    bone.matrix = Matrix.Translation(original.translation) @ rig_rotation.to_4x4()
    bpy.context.view_layer.update()
    bone.keyframe_insert("rotation_quaternion", frame=bpy.context.scene.frame_current)


def export(scene, rig, name):
    scene.frame_set(scene.frame_start)
    bpy.context.view_layer.update()
    blend = OUT / (name + ".blend")
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    fbx = OUT / (name + ".fbx")
    bpy.ops.export_scene.fbx(
        filepath=str(fbx), use_selection=True, object_types={"ARMATURE"},
        add_leaf_bones=False, bake_anim=True,
        bake_anim_use_all_bones=True, bake_anim_use_nla_strips=False,
        bake_anim_use_all_actions=False, bake_anim_step=1.0,
    )
    print("WW_GESTURE", name, "frames", scene.frame_start, scene.frame_end,
          "duration", round((scene.frame_end - scene.frame_start) / FPS, 4),
          "fbx", fbx)


def make_vote():
    scene, rig = open_idle()
    first, last = 1, 54
    scene.frame_set(first)
    bpy.context.view_layer.update()
    start = {n: point(rig, n).copy() for n in
             ("Hips", "LeftFoot", "RightFoot", "RightHand")}

    wrist = start["RightHand"]
    shoulder = point(rig, "RightArm")
    raised = shoulder + Vector((-.21, -.21, .18))
    target = bpy.data.objects.new("WW_Vote_Wrist_Target", None)
    pole = bpy.data.objects.new("WW_Vote_Elbow_Pole", None)
    scene.collection.objects.link(target)
    scene.collection.objects.link(pole)
    for frame, location in ((1, wrist), (8, wrist), (23, raised),
                            (37, raised), (53, wrist), (last, wrist)):
        target.location = location
        target.keyframe_insert("location", frame=frame)
    elbow = point(rig, "RightForeArm")
    pole.location = elbow + Vector((-.28, .07, -.05))
    ik = rig.pose.bones["RightForeArm"].constraints.new("IK")
    ik.target = target
    ik.pole_target = pole
    ik.chain_count = 2
    ik.use_stretch = False
    scene.frame_set(23)
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
    rig.animation_data.action.name = "ANIM_WW_Seated_Vote"
    for frame in (first, 23, last):
        scene.frame_set(frame)
        print("WW_VOTE_CONTACT", frame,
              {n: tuple(round(v, 4) for v in point(rig, n))
               for n in start})
    scene.frame_set(first)
    if max((point(rig, n) - start[n]).length for n in
           ("Hips", "LeftFoot", "RightFoot")) > .002:
        raise RuntimeError("Vote changed the seated contact pose")
    export(scene, rig, "ANIM_WW_Seated_Vote")


def make_sleep():
    scene, rig = open_idle()
    first, last = 1, 327
    action = rig.animation_data.action.copy()
    action.name = "ANIM_WW_Seated_Sleep"
    rig.animation_data.action = action
    rig.animation_data.action_slot = action.slots[0]
    scene.frame_start, scene.frame_end = first, last
    for frame in range(first, last + 1):
        scene.frame_set(frame)
        phase = 2 * pi * (frame - first) / (last - first)
        # Restrained breathing; the main bow is steady and loops cleanly.
        breath = .7 * sin(phase)
        turn_world(rig, "Spine1", 4.5 + breath)
        turn_world(rig, "Neck", 11.0 + .35 * sin(phase))
        turn_world(rig, "Head", 12.0 + .4 * sin(phase))
    scene.frame_set(first)
    a = {n: point(rig, n).copy() for n in
         ("Hips", "LeftFoot", "RightFoot", "Head")}
    scene.frame_set(last)
    seam_cm = max((point(rig, n) - a[n]).length for n in a) * 100
    if seam_cm > .1:
        raise RuntimeError(f"Sleep loop seam: {seam_cm:.3f} cm")
    print("WW_SLEEP_SEAM_CM", round(seam_cm, 5))
    export(scene, rig, "ANIM_WW_Seated_Sleep")


make_vote()
make_sleep()
