"""Show the actual seated pose with the Nagant fitted to the right palm."""

from math import radians
import os
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


root = Path("C:/Users/ingam/OneDrive/Documents/fate-games")
out = root / "art/animations"
bpy.ops.wm.open_mainfile(filepath=os.environ.get("REVOLVER_BLEND", str(out / "seated_revolver.blend")))
body = next(o for o in bpy.data.objects if o.type == "ARMATURE")
mesh = next(o for o in bpy.data.objects if o.type == "MESH")
bpy.ops.import_scene.fbx(filepath="C:/nanos-adk/Saved/CodexAnimation/nagant.fbx")
gun = next(o for o in bpy.context.selected_objects if o.name == "SM_Nagant_M1895")
for obj in list(bpy.context.selected_objects):
    if obj != gun:
        bpy.data.objects.remove(obj, do_unlink=True)
gun.color = (0.8, 0.18, 0.06, 1)

scene = bpy.context.scene
scene.frame_set(23)
world = body.matrix_world
pb = body.pose.bones
def pos(name):
    return world @ pb[name].head

socket = world @ pb["RightHandProp"].matrix
base = gun.matrix_world.copy()
rotate = Matrix.Rotation(radians(15), 4, "Y") @ Matrix.Rotation(radians(90), 4, "Z")
grip = Vector((0, 6.5, -4.5))
muzzle = Vector((0, -11.7, 7.0))
knuckles = (pos("RightHandIndex1") + pos("RightHandPinky1")) / 2
palm = (pos("RightHand") + knuckles) / 2
gun_offset = Vector((float(os.environ.get("REVOLVER_GRIP_X", "0")),
                     float(os.environ.get("REVOLVER_GRIP_Y", "0")),
                     float(os.environ.get("REVOLVER_GRIP_Z", "0"))))
gun.matrix_world = Matrix.Translation(palm + gun_offset - (rotate @ base @ grip)) @ rotate @ base
print("FIT palm", tuple(round(v, 4) for v in palm))
muzzle_world = gun.matrix_world @ muzzle
print("FIT muzzle", tuple(round(v, 4) for v in muzzle_world))
print("FIT grip", tuple(round(v, 4) for v in gun.matrix_world @ grip))
print("FIT socket", tuple(round(v, 4) for v in socket.translation))
depsgraph = bpy.context.evaluated_depsgraph_get()
evaluated = mesh.evaluated_get(depsgraph)
vertices = [evaluated.matrix_world @ v.co for v in evaluated.to_mesh().vertices]
head_base = pos("Head")
axis_xy = Vector((head_base.x, head_base.y))
skull = [v for v in vertices if v.z > head_base.z
         and (Vector((v.x, v.y)) - axis_xy).length < 0.16]
temple_z = head_base.z + (max(v.z for v in skull) - head_base.z) * 0.35
band = [v for v in skull if abs(v.z - temple_z) < 0.02]
temple = Vector((min(v.x for v in band),
                 (min(v.y for v in band) + max(v.y for v in band)) / 2 - 0.01,
                 temple_z))
evaluated.to_mesh_clear()
print("FIT temple", tuple(round(v, 4) for v in temple))
print("FIT muzzle_to_temple_cm", round((muzzle_world - temple).length * 100, 2))
assert (muzzle_world - temple).length < 0.02
socket_rigid = Matrix.Translation(socket.translation) @ socket.to_quaternion().to_matrix().to_4x4()
gun_rigid = Matrix.Translation(gun.matrix_world.translation) @ gun.matrix_world.to_quaternion().to_matrix().to_4x4()
relative = socket_rigid.inverted() @ gun_rigid
print("FIT relative location centimeters", tuple(round(v * 100, 2) for v in relative.translation))
print("FIT relative euler degrees", tuple(round(__import__('math').degrees(v), 2) for v in relative.to_euler()))
for finger in ("Index", "Middle", "Ring", "Pinky", "Thumb"):
    for segment in (1, 2, 3):
        name = f"RightHand{finger}{segment}"
        if name not in pb:
            continue
        point = gun.matrix_world.inverted() @ pos(name)
        print("GRIP_BONE", name, tuple(round(v, 2) for v in point))

scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "OBJECT"
scene.render.resolution_x = 900
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
cam_data = bpy.data.cameras.new("FitCamera")
cam = bpy.data.objects.new("FitCamera", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
cam_data.type = "ORTHO"
cam_data.ortho_scale = 0.7
for name, position in (("front", (0, -1.0, 1.57)),
                       ("rear", (0, 0.7, 1.57)),
                       ("side", (-1.0, -0.2, 1.57)),
                       ("top", (-0.15, -0.2, 2.2))):
    cam.location = position
    cam.rotation_euler = (Vector((-0.15, -0.2, 1.53)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(out / f"fit_{name}.png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", scene.render.filepath)
