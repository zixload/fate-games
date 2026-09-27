"""Tenues des PNJ (tailleur, armurier, forain, musicien, barman), une a la fois.

    blender -b --python scripts/blender/create_pnj_tenues.py -- <pnj> [<pnj>...]

Chaque tenue est une piece de haut du corps (chemise, gilet, accessoires
cousus) sur le corps Creative, ponderee sur son squelette comme les
vetements du tailleur, avec une seule texture cuite (une piece = un materiau,
doc Paintable). Le bas, les chaussures et la tete viennent du kit ou du
catalogue ; la tenue complete est decrite dans Shared/config.lua (pnj.types).

Sorties dans art/cosmetics/pnj/ (hors depot) : SK_PNJ_<Nom>_Haut.fbx,
T_PNJ_<Nom>_Haut.png, Apercu_<Nom>_{face,dos,detail}.png, manifeste.json.
"""

import json
import math
import sys
import importlib
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

PROJECT = Path(__file__).resolve().parents[2]
OUT = PROJECT / "art/cosmetics/pnj"
OUT.mkdir(parents=True, exist_ok=True)


def charger_module(nom, fichier):
    """Charge un script voisin sans lancer son main()."""
    src = (PROJECT / "scripts/blender" / fichier).read_text(encoding="utf-8")
    src = src.replace("\nmain()\n", "\n")
    mod = type(importlib)(nom)
    mod.__file__ = str(PROJECT / "scripts/blender" / fichier)
    exec(compile(src, mod.__file__, "exec"), mod.__dict__)
    return mod


ML = charger_module("manches_longues", "create_manches_longues.py")
P = ML.P                  # outils des pantalons (importer, gonfler, poids, UV)
N, lisse = P.N, P.lisse
EPAULE, BRAS, PENTE, EMMANCHURE = ML.EPAULE, ML.BRAS, ML.PENTE, ML.EMMANCHURE
HAUT_BRAS = Vector((math.sin(PENTE), 0.0, math.cos(PENTE)))   # perpendiculaire au bras, vers le haut


def axe_bras(s, cote):
    """Point de l'axe du bras a la distance s de l'epaule (cote +1 : x > 0)."""
    p = EPAULE + BRAS * s
    return Vector((p.x * cote, p.y, p.z))


def dir_bras(cote):
    return Vector((BRAS.x * cote, BRAS.y, BRAS.z))


# ---------------------------------------------------------------- outils de maillage

def objet_depuis_bm(bm, nom, materiau):
    me = bpy.data.meshes.new(nom)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(nom, me)
    bpy.context.collection.objects.link(o)
    me.materials.append(materiau)
    return o


def anneau(centre, axe, rayon, epais, allonge=1.0, segments=28, anneaux=10):
    """Tore autour de `axe` (bourrelet de manche retroussee, bracelet)."""
    axe = axe.normalized()
    a = axe.orthogonal().normalized()
    b = axe.cross(a).normalized()
    bm = bmesh.new()
    grille = []
    for i in range(segments):
        t = 2 * math.pi * i / segments
        radial = a * math.cos(t) + b * math.sin(t)
        rang = []
        for j in range(anneaux):
            u = 2 * math.pi * j / anneaux
            p = centre + radial * (rayon + epais * math.cos(u)) + axe * (epais * allonge * math.sin(u))
            rang.append(bm.verts.new(p))
        grille.append(rang)
    for i in range(segments):
        for j in range(anneaux):
            bm.faces.new((grille[i][j], grille[(i + 1) % segments][j],
                          grille[(i + 1) % segments][(j + 1) % anneaux], grille[i][(j + 1) % anneaux]))
    bm.normal_update()
    return bm


def sphere(centre, rayon, ecrase=Vector((1, 1, 1)), segs=16):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=max(6, segs // 2), radius=1.0)
    for v in bm.verts:
        v.co = centre + Vector((v.co.x * rayon * ecrase.x, v.co.y * rayon * ecrase.y, v.co.z * rayon * ecrase.z))
    return bm


def cylindre(a, b, rayon, segs=8):
    bm = bmesh.new()
    axe = (b - a)
    long = axe.length
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=rayon, radius2=rayon, depth=long)
    rot = Vector((0, 0, 1)).rotation_difference(axe.normalized())
    milieu = (a + b) / 2
    for v in bm.verts:
        v.co = milieu + rot @ v.co
    return bm


