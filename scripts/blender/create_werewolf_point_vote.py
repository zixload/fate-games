"""Create a seated Werewolf finger point for the end of the voting timer.

The arm points forward in character space. Gameplay must aim the character's
upper body or facing direction at the selected player before playing the clip.
The source and output FBX stay in ignored art/werewolf/.
"""

from math import radians
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art/werewolf"
NAME = "ANIM_WW_Seated_Vote_Point"
FIRST, LAST = 1, 67
FPS = 30

bpy.ops.wm.open_mainfile(filepath=str(OUT / "ANIM_WW_Sitting_Idle.blend"))
scene = bpy.context.scene
scene.render.fps = FPS
rig = bpy.data.objects["Root"]
bones = rig.pose.bones
world = rig.matrix_world
scene.frame_set(FIRST)


def at(name, tail=False):
    bone = bones[name]
    return world @ (bone.tail if tail else bone.head)


def ease(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def amount(frame):
    if frame < 8:
        return 0.0
    if frame < 22:
        return ease((frame - 8) / 14)
    if frame <= 48:
        return 1.0
    return 1.0 - ease((frame - 48) / (LAST - 48))


# The wrist travels from the lap to a comfortable straight-ahead pointing
# pose. Bake IK onto the Creative bones so the exported FBX needs no IK rig.
wrist = at("RightHand").copy()
shoulder = at("RightArm").copy()
goal = shoulder + Vector((-.17, -.44, -.025))
target = bpy.data.objects.new("WW_Point_Wrist", None)
pole = bpy.data.objects.new("WW_Point_Elbow", None)
scene.collection.objects.link(target)
scene.collection.objects.link(pole)
for frame, position in ((FIRST, wrist), (8, wrist), (22, goal),
                        (48, goal), (LAST, wrist)):
    target.location = position
    target.keyframe_insert("location", frame=frame)
pole.location = at("RightForeArm") + Vector((-.28, .07, -.05))
ik = bones["RightForeArm"].constraints.new("IK")
ik.target = target
ik.pole_target = pole
ik.chain_count = 2
ik.use_stretch = False
scene.frame_set(22)
solutions = []
for degrees in range(-180, 180, 15):
    ik.pole_angle = radians(degrees)
    bpy.context.view_layer.update()
    solutions.append(((at("RightForeArm") - pole.location).length, degrees))
ik.pole_angle = radians(min(solutions)[1])
scene.frame_start, scene.frame_end = FIRST, LAST
bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="POSE")
bpy.ops.nla.bake(frame_start=FIRST, frame_end=LAST, step=1,
                 only_selected=False, visual_keying=True,
                 clear_constraints=True, use_current_action=False,
                 bake_types={"POSE"})
bpy.ops.object.mode_set(mode="OBJECT")
for obj in (target, pole):
    bpy.data.objects.remove(obj, do_unlink=True)
rig.animation_data.action.name = NAME


# Close the other fingers, leave the index extended, and rotate the palm until
# the index aims along local forward (-Y), as seen by opponents across the rug.
scene.frame_set(FIRST)
base_hand = {name: bones[name].rotation_quaternion.copy()
             for name in ("RightHand",) + tuple(
                 f"RightHand{finger}{segment}"
                 for finger in ("Index", "Middle", "Ring", "Pinky", "Thumb")
                 for segment in (1, 2))}
normal = (at("RightHandIndex1") - at("RightHand")).cross(
    at("RightHandPinky1") - at("RightHand")).normalized()
palm = (normal if normal.dot(at("RightHandThumb2") - at("RightHand")) > 0
        else -normal)
curl_axis = {}
for finger in ("Index", "Middle", "Ring", "Pinky", "Thumb"):
    bone = bones[f"RightHand{finger}1"]
    original = bone.rotation_quaternion.copy()
    before = at(f"RightHand{finger}2")
    candidates = []
    for axis in ((1, 0, 0), (0, 1, 0), (0, 0, 1)):
        bone.rotation_quaternion = original @ Quaternion(axis, radians(30))
        bpy.context.view_layer.update()
        candidates.append(((at(f"RightHand{finger}2") - before).dot(palm), axis))
    bone.rotation_quaternion = original
    score, axis = max(candidates, key=lambda pair: abs(pair[0]))
    curl_axis[finger] = Vector(axis) * (1 if score > 0 else -1)
bpy.context.view_layer.update()


def basis(x, y):
    z = x.cross(y).normalized()
    y = z.cross(x).normalized()
    return Matrix((x, y, z)).transposed()


curl = {"Index": (-12, -28), "Middle": (72, 78),
        "Ring": (78, 82), "Pinky": (72, 78), "Thumb": (48, 52)}
pointing = Vector((0, -1, 0))
for frame in range(FIRST, LAST + 1):
    scene.frame_set(frame)
    progress = amount(frame)
    if progress:
        hand = at("RightHand")
        knuckles = (at("RightHandIndex1") + at("RightHandPinky1")) / 2
        along = (knuckles - hand).normalized()
        thumb = at("RightHandThumb1") - hand
        thumb = (thumb - along * thumb.dot(along)).normalized()
        current = basis(along, thumb)
        desired = basis(pointing, Vector((0, 0, 1)))
        rotation = Quaternion().slerp(
            (desired @ current.inverted()).to_quaternion(), progress)
        bone = bones["RightHand"]
        original = bone.matrix.copy()
        rotated = (world.to_3x3().inverted() @ rotation.to_matrix()
                   @ world.to_3x3() @ original.to_3x3()).normalized()
        bone.matrix = Matrix.Translation(original.translation) @ rotated.to_4x4()
        bpy.context.view_layer.update()
    bones["RightHand"].keyframe_insert("rotation_quaternion", frame=frame)
    for finger, angles in curl.items():
        for segment, angle in enumerate(angles, start=1):
            name = f"RightHand{finger}{segment}"
            bone = bones[name]
            bone.rotation_quaternion = (
                base_hand[name] @ Quaternion(
                    curl_axis[finger], radians(angle * progress)))
            bone.keyframe_insert("rotation_quaternion", frame=frame)

scene.frame_set(22)
index_direction = (at("RightHandIndex2", tail=True)
                   - at("RightHandIndex1")).normalized()
alignment = index_direction.dot(pointing)
if alignment < .8:
    raise RuntimeError(f"Index misses forward direction: {alignment:.3f}")
print("WW_POINT_POSE", "wrist", tuple(round(v, 3) for v in at("RightHand")),
      "index_alignment", round(alignment, 3))

scene.frame_set(FIRST)
begin = {name: at(name).copy() for name in
         ("Hips", "LeftFoot", "RightFoot", "RightHand")}
scene.frame_set(LAST)
seam_cm = max((at(name) - value).length for name, value in begin.items()) * 100
if seam_cm > .1:
    raise RuntimeError(f"Vote pointing clip does not return to idle: {seam_cm:.3f} cm")
print("WW_POINT_SEAM_CM", round(seam_cm, 5))

scene.frame_set(FIRST)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / (NAME + ".blend")))
bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.fbx(
    filepath=str(OUT / (NAME + ".fbx")), use_selection=True,
    object_types={"ARMATURE"}, add_leaf_bones=False, bake_anim=True,
    bake_anim_use_all_bones=True, bake_anim_use_nla_strips=False,
    bake_anim_use_all_actions=False, bake_anim_step=1.0)
print("WW_POINT_EXPORT", NAME, "duration_seconds", (LAST - FIRST) / FPS)
