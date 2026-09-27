"""Create Creative-rig socks and compact Japanese geta sandals.

The sock uses the licensed Creative kit silhouette. The geta pair is built
here from rounded wood soles, two underside teeth per foot and broad fabric
thongs. All binary outputs stay under ignored art/cosmetics/footwear/.
"""

import json
from math import atan2, pi
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector
from mathutils.kdtree import KDTree


ROOT = Path(__file__).resolve().parents[2]
BASE_BLEND = ROOT / "art/cosmetics/creative_modular_base.blend"
OUT = ROOT / "art/cosmetics/footwear"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE = next(Path("C:/ProgramData/Epic/EpicGamesLauncher/VaultCache/FabLibrary").glob(
    "Creative_Characters_FREE_*/obj/source_extracted/Separate_assets_obj_extracted/Separate_assets_obj"))


def material(name, color, roughness=.85):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    mat.diffuse_color = (*color, 1)
    return mat


def skin_from_body(obj, body, rig):
    tree = KDTree(len(body.data.vertices))
    for v in body.data.vertices:
        tree.insert(body.matrix_world @ v.co, v.index)
    tree.balance()
    names = {group.index: group.name for group in body.vertex_groups}
    for v in obj.data.vertices:
        near = tree.find_n(obj.matrix_world @ v.co, 5)
        weights = {}
        total = 0.0
        for _, index, dist in near:
            influence = 1 / max(dist, .005) ** 2
            total += influence
            for item in body.data.vertices[index].groups:
                name = names[item.group]
                weights[name] = weights.get(name, 0.0) + influence * item.weight
        for name, weight in weights.items():
            w = weight / total
            if w > .002:
                group = obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)
                group.add([v.index], w, "REPLACE")
    mod = obj.modifiers.new("Creative rig", "ARMATURE")
    mod.object = rig


def export(rig, obj):
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.fbx(filepath=str(OUT / (obj.name + ".fbx")),
                             use_selection=True, object_types={"ARMATURE", "MESH"},
                             add_leaf_bones=False, bake_anim=False,
                             use_mesh_modifiers=True, armature_nodetype="NULL")


def textile_image(name, base, stripes):
    size = 1024
    pixels = np.zeros((size, size, 4), dtype=np.float32)
    pixels[:, :, :3] = base
    pixels[:, :, 3] = 1
    # Woven transverse lines are painted into the textile UV, never floated
    # over the mesh as separate tubes.
    for height in stripes:
        row = int(height / .50 * (size - 1))
        pixels[max(0, row - 7):min(size, row + 7), :, :3] = (.055, .055, .062)
    image = bpy.data.images.new(name, width=size, height=size, alpha=False)
    image.pixels.foreach_set(pixels.ravel())
    image.filepath_raw = str(OUT / (name + ".png"))
    image.file_format = "PNG"
    image.save()
    return image