def fusionner(objets, nom):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objets:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objets[0]
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = nom
    return o


def appliquer(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


# ---------------------------------------------------------------- materiaux (emission, pour la cuisson)

def materiau(nom, construire):
    mat = bpy.data.materials.new(nom)
    mat.use_nodes = True
    n = N(mat)
    n.sortie(construire(n))
    return mat


def uni(hexa_):
    return lambda n: n.couleur(hexa_)


def tissu(fond, fonce, echelle=160.0, force=0.18):
    """Toile unie avec un grain de tissage fin."""
    def f(n):
        v, x, y, z = n.coords()
        grain = n.add(n.mul(n.sub(n.bruit(v, echelle, 2.0), 0.5), force), 0.5)
        return n.melange(grain, fonce, fond)
    return f


# ---------------------------------------------------------------- tailleur

def chemise_retroussee(corps):
    """Le sweat Creative sans capuche, col officier, manches coupees au coude
    avec un bourrelet retrousse."""
    obj = ML.base_sans_capuche()
    obj.name = "Chemise"
    ML.col_rond(obj)
    ML.subdiviser(obj)
    # Manches coupees un peu au-dessus du coude (s = 0,27 m depuis l'epaule).
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    a_couper = [v for v in bm.verts if abs(v.co.x) > EMMANCHURE and ML.le_long(v.co)[0] > 0.27]
    bmesh.ops.delete(bm, geom=a_couper, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    ML.sculpter(obj)
    P.gonfler(obj, 0.005)
    # Rayon de la manche a la coupe, pour y poser le bourrelet.
    rayons = {1: [], -1: []}
    for v in obj.data.vertices:
        if abs(v.co.x) > EMMANCHURE:
            s, q = ML.le_long(v.co)
            # Le bas du tronc pointe aussi "le long du bras" : on ne garde que la manche.
            if 0.24 < s <= 0.27 and q.length < 0.1:
                rayons[1 if v.co.x > 0 else -1].append(q.length)
    moyennes = {c: (sum(r) / len(r) if r else 0.055) for c, r in rayons.items()}
    print("MANCHE_RAYONS", {c: round(v, 4) for c, v in moyennes.items()}, {c: len(r) for c, r in rayons.items()})
    return obj, moyennes


def gilet_depuis(chemise):
    """Le tronc de la chemise, ouvert en V devant, sans manches ni col, decolle."""
    g = chemise.copy()
    g.data = chemise.data.copy()
    g.name = "Gilet"
    bpy.context.collection.objects.link(g)
    bm = bmesh.new()
    bm.from_mesh(g.data)
    # Coupes nettes (27/09 : supprimer des sommets laissait des marches) :
    # emmanchures, col, bas, puis les deux bords du V, chacun par un plan.
    X_EMM = EMMANCHURE - 0.012
    PENTE_V = 0.33                      # dx par dz du bord du V (bretelles de 7 cm)
    X0_V, Z0_V = 0.018, 1.08            # pointe du V
    plans = [(Vector((X_EMM, 0, 0)), Vector((1, 0, 0))), (Vector((-X_EMM, 0, 0)), Vector((-1, 0, 0))),
             (Vector((0, 0, 1.43)), Vector((0, 0, 1))), (Vector((0, 0, 0.905)), Vector((0, 0, -1))),
             (Vector((X0_V, 0, Z0_V)), Vector((-1, 0, PENTE_V)).normalized()),
             (Vector((-X0_V, 0, Z0_V)), Vector((1, 0, PENTE_V)).normalized())]
    for co, no in plans:
        geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no, dist=0.0005)

    def dehors(p):
        if abs(p.x) > X_EMM + 0.0006 or p.z > 1.4306 or p.z < 0.9044:
            return True
        largeur_v = X0_V + max(0.0, p.z - Z0_V) * PENTE_V
        return p.y < 0 and abs(p.x) < largeur_v - 0.0006 and p.z > Z0_V
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if dehors(v.co)], context="VERTS")
    # Les petits morceaux restes seuls (bord d'emmanchure, col) : dehors.
    vus, isoles = set(), []
    for f in bm.faces:
        if f in vus:
            continue
        pile, groupe = [f], []
        vus.add(f)
        while pile:
            h = pile.pop()
            groupe.append(h)
            for e in h.edges:
                for k in e.link_faces:
                    if k not in vus:
                        vus.add(k)
                        pile.append(k)
        if len(groupe) < 40:
            isoles += groupe
    bmesh.ops.delete(bm, geom=isoles, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(g.data)
    bm.free()
    g.data.update()
    P.gonfler(g, 0.009)
    s = g.modifiers.new("Epaisseur", "SOLIDIFY")
    s.thickness = 0.004
    s.offset = -1
    appliquer(g)
    return g


def projeter(arbre, angle, z, marge):
    """Point sur la surface (tenue) dans la direction horizontale `angle`
    (0 = devant, -y), a la hauteur z ; puis `marge` vers l'exterieur."""
    d = Vector((math.sin(angle), -math.cos(angle), 0.0))
    depart = Vector((0.0, 0.01, z)) + d * 0.6
    hit, normale, _, _ = arbre.ray_cast(depart, -d, 1.0)
    if hit is None:
        return Vector((0.0, 0.01, z)) + d * 0.16, d
    return hit + normale * marge, normale


def metre_ruban(arbre):
    """Ruban de couturiere passe sur la nuque, pendant sur la poitrine (plus
    long a droite). UV "Bande" : u le long du ruban (m), v en travers."""
    # (angle autour du corps, hauteur) : devant gauche -> nuque -> devant droit.
    chemin = [(0.34, 1.00), (0.36, 1.15), (0.42, 1.28), (0.62, 1.39), (1.2, 1.44), (math.pi, 1.455),
              (-1.2, 1.44), (-0.62, 1.39), (-0.42, 1.28), (-0.37, 1.12), (-0.35, 0.96), (-0.33, 0.91)]
    pts, norms = [], []
    for ang, z in chemin:
        p, nrm = projeter(arbre, ang, z, 0.006)
        pts.append(p)
        norms.append(nrm)
    # Catmull-Rom : un ruban souple.
    fins, fnorms = [], []
    for i in range(len(pts) - 1):
        p0, p1, p2, p3 = pts[max(i - 1, 0)], pts[i], pts[i + 1], pts[min(i + 2, len(pts) - 1)]
        for k in range(8):
            t = k / 8
            t2, t3 = t * t, t * t * t
            p = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
            fins.append(p)
            fnorms.append(norms[i].lerp(norms[i + 1], t).normalized())
    fins.append(pts[-1])
    fnorms.append(norms[-1])
    bm = bmesh.new()
    uv_lay = bm.loops.layers.uv.new("Bande")
    demi = 0.0125
    gauche, droite, longueurs = [], [], [0.0]
    for i, p in enumerate(fins):
        t = (fins[min(i + 1, len(fins) - 1)] - fins[max(i - 1, 0)]).normalized()
        cote = t.cross(fnorms[i]).normalized()
        gauche.append(bm.verts.new(p + cote * demi))
        droite.append(bm.verts.new(p - cote * demi))
        if i:
            longueurs.append(longueurs[-1] + (p - fins[i - 1]).length)
    for i in range(len(fins) - 1):
        f = bm.faces.new((gauche[i], gauche[i + 1], droite[i + 1], droite[i]))
        for loop, (u, v) in zip(f.loops, ((longueurs[i], 1), (longueurs[i + 1], 1), (longueurs[i + 1], 0), (longueurs[i], 0))):
            loop[uv_lay].uv = (u, v)
    bm.normal_update()
    o = objet_depuis_bm(bm, "Metre", MAT_TAILLEUR["metre"])
    s = o.modifiers.new("Epaisseur", "SOLIDIFY")
    s.thickness = 0.0015
    appliquer(o)
    return o


def boutons_et_chaine(arbre):
    objets = []
    zs = [1.085, 1.045, 1.005, 0.965]
    for z in zs:
        p, nrm = projeter(arbre, 0.0, z, 0.002)
        bm = sphere(p, 0.0065, Vector((1, 0.45, 1)))
        objets.append(objet_depuis_bm(bm, "Bouton", MAT_TAILLEUR["laiton"]))
    # Chaine de montre : du 3e bouton a la poche gauche du gilet.
    a, _ = projeter(arbre, 0.0, 1.005, 0.004)
    b, _ = projeter(arbre, 0.55, 0.985, 0.004)
    bm = bmesh.new()
    for k in range(14):
        t = k / 13
        p = a.lerp(b, t) + Vector((0, 0, -0.025 * math.sin(math.pi * t)))
        q, _ = projeter(arbre, math.atan2(p.x, -(p.y - 0.01)), p.z, 0.004)
        tmp = sphere(q, 0.0028, segs=8)
        me = bpy.data.meshes.new("tmp")
        tmp.to_mesh(me)
        tmp.free()
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
    objets.append(objet_depuis_bm(bm, "Chaine", MAT_TAILLEUR["or"]))
    return objets


def pelote(rayons_manche):
    """Pelote a epingles au poignet gauche (x > 0), sur le dessus de l'avant-bras."""
    cote = 1
    s = 0.40
    centre = axe_bras(s, cote)
    axe = dir_bras(cote)
    r_bras = 0.036
    objets = [objet_depuis_bm(anneau(centre, axe, r_bras + 0.004, 0.0045, allonge=1.6), "Bracelet",
                              MAT_TAILLEUR["cuir"])]
    haut = Vector((HAUT_BRAS.x * cote, HAUT_BRAS.y, HAUT_BRAS.z))
    dome_c = centre + haut * (r_bras + 0.006)
    objets.append(objet_depuis_bm(sphere(dome_c, 0.026, Vector((1, 1, 0.62))), "Pelote", MAT_TAILLEUR["pelote"]))
    epingles = bmesh.new()
    tetes = bmesh.new()
    for k, (du, dv) in enumerate(((0.008, 0.004), (-0.006, 0.009), (0.002, -0.009), (-0.01, -0.003), (0.012, -0.006))):
        pied = dome_c + axe * du + axe.cross(haut).normalized() * dv + haut * 0.008
        bout = pied + (haut * 1.0 + axe * (du * 20) + axe.cross(haut) * (dv * 20)).normalized() * 0.018
        for src, dst in ((cylindre(pied, bout, 0.0008, 6), epingles), (sphere(bout, 0.0028, segs=8), tetes)):
            me = bpy.data.meshes.new("tmp")
            src.to_mesh(me)
            src.free()
            dst.from_mesh(me)
            bpy.data.meshes.remove(me)
    objets.append(objet_depuis_bm(epingles, "Epingles", MAT_TAILLEUR["argent"]))
    objets.append(objet_depuis_bm(tetes, "Tetes", MAT_TAILLEUR["tetes"]))
    return objets


def gilet_motif(n):
    """Gilet bordeaux a fines rayures grises ; dos en satin fonce ; poches passepoilees."""
    v, x, y, z = n.coords()
    raie = n.lt(n.absv(n.sub(n.frac(n.mul(x, 110.0)), 0.5)), 0.06)
    devant = n.lt(y, 0.02)
    base = n.melange(n.mul(raie, 0.55), "#5e1a25", "#9a8f8a")
    grain = n.add(n.mul(n.sub(n.bruit(v, 140.0, 2.0), 0.5), 0.25), 0.5)
    base = n.melange(n.mul(grain, 0.5), base, "#4a141d")
    satin = n.melange(n.mul(n.sin(n.mul(z, 90.0)), 0.08), "#5e2632", "#70303c")
    base = n.melange(n.sub(1.0, devant), base, satin)
    # Poches : deux fentes sombres a hauteur de taille, devant.
    for cx in (0.085, -0.085):
        dx = n.absv(n.sub(x, cx))
        poche = n.mul(n.mul(n.lt(dx, 0.032), n.lt(n.absv(n.sub(z, 0.99)), 0.0045)), devant)
        base = n.melange(poche, base, "#1f0a0e")
    return base


def metre_motif(n):
    """Ruban jaune, graduations noires tous les centimetres, plus longues tous les 5 et 10."""
    uv = n.node("ShaderNodeUVMap")
    uv.uv_map = "Bande"
    u, vv, _ = n.sep(uv.outputs[0])
    cm = n.frac(n.mul(u, 100.0))
    trait = n.lt(cm, 0.12)
    long5 = n.lt(n.frac(n.mul(u, 20.0)), 0.025)
    long10 = n.lt(n.frac(n.mul(u, 10.0)), 0.014)
    bord = n.gt(vv, 0.62)
    marque = n.maxv(n.mul(trait, bord), n.maxv(n.mul(long5, n.gt(vv, 0.4)), long10))
    base = n.melange(n.mul(n.lt(n.absv(n.sub(vv, 0.5)), 0.48), 1.0), "#8a6d22", "#ecc94a")
    return n.melange(marque, base, "#1c1c1c")


MAT_TAILLEUR = {}


def tailleur(corps):
    MAT_TAILLEUR.update({
        "chemise": materiau("Chemise", tissu("#efe7d6", "#d9cfbb")),
        "gilet": materiau("Gilet", gilet_motif),
        "laiton": materiau("Laiton", uni("#c9a24a")),
        "or": materiau("Or", uni("#e0bd62")),
        "metre": materiau("Metre", metre_motif),
        "cuir": materiau("Cuir", tissu("#5a3a22", "#3e2716", 90.0, 0.3)),
        "pelote": materiau("Pelote", tissu("#b3282c", "#7e1a1d", 120.0, 0.35)),
        "argent": materiau("Argent", uni("#cfd3d6")),
        "tetes": materiau("Tetes", lambda n: n.rampe(n.bruit(n.coords()[0], 400.0, 1.0),
                                                    [(0.0, "#2f5fb3"), (0.35, "#d23b3b"), (0.6, "#2e8b57"), (1.0, "#e0b33a")], True)),
    })
    chemise, rayons = chemise_retroussee(corps)
    chemise.data.materials.clear()
    chemise.data.materials.append(MAT_TAILLEUR["chemise"])
    for p in chemise.data.polygons:
        p.use_smooth = True
    gilet = gilet_depuis(chemise)
    gilet.data.materials.clear()
    gilet.data.materials.append(MAT_TAILLEUR["gilet"])
    for p in gilet.data.polygons:
        p.use_smooth = True
    # Bourrelets des manches retroussees.
    roulis = []
    for cote in (1, -1):
        c = axe_bras(0.268, cote)
        roulis.append(objet_depuis_bm(anneau(c, dir_bras(cote), rayons[cote] + 0.006, 0.0085, allonge=1.5),
                                      "Retrousse", MAT_TAILLEUR["chemise"]))
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    arbre = BVHTree.FromObject(gilet, deps)
    arbre_tout = BVHTree.FromObject(chemise, deps)
    pieces = [chemise, gilet] + roulis + boutons_et_chaine(arbre) + [metre_ruban(arbre_tout)] + pelote(rayons)
    for o in pieces:
        for poly in o.data.polygons:
            poly.use_smooth = True
    return fusionner(pieces, "SK_PNJ_Tailleur_Haut")


PNJ = {
    # nom : (fabrique, tete du kit pour les apercus, couleur du pantalon d'apercu)
    "Tailleur": (tailleur, ["Hairstyle_male_012", "Moustache_002", "Glasses_004", "Male_emotion_usual_001"], (0.09, 0.09, 0.1, 1)),
}


# ---------------------------------------------------------------- cuisson, export, apercus

def cuire(obj, nom):
    """Nouveau jeu d'UV (seul garde) ; les materiaux (emission) cuits en une texture."""
    uv = obj.data.uv_layers.new(name="Design_UV")
    obj.data.uv_layers.active = uv
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(island_margin=0.01)
    bpy.ops.object.mode_set(mode="OBJECT")
    img = bpy.data.images.new("T_PNJ_" + nom + "_Haut", 2048, 2048, alpha=False)
    for slot in obj.material_slots:
        t = slot.material.node_tree
        cible = t.nodes.new("ShaderNodeTexImage")
        cible.image = img
        uvn = t.nodes.new("ShaderNodeUVMap")
        uvn.uv_map = "Design_UV"
        t.links.new(uvn.outputs[0], cible.inputs["Vector"])
        t.nodes.active = cible
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 4
    scene.cycles.device = "CPU"
    scene.render.bake.margin = 8
    bpy.ops.object.bake(type="EMIT", use_clear=True)
    img.filepath_raw = str(OUT / (img.name + ".png"))
    img.file_format = "PNG"
    img.save()
    for couche in [c for c in obj.data.uv_layers if c.name != "Design_UV"]:
        obj.data.uv_layers.remove(couche)
    obj.data.materials.clear()
    obj.data.materials.append(P.materiau_apercu(img))
    obj.data.update()
    bpy.context.view_layer.update()
    return img


def importer_kit(nom):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.wm.obj_import(filepath=str(P.KIT / (nom + ".obj")))
    objs = [o for o in bpy.context.selected_objects if o.type == "MESH"]
    for o in objs:
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return objs


def camera_vue(scene, vise, direction, distance, lens=50):
    cam = scene.camera
    cam.location = vise + direction.normalized() * distance
    cam.rotation_euler = (vise - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens


def main(noms):
    bpy.ops.wm.open_mainfile(filepath=str(ML.SOURCE))
    scene = bpy.context.scene
    rig = bpy.data.objects["Root"]
    corps = bpy.data.objects["SK_Animations.001"]
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o is not corps:
            bpy.data.objects.remove(o)
    cam = bpy.data.objects.new("Camera PNJ", bpy.data.cameras.new("Camera PNJ"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    manifeste_chemin = OUT / "manifeste.json"
    manifeste = {m["piece"]: m for m in json.loads(manifeste_chemin.read_text(encoding="utf-8"))} \
        if manifeste_chemin.is_file() else {}
    for nom in noms:
        fabrique, tete, couleur_bas = PNJ[nom]
        obj = fabrique(corps)
        P.transferer_poids(obj, corps, rig)
        img = cuire(obj, nom)
        bpy.ops.object.select_all(action="DESELECT")
        rig.select_set(True)
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.export_scene.fbx(filepath=str(OUT / (obj.name + ".fbx")), use_selection=True,
                                 object_types={"ARMATURE", "MESH"}, add_leaf_bones=False,
                                 bake_anim=False, use_mesh_modifiers=True, armature_nodetype="NULL")
        # Apercus : la tenue avec un pantalon, et la tete du kit.
        bas = P.importer("Pants_014")
        P.retirer_genouilleres(bas)
        m = bpy.data.materials.new("Bas")
        m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = couleur_bas
        bas.data.materials.append(m)
        extras = [bas]
        for piece in tete:
            extras += importer_kit(piece)
        scene.render.engine = "BLENDER_EEVEE"
        scene.render.resolution_x, scene.render.resolution_y = 800, 900
        for vue, (vise, direction, distance) in {
            "face": (Vector((0, 0, 1.2)), Vector((0.45, -1, 0.08)), 2.3),
            "dos": (Vector((0, 0, 1.2)), Vector((-0.35, 1, 0.08)), 2.3),
            "detail": (Vector((0.05, -0.05, 1.2)), Vector((0.3, -1, 0.15)), 1.05),
        }.items():
            camera_vue(scene, vise, direction, distance)
            scene.render.filepath = str(OUT / f"Apercu_{nom}_{vue}.png")
            bpy.ops.render.render(write_still=True)
        for o in extras + [obj]:
            o.hide_render = True
        manifeste[obj.name] = {"piece": obj.name, "texture": img.name, "pnj": nom}
        print("TENUE_PRETE", nom, len(obj.data.vertices), "sommets")
    manifeste_chemin.write_text(json.dumps([manifeste[k] for k in sorted(manifeste)], indent=2, ensure_ascii=False),
                                encoding="utf-8")


main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(PNJ))
