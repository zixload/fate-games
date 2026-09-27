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


def bride(nom, points, rayon, mat):
    """Un cordon ouvert qui passe par `points` (sangles)."""
    curve = bpy.data.curves.new(nom, "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 12
    curve.bevel_depth = rayon
    curve.bevel_resolution = 3
    # Bezier a poignees automatiques : une courbe souple (27/09).
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for node, co in zip(spline.bezier_points, points):
        node.co = co
        node.handle_left_type = node.handle_right_type = "AUTO"
    o = bpy.data.objects.new(nom, curve)
    bpy.context.collection.objects.link(o)
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.convert(target="MESH")
    o.data.materials.clear()
    o.data.materials.append(mat)
    return o


def bride_fermee(nom, points, rayon, mat):
    """Un tube ferme qui passe par `points` (bord arrondi du col)."""
    curve = bpy.data.curves.new(nom, "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 12
    curve.bevel_depth = rayon
    curve.bevel_resolution = 3
    # Bezier a poignees automatiques : une courbe souple (27/09).
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for node, co in zip(spline.bezier_points, points):
        node.co = co
        node.handle_left_type = node.handle_right_type = "AUTO"
    spline.use_cyclic_u = True
    o = bpy.data.objects.new(nom, curve)
    bpy.context.collection.objects.link(o)
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.convert(target="MESH")
    o.data.materials.clear()
    o.data.materials.append(mat)
    return o


def gilet_depuis(chemise):
    """Le tronc de la chemise, ouvert en V devant, sans manches ni col, decolle."""
    zc = [v.co.z for v in chemise.data.vertices if abs(v.co.x) < 0.05 and v.co.y > 0]
    ze = [v.co.z for v in chemise.data.vertices if 0.10 < abs(v.co.x) < 0.14]
    print("CHEMISE_HAUT dos", round(max(zc), 3), "epaule", round(max(ze), 3))
    g = chemise.copy()
    g.data = chemise.data.copy()
    g.name = "Gilet"
    bpy.context.collection.objects.link(g)
    bm = bmesh.new()
    bm.from_mesh(g.data)
    # Coupes nettes (27/09 : supprimer des sommets laissait des marches) :
    # emmanchures, col, bas, puis les deux bords du V, chacun par un plan.
    # Le gilet fait le tour du corps jusqu'a la couture des manches ; seule
    # l'emmanchure, en haut, est echancree en biais sous le bras (27/09 : coupe
    # verticale a 1 cm de la couture, la chemise se voyait sur les cotes).
    X_EMM = EMMANCHURE + 0.002
    R_COL = 0.103                        # le gilet vient toucher le col (27/09)
    X_IN, Z_HAUT, Z_BAS = EMMANCHURE - 0.035, 1.30, 1.16
    K_EMM = (X_EMM - X_IN) / (Z_HAUT - Z_BAS)
    # Le V rejoint la base du col (x = 7,5 cm a z = 1,42) : le gilet vient
    # toucher le col, bretelles sur toute l'epaule (27/09).
    PENTE_V = (0.075 - 0.018) / (1.42 - 1.08)
    X0_V, Z0_V = 0.018, 1.08            # pointe du V
    plans = [(Vector((X_EMM, 0, 0)), Vector((1, 0, 0))), (Vector((-X_EMM, 0, 0)), Vector((-1, 0, 0))),
             (Vector((X_IN, 0, Z_HAUT)), Vector((1, 0, K_EMM)).normalized()),
             (Vector((-X_IN, 0, Z_HAUT)), Vector((-1, 0, K_EMM)).normalized()),
             (Vector((0, 0, 0.905)), Vector((0, 0, -1))),
             ]
    for co, no in plans:
        geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no, dist=0.0005)

    def dehors(p):
        if p.z < 0.9044:
            return True
        # En haut, le gilet monte jusqu'a la base du col (rayon ~10 cm autour
        # du cou) au lieu d'une coupe plate a 1,43 m qui laissait une bande
        # blanche au dos et sur les epaules (27/09).
        # Sous l'aisselle, le tronc deborde la couture a la taille : seules les
        # manches (bien plus loin) sont coupees ; au-dessus, la couture.
        if abs(p.x) > (X_EMM + 0.0006 if p.z >= Z_BAS else 0.26):
            return True
        # Emmanchure : au-dessus de la ligne en biais, sous le bras.
        if p.z > Z_BAS and abs(p.x) > X_IN + (Z_HAUT - p.z) * K_EMM + 0.0006:
            return True
        # 27/09 : plus d'ouverture en V (le bord sortait en dents de scie) :
        # le gilet est ferme devant, jusqu'au col.
        return False
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if dehors(v.co)], context="VERTS")
    # Col : faces dont le centre tombe dans le cylindre du col (rayon 11,2 cm).
    # Par faces entieres, pas par sommets : supprimer des sommets laissait des
    # trous et des pointes au dos (27/09).
    def dans_col(f):
        c = f.calc_center_median()
        return c.z > 1.39 and math.hypot(c.x, c.y - 0.034) < R_COL
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if dans_col(f)], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
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
        if len(groupe) < 200:
            isoles += groupe
    bmesh.ops.delete(bm, geom=isoles, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    # Bord du col (coupe en escalier) : lisse le long de sa ligne.
    bord_col = [v for v in bm.verts if v.is_boundary and v.co.z > 1.38]
    # Recaler chaque sommet du bord sur le cercle du col, a sa hauteur : un
    # bord rond et net (le lissage laissait des pointes au dos).
    for v in bord_col:
        d = Vector((v.co.x, v.co.y - 0.034, 0))
        if d.length > 1e-4 and d.length < 0.13:
            d = d.normalized() * R_COL
            v.co.x, v.co.y = d.x, 0.034 + d.y
    # Bord du haut a une hauteur reguliere (les pointes venaient de sommets du
    # bord a des hauteurs differentes) : moyenne avec ses voisins sur le bord,
    # puis les deux rangees suivantes detendues pour suivre sans pli.
    for _ in range(8):
        nouveaux_z = {}
        for v in bord_col:
            voisins = [e.other_vert(v) for e in v.link_edges if e.other_vert(v) in bord_col]
            if voisins:
                nouveaux_z[v] = 0.5 * v.co.z + 0.5 * sum(w.co.z for w in voisins) / len(voisins)
        for v, z in nouveaux_z.items():
            v.co.z = z
    anneau = set(bord_col)
    for _ in range(2):
        anneau |= {e.other_vert(v) for v in list(anneau) for e in v.link_edges}
    interieur = [v for v in anneau if v not in bord_col]
    bmesh.ops.smooth_vert(bm, verts=interieur, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    zs_dos = [v.co.z for v in bm.verts if abs(v.co.x) < 0.05 and v.co.y > 0]
    zs_ep = [v.co.z for v in bm.verts if 0.10 < abs(v.co.x) < 0.14]
    print("GILET_HAUT dos", round(max(zs_dos), 3) if zs_dos else None, "epaule", round(max(zs_ep), 3) if zs_ep else None)
    bm.to_mesh(g.data)
    bm.free()
    g.data.update()
    P.gonfler(g, 0.011)
    s = g.modifiers.new("Epaisseur", "SOLIDIFY")
    s.thickness = 0.004
    s.offset = -1
    appliquer(g)
    return g


def cacher_sous(dessous, arbre_dessus, portee=0.04):
    """Surcouche : retire du vetement de dessous ce que celui du dessus couvre
    (27/09 : la chemise traversait le gilet sur les cotes et au milieu du
    torse). Une face part quand tous ses sommets, vus le long de leur normale,
    tombent sur le dessus a moins de `portee` ; les faces du bord, a moitie
    couvertes, restent : pas de trou a la lisiere du gilet."""
    dessous.data.update()
    couverts = set()
    for v in dessous.data.vertices:
        n = v.normal
        if arbre_dessus.ray_cast(v.co - n * 0.002, n, portee)[0] is not None:
            couverts.add(v.index)
    bm = bmesh.new()
    bm.from_mesh(dessous.data)
    bm.verts.ensure_lookup_table()
    retirees = [f for f in bm.faces if all(v.index in couverts for v in f.verts)]
    bmesh.ops.delete(bm, geom=retirees, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(dessous.data)
    bm.free()
    dessous.data.update()
    print("SURCOUCHE", dessous.name, len(retirees), "faces cachees retirees")


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
    # Bord du col arrondi : un petit bourrelet le long de son sommet (27/09).
    anneau_col = []
    for k in range(48):
        t = 2 * math.pi * k / 48
        dx, dy = math.sin(t), math.cos(t)
        meilleurs = [v.co for v in chemise.data.vertices
                     if 0.07 < math.hypot(v.co.x, v.co.y - 0.034) < 0.115
                     and (v.co.x * dx + (v.co.y - 0.034) * dy) > 0.97 * math.hypot(v.co.x, v.co.y - 0.034)]
        if meilleurs:
            anneau_col.append(max(meilleurs, key=lambda c: c.z).copy())
    if len(anneau_col) > 8:
        roulis_col = bride_fermee("Bord du col", anneau_col, 0.0055, MAT_TAILLEUR["chemise"])
    else:
        roulis_col = None
    # Bourrelets des manches retroussees.
    roulis = []
    for cote in (1, -1):
        c = axe_bras(0.268, cote)
        roulis.append(objet_depuis_bm(anneau(c, dir_bras(cote), rayons[cote] + 0.006, 0.0085, allonge=1.5),
                                      "Retrousse", MAT_TAILLEUR["chemise"]))
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    arbre = BVHTree.FromObject(gilet, deps)
    # Le metre se pose sur la couche la plus exterieure : gilet ou chemise.
    sommets, faces = [], []
    for o in (chemise, gilet):
        base = len(sommets)
        sommets += [o.matrix_world @ v.co for v in o.data.vertices]
        faces += [tuple(base + i for i in poly.vertices) for poly in o.data.polygons]
    arbre_tout = BVHTree.FromPolygons(sommets, faces)
    cacher_sous(chemise, arbre)
    pieces = [chemise, gilet] + roulis + ([roulis_col] if roulis_col else []) + boutons_et_chaine(arbre) + [metre_ruban(arbre_tout)] + pelote(rayons)
    for o in pieces:
        for poly in o.data.polygons:
            poly.use_smooth = True
    if "--debug" in sys.argv:
        bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "debug_tailleur.blend"), copy=True)
    return fusionner(pieces, "SK_PNJ_Tailleur_Haut")


# ---------------------------------------------------------------- armurier (forgeron)

MAT_FORGE = {}


def rigide(o, os_, test):
    """Marque les sommets `test(v)` pour les lier entierement a l'os `os_`
    apres le transfert des poids (voir appliquer_rigides)."""
    g = o.vertex_groups.get("RIGIDE:" + os_) or o.vertex_groups.new(name="RIGIDE:" + os_)
    g.add([v.index for v in o.data.vertices if test(v)], 1.0, "REPLACE")


def appliquer_rigides(obj):
    for g in [g for g in obj.vertex_groups if g.name.startswith("RIGIDE:")]:
        os_ = g.name.split(":", 1)[1]
        cible = obj.vertex_groups.get(os_) or obj.vertex_groups.new(name=os_)
        marques = [v.index for v in obj.data.vertices if any(a.group == g.index for a in v.groups)]
        for autre in obj.vertex_groups:
            if autre.name != os_ and not autre.name.startswith("RIGIDE:"):
                autre.remove(marques)
        cible.add(marques, 1.0, "REPLACE")
    for g in [g for g in obj.vertex_groups if g.name.startswith("RIGIDE:")]:
        obj.vertex_groups.remove(g)


def cuir(fond, fonce, echelle=45.0):
    """Cuir epais : marbrure sombre et grain serre."""
    def f(n):
        v, x, y, z = n.coords()
        marbre = n.bruit(v, echelle, 4.0, 0.6)
        grain = n.add(n.mul(n.sub(n.bruit(v, 260.0, 2.0), 0.5), 0.3), 0.5)
        c = n.melange(marbre, fonce, fond)
        return n.melange(n.mul(grain, 0.35), c, fonce)
    return f


def tablier(arbre_devant):
    """Grand tablier de cuir : bavette sur la poitrine, jupe plate jusqu'a
    mi-cuisse. Chaque point est pose devant la tenue (rayon lance depuis
    l'avant) ; sous la taille, la jupe tombe droit devant les deux jambes."""
    colonnes, rangs = 17, 26
    z_haut, z_bas, z_taille = 1.345, 0.70, 1.0
    grille = []
    for j in range(rangs):
        z = z_haut - (z_haut - z_bas) * j / (rangs - 1)
        # Bavette etroite en haut, qui s'evase jusqu'a la taille.
        t = min(1.0, max(0.0, (z_haut - z) / (z_haut - 1.08)))
        demi = 0.085 + (0.165 - 0.085) * (t * t * (3 - 2 * t))
        rang = []
        for i in range(colonnes):
            x = -demi + 2 * demi * i / (colonnes - 1)
            hit = arbre_devant.ray_cast(Vector((x, -0.6, z)), Vector((0, 1, 0)), 1.0)[0]
            rang.append(Vector((x, (hit.y if hit else -0.13) - 0.012, z)))
        grille.append(rang)
    # Jupe : plate, au niveau le plus en avant de sa rangee de taille.
    ref = min(p.y for r in grille if abs(r[0].z - z_taille) < 0.03 for p in r)
    for j, rang in enumerate(grille):
        z = rang[0].z
        if z < z_taille + 0.08:
            y_plat = min(min(p.y for p in rang), ref)
            # Fondu sur 12 cm autour de la taille : pas de pli au bassin.
            k = min(1.0, max(0.0, (z_taille + 0.08 - z) / 0.12))
            k = k * k * (3 - 2 * k)
            for p in rang:
                # Et 1,5 cm plus en avant : le pull ne depasse plus au bassin.
                p.y = p.y + (y_plat - 0.015 - p.y) * k
    bm = bmesh.new()
    vs = [[bm.verts.new(p) for p in rang] for rang in grille]
    for j in range(rangs - 1):
        for i in range(colonnes - 1):
            bm.faces.new((vs[j][i], vs[j][i + 1], vs[j + 1][i + 1], vs[j + 1][i]))
    bm.normal_update()
    o = objet_depuis_bm(bm, "Tablier", MAT_FORGE["cuir"])
    s = o.modifiers.new("Epaisseur", "SOLIDIFY")
    s.thickness = 0.008
    s.offset = 1
    s.use_rim = True
    b = o.modifiers.new("Bords", "BEVEL")
    b.width = 0.002
    b.segments = 2
    appliquer(o)
    return o, grille


def armurier(corps):
    MAT_FORGE.update({
        "chemise": materiau("Chemise forge", tissu("#3c4148", "#2b2f35")),
        "cuir": materiau("Cuir tablier", cuir("#6e4526", "#3f2513")),
        "sangle": materiau("Sangle", cuir("#3b2616", "#231509", 90.0)),
        "laiton": materiau("Rivets", uni("#c29a45")),
        "fer": materiau("Fer", lambda n: n.melange(n.bruit(n.coords()[0], 60.0, 3.0), "#2b2d30", "#56595e")),
        "bois": materiau("Bois", cuir("#7a5431", "#4e3219", 30.0)),
        "gant": materiau("Gants", cuir("#a07548", "#6d4a28", 70.0)),
    })
    chemise, rayons = chemise_retroussee(corps)
    chemise.data.materials.clear()
    chemise.data.materials.append(MAT_FORGE["chemise"])
    bpy.context.view_layer.update()
    arbre_chemise = BVHTree.FromObject(chemise, bpy.context.evaluated_depsgraph_get())
    mw = corps.matrix_world
    # Devant : chemise + corps (le bas du tablier passe devant le pantalon).
    sommets, faces = [], []
    for o, m in ((chemise, chemise.matrix_world), (corps, mw)):
        base = len(sommets)
        sommets += [m @ v.co for v in o.data.vertices]
        faces += [tuple(base + i for i in poly.vertices) for poly in o.data.polygons]
    arbre_devant = BVHTree.FromPolygons(sommets, faces)
    tab, grille = tablier(arbre_devant)

    pieces = [chemise, tab]
    # Ourlet de cuir fonce tout autour du tablier : un bord fini, epais.
    contour = [p.copy() for p in grille[0]] + [r[-1].copy() for r in grille[1:]]         + [p.copy() for p in reversed(grille[-1][:-1])] + [r[0].copy() for r in reversed(grille[1:-1])]
    for q in contour:
        q.y -= 0.004
    ourlet = bride_fermee("Ourlet", contour, 0.0048, MAT_FORGE["sangle"])
    rigide(ourlet, "Hips", lambda v: v.co.z < 1.0)
    pieces.append(ourlet)
    # Bourrelets des manches retroussees.
    for cote in (1, -1):
        c = axe_bras(0.268, cote)
        pieces.append(objet_depuis_bm(anneau(c, dir_bras(cote), rayons[cote] + 0.006, 0.0085, allonge=1.5),
                                      "Retrousse", MAT_FORGE["chemise"]))
    # Sangle du cou : des coins de la bavette, par-dessus les epaules, derriere la nuque.
    haut_g, haut_d = grille[0][0], grille[0][-1]
    chemin = []
    for ang, z in ((0.62, 1.40), (0.95, 1.44), (1.6, 1.465), (math.pi, 1.47), (-1.6, 1.465), (-0.95, 1.44), (-0.62, 1.40)):
        p, _ = projeter(arbre_chemise, ang, z, 0.006)
        chemin.append(p)
    pieces.append(bride("Sangle cou", [haut_d] + chemin + [haut_g], 0.0055, MAT_FORGE["sangle"]))
    # Sangle de taille : fait le tour du corps, noeud dans le dos.
    tour = []
    for k in range(40):
        ang = 2 * math.pi * k / 40
        p, _ = projeter(arbre_devant, ang, 1.0, 0.009)
        if abs(ang) < 0.9 or abs(ang - 2 * math.pi) < 0.9:
            p.y = min(p.y, grille[13][0].y - 0.004)
        tour.append(p)
    pieces.append(bride_fermee("Sangle taille", tour, 0.006, MAT_FORGE["sangle"]))
    dos, _ = projeter(arbre_devant, math.pi, 1.0, 0.014)
    pieces.append(objet_depuis_bm(sphere(dos, 0.016, Vector((1.4, 0.7, 1))), "Noeud", MAT_FORGE["sangle"]))
    # Rivets aux coins de la bavette et de la poche.
    for p in (grille[1][1], grille[1][-2]):
        pieces.append(objet_depuis_bm(sphere(p + Vector((0, -0.006, 0)), 0.0055, Vector((1, 0.5, 1))), "Rivet", MAT_FORGE["laiton"]))
    # Poche a outils sur la jupe, avec deux rivets.
    jp = 19
    y_jupe = grille[jp][8].y - 0.006
    poche = bmesh.new()
    bmesh.ops.create_cube(poche, size=1.0)
    for v in poche.verts:
        # Poche profonde de 2,4 cm : les manches des outils tiennent dedans.
        v.co = Vector((v.co.x * 0.15, y_jupe - 0.012 + v.co.y * 0.024, grille[jp][0].z + v.co.z * 0.11))
    bmesh.ops.bevel(poche, geom=list(poche.verts) + list(poche.edges), offset=0.004, segments=2, affect="EDGES")
    pieces.append(objet_depuis_bm(poche, "Poche", MAT_FORGE["cuir"]))
    for x in (-0.07, 0.07):
        pieces.append(objet_depuis_bm(sphere(Vector((x, y_jupe - 0.025, grille[jp][0].z + 0.048)), 0.005,
                                             Vector((1, 0.5, 1))), "Rivet", MAT_FORGE["laiton"]))
    # Rigide sur le bassin : la jupe du tablier et ce qui y pend (sinon elle
    # se tord avec les jambes croisees de sa pose, 27/09).
    for o in pieces:
        if o.name.split(".")[0] in ("Poche", "Manche", "Tete marteau", "Pince"):
            rigide(o, "Hips", lambda v: True)
        elif o is tab:
            rigide(o, "Hips", lambda v: v.co.z < 1.0)
    for o in pieces:
        for poly in o.data.polygons:
            poly.use_smooth = True
    return fusionner(pieces, "SK_PNJ_Armurier_Haut")


# ---------------------------------------------------------------- musicien (poncho des Andes)

MAT_MUS = {}


def poncho_motif(n):
    """Tissage andin : bandes (rouge, moutarde, sarcelle, creme, noir) en
    zigzag qui font le tour du corps, sur une maille tressee en chevrons."""
    v, x, y, z = n.coords()
    u = n.mul(n.atan2(x, n.mul(y, -1.0)), 0.15)            # tour du corps, en m
    zig = n.mul(n.absv(n.sub(n.frac(n.mul(u, 18.0)), 0.5)), 0.022)
    # Rythme 1 / 3 (27/09) : une bande de motif, puis trois fois sa hauteur en
    # rouge uni, et ainsi de suite.
    # Unite de 3,3 cm, periode de 4 unites, a partir du bas du poncho (1,17 m) :
    # motif / rouge x3 / motif / rouge x3 / motif sur sa hauteur.
    periode = n.frac(n.mul(n.add(n.sub(z, 1.17), zig), 7.5))
    motif = n.lt(periode, 0.25)
    h = n.mul(periode, 4.0)
    bande = n.rampe(h, [(0.0, "#1c1a1a"), (0.08, "#e2b33c"), (0.34, "#1c1a1a"), (0.40, "#f1e6cf"),
                        (0.58, "#1c1a1a"), (0.64, "#1f6f6a"), (0.92, "#1c1a1a"), (1.0, "#1c1a1a")], True)
    c = n.melange(motif, "#a3262a", bande)
    # Maille tressee : petites cotes en V (chevrons), creuses et bosses.
    cu = n.absv(n.sub(n.frac(n.mul(u, 120.0)), 0.5))
    maille = n.absv(n.sub(n.frac(n.add(n.mul(z, 150.0), n.mul(cu, 1.2))), 0.5))
    c = n.melange(n.mul(n._smooth(0.25, 0.3, maille), 0.45), c, "#1c1a1a")
    grain = n.add(n.mul(n.sub(n.bruit(v, 180.0, 2.0), 0.5), 0.2), 0.5)
    return n.melange(n.mul(grain, 0.2), c, "#1c1a1a")


def poncho_depuis(chemise):
    """Poncho court sur les epaules : le haut de la chemise (au-dessus de
    1,17 m, plus le haut des manches), decolle et epaissi. 27/09 : la version
    evasee en pointe se superposait aux manches, retour a celle-ci."""
    g = chemise.copy()
    g.data = chemise.data.copy()
    g.name = "Poncho"
    bpy.context.collection.objects.link(g)
    bm = bmesh.new()
    bm.from_mesh(g.data)
    Z_BAS = 1.17
    geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector((0, 0, Z_BAS)), plane_no=Vector((0, 0, -1)), dist=0.0005)

    def garder(f):
        c = f.calc_center_median()
        if c.z < Z_BAS - 0.0005:
            return False
        if abs(c.x) > EMMANCHURE and ML.le_long(c)[0] > 0.10:
            return False                       # au-dela du haut des manches
        if c.z > 1.39 and math.hypot(c.x, c.y - 0.034) < 0.103:
            return False                       # le col reste visible
        return True
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if not garder(f)], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(g.data)
    bm.free()
    g.data.update()
    P.gonfler(g, 0.013)
    # Le bord du bas, avant l'epaisseur (qui le referme) : pour les franges.
    bm2 = bmesh.new()
    bm2.from_mesh(g.data)
    g["bord_bas"] = [c for v in bm2.verts if v.is_boundary and v.co.z < Z_BAS + 0.01 for c in v.co]
    bm2.free()
    s = g.modifiers.new("Epaisseur", "SOLIDIFY")
    s.thickness = 0.006
    s.offset = -1
    s.use_rim = True
    appliquer(g)
    return g


