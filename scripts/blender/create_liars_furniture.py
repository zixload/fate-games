"""Create the Liar's Bar table and chair as editable Blender and FBX assets.

Run with the Steam Blender binary in background mode. Geometry uses metres;
the FBX files carry centimetre units for Unreal Engine.
"""

from math import cos, sin, pi
from pathlib import Path
import bpy
from mathutils import Vector


ROOT = Path("C:/Users/ingam/OneDrive/Documents/fate-games")
OUT = ROOT / "art/furniture"
OUT.mkdir(parents=True, exist_ok=True)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.context.scene.unit_settings.system = "METRIC"
bpy.context.scene.unit_settings.scale_length = 1.0


def material(name, color, metallic=0.0, roughness=0.6):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


WALNUT = material("Walnut_Dark", (0.060, 0.028, 0.016), roughness=0.39)
EDGE = material("Walnut_Honey_Edges", (0.15, 0.070, 0.033), roughness=0.43)
FELT = material("Felt_Deep_Teal", (0.009, 0.070, 0.067), roughness=0.92)
LEATHER = material("Leather_Oxblood", (0.17, 0.020, 0.030), roughness=0.66)
LEATHER_EDGE = material("Leather_Seams", (0.095, 0.023, 0.028), roughness=0.75)
BRASS = material("Brass_Aged", (0.58, 0.37, 0.13), metallic=0.78, roughness=0.32)
BRASS_LIGHT = material("Brass_Highlight", (0.84, 0.62, 0.27), metallic=0.72, roughness=0.28)

table_objects = []
chair_objects = []


def add(obj, mat, group):
    obj.data.materials.append(mat)
    group.append(obj)
    return obj


