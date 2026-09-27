"""Prepare the original Creative modular shirt and hair as a Blender design base.

The resulting .blend is a source/reference file, not a game-ready FBX. The
already imported SK_T_Shirt_009 and SK_Hairstyle_male_010 remain the runtime
pieces. Geometry edits require skin weights before skeletal-mesh import.

Run with Blender: blender -b --python prepare_creative_modular_base.py
Optional: -- --source-dir <directory containing T_Shirt_009.obj>
"""

import argparse
import sys
from pathlib import Path

import bpy
from mathutils import Vector


PROJECT = Path(__file__).resolve().parents[2]
OUTPUT = PROJECT / "art" / "cosmetics"
REFERENCE = PROJECT / "art" / "animations" / "seated_card_play.blend"
SOURCE_PATTERN = (
    "Epic/EpicGamesLauncher/VaultCache/FabLibrary/"
    "Creative_Characters_FREE_*/obj/source_extracted/"
    "Separate_assets_obj_extracted/Separate_assets_obj"
)


def arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=Path)
    parser.add_argument("--reference-blend", type=Path, default=REFERENCE)
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])


def source_directory(explicit):
    if explicit:
        candidate = explicit.expanduser().resolve()
        if (candidate / "T_Shirt_009.obj").is_file():
            return candidate
        raise FileNotFoundError(candidate / "T_Shirt_009.obj")
    vault = Path("C:/ProgramData")
    matches = [p for p in vault.glob(SOURCE_PATTERN) if (p / "Textures_4.png").is_file()]
    if not matches:
        raise FileNotFoundError("Creative kit source missing; pass --source-dir")
    return matches[0]


def set_atlas(material, atlas):
    material.use_nodes = True
    nodes = [node for node in material.node_tree.nodes if node.type == "TEX_IMAGE"]
    if not nodes:
        image = material.node_tree.nodes.new("ShaderNodeTexImage")
        bsdf = material.node_tree.nodes.get("Principled BSDF")
        material.node_tree.links.new(image.outputs["Color"], bsdf.inputs["Base Color"])
        nodes = [image]
    for node in nodes:
        node.image = atlas


def import_piece(directory, filename, material):
    bpy.ops.wm.obj_import(filepath=str(directory / filename))
    meshes = [obj for obj in bpy.context.selected_objects if obj.type == "MESH"]
    if len(meshes) != 1:
        raise RuntimeError(f"Expected one mesh in {filename}, got {len(meshes)}")
    obj = meshes[0]
    obj.data.materials.clear()
    obj.data.materials.append(material)
    if not obj.data.uv_layers:
        raise RuntimeError(f"Missing kit UVs: {filename}")
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def aim_at(obj, point):
    obj.rotation_euler = (Vector(point) - obj.location).to_track_quat("-Z", "Y").to_euler()


def render_view(scene, camera, image_name, position, target):
    camera.location = position
    aim_at(camera, target)
    scene.render.filepath = str(OUTPUT / image_name)
    bpy.ops.render.render(write_still=True)


def main():
    args = arguments()
    directory = source_directory(args.source_dir)
    if not args.reference_blend.is_file():
        raise FileNotFoundError(args.reference_blend)
    OUTPUT.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.open_mainfile(filepath=str(args.reference_blend))
    rig = bpy.data.objects["Root"]
    rig.animation_data_clear()
    for bone in rig.pose.bones:
        bone.location = (0, 0, 0)
        bone.rotation_mode = "QUATERNION"
        bone.rotation_quaternion = (1, 0, 0, 0)
        bone.scale = (1, 1, 1)
    body = bpy.data.objects["SK_Animations.001"]
    for obj in bpy.data.objects:
        if obj.type == "MESH" and obj != body:
            obj.hide_render = True
            obj.hide_set(True)

    atlas = bpy.data.images.load(str(directory / "Textures_4.png"), check_existing=True)
    atlas.pack()
    skin_material = bpy.data.materials["M_Color"]
    set_atlas(skin_material, atlas)
    shirt_material = skin_material.copy()
    shirt_material.name = "Creative_TShirt_OriginalAtlas"
    hair_material = skin_material.copy()
    hair_material.name = "Creative_Hair_OriginalAtlas"

    shirt = import_piece(directory, "T_Shirt_009.obj", shirt_material)
    hair = import_piece(directory, "Hairstyle_male_010.obj", hair_material)
    face = import_piece(directory, "Male_emotion_usual_001.obj", skin_material)
    shirt.name = "DESIGN_BASE_T_Shirt_009"
    hair.name = "REFERENCE_Hairstyle_male_010"
    face.name = "REFERENCE_Male_emotion_usual_001"
    shirt["runtime_asset"] = "my-asset-pack::SK_T_Shirt_009"
    hair["runtime_asset"] = "my-asset-pack::SK_Hairstyle_male_010"
    shirt["note"] = "OBJ source has UVs but no skin weights; do not export as worn FBX directly"

    subdivision = shirt.modifiers.new("Preview smooth silhouette", "SUBSURF")
    subdivision.levels = 2
    subdivision.render_levels = 2

    world = bpy.data.worlds.new("Neutral studio")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (.16, .18, .2, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = .7
    bpy.context.scene.world = world
    for name, location, power in (("Key", (2, -3, 4), 750), ("Fill", (-2, -3, 2), 420)):
        light = bpy.data.lights.new(name, "AREA")
        light.energy = power
        light.size = 3
        obj = bpy.data.objects.new(name, light)
        bpy.context.collection.objects.link(obj)
        obj.location = location
        aim_at(obj, (0, 0, 1))

    camera_data = bpy.data.cameras.new("Preview camera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 1.32
    camera = bpy.data.objects.new("Preview camera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene = bpy.context.scene
    scene.camera = camera
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 850
    scene.render.resolution_y = 850
    scene.render.resolution_percentage = 100
    render_view(scene, camera, "creative_base_front.png", (1.5, -3.4, 1.88), (0, 0, 1.13))
    render_view(scene, camera, "creative_base_profile.png", (3.4, 0, 1.75), (0, 0, 1.13))
    render_view(scene, camera, "creative_base_hair.png", (1.15, -2.4, 2.2), (0, 0, 1.64))
    scene.render.filepath = str(OUTPUT / "creative_base_front.png")
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / "creative_modular_base.blend"))
    print("SOURCE", directory)
    print("SHIRT", len(shirt.data.vertices), len(shirt.data.polygons))
    print("HAIR", len(hair.data.vertices), len(hair.data.polygons))
    print("BLEND", OUTPUT / "creative_modular_base.blend")


if __name__ == "__main__":
    main()
