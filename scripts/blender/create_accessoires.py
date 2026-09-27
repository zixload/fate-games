"""Accessoires telecharges (chapeaux, lunettes) poses sur la tete Creative.

    blender -b --python scripts/blender/create_accessoires.py [-- <nom> ...]
    blender -b --python scripts/blender/create_accessoires.py -- --atelier

Reglage a la main : --atelier ecrit art/cosmetics/accessoires/
Reglage_accessoires.blend (le personnage, chaque accessoire pose, pivot au
centre de la tete). On y deplace, tourne, met a l'echelle chaque objet (G, R,
S), on enregistre ; l'export suivant applique ces transformations par-dessus
REGLAGES. L'atelier existant n'est jamais ecrase (le supprimer pour repartir).

Les zips (Downloads) sont extraits dans art/cosmetics/accessoires/brut/. Pour
chacun : import de la source (FBX, OBJ ou .blend), morceaux reunis, orientation
et taille ramenees a la tete (table REGLAGES : rotation, largeur, hauteur du
bas, decalage), toutes ses textures cuites en une seule sur un nouveau jeu
d'UV (en jeu, une piece = un materiau, doc Paintable), accroche rigide a l'os
Head. Apercus face et profil sur le personnage, avec le visage du kit.

Sorties dans art/cosmetics/accessoires/ (hors depot) : SK_COS_<Nom>.fbx,
T_COS_<Nom>.png, Apercu_<Nom>_{face,profil}.png, manifeste.json.
"""

import json
import math
import sys
import zipfile
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector
from mathutils.bvhtree import BVHTree

PROJECT = Path(__file__).resolve().parents[2]
SOURCE = PROJECT / "art/cosmetics/tshirts/creative_tshirt_rarities.blend"
KIT = Path("C:/ProgramData/Epic/EpicGamesLauncher/VaultCache/FabLibrary/"
           "Creative_Characters_FREE_-_Animated_Low_Poly_3D_Models-94fd60a2/obj/source_extracted/"
           "Separate_assets_obj_extracted/Separate_assets_obj")
DOWNLOADS = Path.home() / "Downloads"
OUT = PROJECT / "art/cosmetics/accessoires"
BRUT = OUT / "brut"
TAILLE = 1024
ATELIER = OUT / "Reglage_accessoires.blend"

# Crane Creative : centre (0, -0,014, 1,70), sommet 1,829 m, yeux 1,668 m.
CRANE = Vector((0.0, -0.014, 1.70))

# nom : zip, emplacement, nom affiche, rarete, rotation (degres, appliquee a
# la source), largeur voulue (m, en x), hauteur du bas (m), decalage y (m, vers
# l'arriere > 0), inclinaison vers l'arriere (degres), textures de couleur par
# materiau (nom en minuscules -> fichier de textures/).
REGLAGES = {
    "Tricorne": dict(zip="tricorn-hat-lowpoly.zip", emplacement="chapeau", nom="Tricorne", rarete="epic",
                     rotation=(0, 0, 0), largeur=0.48, bas=1.70, etire_z=1.8, dy=0.04, incline=0,
                     textures={"tricornhatmat": "TricornhatMat_BaseColor.png"}),
    "Capitaine": dict(zip="sea-captain-hat.zip", emplacement="chapeau", nom="Casquette de capitaine", rarete="epic",
                      rotation=(0, 0, 0), largeur=0.25, bas=1.735, dy=0.005, incline=0,
                      textures={"sea_captain_hat": "sea-captain-hat_sea_captain_hat_BaseColor.png"}),
    "Officier": dict(zip="officer-hat.zip", emplacement="chapeau", nom="Casquette d'officier", rarete="rare",
                     rotation=(0, 0, 0), largeur=0.28, bas=1.72, dy=0.005, incline=0,
                     textures={"defaultmaterial": "1943_DefaultMaterial_BaseColor.png"}),
    "Sorciere": dict(zip="witch-hat.zip", emplacement="chapeau", nom="Chapeau de sorcière", rarete="epic",
                     rotation=(90, 0, 0), largeur=0.40, bas=1.695, etire_z=1.5, dy=0.055, incline=0,
                     textures={"hat": "HAT_Base_Color.png"}),
    "Magicien": dict(zip="stylized-wizard-hat.zip", emplacement="chapeau", nom="Chapeau de magicien", rarete="legendary",
                     rotation=(0, 0, 0), largeur=0.40, bas=1.72, dy=0.012, incline=0,
                     textures={"initialshadinggroup": "hat_LP_initialShadingGroup_BaseColor.1001.png"}),
    "Clown": dict(zip="clown-hat.zip", emplacement="chapeau", nom="Bonnet de bouffon", rarete="rare",
                  rotation=(0, 0, 0), largeur=0.8, bas=1.725, dy=0.0, incline=0, textures={}),
    "LunettesCoeur": dict(zip="heart-glasses.zip", emplacement="lunettes", nom="Lunettes cœur", rarete="rare",
                          rotation=(90, 0, 0), largeur=0.19, bas=1.64, dy=0.0, devant=-0.135, incline=0,
                          textures={"monture": "heart_monture_BaseColor.png", "verre": "heart_verre_BaseColor.png"}),
}