def franges(poncho, mat):
    """Franges de laine : un brin tous les 9 mm, longueurs et ondulations
    toutes differentes (pas de rangee uniforme), dans la texture du poncho.
    Chaque brin ondule en descendant, avec beaucoup de segments."""
    import random
    hasard = random.Random(7)
    brut = list(poncho["bord_bas"])
    bas = [Vector(brut[i:i + 3]) for i in range(0, len(brut), 3)]
    bas.sort(key=lambda c: math.atan2(c.x, -c.y))
    brins = []
    dernier = None
    for c in bas:
        if dernier is not None and (c - dernier).length < 0.009:
            continue
        dernier = c
        dehors = Vector((c.x, c.y - 0.01, 0))
        dehors = dehors.normalized() if dehors.length > 1e-4 else Vector((0, -1, 0))
        cote = Vector((0, 0, 1)).cross(dehors).normalized()
        longueur = hasard.uniform(0.022, 0.048)
        phase = hasard.uniform(0, 2 * math.pi)
        amplitude = hasard.uniform(0.002, 0.005)
        penche = hasard.uniform(-0.006, 0.006)
        pts = []
        for k in range(9):
            t = k / 8
            ondule = math.sin(phase + t * 2.6 * math.pi) * amplitude * t
            pts.append(c + Vector((0, 0, 0.002 - longueur * t))
                       + dehors * (0.004 * t + 0.002 * t * t)
                       + cote * (ondule + penche * t))
        brins.append(bride("Frange", pts, hasard.uniform(0.0021, 0.0031), mat))
    for b in brins:
        b.data.materials.clear()
        b.data.materials.append(mat)
    return fusionner(brins, "Franges")


