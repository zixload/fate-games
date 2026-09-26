"""Render the four-seat furniture preview without opening the ADK."""

from pathlib import Path
import bpy
from mathutils import Vector


out = Path("C:/Users/ingam/OneDrive/Documents/fate-games/art/furniture")
bpy.ops.wm.open_mainfile(filepath=str(out / "liars_furniture.blend"))
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 24
scene.render.resolution_x = 1440
scene.render.resolution_y = 1000
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = "AgX"
scene.view_settings.look = "AgX - Medium High Contrast"
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(out / "liars_furniture_preview.png")

ground_mat = bpy.data.materials.new("Preview only warm stone")
ground_mat.diffuse_color = (0.09, 0.075, 0.068, 1)
ground_mat.use_nodes = True
ground_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = ground_mat.diffuse_color
ground_mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.002))
bpy.context.object.data.materials.append(ground_mat)

world = bpy.data.worlds.new("Warm room")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.19, 0.16, 0.14, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.2

for name, location, power, color, size in (
    ("Warm key", (1.2, -3.4, 4.5), 750, (1, .74, .48), 3.0),
    ("Cool fill", (-3.0, 0.5, 2.9), 450, (.48, .65, 1), 2.8),
    ("Rim", (1.0, 3.0, 4.0), 650, (1, .68, .34), 2.5),
):
    data = bpy.data.lights.new(name, "AREA")
    data.energy, data.color, data.shape, data.size = power, color, "DISK", size
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector((0, 0, .5)) - obj.location).to_track_quat("-Z", "Y").to_euler()

data = bpy.data.cameras.new("Furniture preview camera")
camera = bpy.data.objects.new("Furniture preview camera", data)
scene.collection.objects.link(camera)
scene.camera = camera
data.type = "ORTHO"
data.ortho_scale = 3.65
camera.location = (3.7, -5.2, 3.9)
camera.rotation_euler = (Vector((0, 0, .46)) - camera.location).to_track_quat("-Z", "Y").to_euler()

bpy.ops.render.render(write_still=True)
print("RENDERED", scene.render.filepath)