# ---------------------------------------------------------------- source

def extraire(nom, r):
    dossier = BRUT / r["zip"].removesuffix(".zip")
    if not (dossier / "source").is_dir():
        with zipfile.ZipFile(DOWNLOADS / r["zip"]) as z:
            z.extractall(dossier)
    return dossier


def importer_source(dossier):
    """Importe la source ; rend les objets maillage importes."""
    avant = set(bpy.data.objects)
    src = [f for f in (dossier / "source").iterdir() if f.suffix.lower() in (".fbx", ".obj", ".blend")][0]
    if src.suffix.lower() == ".fbx":
        bpy.ops.import_scene.fbx(filepath=str(src))
    elif src.suffix.lower() == ".obj":
        bpy.ops.wm.obj_import(filepath=str(src))
    else:
        with bpy.data.libraries.load(str(src)) as (a, b):
            b.objects = a.objects
        for o in b.objects:
            if o and o.type in ("MESH", "CURVE", "SURFACE"):
                bpy.context.scene.collection.objects.link(o)
    bpy.context.view_layer.update()
    objs = [o for o in bpy.data.objects if o not in avant and o.type in ("MESH", "CURVE", "SURFACE")]
    # Chaque morceau converti en maillage, modificateurs appliques : la
    # reunion ne garde que ceux de l'objet actif (le chapeau de clown tient a
    # ses subdivisions et a l'epaisseur de son bandeau).
    for o in objs:
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.convert(target="MESH")
    return [o for o in bpy.data.objects if o not in avant and o.type == "MESH"], dossier