def musicien(corps):
    MAT_MUS.update({
        "chemise": materiau("Chemise musicien", tissu("#e6dcc4", "#cbbf a3".replace(" ", ""))),
        "poncho": materiau("Poncho", poncho_motif),
        "franges": materiau("Franges", tissu("#efe5cf", "#d6c7a5", 260.0, 0.3)),
    })
    chemise, rayons = chemise_retroussee(corps)
    chemise.data.materials.clear()
    chemise.data.materials.append(MAT_MUS["chemise"])
    poncho = poncho_depuis(chemise)
    poncho.data.materials.clear()
    poncho.data.materials.append(MAT_MUS["poncho"])
    bpy.context.view_layer.update()
    cacher_sous(chemise, BVHTree.FromObject(poncho, bpy.context.evaluated_depsgraph_get()))
    # Franges en laine beige clair (27/09).
    pieces = [chemise, poncho, franges(poncho, MAT_MUS["franges"])]
    for cote in (1, -1):
        c = axe_bras(0.268, cote)
        pieces.append(objet_depuis_bm(anneau(c, dir_bras(cote), rayons[cote] + 0.006, 0.0085, allonge=1.5),
                                      "Retrousse", MAT_MUS["chemise"]))
    for o in pieces:
        for poly in o.data.polygons:
            poly.use_smooth = True
    return fusionner(pieces, "SK_PNJ_Musicien_Haut")



