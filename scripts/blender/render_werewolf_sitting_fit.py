"""Render the Creative proxy on the actual licensed carpet and zabuton.

The reference proxy has the Creative skeleton and proportions. Its parent is
scaled to the in-game 0.8; the Z shift is a placement offset, not root motion.
"""

import os
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art/werewolf"
short = os.environ.get("WW_CLIP", "idle")
name = {"idle": "ANIM_WW_Sitting_Idle",
        "lazy": "ANIM_WW_Sitting_Idle_Lazy",
        "dazed": "ANIM_WW_Sitting_Dazed"}[short]
offset = float(os.environ.get("WW_Z_OFFSET", "0.11"))
bpy.ops.wm.open_mainfile(filepath=str(OUT / (name + ".blend")))
scene = bpy.context.scene
creative_parent = bpy.data.objects["SK_Animations"]
creative_parent.scale = (.008, .008, .008)
creative_parent.location.z = offset
proxy = bpy.data.objects["SK_Animations.001"]
proxy_material = bpy.data.materials.new("Creative body fit proxy")
proxy_material.diffuse_color = (.39, .44, .47, 1)
proxy_material.use_nodes = True
proxy_bsdf = proxy_material.node_tree.nodes.get("Principled BSDF")
proxy_bsdf.inputs["Base Color"].default_value = (.39, .44, .47, 1)
proxy_bsdf.inputs["Roughness"].default_value = .8
proxy.data.materials.clear()
proxy.data.materials.append(proxy_material)


def apply_original_texture(imported, name, color, normal, roughness=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = .9
    for file, input_name, is_data in ((color, "Base Color", False),
                                      (normal, "Normal", True),
                                      (roughness, "Roughness", True)):
        if not file:
            continue
        tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(str(file), check_existing=True)
        if is_data:
            tex.image.colorspace_settings.name = "Non-Color"
        if input_name == "Normal":
            node = mat.node_tree.nodes.new("ShaderNodeNormalMap")
            mat.node_tree.links.new(tex.outputs["Color"], node.inputs["Color"])
            mat.node_tree.links.new(node.outputs["Normal"], bsdf.inputs["Normal"])
        else:
            mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs[input_name])
    for obj in imported:
        if obj.type == "MESH":
            obj.data.materials.clear()
            obj.data.materials.append(mat)
    return imported


bpy.ops.import_scene.fbx(filepath=str(OUT / "SM_WW_Carpet.fbx"), use_anim=False)
carpet = list(bpy.context.selected_objects)
apply_original_texture(carpet, "Carpet licensed preview",
    OUT / "source/carpet/textures/v2_Base_color.png",
    OUT / "source/carpet/textures/v2_Normal.png",
    OUT / "source/carpet/textures/v2_Roughness.png")
bpy.ops.import_scene.fbx(filepath=str(OUT / "SM_WW_Zabuton_Red.fbx"), use_anim=False)
cushion = list(bpy.context.selected_objects)
apply_original_texture(cushion, "Aged red zabuton licensed preview",
    OUT / "source/zabuton_7col_v22_2608_en/Textures/Texture_Aged/T_Col_Aged_Red.png",
    OUT / "source/zabuton_7col_v22_2608_en/Textures/Normal.png")
for obj in cushion:
    obj.location.z += .008

ground = bpy.data.materials.new("Test floor warm sand")
ground.diffuse_color = (.39,.28,.17,1)
ground.use_nodes = True
ground.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = ground.diffuse_color
bpy.ops.mesh.primitive_plane_add(size=12, location=(0,0,-.012))
bpy.context.object.data.materials.append(ground)

world = bpy.data.worlds.new("Studio courtyard")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (.32,.31,.29,1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = .4
for loc, power, color, size in (((-1.5,-2.5,3),450,(1,.78,.58),2),
                               ((2,0,2.5),300,(.5,.7,1),2)):
    data = bpy.data.lights.new("Fit light", "AREA")
    data.energy, data.color, data.shape, data.size = power,color,"DISK",size
    obj = bpy.data.objects.new("Fit light", data)
    scene.collection.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = (Vector((0,0,.7))-obj.location).to_track_quat("-Z","Y").to_euler()

camera_data = bpy.data.cameras.new("Fit camera")
camera = bpy.data.objects.new("Fit camera", camera_data)
scene.collection.objects.link(camera)
scene.camera = camera
camera_data.type = "ORTHO"
camera_data.ortho_scale = 2.1
scene.render.engine = "CYCLES"
scene.cycles.samples = 12
scene.render.resolution_x = 750
scene.render.resolution_y = 750
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.view_settings.view_transform = "AgX"

armature = bpy.data.objects["Root"]
first, last = scene.frame_start, scene.frame_end
scene.frame_set(first + (last-first)//2)
for view, loc in (("front", (0,-2.8,1.12)),
                  ("profile", (2.8,0,1.12))):
    camera.location = loc
    camera.rotation_euler = (Vector((0,-.10,.70))-camera.location).to_track_quat("-Z","Y").to_euler()
    scene.render.filepath = str(OUT / f"fit_{short}_{view}.png")
    bpy.ops.render.render(write_still=True)
    print("WW_FIT", short, view, "Z_OFFSET_M", offset,
          "hips", tuple(round(v,3) for v in
                        armature.matrix_world @ armature.pose.bones["Hips"].head),
          scene.render.filepath)
