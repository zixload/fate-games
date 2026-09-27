"""Pieces de tete : accessoires (chapeaux, couronne, aureole...), coiffures et
expressions du visage, dans le style et avec le materiau du kit Creative.

    python scripts/blender/palette_atlas.py      (une fois : les cases de couleur)
    blender -b --python scripts/blender/create_tete.py

Toutes les pieces utilisent l'atlas Creative (Textures_4.png) : chaque morceau
pose ses UV sur une case de couleur (art/cosmetics/tete/palette.json), comme
les pieces du kit. Accessoires : formes simples, rigides, accrochees a l'os
Head. Coiffures : la coiffure du kit deformee (afro, herisson, palmier,
iroquoise, chignon) ou recoloree. Expressions : le visage du kit, dont les
cinq morceaux (sourcils, yeux, bouche) sont deplaces, tournes, etires.

Sorties dans art/cosmetics/tete/ (hors depot) : un FBX par piece, un apercu,
une planche, manifeste.json.
"""

import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

PROJECT = Path(__file__).resolve().parents[2]
SOURCE = PROJECT / "art/cosmetics/tshirts/creative_tshirt_rarities.blend"
KIT = Path("C:/ProgramData/Epic/EpicGamesLauncher/VaultCache/FabLibrary/"
           "Creative_Characters_FREE_-_Animated_Low_Poly_3D_Models-94fd60a2/obj/source_extracted/"
           "Separate_assets_obj_extracted/Separate_assets_obj")
OUT = PROJECT / "art/cosmetics/tete"
PALETTE = json.loads((OUT / "palette.json").read_text(encoding="utf-8"))

# Reperes de la tete (mesures sur le corps Creative, en metres).
CENTRE = Vector((0.0, -0.014, 1.685))
HAUT = 1.829
RAYON = 0.148
# Les chapeaux flottaient (27/09) : ils descendent d'autant et serrent un peu plus.
BAISSE = 0.035


# ---------------------------------------------------------------- outils

