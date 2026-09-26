"""Card (encre) and showcase (vitrine) renders of the downloaded weapons.

blender -b --python render_armes.py -- <extracted zips dir> <out dir> encre|vitrine [ids]
The zips stay out of the repo (Sketchfab, licence to check); rot.json in the
extracted dir holds per-weapon yaw fixes so every muzzle points left.
"""
import bpy, sys, os, math, json
from mathutils import Vector, Euler

args = sys.argv[sys.argv.index("--") + 1:]
S, OUT, MODE = args[0], args[1], args[2]          # MODE: vitrine | encre | fbx
ONLY = args[3].split(",") if len(args) > 3 else None
W = {
    "revolver": dict(f="stylized-gun revolver/source/gun_new.fbx", tex={"*": ("stylized-gun revolver/textures/1001_Base_color.png", "stylized-gun revolver/textures/1001_Normal.png")}),
    "ice": dict(f="ice-gun/source/StylizedPistol.fbx", tex={"Pistol": ("ice-gun/textures/BASECOLOR_Material.png", None, "ice-gun/textures/EMISSIVE_Material.png"), "Glass1": "glass", "Glass2": "glass", "Light": "light"}),
    "stylized": dict(f="stylized-gun/source/Gun.fbx", tex={"Material_02": ("stylized-gun/textures/train_low_Material_02_AlbedoTransparency.png",)}),
    "lawgiver": dict(f="aquilian-lawgiver-stylized-gun/source/Gun.fbx", tex={"Gun": ("aquilian-lawgiver-stylized-gun/textures/Gun.png",), "GunGlass": ("aquilian-lawgiver-stylized-gun/textures/GunGlass1.png", None, None, "alpha")}),
    "old": dict(f="stylized-old-gun/source/inner/StylizedOldGun.fbx", tex={"M_StylizedGun": ("stylized-old-gun/textures/T_StylizedGun.png",)}),
    "physics": dict(f="pysics-gun-ugen/source/Pysics_gun.blend.blend", tex={"PYSICSGUN": ("pysics-gun-ugen/textures/PYSICSGUN.png",)}, keep=("Cube.002",)),
}
_rot = os.path.join(os.path.dirname(os.path.abspath(__file__)), "render_armes_rot.json")
ROT = json.load(open(_rot)) if os.path.exists(_rot) else {}
INK = (0.011, 0.015, 0.017, 1)   # #1c2123 in linear


def img(p):
    return bpy.data.images.load(os.path.join(S, p), check_existing=True)


def principled(m):
    m.use_nodes = True
    nt = m.node_tree
    return next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), nt


def wire(m, spec):
    b, nt = principled(m)
    if spec == "glass":
        b.inputs["Base Color"].default_value = (0.55, 0.85, 1.0, 1)
        b.inputs["Roughness"].default_value = 0.05
        b.inputs["Alpha"].default_value = 0.45
        return
    if spec == "light":
        b.inputs["Emission Color"].default_value = (0.4, 0.9, 1.0, 1)
        b.inputs["Emission Strength"].default_value = 4
        return
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = img(spec[0])
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    if len(spec) > 1 and spec[1]:
        n = nt.nodes.new("ShaderNodeTexImage"); n.image = img(spec[1]); n.image.colorspace_settings.name = "Non-Color"
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(n.outputs["Color"], nm.inputs["Color"]); nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    if len(spec) > 2 and spec[2]:
        e = nt.nodes.new("ShaderNodeTexImage"); e.image = img(spec[2])
        nt.links.new(e.outputs["Color"], b.inputs["Emission Color"]); b.inputs["Emission Strength"].default_value = 3
    if len(spec) > 3 and spec[3] == "alpha":
        nt.links.new(t.outputs["Alpha"], b.inputs["Alpha"])


def base_color_of(m):
    if not m.use_nodes:
        return None, tuple(m.diffuse_color)
    b = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if not b:
        return None, (0.6, 0.6, 0.6, 1)
    i = b.inputs["Base Color"]
    if i.is_linked:
        return i.links[0].from_socket, None
    return None, tuple(i.default_value)


