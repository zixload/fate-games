"""T-shirts a manches longues en tartan : un tissu epais, avec des plis.

    blender -b --python scripts/blender/create_manches_longues.py

Base : le sweat Outerwear_036 du kit Creative (manches longues, poignets et
bas cotes), sans sa capuche : un col rond cote la remplace. Le maillage est
subdivise puis sculpte de plis (poignets tasses, coudes, aisselles, taille),
decolle du corps pour l'epaisseur, pondere sur le squelette comme les
pantalons. Le tartan suit le tronc (autour du corps) et chaque manche (le long
du bras), avec une couture a l'emmanchure ; col, poignets et bas en cotes
unies.

Sorties dans art/cosmetics/manches_longues/ (hors depot) : le FBX de la
piece, une texture et un apercu par tartan, manifeste.json.
"""

import importlib.util
import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

PROJECT = Path(__file__).resolve().parents[2]
SOURCE = PROJECT / "art/cosmetics/tshirts/creative_tshirt_rarities.blend"
OUT = PROJECT / "art/cosmetics/manches_longues"
OUT.mkdir(parents=True, exist_ok=True)
PIECE = "SK_COS_TShirt_ManchesLongues"

_spec = importlib.util.spec_from_file_location("pantalons_outils", PROJECT / "scripts/blender/create_pantalons.py")
_src = (PROJECT / "scripts/blender/create_pantalons.py").read_text(encoding="utf-8").replace("\nmain()\n", "\n")
P = type(importlib)("pantalons_outils")
P.__file__ = str(PROJECT / "scripts/blender/create_pantalons.py")
exec(compile(_src, P.__file__, "exec"), P.__dict__)
N, lisse = P.N, P.lisse

# Reperes du sweat (mesures sur Outerwear_036) : l'epaule, la pente du bras
# (32 degres sous l'horizontale), les poignets et le bas cotes.
EPAULE = Vector((0.20, 0.0, 1.33))
PENTE = math.radians(32.6)
BRAS = Vector((math.cos(PENTE), 0.0, -math.sin(PENTE)))     # cote x > 0
POIGNET = 0.415          # m le long du bras : debut du poignet cote
EMMANCHURE = 0.205       # |x| de la couture tronc / manche
BAS_COTES = 0.925        # z du haut du bas cote
COL_Z = 1.43


def le_long(p):
    """(s, q) : distance le long du bras depuis l'epaule, et ecart a l'axe."""
    a = Vector((abs(p.x), p.y, p.z)) - EPAULE
    s = a.dot(BRAS)
    return s, a - BRAS * s


# ---------------------------------------------------------------- maillage

def base_sans_capuche():
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.wm.obj_import(filepath=str(P.KIT / "Outerwear_036.obj"))
    obj = [o for o in bpy.context.selected_objects if o.type == "MESH"][0]
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.data.materials.clear()
    P.retirer_genouilleres(obj)          # garde le plus gros morceau : la capuche part
    obj.name = PIECE
    return obj


