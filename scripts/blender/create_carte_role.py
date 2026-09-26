"""Modele de carte de role du loup-garou : coins arrondis, epaisseur, UV.

    blender -b --python scripts/blender/create_carte_role.py

Sortie : art/werewolf/decor/RoleCard/RoleCard.fbx (dossier ignore par git),
importe dans Unreal par scripts/unreal/import_decor_loup_garou.py.

La carte fait 10 x 15 cm pour 1,2 mm d'epaisseur, a plat (face vers +Z), le
long cote sur X ; le jeu la met a l'echelle (Client/loup_garou/cartes.lua).
Trois emplacements de materiau : Face (dessus, UV 0..1 sur toute la carte :
le dessin de la carte), Dos (dessous, meme UV), Tranche (le bord).
"""

from pathlib import Path

import bmesh
import bpy

ROOT = Path(__file__).resolve().parents[2]
SORTIE = ROOT / "art/werewolf/decor/RoleCard/RoleCard.fbx"
LONG, LARGE, EPAIS, RAYON = 0.15, 0.10, 0.0012, 0.009   # metres

bpy.ops.wm.read_factory_settings(use_empty=True)
mesh = bpy.data.meshes.new("RoleCard")
obj = bpy.data.objects.new("RoleCard", mesh)
bpy.context.collection.objects.link(obj)

bm = bmesh.new()
# Rectangle aux coins arrondis : quatre quarts de cercle.
import math
points = []
SEG = 8
coins = [(LONG / 2 - RAYON, LARGE / 2 - RAYON, 0), (-LONG / 2 + RAYON, LARGE / 2 - RAYON, 90),
         (-LONG / 2 + RAYON, -LARGE / 2 + RAYON, 180), (LONG / 2 - RAYON, -LARGE / 2 + RAYON, 270)]
for cx, cy, a0 in coins:
    for k in range(SEG + 1):
        a = math.radians(a0 + 90 * k / SEG)
        points.append((cx + RAYON * math.cos(a), cy + RAYON * math.sin(a)))
bas = [bm.verts.new((x, y, 0)) for x, y in points]
haut = [bm.verts.new((x, y, EPAIS)) for x, y in points]
face_haut = bm.faces.new(haut)
face_bas = bm.faces.new(list(reversed(bas)))
n = len(points)
cotes = []
for i in range(n):
    j = (i + 1) % n
    cotes.append(bm.faces.new((bas[i], bas[j], haut[j], haut[i])))

# UV : le dessin couvre toute la carte ; le haut de l'image vers +X.
uv = bm.loops.layers.uv.new("UVMap")
for f in (face_haut, face_bas):
    for loop in f.loops:
        x, y = loop.vert.co.x, loop.vert.co.y
        u = (y + LARGE / 2) / LARGE
        v = (x + LONG / 2) / LONG
        loop[uv].uv = (1 - u if f is face_bas else u, v)
for f in cotes:
    for loop in f.loops:
        loop[uv].uv = (0.5, 0.5)

face_haut.material_index, face_bas.material_index = 0, 1
for f in cotes:
    f.material_index = 2
    f.smooth = True
bm.to_mesh(mesh)
bm.free()

for nom in ("Face", "Dos", "Tranche"):
    mesh.materials.append(bpy.data.materials.new(nom))

SORTIE.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.fbx(filepath=str(SORTIE), apply_scale_options="FBX_SCALE_UNITS",
                         object_types={"MESH"}, use_selection=False)
print("CARTE", SORTIE)
