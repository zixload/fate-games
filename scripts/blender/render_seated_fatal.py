"""Render quick front and side checks of a baked seated animation."""

import os
from pathlib import Path

import bpy
from mathutils import Vector


out = Path("C:/Users/ingam/OneDrive/Documents/fate-games/art/animations")
source = os.environ.get("SEATED_PREVIEW_SOURCE", "seated_revolver_fatal")
frames = [int(value) for value in os.environ.get("SEATED_PREVIEW_FRAMES", "28,37,52").split(",")]
bpy.ops.wm.open_mainfile(filepath=str(out / f"{source}.blend"))
scene = bpy.context.scene
body = next(obj for obj in scene.objects if obj.type == "ARMATURE")
camera = bpy.data.objects.new("Fatal_Preview_Camera", bpy.data.cameras.new("Fatal_Preview_Camera"))
scene.collection.objects.link(camera)
scene.camera = camera
camera.data.type = "ORTHO"
camera.data.ortho_scale = 2.5
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "MATERIAL"
scene.render.resolution_x = 640
scene.render.resolution_y = 640
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"

for view, location in (("front", (0, -3.0, 1.45)), ("side", (2.7, -2.5, 1.45))):
    camera.location = location
    camera.rotation_euler = (Vector((0, 0, 1.15)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    for frame in frames:
        scene.frame_set(frame)
        scene.render.filepath = str(out / f"{source}_{view}_{frame}.png")
        bpy.ops.render.render(write_still=True)
        head = body.matrix_world @ body.pose.bones["Head"].head
        print("FATAL_PREVIEW", view, frame, scene.render.filepath, tuple(round(v, 3) for v in head))