def pantalon_rapiece(n, reperes_):
    """Toile beige avec trois pieces cousues (velours brun, jean delave, toile
    verte) et leurs points de couture, comme reparees a la main."""
    v, x, y, z = n.coords()
    grain = n.add(n.mul(n.sub(n.bruit(v, 150.0, 2.0), 0.5), 0.22), 0.5)
    base = n.melange(grain, "#a8946c", "#cdb98f")
    devant = n.lt(y, 0.0)
    derriere = n.gt(y, 0.0)
    # (centre x, centre z, demi-largeur, demi-hauteur, face, couleur, couleur fonce)
    pieces = ((0.10, 0.50, 0.055, 0.06, devant, "#6a4a2c", "#4a321d"),     # genou gauche
              (-0.11, 0.78, 0.05, 0.045, devant, "#5c7ea3", "#3f5c7c"),    # cuisse droite
              (0.09, 0.25, 0.045, 0.05, derriere, "#5f7a45", "#435733"))   # mollet gauche, derriere
    for cx, cz, lx, lz, face, c1, c2 in pieces:
        dx, dz = n.absv(n.sub(x, cx)), n.absv(n.sub(z, cz))
        dedans = n.mul(n.mul(n.lt(dx, lx), n.lt(dz, lz)), face)
        texture = n.melange(n.mul(n.lt(n.frac(n.mul(n.add(x, z), 90.0)), 0.5), 0.35), c1, c2)
        base = n.melange(dedans, base, texture)
        # Couture : tirets clairs a 6 mm du bord de la piece.
        bord = n.maxv(n.mul(n.lt(n.absv(n.sub(dx, lx - 0.006)), 0.0016), n.lt(dz, lz - 0.004)),
                      n.mul(n.lt(n.absv(n.sub(dz, lz - 0.006)), 0.0016), n.lt(dx, lx - 0.004)))
        tiret = n.lt(n.frac(n.mul(n.add(x, z), 70.0)), 0.55)
        base = n.melange(n.mul(n.mul(bord, tiret), face), base, "#efe2c0")
    return P.bandes(n, x, z, base, "#8f7b55", reperes_)


