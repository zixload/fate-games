"""Render the imported Nagant on the Creative hand socket at the aiming frame."""

from pathlib import Path
from math import pi
import bpy
from mathutils import Matrix, Vector


root = Path("C:/Users/ingam/OneDrive/Documents/fate-games")
output = Path("C:/nanos-adk/Saved/CodexAnimation/preview")
output.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(root / "art/animations/seated_revolver.blend"))
bpy.ops.import_scene.fbx(filepath="C:/nanos-adk/Saved/CodexAnimation/nagant.fbx")
gun = next(o for o in bpy.context.selected_objects if o.name == "SM_Nagant_M1895")
for obj in list(bpy.context.selected_objects):
    if obj != gun:
        bpy.data.objects.remove(obj, do_unlink=True)
body = next(o for o in bpy.data.objects if o.type == "ARMATURE")

scene = bpy.context.scene
scene.frame_set(23)
old_hand_rotation = body.pose.bones["RightHand"].matrix.to_quaternion()
target = bpy.data.objects.new("Test_Wrist_Target", None)
scene.collection.objects.link(target)
target.location = (-0.31, -0.24, 1.53)
ik = body.pose.bones["RightForeArm"].constraints.new("IK")
ik.target = target
ik.chain_count = 2
ik.use_stretch = False
bpy.context.view_layer.update()
hand = body.pose.bones["RightHand"]
hand.matrix = Matrix.Translation(hand.matrix.translation) @ old_hand_rotation.to_matrix().to_4x4()
bpy.context.view_layer.update()
socket = body.matrix_world @ body.pose.bones["RightHandProp"].matrix
gun.matrix_world = socket @ Matrix.Rotation(pi, 4, "Z")
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "OBJECT"
gun.color = (0.8, 0.18, 0.07, 1)
scene.render.resolution_x = 900
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100

camera_data = bpy.data.cameras.new("GripPreviewCamera")
camera = bpy.data.objects.new("GripPreviewCamera", camera_data)
scene.collection.objects.link(camera)
scene.camera = camera
camera_data.type = "ORTHO"
camera_data.ortho_scale = 0.48
for name, position in (
    ("front", (0.15, -1.0, 1.55)),
    ("side", (-0.85, -0.05, 1.53)),
    ("top", (-0.12, -0.15, 2.05)),
):
    camera.location = position
    target = Vector((-0.08, -0.20, 1.49))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(output / f"grip_{name}.png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", scene.render.filepath)

for label, point in (("muzzle", Vector((0, -11.0, 7.0))),
                     ("grip", Vector((0, 8.0, -4.0)))):
    print("LANDMARK", label, tuple(round(v, 4) for v in gun.matrix_world @ point))
