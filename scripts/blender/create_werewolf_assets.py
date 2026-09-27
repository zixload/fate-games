"""Build the modular Werewolf courtyard kit with Steam Blender.

Run: blender -b -t 4 --python scripts/blender/create_werewolf_assets.py
All sizes are metres; each FBX has a useful local pivot for Unreal.
Preview objects are kept only in the editable .blend, never in exported meshes.
"""

from math import cos, pi, sin
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art" / "werewolf"
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.context.scene.unit_settings.system = "METRIC"
bpy.context.scene.unit_settings.scale_length = 1


def material(name, rgb, metallic=0, roughness=.65, emission=0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*rgb, 1)
        bsdf.inputs["Emission Strength"].default_value = emission
    return mat


SAND = material("WW sandstone ochre", (.51, .33, .18))
STONE = material("WW carved dark stone", (.18, .13, .11))
WALNUT = material("WW smoked walnut", (.10, .048, .026), roughness=.42)
BRASS = material("WW aged brass", (.48, .32, .12), metallic=.75, roughness=.37)
GOLD = material("WW gold highlight", (.81, .57, .23), metallic=.68, roughness=.3)
TURQ = material("WW oxidized turquoise", (.025, .23, .23), metallic=.25)
DARK_TURQ = material("WW woven deep teal", (.018, .088, .094), roughness=.95)
RUST = material("WW oxblood textile", (.30, .045, .046), roughness=.96)
OCHRE = material("WW ochre textile", (.55, .26, .08), roughness=.94)
CREAM = material("WW ivory linen", (.72, .62, .44), roughness=.92)
INK = material("WW charcoal ink", (.046, .043, .047), roughness=.86)
EMBER = material("WW amber ember", (1, .27, .038), roughness=.6, emission=2)
GLASS = material("WW warm amber glass", (.59, .33, .10), roughness=.24, emission=.65)
WOLF = material("WW wolf crimson", (.49, .065, .072), roughness=.64)
SEER = material("WW seer blue", (.075, .31, .39), roughness=.59)

groups = {}


def record(obj, mat, group):
    obj.data.materials.append(mat)
    groups.setdefault(group, []).append(obj)
    return obj