def reunir(objs):
    """Un seul maillage, transformations appliquees ; les morceaux perdus
    loin du reste (un disque oublie dans le chapeau de sorciere) sont retires."""
    bpy.context.view_layer.update()

    def boite(o):
        pts = [o.matrix_world @ v.co for v in o.data.vertices]
        return (Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts))),
                Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts))))

    principal = max(objs, key=lambda o: len(o.data.vertices))
    lo, hi = boite(principal)
    centre, taille = (lo + hi) / 2, (hi - lo).length
    garder = []
    for o in objs:
        a, b = boite(o)
        if ((a + b) / 2 - centre).length > 1.5 * taille:
            print("ACCESSOIRE_ECARTE", o.name)
            bpy.data.objects.remove(o)
        else:
            garder.append(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in garder:
        o.select_set(True)
    bpy.context.view_layer.objects.active = garder[0]
    if len(garder) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.parent = None
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


def poser(obj, r):
    """Orientation, taille et place sur la tete."""
    rot = Euler(tuple(math.radians(a) for a in r["rotation"]), "XYZ").to_matrix()
    for v in obj.data.vertices:
        v.co = rot @ v.co
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    k = r["largeur"] / max(max(xs) - min(xs), 1e-6)
    cx, cy, bas = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2, min(zs)
    incline = Euler((math.radians(-r["incline"]), 0, 0), "XYZ").to_matrix()
    for v in obj.data.vertices:
        # etire_z : calotte trop basse pour le grand crane Creative (tricorne).
        p = Vector(((v.co.x - cx) * k, (v.co.y - cy) * k, (v.co.z - bas) * k * r.get("etire_z", 1.0)))
        p = incline @ p
        v.co = p + Vector((CRANE.x, CRANE.y + r["dy"], r["bas"]))
    # Lunettes : placees par l'avant des verres (les branches filent derriere).
    if "devant" in r:
        avant = min(v.co.y for v in obj.data.vertices)
        for v in obj.data.vertices:
            v.co.y += r["devant"] - avant
    obj.data.update()


def controler_crane(obj, corps, r):
    """Chapeaux : les points du haut du crane (au-dessus de 1,785 m) qui
    passent a travers (aucune face du chapeau au-dela, dans l'axe du centre
    de la tete). Affiche leur nombre et ou ils sont. Plus bas, la nuque sous
    le bord d'une casquette est visible normalement : on ne la compte pas."""
    if r["emplacement"] != "chapeau":
        return 0
    arbre = BVHTree.FromObject(obj, bpy.context.evaluated_depsgraph_get())
    g = corps.vertex_groups["Head"].index
    mw = corps.matrix_world
    centre = Vector((CRANE.x, CRANE.y, 1.70))
    depassent = []
    for v in corps.data.vertices:
        p = mw @ v.co
        if p.z < 1.785 or not any(a.group == g and a.weight > 0.5 for a in v.groups):
            continue
        # Couvert s'il y a du chapeau au-dela du point, dans l'axe du centre.
        d = (p - centre).normalized()
        if arbre.ray_cast(p + d * 0.001, d, 0.6)[0] is None:
            depassent.append(p)
    if depassent:
        m = sum(depassent, Vector()) / len(depassent)
        print("CRANE_DEPASSE", obj.name, len(depassent), "points, centre", tuple(round(c, 3) for c in m))
    else:
        print("CRANE_COUVERT", obj.name)
    return len(depassent)


def ajouter_calotte(obj, r):
    """Calotte interieure, a la couleur du chapeau, qui ferme une coiffe
    creuse (tricorne entre ses rabats, bonnet de fou entre ses cornes) : le
    crane Creative ne passe plus au travers. Une demi-boule juste au-dessus
    du crane, coupee sous `coupe`."""
    c = r.get("calotte")
    if not c:
        return
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=16, radius=1.0)
    for v in bm.verts:
        k = c.get("echelle", 1.0)
        v.co = Vector((v.co.x * 0.118 * k, v.co.y * 0.142 * k, v.co.z * 0.152 * k)) + Vector((0, 0.0 + r["dy"] * 0.3, 1.69))
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < c["coupe"]], context="VERTS")
    me = bpy.data.meshes.new("Calotte")
    bm.to_mesh(me)
    bm.free()
    calotte = bpy.data.objects.new("Calotte", me)
    bpy.context.collection.objects.link(calotte)
    mat = bpy.data.materials.new("Cuisson_calotte")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Base Color"].default_value = tuple(c["couleur"][:3]) + (1.0,)
    me.materials.append(mat)
    bpy.ops.object.select_all(action="DESELECT")
    calotte.select_set(True)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.join()


# ---------------------------------------------------------------- une texture

def materiaux_source(obj, dossier, r):
    """Chaque emplacement recoit un materiau neuf, mat et opaque : sa texture
    de couleur si on la connait, sinon la couleur de base d'origine (chapeau
    de clown). Les materiaux importes etaient parfois metalliques : la couleur
    cuite sortait noire (27/09)."""
    for slot in obj.material_slots:
        m = slot.material
        cle = m.name.lower().split(".")[0] if m else ""
        couleur = (0.5, 0.5, 0.5, 1.0)
        if m and m.use_nodes:
            ancien = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
            if ancien:
                couleur = tuple(ancien.inputs["Base Color"].default_value)
        elif m:
            couleur = tuple(m.diffuse_color)
        neuf = bpy.data.materials.new("Cuisson_" + (cle or "sans"))
        neuf.use_nodes = True
        bsdf = neuf.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Metallic"].default_value = 0.0
        bsdf.inputs["Base Color"].default_value = couleur
        fichier = r["textures"].get(cle)
        if fichier:
            tex = neuf.node_tree.nodes.new("ShaderNodeTexImage")
            tex.image = bpy.data.images.load(str(dossier / "textures" / fichier), check_existing=True)
            neuf.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        slot.material = neuf


