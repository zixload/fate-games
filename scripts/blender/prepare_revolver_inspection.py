"""Create a Blender scene with the Nagant following the animated hand socket.

This scene is for visual inspection only. The two gameplay FBX files export the
armature alone; nanos world attaches the gun as a separate prop.
"""

from math import radians
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


output = Path("C:/Users/ingam/OneDrive/Documents/fate-games/art/animations")
bpy.ops.wm.open_mainfile(filepath=str(output / "seated_revolver.blend"))
bpy.ops.import_scene.fbx(filepath="C:/nanos-adk/Saved/CodexAnimation/nagant.fbx")
gun = next(o for o in bpy.context.selected_objects if o.name == "SM_Nagant_M1895")
for obj in list(bpy.context.selected_objects):
    if obj != gun:
        bpy.data.objects.remove(obj, do_unlink=True)
body = next(o for o in bpy.data.objects if o.type == "ARMATURE")
scene = bpy.context.scene
scene.frame_set(23)
bpy.context.view_layer.update()

def bone(name):
    return body.matrix_world @ body.pose.bones[name].head

knuckles = (bone("RightHandIndex1") + bone("RightHandPinky1")) / 2
palm = (bone("RightHand") + knuckles) / 2
base = gun.matrix_world.copy()
rotation = Matrix.Rotation(radians(15), 4, "Y") @ Matrix.Rotation(radians(90), 4, "Z")
grip = Vector((0, 6.5, -4.5))
muzzle = Vector((0, -11.7, 7.0))
fitted = Matrix.Translation(palm + Vector((0.05, 0.03, 0)) - rotation @ base @ grip) @ rotation @ base

gun.parent = body
gun.parent_type = "BONE"
gun.parent_bone = "RightHandProp"
gun.matrix_world = fitted
bpy.context.view_layer.update()
at_temple = gun.matrix_world @ muzzle
if (at_temple - fitted @ muzzle).length > 0.005:
    raise RuntimeError("Gun changed position when attached to RightHandProp")

scene.frame_set(28)
bpy.context.view_layer.update()
on_recoil = gun.matrix_world @ muzzle
if (on_recoil - at_temple).length < 0.02:
    raise RuntimeError("Gun did not follow the recoil animation")

scene.frame_set(23)
gun.color = (0.8, 0.18, 0.06, 1)
gun.name = "Nagant_Reference_Follows_RightHandProp"
bpy.ops.wm.save_as_mainfile(filepath=str(output / "seated_revolver_inspection.blend"))
print("INSPECTION saved", output / "seated_revolver_inspection.blend")
print("INSPECTION muzzle at temple", tuple(round(v, 4) for v in at_temple))
print("INSPECTION recoil travel cm", round((on_recoil - at_temple).length * 100, 2))
