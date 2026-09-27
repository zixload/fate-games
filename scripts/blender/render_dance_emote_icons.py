"""Render compact preview icons from the retargeted Creative dance clips."""

from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art/animations/dances"
DEST = ROOT / "Packages/fate-games/Client/emotes/img"
DEST.mkdir(parents=True, exist_ok=True)
CLIPS = (
    ("ANIM_Dance_StepHipHop", "step", 35),
    ("ANIM_Dance_Chicken", "chicken", 40),
    ("ANIM_Dance_WaveHipHop", "wave", 100),
    ("ANIM_Dance_TutHipHop", "tut", 90),
    ("ANIM_Dance_BootyHipHop", "booty", 50),
    ("ANIM_Dance_Salsa", "salsa", 80),
    ("ANIM_Dance_Jazz", "jazz", 45),
)

for name, short, frame in CLIPS:
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE / (name + ".blend")))
    scene = bpy.context.scene
    scene.frame_set(frame)
    parent = bpy.data.objects["SK_Animations"]
    parent.scale = (.008, .008, .008)
    proxy = bpy.data.objects["SK_Animations.001"]
    material = bpy.data.materials.new("Warm clay emote preview")
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (.72, .55, .36, 1)
    shader.inputs["Roughness"].default_value = .9
    proxy.data.materials.clear()
    proxy.data.materials.append(material)

    world = bpy.data.worlds.new("Emote preview")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (
        .42, .38, .32, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = .6
    scene.world = world
    for position, energy in (((-2, -3, 4), 420), ((2, 1, 3), 300)):
        light = bpy.data.lights.new("Emote softbox", "AREA")
        light.energy = energy
        light.shape = "DISK"
        light.size = 3
        obj = bpy.data.objects.new("Emote softbox", light)
        scene.collection.objects.link(obj)
        obj.location = position
        obj.rotation_euler = (
            Vector((0, 0, .65)) - obj.location).to_track_quat(
                "-Z", "Y").to_euler()

    camera_data = bpy.data.cameras.new("Emote camera")
    camera = bpy.data.objects.new("Emote camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.location = (0, -3.2, 1.2)
    camera.rotation_euler = (
        Vector((0, 0, .65)) - camera.location).to_track_quat(
            "-Z", "Y").to_euler()
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 1.7
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 10
    scene.render.film_transparent = True
    scene.render.resolution_x = 320
    scene.render.resolution_y = 320
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = str(DEST / (short + ".png"))
    bpy.ops.render.render(write_still=True)
    print("DANCE_ICON", short, scene.render.filepath)