def to_ink(m):
    """Flat colour with one hard shadow step - the card look."""
    sock, rgba = base_color_of(m)
    if not m.use_nodes:
        m.use_nodes = True
    nt = m.node_tree
    out = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL" and n.is_active_output), None) or next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    sh = nt.nodes.new("ShaderNodeBsdfDiffuse")
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    e = ramp.color_ramp.elements
    e[0].position = 0.0; e[0].color = (0.5, 0.5, 0.5, 1)
    e[1].position = 0.12; e[1].color = (1, 1, 1, 1)
    nt.links.new(sh.outputs[0], s2r.inputs[0]); nt.links.new(s2r.outputs["Color"], ramp.inputs["Fac"])
    mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1
    if sock:
        nt.links.new(sock, mix.inputs[6])
    else:
        mix.inputs[6].default_value = rgba
    nt.links.new(ramp.outputs["Color"], mix.inputs[7])
    em = nt.nodes.new("ShaderNodeEmission"); nt.links.new(mix.outputs[2], em.inputs["Color"])
    b = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if b and b.inputs["Alpha"].is_linked:
        tr = nt.nodes.new("ShaderNodeBsdfTransparent"); ms = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(b.inputs["Alpha"].links[0].from_socket, ms.inputs[0])
        nt.links.new(tr.outputs[0], ms.inputs[1]); nt.links.new(em.outputs[0], ms.inputs[2])
        nt.links.new(ms.outputs[0], out.inputs["Surface"])
    else:
        nt.links.new(em.outputs[0], out.inputs["Surface"])


def bounds(meshes):
    pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    mn = Vector([min(p[i] for p in pts) for i in range(3)])
    mx = Vector([max(p[i] for p in pts) for i in range(3)])
    return mn, mx


def load(k):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    p = os.path.join(S, W[k]["f"])
    if p.endswith(".fbx"):
        bpy.ops.import_scene.fbx(filepath=p)
    else:
        with bpy.data.libraries.load(p) as (a, b):
            b.objects = a.objects
        for o in b.objects:
            if o and o.name in W[k].get("keep", (o.name,)):
                bpy.context.scene.collection.objects.link(o)
        for m in bpy.data.materials:
            if m.use_nodes:
                for n in m.node_tree.nodes:
                    if n.type == "OUTPUT_MATERIAL":
                        n.is_active_output = any(l.from_node.type == "BSDF_PRINCIPLED" for l in n.inputs["Surface"].links)
    for m in list(bpy.data.materials):
        spec = W[k]["tex"].get(m.name, W[k]["tex"].get("*"))
        if spec:
            wire(m, spec)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    sc = bpy.context.scene
    tops = [o for o in sc.objects if o.parent is None]
    piv = bpy.data.objects.new("pivot", None); sc.collection.objects.link(piv)
    for o in tops:
        o.parent = piv
    bpy.context.view_layer.update()
    mn, mx = bounds(meshes)
    piv.location = -(mn + mx) / 2
    root = bpy.data.objects.new("root", None); sc.collection.objects.link(root)
    piv.parent = root
    root.rotation_euler = Euler([math.radians(a) for a in ROT.get(k, [0, 0, 0])])
    bpy.context.view_layer.update()
    mn, mx = bounds(meshes)
    root.scale = [1.0 / max(mx - mn)] * 3
    bpy.context.view_layer.update()
    mn, mx = bounds(meshes)
    root.location = -(mn + mx) / 2
    bpy.context.view_layer.update()
    return meshes


def ink_hull(meshes, thick):
    ink = bpy.data.materials.new("ink"); ink.use_nodes = True
    ink.use_backface_culling = True
    nt = ink.node_tree; out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    em = nt.nodes.new("ShaderNodeEmission"); em.inputs["Color"].default_value = INK
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    for o in meshes:
        if any(m and "Glass" in m.name for m in o.data.materials):
            continue
        o.data.materials.append(ink)
        s = o.modifiers.new("hull", "SOLIDIFY")
        s.thickness = thick / max(o.matrix_world.to_scale())
        s.offset = 1; s.use_flip_normals = True
        s.material_offset = len(o.data.materials) - 1


