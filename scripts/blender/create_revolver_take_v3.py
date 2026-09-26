"""Seated revolver gesture, third pass: fit the real Nagant between fist and temple.

This pass keeps the two-clip timing and the v2 grip. The wrist is moved out
and forward to fit the full-size Nagant: its muzzle reaches the right temple
without putting the cylinder inside the head. The index flexes on the shot.

  * an IK pole that swings the elbow out to the right side,
  * a hand orientation at the temple: index above pinky around the handle,
  * a closed grip from the moment the hand reaches the gun until it lets go.

The matching prop offset is measured in preview_revolver_fit.py. Verify the
imported socket frame in game with /prise after cooking the clips.

Run with Steam Blender:
  blender.exe -b --python create_revolver_take_v3.py
"""

from math import radians
import os
from pathlib import Path
import bpy
from mathutils import Matrix, Quaternion, Vector


SOURCE = Path("C:/nanos-adk/Saved/CodexAnimation")
OUTPUT = Path(os.environ.get("REVOLVER_OUTPUT", "C:/Users/ingam/OneDrive/Documents/fate-games/art/animations"))
OUTPUT.mkdir(parents=True, exist_ok=True)
FRAMES = 48

# Timeline shared with the server (adapter.lua): the gun joins the hand at
# 0.3 s (frame 10), the take clip ends at the temple (frame 26), the shot is
# fired from there and the fire clip returns to idle.
GRAB, TEMPLE_IN, TEMPLE_OUT, RELEASE = 10, 21, 31, 41

# Wrist target at the table. With the Nagant attached, its centre is about
# 0.94 m at frame 10 and its lower edge is near the 0.88 m tabletop.
TABLE = Vector((-0.24, -0.45, 1.00))


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def ramp(frame, up_from, up_to, down_from, down_to):
    """0 before up_from, 1 between up_to and down_from, 0 after down_to."""
    if frame <= up_from or frame >= down_to:
        return 0.0
    if frame < up_to:
        return smooth((frame - up_from) / (up_to - up_from))
    if frame > down_from:
        return 1.0 - smooth((frame - down_from) / (down_to - down_from))
    return 1.0


# ------------------------------------------------------------ rig and idle

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.fbx(filepath=str(SOURCE / "creative_skeleton.fbx"))
body = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
mesh = next(o for o in bpy.context.scene.objects if o.type == "MESH")
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
# Keep the rig, its mesh and the wrapper empty above the armature: that
# empty carries the centimetre-to-metre scale and becomes the root track the
# Creative skeleton expects in Unreal.
keep = {body, mesh}
p = body.parent
while p:
    keep.add(p)
    p = p.parent
for o in list(bpy.context.scene.objects):
    if o not in keep and o.parent != body:
        bpy.data.objects.remove(o, do_unlink=True)

scene = bpy.context.scene
scene.render.fps = 30
scene.frame_start, scene.frame_end = 1, FRAMES
pb = body.pose.bones
world = body.matrix_world


def wpos(name, tail=False):
    b = pb[name]
    return world @ (b.tail if tail else b.head)


# ------------------------------------------------------------ landmarks

scene.frame_set(TEMPLE_IN)
bpy.context.view_layer.update()
shoulder = wpos("RightArm")
head_base, head_top = wpos("Head"), wpos("Head", tail=True)
depsgraph = bpy.context.evaluated_depsgraph_get()
evaluated = mesh.evaluated_get(depsgraph)
verts = [evaluated.matrix_world @ v.co for v in evaluated.to_mesh().vertices]
# The skull: vertices above the head bone and near its axis. Temple height:
# a third of the way from the head bone to the top of the skull, on the
# right side of the head (-X).
axis_xy = Vector((head_base.x, head_base.y))
skull = [v for v in verts if v.z > head_base.z
         and (Vector((v.x, v.y)) - axis_xy).length < 0.16]
top_z = max(v.z for v in skull)
temple_z = head_base.z + (top_z - head_base.z) * 0.35
band = [v for v in skull if abs(v.z - temple_z) < 0.02]
right_x = min(v.x for v in band)
mid_y = (min(v.y for v in band) + max(v.y for v in band)) / 2
temple = Vector((right_x, mid_y - 0.01, temple_z))
print("LANDMARK skull", len(skull), "top", round(top_z, 3), "band", len(band))
evaluated.to_mesh_clear()
print("LANDMARK shoulder", tuple(round(c, 3) for c in shoulder))
print("LANDMARK head", tuple(round(c, 3) for c in head_base), tuple(round(c, 3) for c in head_top))
print("LANDMARK temple", tuple(round(c, 3) for c in temple))