def box(name, location, scale, mat, group, bevel=0.008):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new("Soft machined edges", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.affect = "EDGES"
        obj.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    return add(obj, mat, group)


def cylinder(name, radius, depth, z, vertices, mat, group, bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius,
                                        depth=depth, location=(0, 0, z), rotation=(0, 0, pi / 8))
    obj = bpy.context.object
    obj.name = name
    if bevel:
        mod = obj.modifiers.new("Soft machined edges", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        obj.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    return add(obj, mat, group)


def ring(name, outer, inner, bottom, top, mat, group, sides=8):
    verts = []
    for z in (bottom, top):
        for radius in (outer, inner):
            for i in range(sides):
                angle = pi / 8 + 2 * pi * i / sides
                verts.append((radius * cos(angle), radius * sin(angle), z))
    faces = []
    for i in range(sides):
        j = (i + 1) % sides
        faces.extend(((i, j, sides + j, sides + i),
                      (2 * sides + i, 3 * sides + i, 3 * sides + j, 2 * sides + j),
                      (2 * sides + i, 2 * sides + j, j, i),
                      (sides + i, sides + j, 3 * sides + j, 3 * sides + i)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bevel = obj.modifiers.new("Engraved rim", "BEVEL")
    bevel.width = 0.002
    bevel.segments = 2
    obj.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    return add(obj, mat, group)


def beam(name, start, end, width, depth, mat, group, bevel=0.006):
    a, b = Vector(start), Vector(end)
    center = (a + b) / 2
    obj = box(name, center, (width, depth, (b - a).length), mat, group, bevel)
    obj.rotation_euler = (b - a).to_track_quat("Z", "Y").to_euler()
    return obj


def stud(name, location, radius, mat, group):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=4, radius=radius, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale.z = 0.45
    return add(obj, mat, group)


# Table: 1.68 m across; the broad flat felt keeps the centre clear for cards.
cylinder("Table walnut top", 0.84, 0.060, 0.720, 8, WALNUT, table_objects, 0.008)
ring("Honey border", 0.83, 0.745, 0.752, 0.760, EDGE, table_objects)
ring("Thin brass perimeter", 0.838, 0.826, 0.752, 0.758, BRASS, table_objects)
ring("Brass felt divider", 0.747, 0.737, 0.754, 0.758, BRASS_LIGHT, table_objects)
cylinder("Flat green baize", 0.736, 0.004, 0.756, 8, FELT, table_objects)
ring("Carved apron", 0.76, 0.65, 0.618, 0.686, WALNUT, table_objects)
ring("Apron gold bottom", 0.755, 0.747, 0.620, 0.625, BRASS, table_objects)
ring("Apron gold top", 0.755, 0.747, 0.677, 0.682, BRASS, table_objects)
cylinder("Eight-sided pedestal", 0.165, 0.595, 0.33, 8, WALNUT, table_objects, 0.008)
for z, radius in ((0.095, 0.22), (0.575, 0.185)):
    cylinder("Pedestal collar", radius, 0.035, z, 8, EDGE, table_objects, 0.004)
    ring("Pedestal brass fillet", radius + 0.004, radius - 0.004,
         z + 0.015, z + 0.019, BRASS, table_objects)
for i in range(4):
    angle = pi / 4 + i * pi / 2
    direction = Vector((cos(angle), sin(angle), 0))
    beam("Splayed table foot", direction * 0.12 + Vector((0, 0, 0.15)),
         direction * 0.65 + Vector((0, 0, 0.055)), 0.115, 0.12, WALNUT, table_objects, 0.012)
    box("Brass foot shoe", direction * 0.66 + Vector((0, 0, 0.039)),
        (0.12, 0.12, 0.035), BRASS, table_objects, 0.008)

# Four flat suit markers on the rim, kept away from the actual playing area.
for i in range(4):
    angle = pi / 4 + i * pi / 2
    x, y = 0.787 * cos(angle), 0.787 * sin(angle)
    stud("Brass place stud", (x, y, 0.763), 0.014, BRASS_LIGHT, table_objects)
    for side in (-1, 1):
        a = angle + side * 0.11
        stud("Turquoise place inlay", (0.787 * cos(a), 0.787 * sin(a), 0.763),
             0.006, FELT, table_objects)


# Chair faces +Y. Seat height 46 cm, inner width 49 cm, generous knee space.
box("Seat underframe", (0, 0, 0.426), (0.57, 0.56, 0.085), WALNUT, chair_objects, 0.015)
box("Oxblood cushion", (0, 0.018, 0.486), (0.49, 0.49, 0.060), LEATHER,
    chair_objects, 0.023)
box("Seat piping", (0, 0.018, 0.456), (0.505, 0.505, 0.010), LEATHER_EDGE,
    chair_objects, 0.006)
for x in (-0.235, 0.235):
    for y in (-0.215, 0.205):
        rear = y < 0
        beam("Chair leg", (x * 1.12, y * 1.28, 0.03),
             (x, y, 0.44), 0.075, 0.075, WALNUT, chair_objects)
        box("Brass chair foot", (x * 1.12, y * 1.28, 0.023),
            (0.078, 0.078, 0.045), BRASS, chair_objects, 0.006)
        if rear:
            beam("Back post", (x, -0.22, 0.43), (x * 1.03, -0.285, 1.05),
                 0.072, 0.072, WALNUT, chair_objects, 0.008)
            stud("Back post brass cap", (x * 1.03, -0.285, 1.048),
                 0.028, BRASS, chair_objects)

box("Lower back brace", (0, -0.239, 0.625), (0.49, 0.035, 0.08), EDGE,
    chair_objects, 0.008)
box("Back leather cushion", (0, -0.277, 0.805), (0.465, 0.060, 0.295),
    LEATHER, chair_objects, 0.033)
box("Back cushion piping", (0, -0.291, 0.805), (0.482, 0.030, 0.31),
    LEATHER_EDGE, chair_objects, 0.024)
box("Back top rail", (0, -0.297, 1.014), (0.55, 0.070, 0.085),
    EDGE, chair_objects, 0.020)
box("Back top brass inlay", (0, -0.338, 1.016), (0.38, 0.010, 0.012),
    BRASS_LIGHT, chair_objects, 0.003)
for x in (-0.205, 0.205):
    for z in (0.695, 0.805, 0.915):
        stud("Back cushion tack", (x, -0.313, z), 0.010, BRASS, chair_objects)
    beam("Open armrest support", (x * 1.14, -0.19, 0.42),
         (x * 1.14, -0.19, 0.655), 0.04, 0.04, WALNUT, chair_objects)
    beam("Slim armrest", (x * 1.14, -0.265, 0.66),
         (x * 1.14, 0.16, 0.66), 0.055, 0.055, EDGE, chair_objects, 0.018)
    stud("Armrest brass tip", (x * 1.14, 0.17, 0.66), 0.022,
         BRASS, chair_objects)


def export_group(name, objects):
    # One joined FBX mesh per furniture type. The editable source pieces stay
    # separate in the .blend; Unreal gets a single floor-pivot static mesh.
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        duplicate = obj.copy()
        duplicate.data = obj.data.copy()
        bpy.context.collection.objects.link(duplicate)
        duplicate.select_set(True)
        if obj == objects[0]:
            active = duplicate
    bpy.context.view_layer.objects.active = active
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    combined = bpy.context.object
    combined.name = name
    # Joining keeps world geometry; move the origin to the centre of the floor.
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.ops.export_scene.fbx(
        filepath=str(OUT / f"{name}.fbx"), use_selection=True,
        object_types={"MESH"}, apply_unit_scale=True,
        bake_space_transform=False, axis_forward="-Y", axis_up="Z",
        use_mesh_modifiers=True, add_leaf_bones=False,
        path_mode="AUTO", embed_textures=False,
    )
    print("EXPORTED", OUT / f"{name}.fbx")
    bpy.data.objects.remove(combined, do_unlink=True)


export_group("SM_Liars_Table", table_objects)
export_group("SM_Liars_Chair", chair_objects)

# The source scene keeps both editable objects and a staged four-seat preview.
for obj in chair_objects:
    obj.hide_render = True
for index, angle in enumerate((0, pi / 2, pi, 3 * pi / 2)):
    position = Vector((1.16 * cos(angle), 1.16 * sin(angle), 0))
    yaw = angle + pi / 2
    for obj in chair_objects:
        duplicate = obj.copy()
        duplicate.data = obj.data
        bpy.context.collection.objects.link(duplicate)
        duplicate.hide_render = False
        duplicate.location = position + obj.location
        duplicate.location.xy = position.xy + Vector((
            obj.location.x * cos(yaw) - obj.location.y * sin(yaw),
            obj.location.x * sin(yaw) + obj.location.y * cos(yaw),
        ))
        duplicate.rotation_euler.z += yaw
        duplicate.name = f"Preview_{index + 1}_{obj.name}"

bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "liars_furniture.blend"))
print("SAVED", OUT / "liars_furniture.blend")
