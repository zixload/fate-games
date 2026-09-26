"""Card portraits of the ten looks, drawn from the real Creative pieces.

    blender -b --python render_portraits.py -- <out dir> [ids] [--pose NAME] [--frame N]

The pieces come from scripts/unreal/export_vitrine.py (Saved/Vitrine, outside
the repo: Fab assets). Each look is assembled on the body's skeleton, posed
with one frame of an idle animation, then rendered bust-only in the card
style (flat colour, one hard shadow step, ink outline by inverted hull) on a
transparent background. The look list mirrors Shared/appearances.lua.
"""

import bpy, sys, os, math
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
OUT = args[0]
ONLY = args[1].split(",") if len(args) > 1 and not args[1].startswith("--") else None
POSE = args[args.index("--pose") + 1] if "--pose" in args else "ANIM_Idle_Breathing"
FRAME = int(args[args.index("--frame") + 1]) if "--frame" in args else 1

V = "C:/nanos-adk/Saved/Vitrine/"
TEXTURE = V + "T_Textures.png"
INK = (0.011, 0.015, 0.017, 1)   # #1c2123 in linear

LOOKS = {
    "clown":      ["Male_emotion_happy_002", "Clown_nose_001", "Costume_10_001", "Shoe_Slippers_005"],
    "souris":     ["Hat_049", "Male_emotion_usual_001", "Costume_6_001", "Shoe_Slippers_002"],
    "chapeau":    ["Hat_010", "Male_emotion_usual_001", "Glasses_006", "Outerwear_036", "Pants_010", "Shoe_Sneakers_009"],
    "etudiant":   ["Hairstyle_male_010", "Male_emotion_usual_001", "Glasses_004", "T_Shirt_009", "Shorts_003", "Shoe_Sneakers_009"],
    "ronchon":    ["Hairstyle_male_012", "Male_emotion_angry_003", "Moustache_002", "Outerwear_029", "Pants_014", "Shoe_Slippers_002"],
    "casque":     ["Hairstyle_male_010", "Male_emotion_happy_002", "Headphones_002", "T_Shirt_009", "Pants_014", "Socks_008"],
    "nourrisson": ["Male_emotion_usual_001", "Pacifier_001", "T_Shirt_009", "Shorts_003", "Socks_008"],
    "chauve":     ["Male_emotion_angry_003", "Moustache_001", "Outerwear_036", "Pants_010", "Shoe_Slippers_005", "Gloves_006"],
    "bavard":     ["Hairstyle_male_012", "Male_emotion_happy_002", "Glasses_006", "Outerwear_029", "Pants_010", "Shoe_Sneakers_009"],
    "gantier":    ["Hairstyle_male_010", "Male_emotion_angry_003", "Glasses_004", "Moustache_002", "T_Shirt_009", "Pants_010", "Gloves_014", "Shoe_Sneakers_009"],
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

    # Pose : l'action d'une animation du pack, sur le squelette du corps.
    new = importer(V + f"poses/{POSE}.fbx")
    src = next(o for o in new if o.type == "ARMATURE")
    action = src.animation_data.action
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    arm.animation_data_create()
    arm.animation_data.action = action
    if hasattr(arm.animation_data, "action_slot") and action.slots:
        arm.animation_data.action_slot = action.slots[0]
    bpy.context.scene.frame_set(FRAME)
    # Normales lissees : sinon l'ombre dure decoupe chaque facette.
    for o in meshes:
        for poly in o.data.polygons:
            poly.use_smooth = True
        # Coutures : les sommets doubles d'un bord d'UV cassent l'ombre en
        # une ligne au milieu du visage. Souder les rend continus.
        w = o.modifiers.new("soudure", "WELD")
        w.merge_threshold = 0.0005
    return arm, meshes


def materiaux():
    tex = bpy.data.images.load(TEXTURE, check_existing=True)
    for m in bpy.data.materials:
        m.use_nodes = True
        nt = m.node_tree
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        if m.name.startswith("M_Glass"):
            # Verres : a peine teintes, pour que les yeux se lisent derriere.
            tr = nt.nodes.new("ShaderNodeBsdfTransparent")
            em = nt.nodes.new("ShaderNodeEmission"); em.inputs["Color"].default_value = (0.75, 0.9, 1.0, 1)
            mix = nt.nodes.new("ShaderNodeMixShader"); mix.inputs[0].default_value = 0.2
            nt.links.new(tr.outputs[0], mix.inputs[1]); nt.links.new(em.outputs[0], mix.inputs[2])
            nt.links.new(mix.outputs[0], out.inputs["Surface"])
            m.surface_render_method = "BLENDED"
            continue
        # Aplat : la couleur de l'atlas, un seul palier d'ombre dur.
        t = nt.nodes.new("ShaderNodeTexImage"); t.image = tex; t.interpolation = "Closest"
        sh = nt.nodes.new("ShaderNodeBsdfDiffuse")
        s2r = nt.nodes.new("ShaderNodeShaderToRGB")
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.interpolation = "CONSTANT"
        e = ramp.color_ramp.elements
        e[0].position = 0.0; e[0].color = (0.7, 0.68, 0.74, 1)
        e[1].position = 0.06; e[1].color = (1, 1, 1, 1)
        nt.links.new(sh.outputs[0], s2r.inputs[0]); nt.links.new(s2r.outputs["Color"], ramp.inputs["Fac"])
        mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1
        nt.links.new(t.outputs["Color"], mix.inputs[6]); nt.links.new(ramp.outputs["Color"], mix.inputs[7])
        em = nt.nodes.new("ShaderNodeEmission"); nt.links.new(mix.outputs[2], em.inputs["Color"])
        nt.links.new(em.outputs[0], out.inputs["Surface"])


def contour(meshes, epaisseur):
    ink = bpy.data.materials.new("ink"); ink.use_nodes = True
    ink.use_backface_culling = True
    nt = ink.node_tree; out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    em = nt.nodes.new("ShaderNodeEmission"); em.inputs["Color"].default_value = INK
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    for o in meshes:
        if any(m and m.name.startswith("M_Glass") for m in o.data.materials):
            continue
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


def os_monde(arm, nom):
    pb = arm.pose.bones[nom]
    return arm.matrix_world @ pb.head


def cadrer(arm, meshes):
    """Buste : du milieu du torse au sommet du couvre-chef, de face."""
    tete = os_monde(arm, "Head")
    cou = os_monde(arm, "Neck")
    pts = points_deformes(meshes)
    haut = max(p.z for p in pts)
    bas = cou.z - (haut - cou.z) * 1.25
    sc = bpy.context.scene
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
    cam.data.type = "ORTHO"
    # Le personnage regarde vers -Y apres l'import FBX : la camera se place
    # devant, un peu au-dessus et de trois quarts, comme un portrait.
    cam.rotation_euler = (math.radians(90 - 14), 0, math.radians(14))
    avant, droite, dessus = Vector((0, 0, -1)), Vector((1, 0, 0)), Vector((0, 1, 0))
    for v in (avant, droite, dessus):
        v.rotate(cam.rotation_euler)
    # Centre horizontal sur la tete (points au-dessus du cou), vertical sur
    # le buste : on mesure dans le repere de la camera, vue de biais.
    tete_pts = [p for p in pts if p.z > cou.z]
    buste = [p for p in pts if p.z > bas]
    dx = [p.dot(droite) for p in tete_pts]
    dy = [p.dot(dessus) for p in buste]
    haut_cam, bas_cam = max(dy), min(p.dot(dessus) for p in tete_pts) - (max(dy) - min(p.dot(dessus) for p in tete_pts)) * 1.1
    cam.data.ortho_scale = (haut_cam - bas_cam) * 1.08
    centre = droite * ((max(dx) + min(dx)) / 2) + dessus * ((haut_cam + bas_cam) / 2 + (haut_cam - bas_cam) * 0.02)
    cam.location = centre - avant * 10
    return haut - bas


def scene():
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = 1024, 1536
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sun.data.energy = 3
    sun.location = (1.5, -5, 3); sun.rotation_euler = (-Vector(sun.location)).to_track_quat("-Z", "Y").to_euler()
    sc.collection.objects.link(sun)


for look, pieces in LOOKS.items():
    if ONLY and look not in ONLY:
        continue
    arm, meshes = assembler(pieces)
    materiaux()
    scene()
    hauteur_cadre = cadrer(arm, meshes)
    contour(meshes, hauteur_cadre * 0.006)
    bpy.context.scene.render.filepath = os.path.join(OUT, f"{look}.png")
    bpy.ops.render.render(write_still=True)
    print("PORTRAIT", look)
