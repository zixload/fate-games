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
from mathutils import Vector

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


def calotte(corps, ligne, decalage, epaisseur=0.012):
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
    s.levels = 2
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


COUPES = {
    # nom : (fabrique, couleur, nom affiche, rarete)
    "Courte": (courte, "brun", "Coupe courte", "common"),
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
        ligne, decalage = fabrique()
        o = calotte(corps, ligne, decalage)
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
        bpy.ops.export_scene.fbx(filepath=str(OUT / (nom + ".fbx")), use_selection=True,
                                 object_types={"ARMATURE", "MESH"}, add_leaf_bones=False, bake_anim=False,
                                 use_mesh_modifiers=True, armature_nodetype="NULL")
        o.data.materials.append(atlas)
        rendre(scene, style)
        o.hide_render = True
        manifeste.append({"piece": nom, "emplacement": "cheveux", "rarete": rarete, "nom": affiche})
        print("COIFFURE_PRETE", nom, len(o.data.vertices), "sommets")
    (OUT / "manifeste.json").write_text(json.dumps(manifeste, indent=2, ensure_ascii=False), encoding="utf-8")


main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(COUPES))
