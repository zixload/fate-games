"""Build five Creative T-shirt tiers from two approved base silhouettes.

Common reuses the kit's existing SK_T_Shirt_009. The frayed shirt preserves
the earlier body-fitted prototype. Three new designs use the kit shirt's UVs
and transfer Creative body weights to the same 43-bone rig. All generated
media stays under ignored art/cosmetics/tshirts.

Run: blender -b --python scripts/blender/create_creative_tshirt_rarities.py
"""

import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector
from mathutils.kdtree import KDTree


PROJECT = Path(__file__).resolve().parents[2]
OUT = PROJECT / "art" / "cosmetics" / "tshirts"
BASE_BLEND = PROJECT / "art" / "cosmetics" / "creative_modular_base.blend"
FRAYED_BLEND = PROJECT / "art" / "cosmetics" / "prototype_fitted_top.blend"
RIG_NAME = "Root"
BODY_NAME = "SK_Animations.001"
COLORS = {
    "Rare_Compass": {
        "base": (.21, .32, .28), "trim": (.105, .18, .16),
        "accent": (.83, .62, .32), "name": "T-shirt Éclaireur",
    },
    "Epic_Eclipse": {
        "base": (.17, .14, .27), "trim": (.075, .065, .15),
        "accent": (.58, .56, .86), "name": "T-shirt Éclipse",
    },
    "Legendary_Sun": {
        "base": (.31, .12, .14), "trim": (.13, .065, .09),
        "accent": (.98, .65, .20), "name": "T-shirt Soleil d'or",
    },
}


def set_image_material(name, image):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = .87
    tex = material.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    material.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return material


def paint_design(kind, x, y, z, color, palette):
    """Paint broad textile motifs, not floating curves or geometry strips."""
    front = y < -.002
    accent = np.array(palette["accent"], dtype=np.float32)
    trim = np.array(palette["trim"], dtype=np.float32)
    if kind == "Rare_Compass":
        # A broad shoulder yoke and a woven diamond insignia.
        yoke = front & (z > 1.325) & (np.abs(x) < .26)
        color[yoke] = color[yoke] * .50 + trim * .50
        dx = x / .078
        dz = (z - 1.205) / .078
        diamond = np.abs(dx) + np.abs(dz)
        insignia = front & (diamond < .93) & (diamond > .69)
        middle = front & (np.abs(dx) < .12) & (np.abs(dz) < .42)
        middle |= front & (np.abs(dz) < .12) & (np.abs(dx) < .42)
        color[insignia | middle] = accent
    elif kind == "Epic_Eclipse":
        # An eclipse medallion cut into the cloth color and one wide V band.
        band = front & (np.abs(z - (1.285 - .18 * np.abs(x))) < .022)
        color[band] = color[band] * .35 + accent * .65
        radius = np.sqrt((x / .072) ** 2 + ((z - 1.195) / .072) ** 2)
        ring = front & (radius > .70) & (radius < .96)
        crescent = front & (radius < .55) & (((x + .021) / .045) ** 2 + ((z - 1.195) / .045) ** 2 > .84)
        color[ring | crescent] = accent
    elif kind == "Legendary_Sun":
        # Sun disk, eight shaped rays, and a thick woven V-neck chevron.
        dx = x / .074
        dz = (z - 1.185) / .074
        radius = np.sqrt(dx * dx + dz * dz)
        angle = np.arctan2(dz, dx)
        sun = front & (radius < .54)
        rays = front & (radius > .63) & (radius < .99) & (np.cos(8 * angle) > .81)
        color[sun | rays] = accent
        band = front & (np.abs(z - (1.325 - .14 * np.abs(x))) < .018)
        color[band] = color[band] * .20 + accent * .80
    return color