scene.frame_set(1)
bpy.context.view_layer.update()
rest_wrist = wpos("RightForeArm", tail=True)

# Wrist at the temple: out to the right of the head, a little behind and
# below, so a gun held in the fist reaches the temple with its barrel.
wrist_temple = temple + Vector((float(os.environ.get("REVOLVER_WRIST_X", "-0.31")),
                                float(os.environ.get("REVOLVER_WRIST_Y", "-0.04")), -0.07))
arc = lambda a, b: (a + b) / 2 + Vector((-0.06, 0.04, 0.0))

wrist_keys = (
    (1, rest_wrist),
    (6, TABLE + Vector((0, 0, 0.04))),
    (GRAB, TABLE),
    (13, TABLE + Vector((0, 0, 0.05))),
    (17, arc(TABLE, wrist_temple)),
    (TEMPLE_IN, wrist_temple),
    (26, wrist_temple),
    (28, wrist_temple + Vector((-0.04, 0.02, 0.05))),  # recoil: up and out
    (TEMPLE_OUT, wrist_temple),
    (35, arc(wrist_temple, TABLE)),
    (39, TABLE + Vector((0, 0, 0.04))),
    (RELEASE, TABLE),
    (44, TABLE + Vector((0, 0, 0.04))),
    (FRAMES, rest_wrist),
)
pole_low = shoulder + Vector((-0.25, 0.30, -0.45))   # elbow down and back
pole_side = shoulder + Vector((-0.45, 0.08, -0.10))  # elbow out to the side
pole_keys = ((1, pole_low), (13, pole_low), (TEMPLE_IN, pole_side),
             (TEMPLE_OUT, pole_side), (39, pole_low), (FRAMES, pole_low))

target = bpy.data.objects.new("Wrist_Target", None)
pole = bpy.data.objects.new("Elbow_Pole", None)
for o in (target, pole):
    scene.collection.objects.link(o)
for frame, loc in wrist_keys:
    target.location = loc
    target.keyframe_insert("location", frame=frame)
for frame, loc in pole_keys:
    pole.location = loc
    pole.keyframe_insert("location", frame=frame)

ik = pb["RightForeArm"].constraints.new("IK")
ik.target, ik.pole_target = target, pole
ik.chain_count, ik.use_stretch = 2, False

# The pole angle decides the roll of the chain: keep the one that brings the
# elbow closest to the pole at the temple.
scene.frame_set(TEMPLE_IN)
best = None
for angle in (-180, -135, -90, -45, 0, 45, 90, 135):
    ik.pole_angle = radians(angle)
    bpy.context.view_layer.update()
    d = (wpos("RightForeArm") - pole.matrix_world.translation).length
    if best is None or d < best[1]:
        best = (angle, d)
ik.pole_angle = radians(best[0])
print("POLE_ANGLE", best[0], "elbow-to-pole", round(best[1], 3))

# ------------------------------------------------------------ bake the arm

bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.mode_set(mode="POSE")
bpy.ops.nla.bake(frame_start=1, frame_end=FRAMES, step=1, only_selected=False,
                 visual_keying=True, clear_constraints=True, use_current_action=False,
                 bake_types={"POSE"})
bpy.ops.object.mode_set(mode="OBJECT")
for o in (target, pole):
    bpy.data.objects.remove(o, do_unlink=True)

# ------------------------------------------------------------ hand and grip

FINGERS = ("Index", "Middle", "Ring", "Pinky")


def hand_frame():
    """World directions of the right hand: toward the fingers, toward the thumb."""
    wrist = wpos("RightHand")
    knuckles = (wpos("RightHandIndex1") + wpos("RightHandPinky1")) / 2
    fingers = (knuckles - wrist).normalized()
    thumb = wpos("RightHandThumb1") - wrist
    thumb = (thumb - fingers * thumb.dot(fingers)).normalized()
    return fingers, thumb


def palm_side():
    """Unit vector pointing from the back of the hand to the palm."""
    wrist = wpos("RightHand")
    a = wpos("RightHandIndex1") - wrist
    b = wpos("RightHandPinky1") - wrist
    n = a.cross(b).normalized()
    thumb_tip = wpos("RightHandThumb2")
    return n if n.dot(thumb_tip - wrist) > 0 else -n


def basis(x, y):
    z = x.cross(y).normalized()
    y = z.cross(x).normalized()
    return Matrix((x, y, z)).transposed()


