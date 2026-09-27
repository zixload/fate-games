"""Create Creative-rig socks and compact Japanese geta sandals.

The sock uses the licensed Creative kit silhouette. The geta pair is built
here from rounded wood soles, two underside teeth per foot and broad fabric
thongs. All binary outputs stay under ignored art/cosmetics/footwear/.
"""

import json
from math import atan2, pi
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
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


HAUT_CHAUSSETTE = 0.22      # m : mi-mollet, au-dessus des rayures de la texture


def surface_pieds(body):
    """Les faces du pied et du bas de la jambe du corps Creative (sommets lies
    aux os du pied, des orteils et de la jambe), sous HAUT_CHAUSSETTE, en
    coordonnees du monde. 27/09 : l'ancienne chaussette collait une boule
    etiree au bout de la chaussette du kit et n'enveloppait pas le pied."""
    groupes = {g.index for g in body.vertex_groups
               if g.name in ("LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase", "LeftLeg", "RightLeg")}
    mw = body.matrix_world
    garder = set()
    for v in body.data.vertices:
        if (mw @ v.co).z < HAUT_CHAUSSETTE + 0.02 and sum(a.weight for a in v.groups if a.group in groupes) > 0.5:
            garder.add(v.index)
    bm = bmesh.new()
    nouveaux = {}
    for f in body.data.polygons:
        if all(i in garder for i in f.vertices):
            vs = []
            for i in f.vertices:
                if i not in nouveaux:
                    nouveaux[i] = bm.verts.new(mw @ body.data.vertices[i].co)
                vs.append(nouveaux[i])
            try:
                bm.faces.new(vs)
            except ValueError:
                pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0015)
    # Bord du haut net : coupe a HAUT_CHAUSSETTE, le dessus retire.
    geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector((0, 0, HAUT_CHAUSSETTE)),
                           plane_no=Vector((0, 0, 1)), dist=0.0005)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z > HAUT_CHAUSSETTE + 0.0005], context="VERTS")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.normal_update()
    # Decollee de 7 mm : une maille qui epouse le pied sans le traverser (a
    # 4 mm, lissee, la peau passait au travers sur les orteils).
    bmesh.ops.smooth_vert(bm, verts=bm.verts, factor=0.25, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * 0.007
    bm.normal_update()
    return bm


def socks(rig, body):
    result = []
    specs = (
        ("Ivory", (.79, .76, .66), ()),
        ("Charcoal", (.105, .11, .13), ()),
        ("BlackStripe", (.79, .76, .66), (.16, .19)),   # sous le haut a 22 cm
    )
    for suffix, color, stripe_heights in specs:
        bm = surface_pieds(body)
        me = bpy.data.meshes.new("SK_COS_Socks_" + suffix)
        bm.to_mesh(me)
        bm.free()
        obj = bpy.data.objects.new("SK_COS_Socks_" + suffix, me)
        bpy.context.collection.objects.link(obj)
        image = textile_image("T_COS_Socks_" + suffix, color, stripe_heights)
        mat = material("M_COS_Socks_" + suffix, color)
        texture = mat.node_tree.nodes.new("ShaderNodeTexImage")
        texture.image = image
        mat.node_tree.links.new(texture.outputs["Color"],
                                mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
        obj.data.materials.append(mat)
        # Epaisseur vers l'interieur, bord du haut visible comme un revers.
        solid = obj.modifiers.new("Knit thickness", "SOLIDIFY")
        solid.thickness = 0.0025
        solid.offset = -1
        solid.use_rim = True
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=solid.name)
        uv = obj.data.uv_layers.new(name="Cloth_UV")
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
            for loop_index in polygon.loop_indices:
                vert = obj.data.vertices[obj.data.loops[loop_index].vertex_index]
                pos = obj.matrix_world @ vert.co
                side = 1 if pos.x >= 0 else -1
                u = (atan2(pos.y + .015, pos.x - side * .103) / (2 * pi)) % 1
                uv.data[loop_index].uv = (u, max(0, min(1, pos.z / .5)))
        uv.active_render = True
        skin_from_body(obj, body, rig)
        export(rig, obj)
        result.append(obj)
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


SOL_HAUT = 0.030            # m : dessus de la semelle (dents 1,4 cm + semelle 1,6 cm)


def bride(name, points, mat):
    """Un cordon rond qui passe par `points` (brides des geta)."""
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 8
    curve.bevel_depth = .0065
    curve.bevel_resolution = 3
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for node, co in zip(spline.points, points):
        node.co = (co.x, co.y, co.z, 1.0)
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def sur_le_pied(arbre, centre, direction, marge=.006):
    """Point de la peau du pied vu depuis `centre` (dans le pied) dans
    `direction`, decolle de `marge` : la bride suit la surface au lieu de
    la traverser (27/09)."""
    direction = direction.normalized()
    # Rayon lance de l'exterieur vers le pied : il s'arrete sur la vraie peau
    # (depuis l'interieur, il butait sur des faces internes).
    dehors = centre + direction * .25
    hit = arbre.ray_cast(dehors, -direction, .25)[0]
    if hit is None:
        return centre + direction * .05
    return hit + direction * marge


def geta(rig, body):
    amber = material("M_COS_Geta_Hinoki", (.47, .245, .105))
    endgrain = material("M_COS_Geta_Endgrain", (.28, .13, .065))
    fabric = material("M_COS_Geta_Fabric", (.095, .12, .14))
    # En coordonnees du monde : FromObject travaille dans le repere local du
    # corps, en centimetres (echelle 0,01), et les rayons en metres le ratant.
    mw = body.matrix_world
    arbre = BVHTree.FromPolygons([mw @ v.co for v in body.data.vertices],
                                 [tuple(poly.vertices) for poly in body.data.polygons])
    pieces = []
    for label, x in (("L", .103), ("R", -.103)):
        cote = 1 if x > 0 else -1          # exterieur du pied : du cote des x de meme signe
        # 27/09 : bois plus epais (3 cm en tout) et pose sur le sol.
        pieces.append(rounded_box(label + " sole", (x, -.055, .022),
                                  (.150, .300, .016), .005, amber))
        for index, y in enumerate((.045, -.155)):
            pieces.append(rounded_box(label + f" ha {index}", (x, y, .007),
                                      (.140, .026, .014), .004, endgrain))
        # Hanao : un V qui part des deux bords de la semelle a mi-pied, passe
        # sur le cou-de-pied et descend entre le gros orteil et le suivant.
        # Chaque point est pose sur la peau (rayon lance depuis l'interieur).
        interieur = x - cote * .032        # entre les orteils, cote gros orteil
        # Un seul sommet pour les deux branches du V : elles se rejoignent.
        sommet = sur_le_pied(arbre, Vector((x, -.110, .035)), Vector((0, 0, 1)))
        for nom, bord in (("exterieur", 1), ("interieur", -1)):
            pts = [Vector((x + cote * bord * .074, -.035, SOL_HAUT))]
            for k in range(1, 7):
                t = k / 8                      # 0 : bord de la semelle, 1 : sommet
                angle = (1 - t) * 1.35         # du flanc (77 deg) au dessus
                centre = Vector((x, -.035 - .075 * t, .035))
                d = Vector((cote * bord * __import__("math").sin(angle), 0, __import__("math").cos(angle)))
                pts.append(sur_le_pied(arbre, centre, d))
            pts.append(sommet)
            pieces.append(bride(label + " hanao " + nom, pts, fabric))
        # Le cordon du devant : du sommet vers l'entre-orteils, sur la peau.
        pts = [sommet]
        for k in range(1, 6):
            t = k / 6
            centre = Vector((sommet.x + (interieur - sommet.x) * t, sommet.y - .045 * t, .03))
            pts.append(sur_le_pied(arbre, centre, Vector((0, -.35 * t, 1))))
        pts.append(Vector((interieur, -.150, SOL_HAUT)))
        pieces.append(bride(label + " maezubo", pts, fabric))
    bpy.ops.object.select_all(action="DESELECT")
    for piece in pieces:
        piece.select_set(True)
    bpy.context.view_layer.objects.active = pieces[0]
    bpy.ops.object.join()
    obj = pieces[0]
    obj.name = "SK_COS_Geta_Wood"
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
    # Le corps reste visible : on juge l'ajustement sur le pied.
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
    items.append(geta(rig, body))
    render_previews(scene, body, items)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "creative_footwear.blend"))
    (OUT / "manifest.json").write_text(json.dumps({
        "rig": "Creative 43 bones", "items": [item.name for item in items],
        "geta_actor_z_offset_cm": 0,
    }, indent=2), encoding="utf-8")
    print("FOOTWEAR_COMPLETE", [item.name for item in items])


if __name__ == "__main__":
    main()
