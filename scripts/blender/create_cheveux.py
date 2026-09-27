"""Coiffures construites sur le crane du corps Creative.

    python scripts/blender/palette_atlas.py      (une fois : les cases de couleur)
    blender -b --python scripts/blender/create_cheveux.py -- <style> [<style>...]

La surface de la tete du corps (sommets lies a l'os Head) est reprise au-dessus
d'une ligne d'implantation propre a chaque coupe (haute sur le front, basse
derriere), decollee du crane et epaissie : la coiffure epouse la tete, sans
trou ni vide. Chaque style deforme ensuite cette calotte. Couleurs naturelles,
sur l'atlas du kit (art/cosmetics/tete/palette.json), avec un leger degrade.

Sorties dans art/cosmetics/cheveux/ (hors depot) : un FBX par coupe et trois
apercus (face, profil, dos).
"""

import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector, noise
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

PROJECT = Path(__file__).resolve().parents[2]
SOURCE = PROJECT / "art/cosmetics/tshirts/creative_tshirt_rarities.blend"
KIT = Path("C:/ProgramData/Epic/EpicGamesLauncher/VaultCache/FabLibrary/"
           "Creative_Characters_FREE_-_Animated_Low_Poly_3D_Models-94fd60a2/obj/source_extracted/"
           "Separate_assets_obj_extracted/Separate_assets_obj")
OUT = PROJECT / "art/cosmetics/cheveux"
OUT.mkdir(parents=True, exist_ok=True)
PALETTE = json.loads((PROJECT / "art/cosmetics/tete/palette.json").read_text(encoding="utf-8"))

# Centre du crane (mesure sur le corps Creative), le personnage regarde vers -y.
CRANE = Vector((0.0, -0.014, 1.70))


