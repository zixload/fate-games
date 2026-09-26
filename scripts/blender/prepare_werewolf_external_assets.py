"""Rebuild the licensed carpet and seven aged zabutons for Unreal.

Requires inspect_werewolf_sources.py once to unpack the user archives into
art/werewolf/source (ignored by Git). No mesh or texture is stored in Git.
"""

from pathlib import Path
import json
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art/werewolf"
SOURCE = OUT / "source"
ZABUTON = SOURCE / "zabuton_7col_v22_2608_en"
CARPET = SOURCE / "carpet"
COLORS = ("Blue", "Brown", "Green", "Purple", "Red", "White", "Yellow")
CARPET_DIAMETER_M = 5.50  # 212 cm seat radius + cushion + visible outer border.


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def descendants(obj):
    for child in obj.children:
        if child.type == "MESH":
            yield child
        yield from descendants(child)


def bounds(objects):
    corners = [obj.matrix_world @ Vector(corner)
               for obj in objects for corner in obj.bound_box]
    return ([min(point[i] for point in corners) for i in range(3)],
            [max(point[i] for point in corners) for i in range(3)])


def textured(name, color_path, normal_path=None, roughness_path=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = .88
    image = nodes.new("ShaderNodeTexImage")
    image.image = bpy.data.images.load(str(color_path), check_existing=True)
    mat.node_tree.links.new(image.outputs["Color"], bsdf.inputs["Base Color"])
    if normal_path:
        normal_image = nodes.new("ShaderNodeTexImage")
        normal_image.image = bpy.data.images.load(str(normal_path), check_existing=True)
        normal_image.image.colorspace_settings.name = "Non-Color"
        normal = nodes.new("ShaderNodeNormalMap")
        normal.inputs["Strength"].default_value = .75
        mat.node_tree.links.new(normal_image.outputs["Color"], normal.inputs["Color"])
        mat.node_tree.links.new(normal.outputs["Normal"], bsdf.inputs["Normal"])
    if roughness_path:
        rough_image = nodes.new("ShaderNodeTexImage")
        rough_image.image = bpy.data.images.load(str(roughness_path), check_existing=True)
        rough_image.image.colorspace_settings.name = "Non-Color"
        mat.node_tree.links.new(rough_image.outputs["Color"], bsdf.inputs["Roughness"])
    return mat


def make_mesh(name, originals, pivot, scale_xy, scale_z, material):
    baked = []
    for source in originals:
        mesh = source.data.copy()
        mesh.transform(source.matrix_world)
        for vertex in mesh.vertices:
            p = vertex.co
            p.x = (p.x - pivot[0]) * scale_xy
            p.y = (p.y - pivot[1]) * scale_xy
            p.z = (p.z - pivot[2]) * scale_z
        mesh.materials.clear()
        mesh.materials.append(material)
        obj = bpy.data.objects.new(name + "_piece", mesh)
        bpy.context.collection.objects.link(obj)
        baked.append(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in baked:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = baked[0]
    bpy.ops.object.join()
    mesh = baked[0]
    mesh.name = name
    # Geometry has been centered around a real floor pivot; object origin = 0.
    mesh.location = (0, 0, 0)
    bpy.ops.export_scene.fbx(
        filepath=str(OUT / f"{name}.fbx"), use_selection=True,
        object_types={"MESH"}, apply_unit_scale=True,
        bake_space_transform=False, axis_forward="-Y", axis_up="Z",
        use_mesh_modifiers=True, path_mode="AUTO", embed_textures=False,
    )
    low, high = bounds([mesh])
    print("ASSET", name, "bounds_cm", [round(v*100, 2) for v in low],
          [round(v*100, 2) for v in high], "polygons", len(mesh.data.polygons))
    return mesh, low, high


clear_scene()
bpy.ops.import_scene.fbx(filepath=str(ZABUTON / "Zabuton_7col_AllMesh_v2.2_2608.fbx"),
                         use_anim=False)
roots = {color: next(o for o in bpy.data.objects
                     if o.type == "EMPTY" and o.name == f"Zabuton_Lowpoly_Aged_{color}")
         for color in COLORS}

metrics = {"zabuton": {}, "carpet": {}, "sources": {
    "zabuton": "zabuton_7col_v22_2608_en.zip",
    "carpet": "carpet.zip",
}}
for color in COLORS:
    original = list(descendants(roots[color]))
    if not original:
        raise RuntimeError(f"No aged meshes for {color}")
    body = next(obj for obj in original if obj.name.startswith("01_Zabuton_Body"))
    body_low, body_high = bounds([body])
    all_low, _ = bounds(original)
    center = ((body_low[0]+body_high[0])/2, (body_low[1]+body_high[1])/2,
              all_low[2])
    color_file = ZABUTON / "Textures" / "Texture_Aged" / f"T_Col_Aged_{color}.png"
    material = textured(f"M_WW_Zabuton_{color}", color_file,
                        ZABUTON / "Textures" / "Normal.png")
    mesh, low, high = make_mesh(f"SM_WW_Zabuton_{color}", original, center,
                                1.0, 1.0, material)
    # Bounds include the centre stitching and loose corner tassels. The load
    # bearing fabric surface is lower than the decorative centre knot.
    metrics["zabuton"][color] = {
        "bounds_cm": [[round(v*100, 3) for v in low],
                      [round(v*100, 3) for v in high]],
        "body_top_cm": round((body_high[2]-all_low[2])*100, 3),
        "center_knot_top_cm": round(high[2]*100, 3),
        "source_texture": str(color_file),
    }
    mesh.hide_render = True

clear_scene()
bpy.ops.import_scene.fbx(filepath=str(CARPET / "source/libraryCarpetFBX.fbx"),
                         use_anim=False)
original = [o for o in bpy.data.objects if o.type == "MESH"]
if len(original) != 1:
    raise RuntimeError(f"Expected one carpet mesh, found {len(original)}")
low, high = bounds(original)
width = max(high[0]-low[0], high[1]-low[1])
scale_xy = CARPET_DIAMETER_M / width
scale_z = .008 / (high[2]-low[2])
center = ((low[0]+high[0])/2, (low[1]+high[1])/2, low[2])
material = textured("M_WW_Carpet",
                    CARPET / "textures/v2_Base_color.png",
                    CARPET / "textures/v2_Normal.png",
                    CARPET / "textures/v2_Roughness.png")
mesh, low, high = make_mesh("SM_WW_Carpet", original, center,
                            scale_xy, scale_z, material)
metrics["carpet"] = {"bounds_cm": [[round(v*100, 3) for v in low],
                                    [round(v*100, 3) for v in high]],
                     "source_scale_xy": scale_xy, "source_scale_z": scale_z}

(OUT / "external_asset_metrics.json").write_text(
    json.dumps(metrics, indent=2), encoding="utf-8")
print("METRICS", OUT / "external_asset_metrics.json")