def pantalon_pnj(corps, rig, motif, nom):
    """Pantalon droit du kit (Pants_014, sans genouilleres), motif cuit."""
    bas = P.importer("Pants_014")
    P.retirer_genouilleres(bas)
    P.gonfler(bas)
    bas.modifiers.new("Lisse", "SUBSURF").levels = 1
    P.transferer_poids(bas, corps, rig)
    P.deplier(bas)
    bas.name = "SK_PNJ_" + nom + "_Bas"
    rep_ = P.reperes(bas)
    img = bpy.data.images.new("T_PNJ_" + nom + "_Bas", 2048, 2048, alpha=False)
    mat = bpy.data.materials.new("M_PNJ_" + nom + "_Bas")
    mat.use_nodes = True
    nn = N(mat)
    nn.sortie(motif(nn, rep_))
    cible = nn.node("ShaderNodeTexImage")
    cible.image = img
    nn.t.nodes.active = cible
    bas.data.materials.clear()
    bas.data.materials.append(mat)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 4
    scene.render.bake.margin = 8
    bpy.ops.object.select_all(action="DESELECT")
    bas.select_set(True)
    bpy.context.view_layer.objects.active = bas
    bpy.ops.object.bake(type="EMIT", use_clear=True)
    img.filepath_raw = str(OUT / (img.name + ".png"))
    img.file_format = "PNG"
    img.save()
    bas.data.materials.clear()
    bas.data.materials.append(P.materiau_apercu(img))
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    bas.select_set(True)
    bpy.context.view_layer.objects.active = bas
    bpy.ops.export_scene.fbx(filepath=str(OUT / (bas.name + ".fbx")), use_selection=True,
                             object_types={"ARMATURE", "MESH"}, add_leaf_bones=False,
                             bake_anim=False, use_mesh_modifiers=True, armature_nodetype="NULL")
    return bas, img