def lisse(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


def angle_arriere(p):
    """0 face au visage, 1 a l'arriere du crane."""
    return abs(math.atan2(p.x, -(p.y - CRANE.y))) / math.pi


# ---------------------------------------------------------------- calotte

def surface_tete(corps):
    """Les faces de la tete du corps (sommets lies a Head), en coordonnees du monde."""
    g = corps.vertex_groups["Head"].index
    tete = set()
    for v in corps.data.vertices:
        if any(a.group == g and a.weight > 0.5 for a in v.groups):
            tete.add(v.index)
    mw = corps.matrix_world
    bm = bmesh.new()
    nouveaux = {}
    for f in corps.data.polygons:
        if all(i in tete for i in f.vertices):
            vs = []
            for i in f.vertices:
                if i not in nouveaux:
                    nouveaux[i] = bm.verts.new(mw @ corps.data.vertices[i].co)
                vs.append(nouveaux[i])
            try:
                bm.faces.new(vs)
            except ValueError:
                pass
    bm.normal_update()
    return bm


def calotte(corps, ligne, decalage, epaisseur=0.012, apres=None, niveaux=2):
    """ligne(p) -> hauteur d'implantation ; decalage(p, n) -> distance au crane."""
    bm = surface_tete(corps)
    # Le maillage de la tete est en deux moities (sommets doubles au milieu) :
    # sans fusion, chaque moitie se decolle de son cote et la coiffure se fend.
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0015)
    # Le centre de chaque face decide : le maillage a de grandes faces, exiger
    # tous leurs sommets au-dessus de la ligne remontait l'implantation.
    garder = [f for f in bm.faces if f.calc_center_median().z >= ligne(f.calc_center_median())]
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f not in set(garder)], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    # Les petits morceaux isoles (faces restees seules sous la ligne) : dehors.
    vus, isoles = set(), []
    for f in bm.faces:
        if f in vus:
            continue
        pile, groupe = [f], []
        vus.add(f)
        while pile:
            g = pile.pop()
            groupe.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h not in vus:
                        vus.add(h)
                        pile.append(h)
        if len(groupe) < 12:
            isoles += groupe
    bmesh.ops.delete(bm, geom=isoles, context="FACES")
    # Les petits trous dans la calotte (une face exclue au milieu) : combles.
    bmesh.ops.holes_fill(bm, edges=bm.edges, sides=8)
    # Les oreilles ne font pas partie de la coiffure.
    bm.normal_update()
    for v in bm.verts:
        n = v.normal.copy()
        v.co = v.co + n * decalage(v.co, n)
    bmesh.ops.smooth_vert(bm, verts=bm.verts, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    if apres:
        apres(bm, corps)
    me = bpy.data.meshes.new("Coiffure")
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("Coiffure", me)
    bpy.context.collection.objects.link(o)
    bpy.context.view_layer.objects.active = o
    # Epaisseur vers le crane : on ne voit jamais le vide sous la coiffure.
    m = o.modifiers.new("Epaisseur", "SOLIDIFY")
    m.thickness = epaisseur
    m.offset = -1
    m.use_even_offset = True
    m.use_rim = True
    s = o.modifiers.new("Lisse", "SUBSURF")
    s.levels = niveaux
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    for mod in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def colorer_degrade(o, couleur, amplitude=0.02):
    """La case de la couleur, et un leger degrade du bas (fonce) vers le haut."""
    u, v = PALETTE[couleur]
    zs = [x.co.z for x in o.data.vertices]
    bas, haut = min(zs), max(zs)
    if not o.data.uv_layers:
        o.data.uv_layers.new(name="UVMap")
    uv = o.data.uv_layers[0].data
    for poly in o.data.polygons:
        for li in poly.loop_indices:
            z = o.data.vertices[o.data.loops[li].vertex_index].co.z
            t = (z - bas) / max(haut - bas, 1e-4)
            uv[li].uv = (u, min(0.995, max(0.005, v - amplitude / 2 + amplitude * t)))
    return o


# ---------------------------------------------------------------- coupes

def courte():
    """Coupe courte naturelle : implantation haute sur le front, degagee sur
    la nuque, un peu de volume sur le dessus."""
    def ligne(p):
        # Front a 1,765 m, tempes a 1,68 m (au-dessus des oreilles), nuque a
        # 1,60 m ; des pattes descendent devant les oreilles.
        a = angle_arriere(p)
        pattes = math.exp(-((a - 0.42) / 0.035) ** 2)
        return 1.765 - 0.165 * lisse(a) - 0.05 * pattes

    def decalage(p, n):
        dessus = lisse((p.z - 1.74) / 0.08)
        epaisseur = 0.011 + 0.018 * dessus   # 27/09 : plus epais, plus de jour au contour
        # Bord aminci : les cheveux naissent du crane au lieu d'une marche.
        naissance = 0.3 + 0.7 * lisse((p.z - ligne(p)) / 0.03)
        # Meches en relief, dans le sens des cheveux (vers l'arriere, sur le dessus).
        ang = math.atan2(p.x, -(p.y - CRANE.y))
        meches = 0.0022 * math.sin(ang * 38 + p.z * 25) + 0.0015 * math.sin(ang * 71 - p.z * 40)
        return epaisseur * naissance + meches * naissance

    return ligne, decalage


def tomber(bm, corps, jusqua, sauf_devant=0.28, anneaux=12, marge=0.014, rentree=0.45, meches=0.0016):
    """Prolonge le bord de la calotte vers le bas (cheveux qui tombent droit),
    sauf sur le front : anneau par anneau jusqu'a la hauteur jusqua(p).
    Chaque meche est ensuite posee comme une membrane : jamais dans la peau
    (un rayon depuis l'axe du crane la trouve, oreilles comprises), lissee sur
    ses voisines, et un peu rentree vers la nuque en descendant (rentree)
    au lieu de tomber en boite. 27/09 : un rayon fixe de 15,8 cm faisait des
    cache-oreilles, un simple repoussage une marche au-dessus de l'oreille."""
    peau = surface_tete(corps)
    arbre = BVHTree.FromBMesh(peau)
    peau.free()

    def r_peau(axe, d):
        """Distance horizontale a la peau la plus eloignee dans la direction d."""
        loin, depart = None, axe
        for _ in range(4):
            hit, _, _, _ = arbre.ray_cast(depart, d, 0.3)
            if hit is None:
                break
            loin = hit
            depart = hit + d * 0.0005
        if loin is None:
            return 0.0
        return (Vector((loin.x, loin.y, 0)) - Vector((axe.x, axe.y, 0))).length

    def rayon_mini(co):
        # Les sommets sont espaces de 1 a 2 cm : on sonde autour (hauteur et
        # angle), sinon une oreille passe entre deux sommets et perce la meche.
        axe = Vector((CRANE.x, CRANE.y, co.z))
        d = Vector((co.x - axe.x, co.y - axe.y, 0)).normalized()
        r = 0.0
        for dz in (-0.015, -0.0075, 0.0, 0.0075, 0.015):
            for da in (-0.12, -0.06, 0.0, 0.06, 0.12):
                c, s_ = math.cos(da), math.sin(da)
                dd = Vector((d.x * c - d.y * s_, d.x * s_ + d.y * c, 0))
                r = max(r, r_peau(axe + Vector((0, 0, dz)), dd))
        return r + marge

    def rayon(v):
        return math.hypot(v.co.x - CRANE.x, v.co.y - CRANE.y)

    def poser(v, r):
        d = Vector((v.co.x - CRANE.x, v.co.y - CRANE.y, 0)).normalized()
        v.co.x, v.co.y = CRANE.x + d.x * r, CRANE.y + d.y * r

    courant = [e for e in bm.edges if e.is_boundary
               and all(angle_arriere(v.co) > sauf_devant for v in e.verts)]
    rang = {v: 0 for e in courant for v in e.verts}
    for k in range(anneaux):
        if not courant:
            break
        res = bmesh.ops.extrude_edge_only(bm, edges=courant)
        nouveaux = {g for g in res["geom"] if isinstance(g, bmesh.types.BMVert)}
        for v in nouveaux:
            v.co.z -= (v.co.z - jusqua(v.co)) / (anneaux - k)
            rang[v] = k + 1
        courant = [g for g in res["geom"] if isinstance(g, bmesh.types.BMEdge)
                   and all(v in nouveaux for v in g.verts)]
    rideau = [v for v, k in rang.items() if k > 0]
    mini = {v: rayon_mini(v.co) for v in rideau}
    droit = {v: rayon(v) for v in rideau}
    # Rayon voulu : tomber droit, en rentrant peu a peu vers la peau.
    voulu = {v: max(mini[v], droit[v] - (droit[v] - mini[v]) * rentree * rang[v] / anneaux) for v in rideau}
    r = {v: max(mini[v], droit[v]) for v in rideau}
    for v in rang:
        if rang[v] == 0:
            r[v] = rayon(v)
    for _ in range(60):
        nouveau = {}
        for v in rideau:
            vois = [e.other_vert(v) for e in v.link_edges if e.other_vert(v) in r]
            moy = sum(r[w] for w in vois) / len(vois) if vois else r[v]
            nouveau[v] = max(mini[v], 0.7 * moy + 0.3 * voulu[v])
        r.update(nouveau)
    # Meches verticales discretes : des cheveux, pas un casque lisse.
    for v in rideau:
        ang = math.atan2(v.co.x, -(v.co.y - CRANE.y))
        relief = meches * (math.sin(ang * 52) + 0.6 * math.sin(ang * 97 + 1.3)) * min(1.0, rang[v] / 3)
        poser(v, r[v] + max(0.0, relief))
    bm.normal_update()


def lisses():
    """Cheveux lisses mi-longs : frange de cote, tombent droit jusqu'a la
    machoire sur les cotes et derriere, par-dessus les oreilles."""
    def ligne(p):
        # Frange : plus basse sur le front, en biais (raie sur le cote gauche) ;
        # sur les cotes et derriere, le bord s'arrete au-dessus des oreilles,
        # le reste tombe (tomber).
        a = angle_arriere(p)
        frange = 1.735 + 0.025 * max(-1.0, min(1.0, p.x / 0.08))
        cotes = 1.725 - 0.02 * lisse((a - 0.5) / 0.5)
        return frange - (frange - cotes) * lisse((a - 0.15) / 0.2)

    def decalage(p, n):
        dessus = lisse((p.z - 1.74) / 0.08)
        # Bord aminci sur la frange seulement : sur les cotes et derriere, la
        # calotte se prolonge par les cheveux qui tombent, sans marche.
        devant = 1 - lisse((angle_arriere(p) - 0.2) / 0.1)
        naissance = 1 - devant * (0.7 - 0.7 * lisse((p.z - ligne(p)) / 0.03))
        ang = math.atan2(p.x, -(p.y - CRANE.y))
        meches = 0.0018 * math.sin(ang * 46 + p.z * 10)
        return (0.013 + 0.012 * dessus) * naissance + meches

    def apres(bm, corps):
        # La longueur : a la machoire sur les cotes (1,59 m), un peu plus
        # courte derriere (1,58 m).
        tomber(bm, corps, lambda p: 1.59 - 0.01 * lisse(angle_arriere(p)))

    return ligne, decalage, apres


def afro():
    """Afro : implantation naturelle (front, tempes, nuque basse), puis un
    grand volume rond autour du crane, frise en surface. Le volume part de la
    peau a la ligne d'implantation et s'arrondit vite, comme le bas d'une
    boule (27/09 : un fondu lent laissait une corniche plate sous la nuque)."""
    CENTRE = Vector((0.0, 0.015, 1.745))

    def ligne(p):
        a = angle_arriere(p)
        return 1.77 - 0.17 * lisse(a) - 0.02 * math.exp(-((a - 0.45) / 0.06) ** 2)

    def decalage(p, n):
        return 0.008

    bord = {}   # distance de chaque sommet au bord de la coiffure (apres)

    def montee(v):
        """0 a l'implantation, 1 dans le plein volume, selon la distance au
        bord (27/09 : mesuree en hauteur, elle faisait une marche la ou la
        ligne descend, derriere l'oreille). Plus progressif aux tempes."""
        a = angle_arriere(v.co)
        longueur = 0.055 + 0.05 * math.exp(-((a - 0.42) / 0.14) ** 2)
        # Les 1,2 premiers cm restent a plat sur la peau (contour colle au crane).
        t = min(1.0, max(0.0, (bord[v] - 0.012) / longueur))
        return 1 - (1 - t) ** 2.2

    def apres(bm, corps):
        # Assez de sommets pour les boucles, avant de gonfler.
        bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=3, use_grid_fill=True)
        bm.normal_update()
        aretes = [v for v in bm.verts if v.is_boundary]
        kd = KDTree(len(aretes))
        for k, v in enumerate(aretes):
            kd.insert(v.co, k)
        kd.balance()
        for v in bm.verts:
            bord[v] = kd.find(v.co)[2]
        for v in bm.verts:
            d = v.co - CENTRE
            if d.length < 1e-4:
                continue
            u = d.normalized()
            # Enveloppe : une boule un peu haute, plus profonde derriere.
            ry = 0.16 if u.y < 0 else 0.18
            k = 1.0 / math.sqrt((u.x / 0.175) ** 2 + (u.y / ry) ** 2 + (u.z / 0.19) ** 2)
            monte = montee(v)
            r = d.length + max(0.0, k - d.length) * monte
            # Le volume s'ecarte de la peau en pente (au plus 1,7 cm par cm de
            # hauteur) : pas de corniche sous la nuque, le dessous remonte en biais.
            h = max(0.0, bord[v] - 0.012)
            v.co = CENTRE + u * min(r, d.length + 1.7 * h)
        bmesh.ops.smooth_vert(bm, verts=bm.verts, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
        # Frisure apres le lissage : des boucles serrees en relief.
        bm.normal_update()
        for v in bm.verts:
            t = montee(v)
            f = noise.turbulence(v.co * 52.0, 2, False) - 0.5
            f += 0.5 * (noise.turbulence(v.co * 110.0, 1, False) - 0.5)
            v.co += v.normal * 0.01 * f * t
        # Le contour sur la peau : pres de l'implantation, chaque sommet est
        # ramene au point de peau le plus proche, a 3 mm (27/09 : les bords
        # flottaient au-dessus du front, des tempes et de la nuque).
        peau = surface_tete(corps)
        bmesh.ops.remove_doubles(peau, verts=peau.verts, dist=0.0015)
        arbre = BVHTree.FromBMesh(peau)
        peau.free()
        for v in bm.verts:
            poids = 1 - lisse(montee(v) / 0.25)
            if poids <= 0:
                continue
            hit, n, _, _ = arbre.find_nearest(v.co)
            if hit is None:
                continue
            if n.dot(v.co - CRANE) < 0:
                n = -n
            v.co = v.co.lerp(hit + n * 0.003, poids)

    return ligne, decalage, apres


NIVEAUX = {"Afro": 1}   # subdivision finale : l'afro est deja dense (apres)

COUPES = {
    # nom : (fabrique, couleur, nom affiche, rarete)
    "Courte": (courte, "brun", "Coupe courte", "common"),
    "Lisses": (lisses, "blond_fonce", "Cheveux lisses", "common"),
    "Afro": (afro, "brun_fonce", "Afro", "uncommon"),
}


# ---------------------------------------------------------------- apercus

def materiau_atlas():
    mat = bpy.data.materials.new("Atlas Creative")
    mat.use_nodes = True
    t = mat.node_tree
    tex = t.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(KIT / "Textures_4.png"), check_existing=True)
    t.links.new(tex.outputs["Color"], t.nodes["Principled BSDF"].inputs["Base Color"])
    t.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.85
    return mat