def paint_texture(shirt, original_atlas, kind, palette):
    width = height = 2048
    pixels = np.ones((height, width, 4), dtype=np.float32)
    pixels[:, :, :3] = palette["base"]
    painted = np.zeros((height, width), dtype=np.bool_)
    mesh = shirt.data
    mesh.calc_loop_triangles()
    uv_data = mesh.uv_layers.active.data
    base = np.array(palette["base"], dtype=np.float32)
    trim = np.array(palette["trim"], dtype=np.float32)
    for triangle in mesh.loop_triangles:
        uv = np.array([uv_data[i].uv[:] for i in triangle.loops], dtype=np.float32)
        xy = uv * (width - 1, height - 1)
        positions = np.array([(shirt.matrix_world @ mesh.vertices[i].co)[:]
                              for i in triangle.vertices], dtype=np.float32)
        xmin = max(0, int(np.floor(np.min(xy[:, 0]))))
        xmax = min(width - 1, int(np.ceil(np.max(xy[:, 0]))))
        ymin = max(0, int(np.floor(np.min(xy[:, 1]))))
        ymax = min(height - 1, int(np.ceil(np.max(xy[:, 1]))))
        if xmax < xmin or ymax < ymin:
            continue
        denominator = ((xy[1, 1] - xy[2, 1]) * (xy[0, 0] - xy[2, 0]) +
                       (xy[2, 0] - xy[1, 0]) * (xy[0, 1] - xy[2, 1]))
        if abs(denominator) < .00001:
            continue
        yy, xx = np.mgrid[ymin:ymax + 1, xmin:xmax + 1]
        a = ((xy[1, 1] - xy[2, 1]) * (xx - xy[2, 0]) +
             (xy[2, 0] - xy[1, 0]) * (yy - xy[2, 1])) / denominator
        b = ((xy[2, 1] - xy[0, 1]) * (xx - xy[2, 0]) +
             (xy[0, 0] - xy[2, 0]) * (yy - xy[2, 1])) / denominator
        c = 1 - a - b
        mask = (a >= -.002) & (b >= -.002) & (c >= -.002)
        if not np.any(mask):
            continue
        px = xx[mask]
        py = yy[mask]
        local = a[mask, None] * positions[0] + b[mask, None] * positions[1] + c[mask, None] * positions[2]
        x, y, z = local[:, 0], local[:, 1], local[:, 2]
        shade = np.clip(.89 + .10 * np.maximum(0, -y) + .04 * (z - .9), .84, 1.03)
        weave = .014 * np.sin(px * 1.7) * np.sin(py * 1.9)
        cloth = base[None, :] * (shade + weave)[:, None]
        edge = ((z < .91) | ((z > 1.365) & (np.abs(x) < .19)) |
                ((np.abs(x) > .265) & (z < 1.30)))
        cloth[edge] = cloth[edge] * .25 + trim * .75
        cloth = paint_design(kind, x, y, z, cloth, palette)
        pixels[py, px, :3] = np.clip(cloth, 0, 1)
        pixels[py, px, 3] = 1
        painted[py, px] = True
    # Extrude UV island colors into the empty margin for clean mipmaps/seams.
    for _ in range(7):
        grown = painted.copy()
        for target, source in (
            ((slice(1, None), slice(None)), (slice(None, -1), slice(None))),
            ((slice(None, -1), slice(None)), (slice(1, None), slice(None))),
            ((slice(None), slice(1, None)), (slice(None), slice(None, -1))),
            ((slice(None), slice(None, -1)), (slice(None), slice(1, None))),
        ):
            fill = (~grown[target]) & painted[source]
            pixels[target][fill] = pixels[source][fill]
            grown[target][fill] = True
        painted = grown
    image = bpy.data.images.new("T_COS_TShirt_" + kind, width=width, height=height, alpha=True)
    image.pixels.foreach_set(pixels.ravel())
    image.filepath_raw = str(OUT / (image.name + ".png"))
    image.file_format = "PNG"
    image.save()
    return image


def transfer_skin_weights(garment, body, rig):
    # The OBJ is in metres while the reference body's local mesh is in cm.
    # Comparing matrix_world-transformed positions avoids unit/axis mistakes.
    body.update_from_editmode()
    points = [body.matrix_world @ vertex.co for vertex in body.data.vertices]
    tree = KDTree(len(points))
    for index, point in enumerate(points):
        tree.insert(point, index)
    tree.balance()
    groups = {group.index: group.name for group in body.vertex_groups}
    for vertex in garment.data.vertices:
        point = garment.matrix_world @ vertex.co
        nearby = tree.find_n(point, 5)
        blended = {}
        total = 0.0
        for _location, index, distance in nearby:
            factor = 1.0 / max(distance, .005) ** 2
            total += factor
            for assignment in body.data.vertices[index].groups:
                key = groups[assignment.group]
                blended[key] = blended.get(key, 0.0) + factor * assignment.weight
        for bone_name, weight in blended.items():
            value = weight / total
            if value > .002:
                group = garment.vertex_groups.get(bone_name) or garment.vertex_groups.new(name=bone_name)
                group.add([vertex.index], value, "REPLACE")
    armature = garment.modifiers.new("Creative skeleton", "ARMATURE")
    armature.object = rig
    garment.parent = None
    if not garment.vertex_groups:
        raise RuntimeError("Weight transfer failed")


def reshape(shirt, kind):
    # Restrained silhouette adjustments keep the Creative topology intact.
    for vertex in shirt.data.vertices:
        # The kit OBJ keeps Y vertical; the imported object rotates X by 90°.
        x, height, depth = vertex.co
        if kind == "Rare_Compass":
            waist = max(0, 1 - abs(height - 1.08) / .24)
            vertex.co.x *= 1 - .018 * waist
        elif kind == "Epic_Eclipse":
            hem = max(0, min(1, (1.03 - height) / .16))
            vertex.co.y -= .025 * hem
            vertex.co.x *= 1 + .035 * hem
        elif kind == "Legendary_Sun":
            hem = max(0, min(1, (1.02 - height) / .15))
            vertex.co.y -= .040 * hem
            vertex.co.x *= 1 + .055 * hem
    shirt.data.update()


