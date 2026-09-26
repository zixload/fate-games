"""Render four frames for visual QA of the seated revolver gesture."""

from pathlib import Path
import bpy
from mathutils import Vector


output = Path("C:/nanos-adk/Saved/CodexAnimation/preview")
output.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath="C:/Users/ingam/OneDrive/Documents/fate-games/art/animations/seated_revolver.blend")
scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "MATERIAL"
scene.render.resolution_x = 720
scene.render.resolution_y = 720
scene.render.resolution_percentage = 100

camera_data = bpy.data.cameras.new("PreviewCamera")
camera = bpy.data.objects.new("PreviewCamera", camera_data)
scene.collection.objects.link(camera)
scene.camera = camera
camera_data.type = "ORTHO"
camera_data.ortho_scale = 2.2
camera.location = (2.0, -3.2, 1.6)
look = Vector((0, -0.15, 0.9)) - camera.location
camera.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()

for frame in (1, 10, 23, 48):
    scene.frame_set(frame)
    scene.render.filepath = str(output / f"pose_{frame:02}.png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", scene.render.filepath)