def objet_actif(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def appliquer(o):
    objet_actif(o)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def colorer(o, couleur):
    """Tous les UV du morceau sur une case de l'atlas : une teinte unie."""
    u, v = PALETTE[couleur]
    if not o.data.uv_layers:
        o.data.uv_layers.new(name="UVMap")
    for d in o.data.uv_layers[0].data:
        d.uv = (u, v)
    return o


def lisser(o, niveaux=1):
    for p in o.data.polygons:
        p.use_smooth = True
    if niveaux:
        objet_actif(o)
        m = o.modifiers.new("Lisse", "SUBSURF")
        m.levels = niveaux
        bpy.ops.object.modifier_apply(modifier=m.name)
    return o


def sphere(centre, rayon, echelle=(1, 1, 1), segments=24, anneaux=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=anneaux, radius=rayon, location=centre)
    o = bpy.context.active_object
    o.scale = echelle
    appliquer(o)
    return o


def cylindre(centre, rayon, hauteur, sommets=32, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=sommets, radius=rayon, depth=hauteur, location=centre,
                                        rotation=rotation)
    o = bpy.context.active_object
    appliquer(o)
    return o


def cone(centre, r1, r2, hauteur, sommets=16, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(vertices=sommets, radius1=r1, radius2=r2, depth=hauteur,
                                    location=centre, rotation=rotation)
    o = bpy.context.active_object
    appliquer(o)
    return o


def tore(centre, grand, petit, rotation=(0, 0, 0), maj=32, mino=12):
    bpy.ops.mesh.primitive_torus_add(major_radius=grand, minor_radius=petit, location=centre,
                                     rotation=rotation, major_segments=maj, minor_segments=mino)
    o = bpy.context.active_object
    appliquer(o)
    return o


def couper_sous(o, z):
    """Garde ce qui est au-dessus de z (une calotte a partir d'une sphere)."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < z - 1e-5], context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    return o


def epaissir(o, e=0.004):
    objet_actif(o)
    m = o.modifiers.new("Epaisseur", "SOLIDIFY")
    m.thickness = e
    bpy.ops.object.modifier_apply(modifier=m.name)
    return o


def fusionner(morceaux, nom):
    bpy.ops.object.select_all(action="DESELECT")
    for m in morceaux:
        m.select_set(True)
    bpy.context.view_layer.objects.active = morceaux[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = nom
    return o


def importer_kit(nom):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.wm.obj_import(filepath=str(KIT / (nom + ".obj")))
    o = [x for x in bpy.context.selected_objects if x.type == "MESH"][0]
    appliquer(o)
    o.data.materials.clear()
    return o


def morceaux(o):
    """Les morceaux detaches d'un maillage : listes d'indices de sommets."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.verts.ensure_lookup_table()
    vus, out = set(), []
    for v in bm.verts:
        if v.index in vus:
            continue
        pile, comp = [v], []
        vus.add(v.index)
        while pile:
            a = pile.pop()
            comp.append(a.index)
            for e in a.link_edges:
                b = e.other_vert(a)
                if b.index not in vus:
                    vus.add(b.index)
                    pile.append(b)
        out.append(comp)
    bm.free()
    return out


def rigide_sur_tete(o, rig):
    """Toute la piece suit l'os de la tete."""
    g = o.vertex_groups.new(name="Head")
    g.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
    m = o.modifiers.new("Creative skeleton", "ARMATURE")
    m.object = rig


# ---------------------------------------------------------------- accessoires

def casquette(couleur, fonce):
    dome = couper_sous(sphere(CENTRE + Vector((0, 0.005, 0.045 - BAISSE)), RAYON * 1.1, (1, 1.04, 0.85)),
                       CENTRE.z + 0.045 - BAISSE)
    colorer(lisser(epaissir(dome)), couleur)
    visiere = cylindre(CENTRE + Vector((0, -0.165, 0.052 - BAISSE)), 0.105, 0.012, rotation=(math.radians(-8), 0, 0))
    visiere.scale = (1, 0.72, 1)
    appliquer(visiere)
    colorer(visiere, fonce)
    bouton = colorer(sphere(Vector((0, -0.005, HAUT + 0.02 - BAISSE)), 0.014), fonce)
    return [dome, visiere, bouton]


def couronne():
    z = HAUT - 0.03 - BAISSE * 0.6
    bande = cylindre(Vector((0, -0.01, z)), 0.122, 0.055, sommets=48)
    bm = bmesh.new()
    bm.from_mesh(bande.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if abs(f.normal.z) > 0.9], context="FACES_ONLY")
    bm.to_mesh(bande.data)
    bm.free()
    colorer(lisser(epaissir(bande, 0.008), 0), "or")
    pieces = [bande]
    for k in range(8):
        a = k * math.pi / 4
        p = Vector((math.cos(a) * 0.118, -0.01 + math.sin(a) * 0.118, z + 0.055))
        pieces.append(colorer(cone(p, 0.03, 0.0, 0.055, sommets=4, rotation=(0, 0, a + math.pi / 4)), "or"))
        pieces.append(colorer(sphere(p + Vector((0, 0, 0.032)), 0.011, segments=12, anneaux=6), "or"))
        joyau = sphere(Vector((math.cos(a) * 0.124, -0.01 + math.sin(a) * 0.124, z)), 0.013, segments=12, anneaux=6)
        pieces.append(colorer(joyau, "rouge" if k % 2 else "bleu"))
    return pieces


def haut_de_forme():
    b = HAUT - BAISSE
    bord = colorer(lisser(cylindre(Vector((0, -0.01, b - 0.012)), 0.17, 0.012, sommets=48), 0), "noir")
    tube = colorer(lisser(cylindre(Vector((0, -0.01, b + 0.1)), 0.118, 0.21, sommets=48), 0), "noir")
    ruban = colorer(cylindre(Vector((0, -0.01, b + 0.018)), 0.121, 0.035, sommets=48), "rouge")
    return [bord, tube, ruban]


def bonnet(couleur, bord_couleur):
    calotte = couper_sous(sphere(CENTRE + Vector((0, 0.005, 0.03 - BAISSE)), RAYON * 1.1, (1, 1.03, 1.08)),
                          CENTRE.z + 0.05 - BAISSE)
    colorer(lisser(epaissir(calotte)), couleur)
    revers = colorer(lisser(tore(CENTRE + Vector((0, 0.005, 0.058 - BAISSE)), RAYON * 1.08, 0.022), 0), bord_couleur)
    pompon = colorer(lisser(sphere(Vector((0, 0.0, HAUT + 0.07 - BAISSE)), 0.042, segments=16, anneaux=10), 1),
                     bord_couleur)
    return [calotte, revers, pompon]


def chapeau_paille():
    b = HAUT - BAISSE
    bord = cylindre(Vector((0, -0.01, b - 0.03)), 0.26, 0.01, sommets=48)
    colorer(lisser(bord, 0), "paille")
    calotte = colorer(lisser(cone(Vector((0, -0.01, b + 0.03)), 0.13, 0.11, 0.11, sommets=40), 0), "paille")
    ruban = colorer(cylindre(Vector((0, -0.01, b)), 0.129, 0.03, sommets=40), "rouge")
    return [bord, calotte, ruban]


def aureole():
    return [colorer(lisser(tore(Vector((0, -0.01, HAUT + 0.07)), 0.1, 0.012), 0), "or")]


def cornes():
    pieces = []
    for cote in (1, -1):
        c = cone(Vector((cote * 0.085, -0.03, HAUT - 0.005)), 0.028, 0.0, 0.11, sommets=16,
                 rotation=(math.radians(-10), cote * math.radians(25), 0))
        pieces.append(colorer(lisser(c, 1), "rouge"))
    return pieces


def bandeau_pirate():
    bande = tore(CENTRE + Vector((0, 0.0, 0.01)), RAYON * 1.02, 0.013,
                 rotation=(math.radians(-4), math.radians(10), 0), maj=48, mino=8)
    bande.scale = (1, 1.03, 1)
    appliquer(bande)
    cache = cylindre(Vector((-0.044, -0.152, 1.675)), 0.03, 0.008, rotation=(math.radians(90), 0, 0))
    return [colorer(bande, "noir"), colorer(lisser(cache, 1), "noir")]


def lunettes_soleil(verre):
    pieces = []
    for cote in (1, -1):
        v = cylindre(Vector((cote * 0.042, -0.158, 1.668)), 0.03, 0.008, rotation=(math.radians(90), 0, 0))
        pieces.append(colorer(lisser(v, 1), verre))
        cadre = tore(Vector((cote * 0.042, -0.16, 1.668)), 0.031, 0.004, rotation=(math.radians(90), 0, 0))
        pieces.append(colorer(cadre, "noir"))
        branche = cylindre(Vector((cote * 0.12, -0.08, 1.672)), 0.003, 0.16, sommets=8,
                           rotation=(math.radians(90), 0, 0))
        pieces.append(colorer(branche, "noir"))
    pont = cylindre(Vector((0, -0.162, 1.672)), 0.003, 0.03, sommets=8, rotation=(0, math.radians(90), 0))
    pieces.append(colorer(pont, "noir"))
    return pieces


# ---------------------------------------------------------------- coiffures

def coiffure(deformation, couleur, extras=None):
    o = importer_kit("Hairstyle_male_010")
    if deformation:
        for v in o.data.vertices:
            v.co = deformation(v.co.copy())
        o.data.update()
    colorer(o, couleur)
    pieces = [o]
    if extras:
        pieces += extras()
    return pieces


def afro(p):
    d = p - CENTRE
    if p.z < 1.66:
        return p
    f = 1.5 if p.z > 1.7 else 1 + 0.5 * (p.z - 1.66) / 0.04
    return CENTRE + Vector((d.x * f, d.y * f + 0.01, d.z * f + 0.02))


def herisson(p):
    d = p - CENTRE
    if p.z < 1.7:
        return p
    pointe = 0.5 + 0.5 * math.sin(p.x * 90) * math.sin(p.y * 80)
    return p + d.normalized() * (0.03 + 0.05 * max(0.0, pointe))


def palmier(p):
    if p.z < 1.78:
        return p
    # Une touffe haute et eclatee : des meches qui partent en eventail.
    t = min(1.0, (p.z - 1.78) / 0.05)
    ang = math.atan2(p.y + 0.014, p.x)
    pointe = max(0.0, math.cos(ang * 6)) ** 2
    ecart = 1 + 1.4 * t * pointe
    return Vector((p.x * ecart, (p.y + 0.014) * ecart - 0.014, p.z + t * (0.05 + 0.14 * pointe)))


def iroquoise(p):
    if abs(p.x) > 0.035:
        # Cote rase : on rabat sur le crane.
        d = p - CENTRE
        return CENTRE + d.normalized() * (RAYON + 0.004)
    if p.z < 1.72:
        return p
    return p + Vector((0, 0, 0.09 * (0.6 + 0.4 * math.sin(p.y * 60))))


def chignon_extra():
    return [colorer(lisser(sphere(Vector((0, 0.1, HAUT - 0.005)), 0.055, segments=16, anneaux=10), 1), "brun")]


# ---------------------------------------------------------------- expressions

def expression(transformations):
    """transformations(nom_du_morceau, centre) -> Matrix appliquee au morceau."""
    o = importer_kit("Male_emotion_usual_001")
    parts = morceaux(o)
    for idx in parts:
        c = sum((o.data.vertices[i].co for i in idx), Vector()) / len(idx)
        if c.z > 1.69:
            nom = "sourcil_d" if c.x > 0 else "sourcil_g"
        elif c.z > 1.63:
            nom = "oeil_d" if c.x > 0 else "oeil_g"
        else:
            nom = "bouche"
        m = transformations(nom, c)
        if m is None:
            continue
        for i in idx:
            v = o.data.vertices[i]
            v.co = c + m @ (v.co - c)
    o.data.update()
    return [o]


def M(sx=1, sz=1, rot=0, dx=0, dz=0):
    """Matrice : etirement x/z, rotation autour de l'axe du regard, decalage."""
    return (Matrix.Translation((dx, 0, dz)) @ Matrix.Rotation(math.radians(rot), 4, "Y")
            @ Matrix.Diagonal((sx, 1, sz, 1)))


def petits_yeux(n, c):
    return M(0.6, 0.6) if n.startswith("oeil") else None


def enerve(n, c):
    if n.startswith("sourcil"):
        return M(1.0, 1.0, rot=(-24 if n.endswith("d") else 24), dx=(-0.004 if n.endswith("d") else 0.004), dz=-0.006)
    if n.startswith("oeil"):
        return M(1.0, 0.65)
    if n == "bouche":
        return M(0.8, -0.8)
    return None


def etonne(n, c):
    if n.startswith("sourcil"):
        return M(1.0, 1.0, dz=0.014)
    if n.startswith("oeil"):
        return M(1.35, 1.35)
    if n == "bouche":
        return M(0.42, 0.55, dz=0.004)   # un petit "o"
    return None


def endormi(n, c):
    if n.startswith("oeil"):
        return M(1.1, 0.22)
    if n.startswith("sourcil"):
        return M(1.0, 1.0, dz=-0.004)
    return None


def triste(n, c):
    if n.startswith("sourcil"):
        return M(1.0, 1.0, rot=(18 if n.endswith("d") else -18), dz=0.003)
    if n == "bouche":
        return M(0.85, -1.0)
    return None


def clin_oeil(n, c):
    if n == "oeil_d":
        return M(1.1, 0.18)
    if n == "sourcil_d":
        return M(1.0, 1.0, dz=-0.005)
    if n == "bouche":
        return M(1.05, 1.0, rot=-12, dx=0.006)
    return None


def grand_sourire(n, c):
    if n == "bouche":
        return M(1.45, 1.4)
    if n.startswith("oeil"):
        return M(1.0, 0.8)
    return None


# ---------------------------------------------------------------- liste

PIECES = [
    # nom d'asset, emplacement, rarete, nom affiche, fabrique
    ("SK_COS_Chapeau_CasquetteRouge", "chapeau", "common", "Casquette rouge", lambda: casquette("rouge", "rouge_fonce")),
    ("SK_COS_Chapeau_CasquetteBleue", "chapeau", "common", "Casquette bleue", lambda: casquette("bleu", "bleu_fonce")),
    ("SK_COS_Chapeau_CasquetteNoire", "chapeau", "uncommon", "Casquette noire", lambda: casquette("noir", "gris")),
    ("SK_COS_Chapeau_Bonnet", "chapeau", "uncommon", "Bonnet à pompon", lambda: bonnet("bleu", "blanc")),
    ("SK_COS_Chapeau_Paille", "chapeau", "rare", "Chapeau de paille", chapeau_paille),
    ("SK_COS_Chapeau_HautDeForme", "chapeau", "epic", "Haut-de-forme", haut_de_forme),
    ("SK_COS_Chapeau_Couronne", "chapeau", "legendary", "Couronne", couronne),
    ("SK_COS_Accessoire_Cornes", "accessoire", "epic", "Cornes de diable", cornes),
    ("SK_COS_Accessoire_Aureole", "accessoire", "legendary", "Auréole", aureole),
    ("SK_COS_Accessoire_Pirate", "accessoire", "rare", "Bandeau de pirate", bandeau_pirate),
    ("SK_COS_Lunettes_Soleil", "lunettes", "common", "Lunettes de soleil", lambda: lunettes_soleil("noir")),
    ("SK_COS_Lunettes_Roses", "lunettes", "rare", "Lunettes roses", lambda: lunettes_soleil("rose")),
    ("SK_COS_Cheveux_Blond", "cheveux", "common", "Coiffure blonde", lambda: coiffure(None, "blond")),
    ("SK_COS_Cheveux_Roux", "cheveux", "common", "Coiffure rousse", lambda: coiffure(None, "roux")),
    ("SK_COS_Cheveux_Noir", "cheveux", "common", "Coiffure noire", lambda: coiffure(None, "noir")),
    ("SK_COS_Cheveux_Bleu", "cheveux", "uncommon", "Coiffure bleue", lambda: coiffure(None, "bleu")),
    ("SK_COS_Cheveux_Afro", "cheveux", "rare", "Afro", lambda: coiffure(afro, "noir")),
    ("SK_COS_Cheveux_Herisson", "cheveux", "rare", "Hérisson", lambda: coiffure(herisson, "blond")),
    ("SK_COS_Cheveux_Chignon", "cheveux", "uncommon", "Chignon", lambda: coiffure(None, "brun", chignon_extra)),
    ("SK_COS_Cheveux_Iroquoise", "cheveux", "epic", "Iroquoise", lambda: coiffure(iroquoise, "vert")),
    ("SK_COS_Cheveux_Palmier", "cheveux", "legendary", "Palmier", lambda: coiffure(palmier, "roux")),
    ("SK_COS_Visage_PetitsYeux", "visage", "common", "Petits yeux", lambda: expression(petits_yeux)),
    ("SK_COS_Visage_Enerve", "visage", "common", "Énervé", lambda: expression(enerve)),
    ("SK_COS_Visage_Etonne", "visage", "uncommon", "Étonné", lambda: expression(etonne)),
    ("SK_COS_Visage_Endormi", "visage", "uncommon", "Endormi", lambda: expression(endormi)),
    ("SK_COS_Visage_Triste", "visage", "uncommon", "Triste", lambda: expression(triste)),
    ("SK_COS_Visage_ClinOeil", "visage", "rare", "Clin d'œil", lambda: expression(clin_oeil)),
    ("SK_COS_Visage_GrandSourire", "visage", "rare", "Grand sourire", lambda: expression(grand_sourire)),
]


# ---------------------------------------------------------------- apercus

def materiau_atlas():
    mat = bpy.data.materials.new("Atlas Creative")
    mat.use_nodes = True
    t = mat.node_tree
    tex = t.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(KIT / "Textures_4.png"), check_existing=True)
    t.links.new(tex.outputs["Color"], t.nodes["Principled BSDF"].inputs["Base Color"])
    t.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.7
    return mat


