"""Ink previews of the emotes, for the emote wheel (Client/emotes/emotes.html).

    blender -b --python render_emotes.py -- <out dir> <anim.fbx> <frame> <name> [look]

One look (default "etudiant", see render_portraits.py) is assembled from the
Creative pieces exported by scripts/unreal/export_vitrine.py, posed on one
frame of the emote animation, and drawn full body in black ink: paper-white
fill, one grey shadow step, ink outline by inverted hull, transparent
background. Output: <out dir>/<name>.png, the `apercu` of the emote in
Shared/config.lua (emotes.liste). Copy it to Client/emotes/img/ (outside the
repo, like the other renders). The title is written by the wheel itself.
"""

import bpy, sys, os, math
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
OUT, ANIM, FRAME, NOM = args[0], args[1], int(args[2]), args[3]
LOOK = args[4] if len(args) > 4 else "etudiant"

V = "C:/nanos-adk/Saved/Vitrine/"
INK = (0.011, 0.015, 0.017, 1)       # #1c2123 en lineaire
PAPIER = (0.86, 0.79, 0.65, 1)       # #efe6d2 en lineaire
OMBRE = (0.55, 0.52, 0.47, 1)

LOOKS = {
    "etudiant": ["Hairstyle_male_010", "Male_emotion_usual_001", "Glasses_004", "T_Shirt_009", "Shorts_003", "Shoe_Sneakers_009"],
    "chapeau":  ["Hat_010", "Male_emotion_usual_001", "Glasses_006", "Outerwear_036", "Pants_010", "Shoe_Sneakers_009"],
    "clown":    ["Male_emotion_happy_002", "Clown_nose_001", "Costume_10_001", "Shoe_Slippers_005"],
}


def importer(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def assembler(pieces):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    new = importer(V + "pieces/SK_Body_010.fbx")
    arm = next(o for o in new if o.type == "ARMATURE")
    meshes = [o for o in new if o.type == "MESH"]
    for nom in pieces:
        new = importer(V + f"pieces/SK_{nom}.fbx")
        for o in new:
            if o.type != "MESH":
                continue
            mw = o.matrix_world.copy()
            o.parent = arm
            o.matrix_world = mw
            for m in o.modifiers:
                if m.type == "ARMATURE":
                    m.object = arm
            meshes.append(o)
        for o in new:
            if o.type in ("ARMATURE", "EMPTY"):
                bpy.data.objects.remove(o, do_unlink=True)

    # La pose : l'action de l'emote, sur le squelette du corps.
    new = importer(ANIM)
    src = next(o for o in new if o.type == "ARMATURE")
    action = src.animation_data.action
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    arm.animation_data_create()
    arm.animation_data.action = action
    if hasattr(arm.animation_data, "action_slot") and action.slots:
        arm.animation_data.action_slot = action.slots[0]
    bpy.context.scene.frame_set(FRAME)
    for o in meshes:
        for poly in o.data.polygons:
            poly.use_smooth = True
        w = o.modifiers.new("soudure", "WELD")
        w.merge_threshold = 0.0005
    return arm, meshes


def materiaux():
    # Encre noire : tout en papier, un seul palier d'ombre gris, pas d'atlas.
    for m in bpy.data.materials:
        m.use_nodes = True
        nt = m.node_tree
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        sh = nt.nodes.new("ShaderNodeBsdfDiffuse")
        s2r = nt.nodes.new("ShaderNodeShaderToRGB")
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.interpolation = "CONSTANT"
        e = ramp.color_ramp.elements
        e[0].position = 0.0; e[0].color = OMBRE
        e[1].position = 0.06; e[1].color = PAPIER
        nt.links.new(sh.outputs[0], s2r.inputs[0]); nt.links.new(s2r.outputs["Color"], ramp.inputs["Fac"])
        em = nt.nodes.new("ShaderNodeEmission"); nt.links.new(ramp.outputs["Color"], em.inputs["Color"])
        nt.links.new(em.outputs[0], out.inputs["Surface"])


def contour(meshes, epaisseur):
    ink = bpy.data.materials.new("ink"); ink.use_nodes = True
    ink.use_backface_culling = True
    nt = ink.node_tree; out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    em = nt.nodes.new("ShaderNodeEmission"); em.inputs["Color"].default_value = INK
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    for o in meshes:
        o.data.materials.append(ink)
        s = o.modifiers.new("contour", "SOLIDIFY")
        s.thickness = epaisseur / max(o.matrix_world.to_scale())
        s.offset = 1; s.use_flip_normals = True
        s.material_offset = len(o.data.materials) - 1


def points_deformes(meshes):
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in meshes:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        pts += [ev.matrix_world @ v.co for v in me.vertices]
        ev.to_mesh_clear()
    return pts


def cadrer(meshes):
    """Corps entier, de trois quarts, centre dans un carre."""
    sc = bpy.context.scene
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
    cam.data.type = "ORTHO"
    cam.rotation_euler = (math.radians(90 - 8), 0, math.radians(20))
    avant, droite, dessus = Vector((0, 0, -1)), Vector((1, 0, 0)), Vector((0, 1, 0))
    for v in (avant, droite, dessus):
        v.rotate(cam.rotation_euler)
    pts = points_deformes(meshes)
    dx = [p.dot(droite) for p in pts]
    dy = [p.dot(dessus) for p in pts]
    taille = max(max(dx) - min(dx), max(dy) - min(dy))
    cam.data.ortho_scale = taille * 1.1
    centre = droite * ((max(dx) + min(dx)) / 2) + dessus * ((max(dy) + min(dy)) / 2)
    cam.location = centre - avant * 10
    return max(p.z for p in pts) - min(p.z for p in pts)


def scene():
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = sc.render.resolution_y = 512
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sun.data.energy = 3
    sun.location = (1.5, -5, 3); sun.rotation_euler = (-Vector(sun.location)).to_track_quat("-Z", "Y").to_euler()
    sc.collection.objects.link(sun)


arm, meshes = assembler(LOOKS[LOOK])
materiaux()
scene()
hauteur = cadrer(meshes)
contour(meshes, hauteur * 0.008)
bpy.context.scene.render.filepath = os.path.join(OUT, f"{NOM}.png")
bpy.ops.render.render(write_still=True)
print("EMOTE", NOM)