def unwrap_for_design(shirt):
    # Keep the kit atlas UV for reference, then create full-resolution garment
    # islands for actual textile motifs. The kit UV uses only ~14 horizontal px.
    original = shirt.data.uv_layers.active
    original.name = "Creative_Atlas"
    shirt.data.uv_layers.new(name="Design_UV")
    shirt.data.uv_layers.active = shirt.data.uv_layers["Design_UV"]
    shirt.data.uv_layers["Design_UV"].active_render = True
    bpy.ops.object.select_all(action="DESELECT")
    shirt.select_set(True)
    bpy.context.view_layer.objects.active = shirt
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(island_margin=.02)
    bpy.ops.object.mode_set(mode="OBJECT")


def export_piece(rig, shirt, path):
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    shirt.select_set(True)
    bpy.context.view_layer.objects.active = shirt
    bpy.ops.export_scene.fbx(
        filepath=str(path), use_selection=True, object_types={"ARMATURE", "MESH"},
        add_leaf_bones=False, bake_anim=False, use_mesh_modifiers=True,
        path_mode="AUTO", armature_nodetype="NULL")


def save_render(scene, camera, name, shirt):
    for obj in bpy.data.objects:
        if obj.type == "MESH" and obj.name.startswith("SK_COS_TShirt_"):
            obj.hide_render = obj != shirt
    scene.render.filepath = str(OUT / (name + ".png"))
    bpy.ops.render.render(write_still=True)


def add_frayed():
    with bpy.data.libraries.load(str(FRAYED_BLEND), link=False) as (source, target):
        target.objects = [name for name in source.objects if name == "SK_COS_Top_Tailored_Prototype"]
    garment = target.objects[0]
    if garment is None:
        raise RuntimeError("Approved frayed prototype mesh missing")
    bpy.context.collection.objects.link(garment)
    garment.name = "SK_COS_TShirt_Uncommon_Frayed"
    # The original prototype was created against the same Creative rig.
    rig = bpy.data.objects[RIG_NAME]
    for modifier in garment.modifiers:
        if modifier.type == "ARMATURE":
            modifier.object = rig
    garment.parent = None
    return garment


def main():
    if not BASE_BLEND.is_file() or not FRAYED_BLEND.is_file():
        raise FileNotFoundError("Run prepare_creative_modular_base.py first; keep prototype_fitted_top.blend")
    OUT.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(BASE_BLEND))
    rig = bpy.data.objects[RIG_NAME]
    body = bpy.data.objects[BODY_NAME]
    source_shirt = bpy.data.objects["DESIGN_BASE_T_Shirt_009"]
    source_shirt.hide_render = True
    atlas = bpy.data.images.get("Textures_4.png")
    if atlas is None:
        raise RuntimeError("Creative texture atlas missing")
    scene = bpy.context.scene
    camera = bpy.data.objects["Preview camera"]
    camera.location = (1.5, -3.4, 1.88)
    camera.rotation_euler = (Vector((0, 0, 1.13)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    manifest = [{"tier": "common", "name": "T-shirt Creative", "asset": "my-asset-pack::SK_T_Shirt_009", "source": "kit"}]

    frayed = add_frayed()
    export_piece(rig, frayed, OUT / "SK_COS_TShirt_Uncommon_Frayed.fbx")
    save_render(scene, camera, "Preview_Uncommon_Frayed", frayed)
    manifest.append({"tier": "uncommon", "name": "T-shirt Effiloché",
                     "asset": "my-asset-pack::SK_COS_TShirt_Uncommon_Frayed", "source": "prototype"})

    for kind, palette in COLORS.items():
        shirt = source_shirt.copy()
        shirt.data = source_shirt.data.copy()
        bpy.context.collection.objects.link(shirt)
        shirt.name = "SK_COS_TShirt_" + kind
        shirt.hide_render = False
        shirt.modifiers.clear()
        reshape(shirt, kind)
        unwrap_for_design(shirt)
        image = paint_texture(shirt, atlas, kind, palette)
        shirt.data.uv_layers.remove(shirt.data.uv_layers["Creative_Atlas"])
        shirt.data.materials.clear()
        shirt.data.materials.append(set_image_material("M_COS_TShirt_" + kind, image))
        subdivision = shirt.modifiers.new("Smooth woven cloth", "SUBSURF")
        subdivision.levels = 2
        subdivision.render_levels = 2
        transfer_skin_weights(shirt, body, rig)
        export_piece(rig, shirt, OUT / (shirt.name + ".fbx"))
        save_render(scene, camera, "Preview_" + kind, shirt)
        tier = kind.split("_", 1)[0].lower()
        manifest.append({"tier": tier, "name": palette["name"],
                         "asset": "my-asset-pack::" + shirt.name, "source": "Creative T_Shirt_009"})

    (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    scene.render.filepath = str(OUT / "Preview_Legendary_Sun.png")
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "creative_tshirt_rarities.blend"))
    print("CREATED", len(manifest), "TIERS", OUT)


if __name__ == "__main__":
    main()