def set_world_rotation(bone, rotation):
    """Rotate a pose bone in world space about its own head, then key it."""
    arm_space = world.inverted() @ (world @ bone.matrix)
    loc = arm_space.translation
    rot_arm = (world.to_3x3().inverted() @ rotation @ world.to_3x3() @ arm_space.to_3x3()).normalized()
    bone.matrix = Matrix.Translation(loc) @ rot_arm.to_4x4()
    bpy.context.view_layer.update()
    bone.keyframe_insert("rotation_quaternion")


# Curl direction of each finger bone: the local axis sign that moves the
# fingertip toward the palm.
scene.frame_set(1)
bpy.context.view_layer.update()
curl_axis = {}
palm = palm_side()
for f in FINGERS + ("Thumb",):
    bone = pb[f"RightHand{f}1"]
    tip_name = f"RightHand{f}2"
    base_q = bone.rotation_quaternion.copy()
    before = wpos(tip_name)
    best = None
    for axis in ((1, 0, 0), (0, 0, 1), (0, 1, 0)):
        bone.rotation_quaternion = base_q @ Quaternion(axis, radians(30))
        bpy.context.view_layer.update()
        score = (wpos(tip_name) - before).dot(palm)
        if best is None or abs(score) > abs(best[1]):
            best = (axis, score)
    bone.rotation_quaternion = base_q
    bpy.context.view_layer.update()
    sign = 1 if best[1] > 0 else -1
    curl_axis[f] = Vector(best[0]) * sign
print("CURL_AXES", {k: tuple(v) for k, v in curl_axis.items()})

CURL = {  # degrees at full grip, per segment; the index stays on the trigger
    "Index": (40, 30), "Middle": (75, 85), "Ring": (80, 85), "Pinky": (80, 80),
    "Thumb": (25, 35),
}

for frame in range(1, FRAMES + 1):
    scene.frame_set(frame)
    bpy.context.view_layer.update()

    # Hand orientation: idle until the gun is lifted, then fingers toward
    # the head (+X) and thumb up at the temple, then back.
    w = ramp(frame, 12, TEMPLE_IN, TEMPLE_OUT, 38)
    if w > 0:
        fingers, thumb = hand_frame()
        current = basis(fingers, thumb)
        # Keep index above pinky so the fingers line up along the Nagant grip.
        # The hand stays further out; its knuckles surround the handle.
        wanted = basis(Vector((1, 0.15, 0)).normalized(),
                       Vector((0, 0, float(os.environ.get("REVOLVER_THUMB_Z", "1")))))
        full = wanted @ current.inverted()
        partial = Quaternion().slerp(full.to_quaternion(), w).to_matrix()
        set_world_rotation(pb["RightHand"], partial)

    # Grip: closed from the grab until the gun is back on the table.
    g = ramp(frame, 7, GRAB + 1, RELEASE - 1, RELEASE + 3)
    trigger = ramp(frame, 26, 28, 29, 31)
    for f, (a1, a2) in CURL.items():
        for seg, angle in ((1, a1), (2, a2)):
            bone = pb[f"RightHand{f}{seg}"]
            base = bone.rotation_quaternion.copy()
            if f == "Index":
                angle += (10 if seg == 1 else 25) * trigger
            bone.rotation_quaternion = base @ Quaternion(curl_axis[f], radians(angle * g))
            bone.keyframe_insert("rotation_quaternion")

baked = body.animation_data.action
baked.name = "ANIM_Seated_Revolver"
body.name = "Root"
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / "seated_revolver.blend"))
print("SAVED", OUTPUT / "seated_revolver.blend")

# ------------------------------------------------------------ export

bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
bpy.context.view_layer.objects.active = body
for name, start, end in (("seated_revolver", 1, FRAMES),
                         ("seated_revolver_take", 1, 26),
                         ("seated_revolver_fire", 26, FRAMES)):
    scene.frame_start, scene.frame_end = start, end
    scene.frame_set(start)
    bpy.ops.export_scene.fbx(
        filepath=str(OUTPUT / f"{name}.fbx"), use_selection=True,
        object_types={"ARMATURE"}, add_leaf_bones=False, bake_anim=True,
        bake_anim_use_all_bones=True, bake_anim_use_nla_strips=False,
        bake_anim_use_all_actions=False, bake_anim_step=1.0)
    print("EXPORTED", name, start, end)
scene.frame_start, scene.frame_end = 1, FRAMES