# Pantalons des PNJ (nom -> motif) ; les autres gardent un pantalon uni d'apercu.
BAS_PNJ = {"Musicien": pantalon_rapiece}


PNJ = {
    # nom : (fabrique, tete du kit pour les apercus, couleur du pantalon d'apercu)
    "Tailleur": (tailleur, ["Hairstyle_male_012", "Moustache_002", "Glasses_004", "Male_emotion_usual_001"], (0.09, 0.09, 0.1, 1)),
    "Armurier": (armurier, ["Moustache_001", "Male_emotion_angry_003"], (0.16, 0.13, 0.1, 1)),
    "Musicien": (musicien, ["Hairstyle_male_010", "Male_emotion_happy_002"], (0.2, 0.15, 0.1, 1)),
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
        appliquer_rigides(obj)
        img = cuire(obj, nom)
        bpy.ops.object.select_all(action="DESELECT")
        rig.select_set(True)
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.export_scene.fbx(filepath=str(OUT / (obj.name + ".fbx")), use_selection=True,
                                 object_types={"ARMATURE", "MESH"}, add_leaf_bones=False,
                                 bake_anim=False, use_mesh_modifiers=True, armature_nodetype="NULL")
        # Apercus : la tenue avec son pantalon (ou un pantalon uni), et la tete du kit.
        if nom in BAS_PNJ:
            bas, img_bas = pantalon_pnj(corps, rig, BAS_PNJ[nom], nom)
            manifeste[bas.name] = {"piece": bas.name, "texture": img_bas.name, "pnj": nom}
        else:
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


main([a for a in sys.argv[sys.argv.index("--") + 1:] if not a.startswith("--")] if "--" in sys.argv else list(PNJ))