def importer_kit(nom):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.wm.obj_import(filepath=str(KIT / (nom + ".obj")))
    o = [x for x in bpy.context.selected_objects if x.type == "MESH"][0]
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return o


VUES = {"face": (0.0, -1.0, 1.74), "profil": (1.0, -0.15, 1.74), "dos": (0.25, 1.0, 1.76)}


def rendre(scene, nom):
    cam = scene.camera
    for vue, direction in VUES.items():
        d = Vector(direction[:2] + (0,)).normalized()
        cam.location = Vector((0, -0.01, direction[2])) + d * 0.95 + Vector((0, 0, 0.03))
        cam.rotation_euler = (Vector((0, -0.01, 1.72)) - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(OUT / f"Apercu_{nom}_{vue}.png")
        bpy.ops.render.render(write_still=True)


def main(styles):
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    scene = bpy.context.scene
    rig = bpy.data.objects["Root"]
    corps = bpy.data.objects["SK_Animations.001"]
    for o in bpy.data.objects:
        if o.type == "MESH" and o is not corps:
            o.hide_render = True
    atlas = materiau_atlas()
    visage = importer_kit("Male_emotion_usual_001")
    visage.data.materials.clear()
    visage.data.materials.append(atlas)
    cam = bpy.data.objects.new("Camera coiffure", bpy.data.cameras.new("Camera coiffure"))
    scene.collection.objects.link(cam)
    cam.data.lens = 60
    scene.camera = cam
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 520, 560

    manifeste = []
    for style in styles:
        fabrique, couleur, affiche, rarete = COUPES[style]
        f = fabrique()
        ligne, decalage, apres = f if len(f) == 3 else (f[0], f[1], None)
        o = calotte(corps, ligne, decalage, apres=apres, niveaux=NIVEAUX.get(style, 2))
        nom = "SK_COS_Cheveux_" + style
        o.name = nom
        colorer_degrade(o, couleur)
        g = o.vertex_groups.new(name="Head")
        g.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
        arm = o.modifiers.new("Creative skeleton", "ARMATURE")
        arm.object = rig
        bpy.ops.object.select_all(action="DESELECT")
        rig.select_set(True)
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.export_scene.fbx(mesh_smooth_type="FACE", filepath=str(OUT / (nom + ".fbx")), use_selection=True,
                                 object_types={"ARMATURE", "MESH"}, add_leaf_bones=False, bake_anim=False,
                                 use_mesh_modifiers=True, armature_nodetype="NULL")
        o.data.materials.append(atlas)
        rendre(scene, style)
        o.hide_render = True
        manifeste.append({"piece": nom, "emplacement": "cheveux", "rarete": rarete, "nom": affiche})
        print("COIFFURE_PRETE", nom, len(o.data.vertices), "sommets")
    (OUT / "manifeste.json").write_text(json.dumps(manifeste, indent=2, ensure_ascii=False), encoding="utf-8")


main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(COUPES))