def socks(rig, body):
    before = set(bpy.data.objects)
    bpy.ops.wm.obj_import(filepath=str(SOURCE / "Socks_008.obj"))
    original = next(obj for obj in bpy.data.objects if obj not in before and obj.type == "MESH")
    # The kit's "sock" OBJ ends at the ankle. Complete it with smooth fitted
    # foot sections so this is a full sock rather than two cut-off gaiters.
    feet = []
    for side in (-1, 1):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=40, ring_count=24,
                                             location=(side * .095, -.052, .061))
        foot = bpy.context.object
        foot.name = "Sock foot section"
        foot.scale = (.076, .158, .058)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        for polygon in foot.data.polygons:
            polygon.use_smooth = True
        feet.append(foot)
    bpy.ops.object.select_all(action="DESELECT")
    original.select_set(True)
    for foot in feet:
        foot.select_set(True)
    bpy.context.view_layer.objects.active = original
    bpy.ops.object.join()
    result = []
    specs = (
        ("Ivory", (.79, .76, .66), ()),
        ("Charcoal", (.105, .11, .13), ()),
        ("BlackStripe", (.79, .76, .66), (.29, .33)),
    )
    for suffix, color, stripe_heights in specs:
        obj = original.copy()
        obj.data = original.data.copy()
        bpy.context.collection.objects.link(obj)
        obj.name = "SK_COS_Socks_" + suffix
        obj.data.materials.clear()
        image = textile_image("T_COS_Socks_" + suffix, color, stripe_heights)
        mat = material("M_COS_Socks_" + suffix, color)
        texture = mat.node_tree.nodes.new("ShaderNodeTexImage")
        texture.image = image
        mat.node_tree.links.new(texture.outputs["Color"],
                                mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
        obj.data.materials.append(mat)
        uv = obj.data.uv_layers.new(name="Cloth_UV")
        for polygon in obj.data.polygons:
            for loop_index in polygon.loop_indices:
                vert = obj.data.vertices[obj.data.loops[loop_index].vertex_index]
                pos = obj.matrix_world @ vert.co
                side = 1 if pos.x >= 0 else -1
                u = (atan2(pos.y + .015, pos.x - side * .095) / (2 * pi)) % 1
                uv.data[loop_index].uv = (u, max(0, min(1, pos.z / .5)))
        for layer in list(obj.data.uv_layers):
            if layer != uv:
                obj.data.uv_layers.remove(layer)
        uv.active_render = True
        subdiv = obj.modifiers.new("Smooth knitted surface", "SUBSURF")
        subdiv.levels = 1
        subdiv.render_levels = 1
        skin_from_body(obj, body, rig)
        export(rig, obj)
        result.append(obj)
    bpy.data.objects.remove(original, do_unlink=True)
    return result


def rounded_box(name, location, size, radius, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bevel = obj.modifiers.new("Rounded timber edge", "BEVEL")
    bevel.width = radius
    bevel.segments = 5
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def fabric_strap(name, side, start, end, mat):
    # Widened 3-D ribbon; rounded cross section avoids wire-like decoration.
    points = []
    for t in range(13):
        q = t / 12
        x = start[0] * (1 - q) + end[0] * q
        y = start[1] * (1 - q) + end[1] * q
        z = start[2] * (1 - q) + end[2] * q + .027 * (1 - (2 * q - 1) ** 2)
        points.append((x, y, z))
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 16
    curve.bevel_depth = .011
    curve.bevel_resolution = 4
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for node, co in zip(spline.bezier_points, points):
        node.co = co
        node.handle_left_type = "AUTO"
        node.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    obj.data.materials.append(mat)
    return obj


def geta(rig):
    amber = material("M_COS_Geta_Hinoki", (.47, .245, .105))
    endgrain = material("M_COS_Geta_Endgrain", (.28, .13, .065))
    fabric = material("M_COS_Geta_Fabric", (.095, .12, .14))
    pieces = []
    for label, x in (("L", .095), ("R", -.095)):
        pieces.append(rounded_box(label + " sole", (x, -.055, .046),
                                  (.142, .295, .025), .014, amber))
        for index, y in enumerate((.045, -.155)):
            pieces.append(rounded_box(label + f" ha {index}", (x, y, .021),
                                      (.132, .024, .038), .006, endgrain))
        # The V thong rises over the toes and lands on opposite side rims.
        joint = (x, -.143, .068)
        pieces.append(fabric_strap(label + " inside thong", x,
                                   (x - .06, -.002, .06), joint, fabric))
        pieces.append(fabric_strap(label + " outside thong", x,
                                   (x + .06, -.002, .06), joint, fabric))
    bpy.ops.object.select_all(action="DESELECT")
    for piece in pieces:
        piece.select_set(True)
    bpy.context.view_layer.objects.active = pieces[0]
    bpy.ops.object.join()
    obj = pieces[0]
    obj.name = "SK_COS_Geta_Wood"
    # Set the top of the timber at the Creative bare-foot ground plane. Raising
    # the entire actor 5.8 cm then puts the geta teeth on the world floor.
    for vertex in obj.data.vertices:
        vertex.co.z -= .0585
    # Both sandals follow the respective feet rigidly. Toe articulation is
    # deliberately kept inside the sole instead of bending the timber.
    left = obj.vertex_groups.new(name="LeftFoot")
    right = obj.vertex_groups.new(name="RightFoot")
    for vertex in obj.data.vertices:
        world_x = (obj.matrix_world @ vertex.co).x
        (left if world_x >= 0 else right).add([vertex.index], 1.0, "REPLACE")
    armature = obj.modifiers.new("Creative rig", "ARMATURE")
    armature.object = rig
    export(rig, obj)
    return obj


def render_previews(scene, body, items):
    camera = bpy.data.objects["Preview camera"]
    camera.location = (1.0, -2.4, .70)
    camera.rotation_euler = (Vector((0, -.04, .20)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.ortho_scale = .85
    scene.camera = camera
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    body.hide_render = True
    for item in items:
        for other in items:
            other.hide_render = other != item
        scene.render.filepath = str(OUT / ("Preview_" + item.name + ".png"))
        bpy.ops.render.render(write_still=True)
    body.hide_render = False


def main():
    bpy.ops.wm.open_mainfile(filepath=str(BASE_BLEND))
    scene = bpy.context.scene
    rig = bpy.data.objects["Root"]
    body = bpy.data.objects["SK_Animations.001"]
    items = socks(rig, body)
    items.append(geta(rig))
    render_previews(scene, body, items)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "creative_footwear.blend"))
    (OUT / "manifest.json").write_text(json.dumps({
        "rig": "Creative 43 bones", "items": [item.name for item in items],
        "geta_actor_z_offset_cm": 5.8,
    }, indent=2), encoding="utf-8")
    print("FOOTWEAR_COMPLETE", [item.name for item in items])


if __name__ == "__main__":
    main()