def camera_tete(scene):
    cam = bpy.data.objects.new("Camera tete", bpy.data.cameras.new("Camera tete"))
    scene.collection.objects.link(cam)
    cam.location = Vector((0.55, -1.05, 1.82))
    cam.rotation_euler = (Vector((0, -0.01, 1.74)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 70
    scene.camera = cam
    scene.render.resolution_x, scene.render.resolution_y = 520, 560


def main():
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    scene = bpy.context.scene
    rig = bpy.data.objects["Root"]
    for o in bpy.data.objects:
        if o.type == "MESH" and (o.name.startswith("SK_COS_") or o.name.startswith("DESIGN_")
                                 or o.name.startswith("REFERENCE_")):
            o.hide_render = True
    atlas = materiau_atlas()
    camera_tete(scene)
    scene.render.engine = "BLENDER_EEVEE"
    # Le visage et la coiffure du kit, pour le contexte des apercus.
    visage_kit = importer_kit("Male_emotion_usual_001")
    cheveux_kit = importer_kit("Hairstyle_male_010")
    for o in (visage_kit, cheveux_kit):
        o.data.materials.append(atlas)

    manifeste = []
    faites = []
    for nom, emplacement, rarete, affiche, fabrique in PIECES:
        piece = fusionner(fabrique(), nom)
        # Un seul jeu d'UV (Unreal lit le premier canal).
        while len(piece.data.uv_layers) > 1:
            piece.data.uv_layers.remove(piece.data.uv_layers[1])
        rigide_sur_tete(piece, rig)
        objet_actif(rig)
        piece.select_set(True)
        bpy.context.view_layer.objects.active = piece
        bpy.ops.export_scene.fbx(mesh_smooth_type="FACE", filepath=str(OUT / (nom + ".fbx")), use_selection=True,
                                 object_types={"ARMATURE", "MESH"}, add_leaf_bones=False, bake_anim=False,
                                 use_mesh_modifiers=True, armature_nodetype="NULL")
        piece.data.materials.clear()
        piece.data.materials.append(atlas)
        for o in faites:
            o.hide_render = True
        piece.hide_render = False
        visage_kit.hide_render = emplacement == "visage"
        cheveux_kit.hide_render = emplacement in ("cheveux", "chapeau")
        scene.render.filepath = str(OUT / ("Apercu_" + nom + ".png"))
        bpy.ops.render.render(write_still=True)
        faites.append(piece)
        manifeste.append({"piece": nom, "emplacement": emplacement, "rarete": rarete, "nom": affiche})
        print("TETE_PRETE", nom)
    (OUT / "manifeste.json").write_text(json.dumps(manifeste, indent=2, ensure_ascii=False), encoding="utf-8")


main()