def box(name, loc, dimensions, mat, group, bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new("Soft edges", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        obj.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    return record(obj, mat, group)


def cyl(name, radius, depth, z, mat, group, sides=12, loc=(0, 0), bevel=0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=radius,
                                        depth=depth, location=(loc[0], loc[1], z))
    obj = bpy.context.object
    obj.name = name
    if bevel:
        mod = obj.modifiers.new("Soft rim", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        obj.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    return record(obj, mat, group)


def ring(name, outer, inner, bottom, top, mat, group, sides=16):
    verts = []
    for z in (bottom, top):
        for r in (outer, inner):
            for i in range(sides):
                a = 2 * pi * i / sides + pi / sides
                verts.append((r * cos(a), r * sin(a), z))
    faces = []
    for i in range(sides):
        j = (i + 1) % sides
        faces.extend(((i, j, sides + j, sides + i),
                      (2*sides+i, 2*sides+j, 3*sides+j, 3*sides+i),
                      (i, 2*sides+i, 2*sides+j, j),
                      (sides+i, sides+j, 3*sides+j, 3*sides+i)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return record(obj, mat, group)


def beam(name, a, b, width, mat, group, bevel=.003):
    a, b = Vector(a), Vector(b)
    obj = box(name, (a+b)/2, (width, width, (b-a).length), mat, group, bevel)
    obj.rotation_euler = (b-a).to_track_quat("Z", "Y").to_euler()
    return obj


def sphere(name, loc, scale, mat, group, segments=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=6, radius=1,
                                         location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    return record(obj, mat, group)


def path(name, points, thickness, mat, group, cyclic=False):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = thickness
    curve.bevel_resolution = 1
    poly = curve.splines.new("POLY")
    poly.points.add(len(points)-1)
    for node, xyz in zip(poly.points, points):
        node.co = (*xyz, 1)
    poly.use_cyclic_u = cyclic
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    return record(obj, mat, group)


# The centre is clear of tall solids. Embers are static; flame/light belongs in Unreal.
G = "SM_WW_Firepit"
cyl("Recessed charcoal bowl", .52, .13, .12, STONE, G, 12, bevel=.01)
ring("Carved octagonal stone wall", .69, .47, .035, .32, SAND, G, 8)
ring("Inner soot lip", .50, .455, .29, .33, STONE, G, 8)
ring("Bronze top fillet", .695, .675, .319, .329, BRASS, G, 8)
ring("Low stone plinth", .77, .66, .002, .058, STONE, G, 8)
for i in range(8):
    a = 2*pi*i/8 + pi/8
    x, y = .58*cos(a), .58*sin(a)
    box("Sandstone incised tile", (x, y, .345), (.13, .012, .012), BRASS, G, .002).rotation_euler.z = a + pi/2
for a in (pi/5, pi/5+pi/2, pi/5+pi):
    start = (-.34*cos(a), -.34*sin(a), .22)
    end = (.34*cos(a), .34*sin(a), .22)
    beam("Charred wood log", start, end, .10, WALNUT, G, .01)
for i in range(13):
    a = i*2.39996
    r = .08 + .31*((i*7) % 11)/11
    sphere("Low ember", (r*cos(a), r*sin(a), .23),
           (.018+.009*(i%3), .016, .012), EMBER, G, 8)

# Optional day/night switch: this is a separate static mesh above the embers.
# It stays low enough to preserve every player's view across the circle.
G = "SM_WW_Flame"
for i in range(7):
    a = 2*pi*i/7
    r = .04 + .18*(i%3)/2
    x, y = r*cos(a), r*sin(a)
    height = .30 + .08*(i%3)
    side = .095 if i%2 else .075
    verts = [
        (x-side,y-.018,.23), (x+side,y-.018,.23),
        (x+side,y+.018,.23), (x-side,y+.018,.23),
        (x-side*.65,y-.015,.23+height*.53),
        (x+side*.55,y-.015,.23+height*.53),
        (x+side*.55,y+.015,.23+height*.53),
        (x-side*.65,y+.015,.23+height*.53),
        (x+.03,y,.23+height),
    ]
    faces = [(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),
             (4,5,8),(5,6,8),(6,7,8),(7,4,8)]
    mesh = bpy.data.meshes.new("Faceted flame tongue")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("Faceted flame tongue", mesh)
    bpy.context.collection.objects.link(obj)
    record(obj, EMBER if i%2 else GOLD, G)

# Circular rug has no baked seat count. Seat markers can be placed at 8–16 angles.
G = "SM_WW_Rug"
cyl("Main teal weave", 2.42, .018, .011, DARK_TURQ, G, 48)
ring("Oxblood outer braid", 2.48, 2.37, .012, .023, RUST, G, 48)
ring("Sandstone inner border", 2.29, 2.25, .019, .026, CREAM, G, 48)
ring("Turquoise ring", 2.19, 2.16, .020, .026, TURQ, G, 48)
ring("Centre clear zone", .90, .88, .020, .026, OCHRE, G, 32)
for i in range(32):
    a = i*2*pi/32
    x, y = 2.31*cos(a), 2.31*sin(a)
    glyph = box("Angular woven border motif", (x, y, .026),
                (.078, .038, .004), GOLD if i%4 == 0 else OCHRE, G, .001)
    glyph.rotation_euler.z = a + pi/4
for i in range(96):
    a = i*2*pi/96
    beam("Short woven fringe", (2.48*cos(a), 2.48*sin(a), .012),
         (2.58*cos(a), 2.58*sin(a), .008), .007, CREAM if i%2 else RUST, G, 0)

for suffix, textile in (("Oxblood", RUST), ("Turquoise", TURQ), ("Ochre", OCHRE)):
    G = "SM_WW_Cushion_" + suffix
    box("Firm floor cushion", (0, 0, .102), (.60, .56, .17), textile, G, .07)
    box("Piped lower edge", (0, 0, .045), (.612, .572, .022), CREAM, G, .010)
    for x in (-.23, .23):
        beam("Textile seam", (x, -.17, .186), (x, .17, .186), .004, GOLD, G, 0)
    for x, y in ((-.23,-.19), (.23,-.19),(-.23,.19),(.23,.19)):
        sphere("Tucked corner stitch", (x,y,.17), (.013,.013,.005), GOLD, G, 8)
    for side in (-1, 1):
        for i in range(5):
            y = -.17 + i*.085
            beam("Short side tassel", (side*.30,y,.075),
                 (side*.37,y,.042), .009, CREAM, G, 0)

G = "SM_WW_SeatMarker"
cyl("Flat place medallion", .13, .009, .005, RUST, G, 16)
ring("Bronze embroidered edge", .132, .114, .008, .013, BRASS, G, 16)
for i in range(8):
    a = 2*pi*i/8
    sphere("Turquoise stitch", (.096*cos(a), .096*sin(a), .013),
           (.010,.010,.003), TURQ, G, 8)
for a in (0, pi/2):
    beam("Compass rose line", (-.061*cos(a),-.061*sin(a),.013),
         (.061*cos(a),.061*sin(a),.013), .008, GOLD, G, 0)

G = "SM_WW_Lantern"
cyl("Lantern foot", .15, .035, .022, BRASS, G, 10, bevel=.004)
cyl("Lower ventilated collar", .125, .047, .068, WALNUT, G, 10, bevel=.004)
cyl("Amber glowing core", .083, .27, .228, GLASS, G, 10)
ring("Lantern lower frame", .13, .10, .095, .12, BRASS, G, 10)
ring("Lantern upper frame", .13, .10, .346, .37, BRASS, G, 10)
for i in range(10):
    a = 2*pi*i/10
    beam("Open bronze cage bar", (.12*cos(a),.12*sin(a),.11),
         (.12*cos(a),.12*sin(a),.36), .014, BRASS, G, .002)
cyl("Lantern roof", .17, .035, .39, WALNUT, G, 10, bevel=.006)
cyl("Roof finial", .052, .065, .445, BRASS, G, 10, bevel=.006)
path("Heavy carrying handle", [(.10*cos(pi*i/12), 0, .49+.092*sin(pi*i/12))
                               for i in range(13)], .011, GOLD, G)

G = "SM_WW_LanternStand"
cyl("Stand heavy foot", .18, .035, .018, STONE, G, 10, bevel=.004)
cyl("Stand central bronze shaft", .024, .75, .405, BRASS, G, 10)
ring("Stand lower collar", .07, .023, .075, .10, GOLD, G, 10)
ring("Stand upper collar", .067, .023, .72, .745, GOLD, G, 10)
cyl("Lantern seating plate", .13, .019, .789, WALNUT, G, 10)

G = "SM_WW_CardBox"
box("Carved walnut box", (0,0,.09), (.27,.19,.18), WALNUT, G, .018)
box("Open velvet tray", (0,0,.181), (.236,.156,.012), RUST, G, .008)
for x in (-.119,.119):
    beam("Bronze box seam", (x,-.08,.18), (x,.08,.18), .005, BRASS, G, 0)
for y in (-.085,.085):
    beam("Bronze box seam", (-.12,y,.18), (.12,y,.18), .005, BRASS, G, 0)
box("Hinged lid", (0,-.135,.27), (.27,.018,.19), WALNUT, G, .009).rotation_euler.x = -.20
box("Lid inlay", (0,-.128,.29), (.19,.014,.11), TURQ, G, .006).rotation_euler.x = -.20
for x in (-.09,.09):
    sphere("Box clasp", (x,.098,.13), (.010,.006,.012), GOLD, G, 8)

# Two vote tokens, one for day and one for night, sized for a player's hand.
for name, accent, phase in (("Day", GOLD, 0), ("Night", TURQ, 1)):
    G = "SM_WW_VoteToken_" + name
    cyl("Thick minted bronze token", .040, .007, .004, BRASS, G, 24, bevel=.001)
    ring("Coin inset", .034, .028, .008, .009, accent, G, 24)
    if phase == 0:
        cyl("Sun face", .012, .002, .009, accent, G, 16)
        for i in range(8):
            a = 2*pi*i/8
            beam("Sun ray", (.017*cos(a),.017*sin(a),.009),
                 (.026*cos(a),.026*sin(a),.009), .002, accent, G, 0)
    else:
        cyl("Moon disk", .015, .002, .009, accent, G, 24)
        cyl("Crescent cutout", .013, .003, .011, WALNUT, G, 24, loc=(.007,.003))
        for x,y in ((-.021,.016),(.021,-.013)):
            sphere("Night star", (x,y,.010), (.002,.002,.001), GOLD, G, 8)


def card_base(group, accent):
    box("Stiff linen card", (0,0,.002), (.074,.106,.004), CREAM, group, .004)
    # Black inner field leaves a clear ivory margin and keeps icons legible.
    box("Printed charcoal field", (0,0,.0044), (.064,.095,.0008), INK, group, .001)
    for x in (-.029,.029):
        beam("Border engraving", (x,-.041,.005), (x,.041,.005), .0009, accent, group, 0)
    for y in (-.041,.041):
        beam("Border engraving", (-.029,y,.005), (.029,y,.005), .0009, accent, group, 0)
    cyl("Icon ground", .022, .0007, .0053, accent, group, 32, loc=(0,.002))
    cyl("Icon silhouette field", .019, .001, .0058, INK, group, 32, loc=(0,.002))
    for y in (-.032,.035):
        sphere("Small engraved corner star", (0,y,.0055),
               (.002,.002,.0005), accent, group, 8)


def icon_beam(group, points, mat=GOLD, width=.003):
    for a,b in zip(points, points[1:]):
        beam("Embossed icon stroke", (a[0],a[1],.007),
             (b[0],b[1],.007), width, mat, group, 0)


G = "SM_WW_RoleCard_Back"
card_base(G, GOLD)
ring("Secret moon sigil", .014, .012, .006, .007, GOLD, G, 24)
sphere("Moon pupil", (0,.002,.008), (.004,.004,.001), TURQ, G, 12)
for side in (-1,1):
    icon_beam(G, [(side*.014,.002), (side*.009,.011), (0,.015)], GOLD, .0015)

ROLE_CARDS = (
    ("Villager", GOLD), ("Wolf", WOLF), ("Seer", SEER),
    ("Witch", TURQ), ("Hunter", OCHRE), ("Guard", GOLD),
    ("Cupid", RUST), ("LittleGirl", CREAM),
)
for role, accent in ROLE_CARDS:
    G = "SM_WW_RoleCard_" + role
    card_base(G, accent)
    if role == "Villager":
        icon_beam(G, [(-.013,-.002),(0,.011),(.013,-.002)], accent)
        icon_beam(G, [(-.010,-.003),(-.010,-.013),(.010,-.013),(.010,-.003)], accent)
        box("Village doorway", (0,-.009,.007), (.004,.008,.001), accent, G)
    elif role == "Wolf":
        icon_beam(G, [(-.016,-.013),(-.011,.014),(-.003,.005),
                      (.003,.005),(.011,.014),(.016,-.013)], accent)
        icon_beam(G, [(-.016,-.013),(0,-.016),(.016,-.013)], accent)
        for x in (-.007,.007):
            sphere("Wolf eye", (x,-.004,.008), (.002,.002,.001), GOLD, G, 8)
    elif role == "Seer":
        icon_beam(G, [(-.017,0),(-.008,.007),(0,.009),(.008,.007),(.017,0),
                      (.008,-.007),(0,-.009),(-.008,-.007),(-.017,0)], accent)
        cyl("Seer iris", .0045, .001, .008, GOLD, G, 16)
    elif role == "Witch":
        icon_beam(G, [(-.008,.013),(.008,.013)], accent)
        icon_beam(G, [(-.005,.012),(-.005,.004),(-.013,-.012),
                      (.013,-.012),(.005,.004),(.005,.012)], accent)
        sphere("Potion glint", (0,-.007,.008), (.004,.003,.001), GOLD, G, 8)
    elif role == "Hunter":
        for side in (-1,1):
            icon_beam(G, [(side*.014,-.013),(-side*.013,.014)], accent)
            icon_beam(G, [(-side*.013,.014),(-side*.004,.011)], accent, .0015)
    elif role == "Guard":
        icon_beam(G, [(-.014,.012),(.014,.012),(.011,-.007),
                      (0,-.016),(-.011,-.007),(-.014,.012)], accent)
        icon_beam(G, [(0,.009),(0,-.010)], accent, .002)
    elif role == "Cupid":
        icon_beam(G, [(0,-.015),(-.015,.002),(-.012,.012),(-.003,.012),
                      (0,.007),(.003,.012),(.012,.012),(.015,.002),(0,-.015)], accent)
    elif role == "LittleGirl":
        cyl("Listening keyhole round", .006, .001, .007, accent, G, 16, loc=(0,.006))
        icon_beam(G, [(-.004,.003),(-.007,-.014),(.007,-.014),(.004,.003)], accent)


def export_group(group):
    bpy.ops.object.select_all(action="DESELECT")
    for source in groups[group]:
        dup = source.copy()
        dup.data = source.data.copy()
        bpy.context.collection.objects.link(dup)
        dup.select_set(True)
        bpy.context.view_layer.objects.active = dup
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    combined = bpy.context.object
    combined.name = group
    bpy.context.scene.cursor.location = (0,0,0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.ops.export_scene.fbx(
        filepath=str(OUT / (group + ".fbx")), use_selection=True,
        object_types={"MESH"}, apply_unit_scale=True,
        bake_space_transform=False, axis_forward="-Y", axis_up="Z",
        use_mesh_modifiers=True, path_mode="AUTO", embed_textures=False,
    )
    print("EXPORTED", group, len(groups[group]))
    bpy.data.objects.remove(combined, do_unlink=True)


for name in sorted(groups):
    export_group(name)

# Keep source meshes organised. The scene opens on an example twelve-seat layout.
for group, members in groups.items():
    collection = bpy.data.collections.new(group)
    bpy.context.scene.collection.children.link(collection)
    for obj in members:
        for parent in tuple(obj.users_collection):
            parent.objects.unlink(obj)
        collection.objects.link(obj)
        obj.hide_render = group not in ("SM_WW_Firepit", "SM_WW_Flame", "SM_WW_Rug")


def preview(group, at, angle=0):
    for source in groups[group]:
        obj = source.copy()
        obj.data = source.data
        bpy.context.collection.objects.link(obj)
        obj.hide_render = False
        x,y,z = source.location
        obj.location = (at[0] + x*cos(angle)-y*sin(angle),
                        at[1] + x*sin(angle)+y*cos(angle), at[2]+z)
        obj.rotation_euler.z += angle
        obj.name = "Preview_" + source.name


for i in range(12):
    angle = 2*pi*i/12
    x,y = 2.12*cos(angle), 2.12*sin(angle)
    preview(("SM_WW_Cushion_Oxblood", "SM_WW_Cushion_Turquoise",
             "SM_WW_Cushion_Ochre")[i%3], (x,y,0), angle+pi/2)
    preview("SM_WW_SeatMarker", (2.36*cos(angle),2.36*sin(angle),.03), angle)
for a in (pi/4, 5*pi/4):
    pos = (3.02*cos(a), 3.02*sin(a),0)
    preview("SM_WW_LanternStand", pos)
    preview("SM_WW_Lantern", (pos[0],pos[1],.80))
preview("SM_WW_CardBox", (0,-1.18,.03))
preview("SM_WW_VoteToken_Day", (-.12,-1.28,.03))
preview("SM_WW_VoteToken_Night", (.12,-1.28,.03))

bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "werewolf_courtyard_kit.blend"))
print("SAVED", OUT / "werewolf_courtyard_kit.blend", len(groups), "meshes")
