"""Render the Werewolf courtyard kit and role-card proof images."""

from pathlib import Path
import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art" / "werewolf"
bpy.ops.wm.open_mainfile(filepath=str(OUT / "werewolf_courtyard_kit.blend"))
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 16
scene.render.resolution_x = 1350
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.view_settings.view_transform = "AgX"
scene.view_settings.look = "AgX - Medium High Contrast"


def diffuse(name, color):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*color, 1)
    mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = .9
    return mat


ground = diffuse("Preview sandstone floor", (.32,.24,.18))
bpy.ops.mesh.primitive_plane_add(size=200, location=(0,0,-.017))
floor = bpy.context.object
floor.name = "Preview floor only"
floor.data.materials.append(ground)

world = bpy.data.worlds.new("Courtyard dusk")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (.25,.28,.31,1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = .18


def light(name, position, energy, color, size, target=(0,0,0)):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.color = color
    data.shape = "DISK"
    data.size = size
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = position
    obj.rotation_euler = (Vector(target)-obj.location).to_track_quat("-Z","Y").to_euler()
    return obj


light("Moonlit courtyard fill", (2,-1,7), 550, (.56,.76,1), 6)
light("Firelight preview", (0,0,2.4), 340, (1,.36,.13), 2)
light("Back bounce", (-4,3,4), 240, (1,.66,.36), 4)

camera_data = bpy.data.cameras.new("Kit preview camera")
camera = bpy.data.objects.new("Kit preview camera", camera_data)
scene.collection.objects.link(camera)
scene.camera = camera
camera_data.type = "ORTHO"
camera_data.ortho_scale = 8.7
camera.location = (6,-8,7.6)
camera.rotation_euler = (Vector((0,0,.10))-camera.location).to_track_quat("-Z","Y").to_euler()
scene.render.filepath = str(OUT / "werewolf_courtyard_preview.png")
bpy.ops.render.render(write_still=True)
print("RENDERED", scene.render.filepath)

# Isolated contact sheet from the same exported role meshes; no extra art source.
for obj in list(bpy.context.scene.objects):
    if obj.type in ("MESH", "CURVE"):
        obj.hide_render = True

backdrop = diffuse("Preview card backdrop", (.14,.10,.087))
bpy.ops.mesh.primitive_plane_add(size=200, location=(0,0,-.01))
bpy.context.object.name = "Card backdrop"
bpy.context.object.data.materials.append(backdrop)

cards = ["Back", "Villager", "Wolf", "Seer", "Witch", "Hunter",
         "Guard", "Cupid", "LittleGirl"]
for index, role in enumerate(cards):
    group = "SM_WW_RoleCard_" + role
    col = bpy.data.collections[group]
    x = ((index%3)-1)*.14
    y = (1-(index//3))*.19
    for source in col.objects:
        obj = source.copy()
        obj.data = source.data
        bpy.context.collection.objects.link(obj)
        obj.hide_render = False
        obj.location = (source.location.x+x, source.location.y+y, source.location.z)
        obj.name = "CardProof_" + source.name

camera.location = (0,0,2.1)
camera.rotation_euler = (0,0,0)
camera_data.ortho_scale = .56
scene.render.resolution_x = 960
scene.render.resolution_y = 1280
scene.render.filepath = str(OUT / "werewolf_role_cards_preview.png")
bpy.ops.render.render(write_still=True)
print("RENDERED", scene.render.filepath)