def cuire_une_texture(obj, nom):
    """Nouveau jeu d'UV (seul garde), couleurs de tous les materiaux cuites dessus."""
    uv = obj.data.uv_layers.new(name="Design_UV")
    obj.data.uv_layers.active = uv
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")
    img = bpy.data.images.new("T_COS_" + nom, TAILLE, TAILLE, alpha=False)
    for slot in obj.material_slots:
        m = slot.material
        if m is None:
            continue
        m.use_nodes = True
        cible = m.node_tree.nodes.new("ShaderNodeTexImage")
        cible.image = img
        uvn = m.node_tree.nodes.new("ShaderNodeUVMap")
        uvn.uv_map = "Design_UV"
        m.node_tree.links.new(uvn.outputs[0], cible.inputs["Vector"])
        m.node_tree.nodes.active = cible
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 4
    scene.cycles.device = "CPU"
    scene.render.bake.margin = 8
    scene.render.bake.use_pass_direct = False
    scene.render.bake.use_pass_indirect = False
    scene.render.bake.use_pass_color = True
    bpy.ops.object.bake(type="DIFFUSE", use_clear=True)
    img.filepath_raw = str(OUT / (img.name + ".png"))
    img.file_format = "PNG"
    img.save()
    # Un seul materiau, un seul jeu d'UV : ce qu'Unreal recevra.
    for couche in [c for c in obj.data.uv_layers if c.name != "Design_UV"]:
        obj.data.uv_layers.remove(couche)
    mat = bpy.data.materials.new("M_COS_" + nom)
    mat.use_nodes = True
    t = mat.node_tree
    tex = t.nodes.new("ShaderNodeTexImage")
    tex.image = img
    t.links.new(tex.outputs["Color"], t.nodes["Principled BSDF"].inputs["Base Color"])
    t.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.8
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    obj.data.update()
    bpy.context.view_layer.update()
    return img


# ---------------------------------------------------------------- reglage a la main

def reglages_main():
    """nom -> matrice de l'objet dans l'atelier (pivot au centre de la tete)."""
    if not ATELIER.is_file():
        return {}
    with bpy.data.libraries.load(str(ATELIER)) as (a, b):
        b.objects = [n for n in a.objects if n in REGLAGES]
    res = {}
    for o in b.objects:
        if o is None:
            continue
        rot = o.rotation_quaternion.to_matrix().to_4x4() if o.rotation_mode == "QUATERNION"             else o.rotation_euler.to_matrix().to_4x4()
        res[o.name] = Matrix.Translation(o.location) @ rot @ Matrix.Diagonal(o.scale.to_4d())
        bpy.data.objects.remove(o)
    return res


def appliquer_reglage(obj, matrice):
    """Les sommets, poses par REGLAGES, passent par la transformation faite a
    la main (autour du centre de la tete, comme dans l'atelier)."""
    for v in obj.data.vertices:
        v.co = matrice @ (v.co - CRANE)
    obj.data.update()


def atelier(noms):
    if ATELIER.is_file():
        print("ATELIER_EXISTE", ATELIER, "(le supprimer pour le refaire)")
        return
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    corps = bpy.data.objects["SK_Animations.001"]
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o is not corps:
            bpy.data.objects.remove(o)
    importer_kit("Male_emotion_usual_001").name = "Visage"
    for i, nom in enumerate(noms):
        r = REGLAGES[nom]
        obj = reunir(importer_source(extraire(nom, r))[0])
        materiaux_source(obj, BRUT / r["zip"].removesuffix(".zip"), r)
        poser(obj, r)
        ajouter_calotte(obj, r)
        # Pivot au centre de la tete : tourner et agrandir se font autour d'elle.
        for v in obj.data.vertices:
            v.co -= CRANE
        obj.data.update()
        obj.location = CRANE
        obj.name = nom
        # Un seul accessoire visible au depart (les autres caches : H / Alt+H).
        obj.hide_set(i > 0)
        print("ATELIER_PIECE", nom)
    bpy.ops.wm.save_as_mainfile(filepath=str(ATELIER), copy=True)
    print("ATELIER_PRET", ATELIER)