def look_at(obj, target=Vector((0, 0, 0))):
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def scene_setup():
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = 1024, 640
    sc.render.film_transparent = True
    w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.85, 0.79, 0.66, 1)   # cream #efe6d2
    bg.inputs[1].default_value = 1.0 if MODE == "encre" else 0.35
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
    if MODE == "encre":
        sc.view_settings.view_transform = "Standard"
        cam.data.type = "ORTHO"
        mn, mx = bounds([o for o in sc.objects if o.type == "MESH"])
        cam.data.ortho_scale = 1.12 * max(mx.x - mn.x, (mx.z - mn.z) * 1024 / 640)
        cam.location = (0, -5, 0); look_at(cam)
        sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sun.data.energy = 3
        sun.location = (1, -2, 3); look_at(sun); sc.collection.objects.link(sun)
    else:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = "AgX - Medium High Contrast"
        cam.data.lens = 85
        cam.location = Vector((1.3, -4.6, 1.0)); look_at(cam)
        cam.data.dof.use_dof = False
        for name, loc, e, col in [("key", (2.2, -3, 3), 700, (1, .92, .8)),
                                  ("rim", (-2.5, 3, 2), 1200, (.7, .82, 1)),
                                  ("fill", (-3, -3, 0), 180, (1, 1, 1))]:
            L = bpy.data.objects.new(name, bpy.data.lights.new(name, "AREA"))
            L.data.energy = e; L.data.size = 2; L.data.color = col
            L.location = loc; look_at(L); sc.collection.objects.link(L)


# Nom de chaque arme dans Shared/catalogue.lua.
# Armes a alleger avant l'export FBX (voir plus bas).
ALLEGER = {"ice"}
IDS = {"revolver": "revolver", "old": "canon", "lawgiver": "duel", "stylized": "flammes", "ice": "glace", "physics": "physique"}

for k in (ONLY or W):
    meshes = load(k)
    if MODE == "fbx":
        # Pour l'ADK : transformations appliquees, 100 cm de long, centre a
        # l'origine, textures dans le fichier.
        if k in ALLEGER:
            # Le pistolet a glace faisait planter le jeu a l'affichage : textures
            # ramenees a 1024 px, verres et lumiere rendus opaques et mats.
            for img in bpy.data.images:
                if img.size[0] > 1024 or img.size[1] > 1024:
                    img.scale(1024, 1024)
                    img.pack()
            for m in bpy.data.materials:
                b = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None) if m.use_nodes else None
                if not b:
                    continue
                for lien in list(b.inputs["Alpha"].links):
                    m.node_tree.links.remove(lien)
                b.inputs["Alpha"].default_value = 1.0
                b.inputs["Emission Strength"].default_value = 0.0
        bpy.ops.object.select_all(action="DESELECT")
        for o in meshes:
            o.select_set(True)
        bpy.context.view_layer.objects.active = meshes[0]
        bpy.ops.object.make_single_user(object=True, obdata=True)
        bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        bpy.ops.export_scene.fbx(
            filepath=os.path.join(OUT, f"SM_Arme_{IDS[k]}.fbx"), use_selection=True,
            object_types={"MESH"}, apply_unit_scale=True, apply_scale_options="FBX_SCALE_ALL",
            path_mode="COPY", embed_textures=True, mesh_smooth_type="FACE")
        print("FBX", k)
        continue
    if MODE == "encre":
        for m in list(bpy.data.materials):
            to_ink(m)
        ink_hull(meshes, 0.006)
    scene_setup()
    bpy.context.scene.render.filepath = os.path.join(OUT, f"{MODE}_{k}.png")
    bpy.ops.render.render(write_still=True)
    print("RENDU", k)
