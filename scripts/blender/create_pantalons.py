"""Pantalons Creative : des coupes (droit, pattes d'elephant, baggy, jogger,
slim, cargo, short) et des motifs, du commun au legendaire.

    blender -b --python scripts/blender/create_pantalons.py

Bases du kit Creative (Pants_010, Shorts_003), sur le corps et le squelette de
art/cosmetics/tshirts/creative_tshirt_rarities.blend (lu, pas modifie). Chaque
coupe deforme la jambe autour de son axe (evasement sous le genou, ampleur,
cheville resserree...), le cargo recoit des poches cousues sur les cuisses.
Puis, comme pour les T-shirts : poids du corps transferes (skinning), UV
depliees, motifs dessines en 3D et cuits dans une texture par pantalon
(scripts/blender/create_tshirt_motifs.py fournit les outils et une partie des
motifs).

Sorties dans art/cosmetics/pantalons/ (hors depot) : un FBX par coupe, une
texture et un apercu par pantalon, une planche, manifeste.json.
"""

import importlib.util
import json
import math
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector
from mathutils.kdtree import KDTree

PROJECT = Path(__file__).resolve().parents[2]
SOURCE = PROJECT / "art/cosmetics/tshirts/creative_tshirt_rarities.blend"
KIT = Path("C:/ProgramData/Epic/EpicGamesLauncher/VaultCache/FabLibrary/"
           "Creative_Characters_FREE_-_Animated_Low_Poly_3D_Models-94fd60a2/obj/source_extracted/"
           "Separate_assets_obj_extracted/Separate_assets_obj")
OUT = PROJECT / "art/cosmetics/pantalons"
OUT.mkdir(parents=True, exist_ok=True)
TAILLE = 2048

_spec = importlib.util.spec_from_file_location("motifs", PROJECT / "scripts/blender/create_tshirt_motifs.py")
M = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(M)
N, hexa = M.N, M.hexa


# ---------------------------------------------------------------- import et reperes

def importer(nom):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.wm.obj_import(filepath=str(KIT / (nom + ".obj")))
    obj = [o for o in bpy.context.selected_objects if o.type == "MESH"][0]
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.data.materials.clear()
    return obj


def retirer_genouilleres(obj):
    """Pants_014 porte des genouilleres : des morceaux detaches du pantalon,
    petits et places aux genoux. On ne garde que le plus gros morceau."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    vus, morceaux = set(), []
    for v in bm.verts:
        if v in vus:
            continue
        pile, morceau = [v], []
        vus.add(v)
        while pile:
            a = pile.pop()
            morceau.append(a)
            for e in a.link_edges:
                b = e.other_vert(a)
                if b not in vus:
                    vus.add(b)
                    pile.append(b)
        morceaux.append(morceau)
    morceaux.sort(key=len, reverse=True)
    retires = [v for m in morceaux[1:] for v in m]
    print("PANTALON_MORCEAUX", obj.name, [len(m) for m in morceaux[:6]], "retires", len(retires))
    bmesh.ops.delete(bm, geom=retires, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def reperes(obj):
    zs = [v.co.z for v in obj.data.vertices]
    bas, haut = min(zs), max(zs)
    # Entrejambe : le point le plus bas pres de l'axe du corps (|x| < 2 cm),
    # cherche dans le haut du vetement (les chevilles interieures passent
    # aussi pres de l'axe quand les jambes sont serrees).
    milieu = [v.co.z for v in obj.data.vertices if abs(v.co.x) < 0.02 and v.co.z > bas + 0.4 * (haut - bas)]
    entrejambe = min(milieu) if milieu else bas + 0.6 * (haut - bas)
    return bas, haut, entrejambe


def axes_des_jambes(obj, pas=0.02):
    """Centre (x, y) de chaque jambe par tranche de hauteur."""
    tranches = {}
    for v in obj.data.vertices:
        cle = (1 if v.co.x > 0 else -1, round(v.co.z / pas))
        t = tranches.setdefault(cle, [0.0, 0.0, 0])
        t[0] += v.co.x
        t[1] += v.co.y
        t[2] += 1
    return {k: (a / n, b / n) for k, (a, b, n) in tranches.items()}, pas


def elargir(obj, facteur):
    """facteur(t) : echelle radiale d'une jambe, t = 0 a l'ourlet, 1 a l'entrejambe."""
    bas, haut, entrejambe = reperes(obj)
    axes, pas = axes_des_jambes(obj)
    for v in obj.data.vertices:
        z = v.co.z
        if z > entrejambe + 0.06:
            continue
        cle = (1 if v.co.x > 0 else -1, round(z / pas))
        cx, cy = axes.get(cle, (v.co.x, v.co.y))
        t = (z - bas) / max(entrejambe - bas, 1e-3)
        s = facteur(min(1.0, max(0.0, t)))
        # Au-dessus de l'entrejambe, retour progressif a la coupe d'origine.
        fondu = min(1.0, max(0.0, (entrejambe + 0.06 - z) / 0.08))
        s = 1 + (s - 1) * fondu
        v.co.x = cx + (v.co.x - cx) * s
        v.co.y = cy + (v.co.y - cy) * s
    obj.data.update()