def col_rond(obj):
    """Un col cote a la place de la capuche : le bord de l'encolure monte de
    2 cm en se resserrant, puis replonge a l'interieur (epaisseur du col)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bord = [e for e in bm.edges if e.is_boundary and all(v.co.z > 1.34 and abs(v.co.x) < 0.16 for v in e.verts)]
    centre = sum((v.co for e in bord for v in e.verts), Vector()) / (2 * max(len(bord), 1))
    print("COL", len(bord), "aretes, centre", tuple(round(c, 3) for c in centre))
    for monte, serre in ((0.012, 0.95), (0.012, 0.97), (-0.03, 0.93)):
        res = bmesh.ops.extrude_edge_only(bm, edges=bord)
        vs = [g for g in res["geom"] if isinstance(g, bmesh.types.BMVert)]
        for v in vs:
            v.co.z += monte
            v.co.x = centre.x + (v.co.x - centre.x) * serre
            v.co.y = centre.y + (v.co.y - centre.y) * serre
        bord = [g for g in res["geom"] if isinstance(g, bmesh.types.BMEdge)
                and all(v in vs for v in g.verts)]
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def subdiviser(obj, niveaux=2):
    m = obj.modifiers.new("Densite", "SUBSURF")
    m.levels = niveaux
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=m.name)


def plis(p):
    """Relief des plis (m, vers l'exterieur) : poignets tasses, coudes,
    aisselles, taille. Rien sur les cotes (col, poignets, bas)."""
    ax = abs(p.x)
    if p.z < BAS_COTES or p.z > COL_Z - 0.01:
        return 0.0
    if ax > EMMANCHURE:
        s, q = le_long(p)
        if s > POIGNET:
            return 0.0
        tour = math.atan2(q.y, q.dot(Vector((math.sin(PENTE), 0, math.cos(PENTE)))))
        # La manche se tasse au-dessus du poignet : anneaux serres, un peu en biais.
        tasse = lisse((s - 0.27) / 0.08) * 0.0065 * math.sin(s * 150 + tour * 1.3)
        # Coude : deux ou trois plis plus larges, surtout a l'interieur du bras.
        coude = math.exp(-((s - 0.2) / 0.05) ** 2) * 0.0055 * math.sin(s * 95 + tour * 0.8) \
            * (0.5 + 0.5 * math.cos(tour + 1.2))
        # Aisselle : plis en eventail qui partent du dessous de l'epaule.
        dessous = max(0.0, -math.sin(tour))
        aisselle = math.exp(-(s / 0.07) ** 2) * dessous * 0.0045 * math.sin(tour * 7 + s * 40)
        return tasse + coude + aisselle
    # Tronc : plis doux au-dessus du bas cote (le tissu bouffe a la taille)...
    t = math.atan2(p.x, -p.y)
    taille = lisse((1.03 - p.z) / 0.1) * 0.006 * (0.5 + 0.5 * math.sin(p.z * 70 + math.sin(t * 3) * 1.8)) \
        * (0.6 + 0.4 * math.sin(t * 5 + 0.7))
    # ... et des plis en biais qui partent des aisselles sur les flancs.
    flanc = lisse((ax - 0.1) / 0.08) * math.exp(-((p.z - 1.2) / 0.08) ** 2)
    biais = flanc * 0.004 * math.sin((p.z + (ax - 0.15) * 0.8) * 90)
    return taille + biais


def sculpter(obj):
    obj.data.update()
    for v in obj.data.vertices:
        v.co += v.normal * plis(v.co)
    obj.data.update()


# ---------------------------------------------------------------- tartan

def coords_tissu(n, pas):
    """(u, w, z, masque des cotes) : u autour du corps / de la manche, w de
    haut en bas (hauteur sur le tronc, longueur sur la manche)."""
    v, x, y, z = n.coords()
    ax = n.absv(x)
    manche = n.gt(ax, EMMANCHURE)
    # Tronc : l'arc autour du corps (rayon moyen ~15 cm), la hauteur. Le tour
    # vaut un nombre entier de motifs : pas de raccord au milieu du dos.
    r_tronc = max(1, round(2 * math.pi * 0.15 * pas)) / (2 * math.pi * pas)
    u_tronc = n.mul(n.atan2(x, n.mul(y, -1.0)), r_tronc)
    # Manche : longueur le long du bras et arc autour (rayon ~5,5 cm, tour
    # entier lui aussi : le raccord sous le bras disparait).
    r_manche = max(1, round(2 * math.pi * 0.055 * pas)) / (2 * math.pi * pas)
    dx, dz = n.sub(ax, EPAULE.x), n.sub(z, EPAULE.z)
    s = n.add(n.mul(dx, BRAS.x), n.mul(dz, BRAS.z))
    haut = n.add(n.mul(dx, math.sin(PENTE)), n.mul(dz, math.cos(PENTE)))
    u_manche = n.mul(n.atan2(y, haut), r_manche)
    u = n.add(u_tronc, n.mul(manche, n.sub(u_manche, u_tronc)))
    w = n.add(z, n.mul(manche, n.sub(n.mul(s, -1.0), z)))
    cotes = n.maxv(n.maxv(n.lt(z, BAS_COTES), n.gt(z, COL_Z)), n.mul(manche, n.gt(s, POIGNET)))
    return u, w, cotes


def tartan(fond, bande, croise, filet, filet2=None, pas=9.0):
    """Un tartan : fond, larges bandes sombres dans les deux sens (plus sombres
    ou elles se croisent), filets fins ; serge en biais pour le tissage."""
    def motif(n):
        u, w, cotes = coords_tissu(n, pas)
        fu, fw = n.frac(n.mul(u, pas)), n.frac(n.mul(w, pas))
        bu, bw = n.lt(n.absv(n.sub(fu, 0.25)), 0.17), n.lt(n.absv(n.sub(fw, 0.25)), 0.17)
        c = n.couleur(fond)
        c = n.melange(n.mul(n.maxv(bu, bw), 0.8), c, bande)
        c = n.melange(n.mul(bu, bw), c, croise)
        fin = n.maxv(n.lt(n.absv(n.sub(fu, 0.7)), 0.009), n.lt(n.absv(n.sub(fw, 0.7)), 0.009))
        c = n.melange(fin, c, filet)
        if filet2:
            fin2 = n.maxv(n.lt(n.absv(n.sub(fu, 0.25)), 0.007), n.lt(n.absv(n.sub(fw, 0.25)), 0.007))
            c = n.melange(fin2, c, filet2)
        serge = n.lt(n.frac(n.mul(n.add(u, w), 260.0)), 0.5)
        c = n.melange(n.mul(serge, 0.1), c, "#000000")
        # Cotes (col, poignets, bas) : la couleur des bandes, cotes verticales.
        v, x, y, z = n.coords()
        rib = n.lt(n.frac(n.mul(u, 180.0)), 0.5)
        cote = n.melange(n.mul(rib, 0.25), bande, "#000000")
        return n.melange(cotes, c, cote)
    return motif


TARTANS = [
    # nom, motif, rarete, nom affiche
    ("Rouge", tartan("#b3202a", "#1e3a2f", "#12211b", "#f2d16b", "#f4f1ea"), "rare", "Manches longues tartan rouge"),
    ("Foret", tartan("#27543a", "#15234a", "#0b1226", "#0a0a0a"), "rare", "Manches longues tartan forêt"),
    ("Gris", tartan("#8d9095", "#2b2d31", "#17181b", "#e6e6e3"), "uncommon", "Manches longues tartan gris"),
    ("Moutarde", tartan("#c99a2e", "#3a2a1a", "#22170d", "#efe7d4"), "rare", "Manches longues tartan moutarde"),
    ("Ciel", tartan("#6fa9da", "#1f4f8a", "#133259", "#ffffff"), "uncommon", "Manches longues tartan ciel"),
    ("Rose", tartan("#dd8fab", "#6e3b55", "#4a2538", "#fbf6f0"), "rare", "Manches longues tartan rose"),
]


# ---------------------------------------------------------------- cuisson, apercus

def cuire(obj, motif, nom):
    img = bpy.data.images.new("T_COS_ML_" + nom, 2048, 2048, alpha=False)
    mat = bpy.data.materials.new("M_COS_ML_" + nom)
    mat.use_nodes = True
    n = N(mat)
    n.sortie(motif(n))
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
    import time
    for essai in range(5):
        try:
            img.save()
            break
        except RuntimeError:
            if essai == 4:
                raise
            time.sleep(1.5)
    return img


def main():
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    scene = bpy.context.scene
    rig = bpy.data.objects["Root"]
    corps = bpy.data.objects["SK_Animations.001"]
    for o in bpy.data.objects:
        if o.type == "MESH" and o is not corps:
            o.hide_render = True
    pantalon = P.importer("Pants_014")
    P.retirer_genouilleres(pantalon)
    jean = bpy.data.materials.new("Jean")
    jean.use_nodes = True
    jean.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.03, 0.05, 0.11, 1)
    pantalon.data.materials.append(jean)

    obj = base_sans_capuche()
    col_rond(obj)
    subdiviser(obj)
    sculpter(obj)
    P.gonfler(obj, 0.005)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    P.transferer_poids(obj, corps, rig)
    P.deplier(obj)
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.fbx(mesh_smooth_type="FACE", filepath=str(OUT / (PIECE + ".fbx")), use_selection=True,
                             object_types={"ARMATURE", "MESH"}, add_leaf_bones=False,
                             bake_anim=False, use_mesh_modifiers=True, armature_nodetype="NULL")
    print("PIECE", PIECE, len(obj.data.vertices), "sommets")

    cam = bpy.data.objects.new("Camera ML", bpy.data.cameras.new("Camera ML"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.lens = 50
    scene.render.resolution_x, scene.render.resolution_y = 700, 700
    manifeste = []
    for nom, motif, rarete, affiche in TARTANS:
        img = cuire(obj, motif, nom)
        obj.data.materials.clear()
        obj.data.materials.append(P.materiau_apercu(img))
        scene.render.engine = "BLENDER_EEVEE"
        for vue, direction in (("face", Vector((0.35, -1, 0.05))), ("dos", Vector((-0.4, 1, 0.1)))):
            vise = Vector((0, 0, 1.13))
            cam.location = vise + direction.normalized() * 1.9
            cam.rotation_euler = (vise - cam.location).to_track_quat("-Z", "Y").to_euler()
            scene.render.filepath = str(OUT / f"Apercu_{nom}{'' if vue == 'face' else '_dos'}.png")
            bpy.ops.render.render(write_still=True)
        if nom == TARTANS[0][0]:
            # Gros plan de verification sur la manche (plis), hors manifeste.
            vise = Vector((0.42, -0.02, 1.16))
            cam.location = vise + Vector((0.15, -1, 0.25)).normalized() * 0.8
            cam.rotation_euler = (vise - cam.location).to_track_quat("-Z", "Y").to_euler()
            scene.render.filepath = str(OUT / "verif_manche.png")
            bpy.ops.render.render(write_still=True)
        manifeste.append({"nom": affiche, "rarete": rarete, "piece": PIECE, "texture": img.name})
        print("TARTAN_PRET", nom)
    (OUT / "manifeste.json").write_text(json.dumps(manifeste, indent=2, ensure_ascii=False), encoding="utf-8")


main()