# ---------------------------------------------------------------- scene, apercus

def importer_kit(nom):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.wm.obj_import(filepath=str(KIT / (nom + ".obj")))
    o = [x for x in bpy.context.selected_objects if x.type == "MESH"][0]
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return o


VUES = {"face": (0.35, -1.0, 1.74), "profil": (1.0, -0.1, 1.74), "dos": (-0.3, 1.0, 1.76)}


def rendre(scene, nom):
    cam = scene.camera
    for vue, direction in VUES.items():
        d = Vector(direction[:2] + (0,)).normalized()
        cam.location = Vector((0, -0.01, direction[2])) + d * 1.15 + Vector((0, 0, 0.06))
        cam.rotation_euler = (Vector((0, -0.01, 1.76)) - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(OUT / f"Apercu_{nom}_{vue}.png")
        bpy.ops.render.render(write_still=True)


def main(noms):
    OUT.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    scene = bpy.context.scene
    rig = bpy.data.objects["Root"]
    corps = bpy.data.objects["SK_Animations.001"]
    for o in bpy.data.objects:
        if o.type == "MESH" and o is not corps:
            o.hide_render = True
    visage = importer_kit("Male_emotion_usual_001")
    cam = bpy.data.objects.new("Camera accessoire", bpy.data.cameras.new("Camera accessoire"))
    scene.collection.objects.link(cam)
    cam.data.lens = 55
    scene.camera = cam
    scene.render.resolution_x, scene.render.resolution_y = 520, 560

    manifeste_chemin = OUT / "manifeste.json"
    manifeste = {m["piece"]: m for m in json.loads(manifeste_chemin.read_text(encoding="utf-8"))} \
        if manifeste_chemin.is_file() else {}
    a_la_main = reglages_main()
    for nom in noms:
        r = REGLAGES[nom]
        objs, dossier = importer_source(extraire(nom, r))
        obj = reunir(objs)
        materiaux_source(obj, dossier, r)
        poser(obj, r)
        ajouter_calotte(obj, r)
        if nom in a_la_main:
            appliquer_reglage(obj, a_la_main[nom])
            print("REGLAGE_MAIN", nom)
        controler_crane(obj, corps, r)
        piece = "SK_COS_" + nom
        obj.name = piece
        img = cuire_une_texture(obj, nom)
        for p in obj.data.polygons:
            p.use_smooth = True
        g = obj.vertex_groups.new(name="Head")
        g.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
        arm = obj.modifiers.new("Creative skeleton", "ARMATURE")
        arm.object = rig
        bpy.ops.object.select_all(action="DESELECT")
        rig.select_set(True)
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.export_scene.fbx(filepath=str(OUT / (piece + ".fbx")), use_selection=True,
                                 object_types={"ARMATURE", "MESH"}, add_leaf_bones=False, bake_anim=False,
                                 use_mesh_modifiers=True, armature_nodetype="NULL")
        scene.render.engine = "BLENDER_EEVEE"
        rendre(scene, nom)
        obj.hide_render = True
        manifeste[piece] = {"piece": piece, "emplacement": r["emplacement"], "rarete": r["rarete"],
                            "nom": r["nom"], "texture": img.name}
        print("ACCESSOIRE_PRET", nom, len(obj.data.vertices), "sommets")
    manifeste_chemin.write_text(json.dumps([manifeste[k] for k in sorted(manifeste)], indent=2, ensure_ascii=False),
                                encoding="utf-8")


_args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if "--atelier" in _args:
    atelier([a for a in _args if a != "--atelier"] or list(REGLAGES))
else:
    main(_args or list(REGLAGES))