def lisse(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


COUPES = {
    "Droit": lambda t: 1.0,
    "PattesEph": lambda t: 1 + 1.35 * lisse((0.62 - t) / 0.62) ** 1.2,
    "Baggy": lambda t: 1.62 - 0.28 * lisse((0.1 - t) / 0.1),
    "Jogger": lambda t: 1.16 - 0.42 * lisse((0.24 - t) / 0.24),
    "Slim": lambda t: 0.97 - 0.05 * lisse((0.45 - t) / 0.45),
    "Cargo": lambda t: 1.16,
}


def poches_cargo(obj):
    """Deux poches plaquees sur l'exterieur des cuisses, avec rabat."""
    bas, haut, entrejambe = reperes(obj)
    z0 = entrejambe - 0.17
    print("PANTALON_REPERES", obj.name, "bas", round(bas, 3), "haut", round(haut, 3), "entrejambe", round(entrejambe, 3))
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for cote in (1, -1):
        # Le bord exterieur de la jambe a cette hauteur.
        cote_v = [v.co for v in obj.data.vertices if v.co.x * cote > 0]
        proche = min(abs(p.z - z0) for p in cote_v)
        pts = [p for p in cote_v if abs(p.z - z0) <= proche + 0.03]
        xe = max(p.x * cote for p in pts) * cote
        ym = sum(p.y for p in pts) / len(pts)
        for (dz, hz, ep, larg) in ((0.0, 0.065, 0.018, 0.055), (0.07, 0.018, 0.024, 0.06)):
            res = bmesh.ops.create_cube(bm, size=1.0)
            vs = res["verts"]
            for v in vs:
                v.co.x = xe + cote * (v.co.x + 0.5) * ep - cote * 0.004
                v.co.y = ym + v.co.y * 2 * larg
                v.co.z = z0 + dz + v.co.z * 2 * hz
            aretes = list({e for v in vs for e in v.link_edges})
            bmesh.ops.bevel(bm, geom=list(vs) + aretes, offset=0.004,
                            segments=2, affect="EDGES")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def transferer_poids(vetement, corps, rig):
    corps.update_from_editmode()
    points = [corps.matrix_world @ v.co for v in corps.data.vertices]
    arbre = KDTree(len(points))
    for i, p in enumerate(points):
        arbre.insert(p, i)
    arbre.balance()
    groupes = {g.index: g.name for g in corps.vertex_groups}
    for v in vetement.data.vertices:
        proches = arbre.find_n(vetement.matrix_world @ v.co, 6)
        melange, total = {}, 0.0
        for _l, i, d in proches:
            f = 1.0 / max(d, 0.005) ** 2
            total += f
            for a in corps.data.vertices[i].groups:
                cle = groupes[a.group]
                melange[cle] = melange.get(cle, 0.0) + f * a.weight
        for os_, w in melange.items():
            if w / total > 0.002:
                g = vetement.vertex_groups.get(os_) or vetement.vertex_groups.new(name=os_)
                g.add([v.index], w / total, "REPLACE")
    mod = vetement.modifiers.new("Creative skeleton", "ARMATURE")
    mod.object = rig


def deplier(obj):
    obj.data.uv_layers.new(name="Design_UV")
    obj.data.uv_layers.active = obj.data.uv_layers["Design_UV"]
    obj.data.uv_layers["Design_UV"].active_render = True
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")


# ---------------------------------------------------------------- motifs de pantalon

def cote_exterieur(n, x, largeur=0.25):
    """1 sur le flanc exterieur de la jambe, d'apres l'orientation de la surface."""
    geo = n.node("ShaderNodeNewGeometry")
    nx, ny, nz = n.sep(geo.outputs["Normal"])
    signe = n.math("SIGN", x)
    face = n.mul(nx, signe)
    return n.mul(n.gt(face, 0.8), n.lt(n.absv(ny), largeur))


def bandes(n, x, z, base, bord, reperes_):
    bas, haut, entrejambe = reperes_
    m = n.maxv(n.lt(z, bas + 0.03), n.gt(z, haut - 0.035))
    return n.melange(m, base, bord)


def jean(n, reperes_, clair=False):
    v, x, y, z = n.coords()
    serge = n.frac(n.mul(n.add(n.mul(z, 180.0), n.mul(x, 180.0)), 1.0))
    grain = n.add(n.mul(n.lt(serge, 0.5), 0.06), n.mul(n.sub(n.bruit(v, 60.0, 2.0), 0.5), 0.12))
    if clair:
        use = n._smooth(0.5, 0.5, n.add(n.bruit(v, 3.0, 3.0), n.mul(n.sub(0.9, z), 0.4)))
        base = n.melange(use, "#27486e", "#86aed0")
    else:
        base = n.couleur("#1f355a")
    base = n.melange(n.add(0.5, grain), "#0f1f38", base)
    # Couture orange sur le flanc exterieur de chaque jambe.
    couture = n.mul(cote_exterieur(n, x, 0.05), n.lt(z, reperes_[2]))
    base = n.melange(couture, base, "#d9892b")
    return bandes(n, x, z, base, "#172a47", reperes_)


def jogging(n, reperes_):
    v, x, y, z = n.coords()
    base = n.melange(n.mul(n.sub(n.bruit(v, 80.0, 2.0), 0.5), 0.3), "#8d9196", "#6f7378")
    # Trois bandes blanches sur le flanc exterieur.
    geo = n.node("ShaderNodeNewGeometry")
    nx, ny, nz = n.sep(geo.outputs["Normal"])
    bande = n.lt(n.absv(n.sub(n.frac(n.mul(n.add(ny, 1.0), 7.5)), 0.5)), 0.2)
    zone = cote_exterieur(n, x, 0.62)
    base = n.melange(n.mul(bande, zone), base, "#f4f4f2")
    return bandes(n, x, z, base, "#4a4d52", reperes_)


def kaki(n, reperes_):
    v, x, y, z = n.coords()
    base = n.melange(n.mul(n.sub(n.bruit(v, 25.0, 3.0), 0.5), 0.4), "#6b6a3a", "#7d7b47")
    return bandes(n, x, z, base, "#4f4e2a", reperes_)


def velours(n, reperes_):
    v, x, y, z = n.coords()
    a = n.atan2(y, x)
    cote = n.frac(n.mul(n.add(n.mul(x, 90.0), n.mul(y, 90.0)), 1.0))
    ride = n.math("POWER", n.absv(n.sin(n.mul(n.add(x, n.mul(y, 0.7)), 260.0))), 0.6)
    base = n.melange(ride, "#5c3a1e", "#8b5a2b")
    return bandes(n, x, z, base, "#3e2612", reperes_)


def tartan(n, reperes_):
    v, x, y, z = n.coords()
    h = n.lt(n.frac(n.mul(z, 7.0)), 0.35)
    w = n.lt(n.frac(n.mul(n.add(x, n.mul(y, 0.5)), 7.0)), 0.35)
    fh = n.lt(n.absv(n.sub(n.frac(n.mul(z, 7.0)), 0.7)), 0.02)
    fw = n.lt(n.absv(n.sub(n.frac(n.mul(n.add(x, n.mul(y, 0.5)), 7.0)), 0.7)), 0.02)
    base = n.couleur("#b3202a")
    base = n.melange(n.mul(n.maxv(h, w), 0.55), base, "#1e3a2f")
    base = n.melange(n.mul(h, w), base, "#12211b")
    base = n.melange(n.maxv(fh, fw), base, "#f2d16b")
    return bandes(n, x, z, base, "#12211b", reperes_)


def repris(fonction):
    """Un motif de T-shirt, recale sur la hauteur du pantalon."""
    def motif(n, reperes_):
        bas, haut, entrejambe = reperes_
        M.BAS_Z, M.HAUT_Z, M.POITRINE_Z = bas, haut, (bas + haut) / 2
        return fonction(n)
    return motif


PANTALONS = [
    # nom, base du kit, coupe, motif, rarete, nom affiche
    ("JeanBrut", "Pants_014", "Droit", lambda n, r: jean(n, r), "common", "Jean brut"),
    ("Jogging", "Pants_014", "Jogger", jogging, "common", "Jogging"),
    ("Cargo", "Pants_010", "Cargo", kaki, "uncommon", "Cargo kaki"),
    ("Velours", "Pants_014", "PattesEph", velours, "uncommon", "Pattes d'eph velours"),
    ("JeanBaggy", "Pants_014", "Baggy", lambda n, r: jean(n, r, clair=True), "rare", "Baggy délavé"),
    ("Tartan", "Pants_014", "Slim", tartan, "rare", "Slim tartan"),
    ("CamoCargo", "Pants_010", "Cargo", repris(M.camouflage), "rare", "Cargo camo"),
    ("ShortHawai", "Shorts_003", "Droit", repris(M.hawai), "rare", "Short hawaïen"),
    ("TieDye", "Pants_014", "PattesEph", repris(M.tie_dye), "epic", "Pattes d'eph tie & dye"),
    ("Flammes", "Pants_014", "Droit", repris(M.flammes), "epic", "Flammes"),
    ("Leopard", "Pants_014", "Slim", repris(M.leopard), "epic", "Slim léopard"),
    ("Galaxie", "Pants_014", "PattesEph", repris(M.galaxie), "legendary", "Pattes d'eph galaxie"),
    ("Dark", "Pants_010", "Cargo", repris(M.dark), "legendary", "Cargo nuit noire"),
]


# ---------------------------------------------------------------- cuisson, export, apercus

def cuire(obj, motif, reperes_, nom):
    img = bpy.data.images.new("T_COS_Pants_" + nom, TAILLE, TAILLE, alpha=False)
    mat = bpy.data.materials.new("M_COS_Pants_" + nom)
    mat.use_nodes = True
    n = N(mat)
    n.sortie(motif(n, reperes_))
    cible = n.node("ShaderNodeTexImage")
    cible.image = img
    n.t.nodes.active = cible
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 4
    scene.cycles.device = "CPU"
    scene.render.bake.margin = 12
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.bake(type="EMIT", use_clear=True)
    img.filepath_raw = str(OUT / (img.name + ".png"))
    img.file_format = "PNG"
    img.save()
    return img


def materiau_apercu(img):
    mat = bpy.data.materials.new("Apercu_" + img.name)
    mat.use_nodes = True
    t = mat.node_tree
    bsdf = t.nodes.get("Principled BSDF")
    tex = t.nodes.new("ShaderNodeTexImage")
    tex.image = img
    uv = t.nodes.new("ShaderNodeUVMap")
    uv.uv_map = "Design_UV"
    t.links.new(uv.outputs[0], tex.inputs["Vector"])
    t.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    return mat


def camera_jambes(scene):
    cam = bpy.data.objects.new("Camera jambes", bpy.data.cameras.new("Camera jambes"))
    scene.collection.objects.link(cam)
    cam.location = Vector((0.9, -2.7, 0.75))
    cam.rotation_euler = (Vector((0, 0, 0.55)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 55
    scene.camera = cam
    scene.render.resolution_x, scene.render.resolution_y = 620, 900


def main():
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    scene = bpy.context.scene
    rig = bpy.data.objects["Root"]
    corps = bpy.data.objects["SK_Animations.001"]
    for o in bpy.data.objects:
        if o.type == "MESH" and (o.name.startswith("SK_COS_") or o.name.startswith("DESIGN_")):
            o.hide_render = True
    # Un T-shirt uni du kit pour le contexte des apercus.
    haut = bpy.data.objects.get("DESIGN_BASE_T_Shirt_009")
    if haut:
        haut.hide_render = False
    camera_jambes(scene)

    pieces = {}      # (base, coupe) -> objet
    manifeste = []
    for nom, base, coupe, motif, rarete, affiche in PANTALONS:
        cle = (base, coupe)
        if cle not in pieces:
            obj = importer(base)
            # Pants_010 est deja un cargo (poches du kit) ; Pants_014 sert aux autres coupes.
            obj.name = "SK_COS_Shorts" if base == "Shorts_003" else f"SK_COS_Pants_{coupe}"
            if base == "Pants_014":
                retirer_genouilleres(obj)
            elargir(obj, COUPES[coupe])
            obj.modifiers.new("Lisse", "SUBSURF").levels = 2
            transferer_poids(obj, corps, rig)
            deplier(obj)
            pieces[cle] = obj
            bpy.ops.object.select_all(action="DESELECT")
            rig.select_set(True)
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            bpy.ops.export_scene.fbx(filepath=str(OUT / (obj.name + ".fbx")), use_selection=True,
                                     object_types={"ARMATURE", "MESH"}, add_leaf_bones=False,
                                     bake_anim=False, use_mesh_modifiers=True, armature_nodetype="NULL")
        obj = pieces[cle]
        for o in pieces.values():
            o.hide_render = o is not obj
        rep = reperes(obj)
        img = cuire(obj, motif, rep, nom)
        obj.data.materials.clear()
        obj.data.materials.append(materiau_apercu(img))
        scene.render.engine = "BLENDER_EEVEE"
        scene.render.filepath = str(OUT / ("Apercu_" + nom + ".png"))
        bpy.ops.render.render(write_still=True)
        manifeste.append({"nom": affiche, "rarete": rarete, "piece": obj.name, "texture": img.name})
        print("PANTALON_PRET", nom, obj.name, rarete)

    (OUT / "manifeste.json").write_text(json.dumps(manifeste, indent=2, ensure_ascii=False), encoding="utf-8")


main()
