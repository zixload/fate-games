"""Decouper le decor Club Penguin (Clothing Customizer) en pieces reutilisables.

    blender -b --python scripts/blender/decoupe_decor.py -- --atelier
    blender -b --python scripts/blender/decoupe_decor.py -- --exporter

--atelier ecrit art/werewolf/decor/ClothingCustomizer/Decoupe_ClothingCustomizer.blend :
le decor texture, en metres, en trois objets (Decor, Rideaux, Lumieres). On y
detache les pieces voulues (mode Edition, L sur une piece puis P > Selection),
on les renomme, on supprime le reste, on peut en reunir (Ctrl+J), puis on
enregistre. Un atelier existant n'est jamais ecrase.

--exporter fait de chaque objet restant un decor a part :
art/werewolf/decor/CC_<Nom>/CC_<Nom>.fbx (pivot au milieu du bas de la piece)
et ses textures, liste dans art/werewolf/decor/decoupe.json. Le script Unreal
import_decor_loup_garou.py les importe ensuite (my-asset-pack::SM_WW_CC_<Nom>),
avec une collision qui suit la vraie forme (pas de murs invisibles).
"""

import json
import re
import shutil
import sys
from pathlib import Path

import bpy
from mathutils import Vector

PROJECT = Path(__file__).resolve().parents[2]
DECORS = PROJECT / "art/werewolf/decor"
SOURCE = DECORS / "ClothingCustomizer"
BRUT = DECORS / "_brut/ClothingCustomizer"
ATELIER = SOURCE / "Decoupe_ClothingCustomizer.blend"
MANIFESTE = DECORS / "decoupe.json"

# Materiau d'origine (usemtl) -> texture de couleur, et le reglage du
# materiau cote Unreal (meme forme que DECORS dans import_decor_loup_garou.py).
TEXTURES = {"clothingdesignerstatic": "ClothingDesigner.png",
            "catalogchallengecurtains": "CatalogChallengeCurtain.png"}
MATERIAUX = {
    "clothingdesignerstatic": {"base": "ClothingDesigner.png"},
    "catalogchallengecurtains": {"base": "CatalogChallengeCurtain.png"},
    "lighteffects": {"verre": True, "couleur": (1.0, 0.95, 0.8), "emissif": 2.0},
}
NOMS = {"ClothingDesignerStaticCombined": "Decor", "CatalogChallengeCurtains": "Rideaux",
        "ClothingDesignerLightEffects": "Lumieres"}


def normaliser(nom):
    return re.sub(r"[\s_\-.]|\d+$", "", nom.lower())


def atelier():
    if ATELIER.is_file():
        print("DECOUPE_ATELIER_EXISTE", ATELIER, "(le supprimer pour le refaire)")
        return
    source = next(BRUT.rglob("*.obj"))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.obj_import(filepath=str(source))
    for o in list(bpy.context.scene.objects):
        o.name = NOMS.get(o.name, o.name)
    # Des materiaux textures pour y voir clair (vue Material Preview, touche Z).
    for m in bpy.data.materials:
        fichier = TEXTURES.get(normaliser(m.name))
        m.use_nodes = True
        bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if not (fichier and bsdf):
            continue
        tex = m.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(str(SOURCE / "textures" / fichier), check_existing=True)
        m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bpy.ops.wm.save_as_mainfile(filepath=str(ATELIER))
    print("DECOUPE_ATELIER_PRET", ATELIER, [o.name for o in bpy.context.scene.objects])


def exporter():
    bpy.ops.wm.open_mainfile(filepath=str(ATELIER))
    manifeste = []
    for o in [x for x in bpy.data.objects if x.type == "MESH"]:
        nom = "CC_" + re.sub(r"[^A-Za-z0-9]", "", o.name.title()) or "Piece"
        dossier = DECORS / nom
        if dossier.exists():
            shutil.rmtree(dossier)
        (dossier / "textures").mkdir(parents=True)
        # Transformations appliquees, pivot au milieu du bas de la piece, a l'origine.
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        pts = [v.co for v in o.data.vertices]
        bas = Vector(((min(p.x for p in pts) + max(p.x for p in pts)) / 2,
                      (min(p.y for p in pts) + max(p.y for p in pts)) / 2, min(p.z for p in pts)))
        for v in o.data.vertices:
            v.co -= bas
        o.data.update()
        bpy.ops.export_scene.fbx(mesh_smooth_type="FACE", filepath=str(dossier / f"{nom}.fbx"), use_selection=True,
                                 apply_scale_options="FBX_SCALE_UNITS", object_types={"MESH"},
                                 path_mode="COPY", embed_textures=False)
        cles = {normaliser(s.material.name) for s in o.material_slots if s.material}
        for cle in cles:
            fichier = TEXTURES.get(cle)
            if fichier:
                shutil.copy2(SOURCE / "textures" / fichier, dossier / "textures" / fichier)
        manifeste.append({"nom": nom, "echelle": 100.0, "collision": "exacte",
                          "materiaux": {c: MATERIAUX[c] for c in cles if c in MATERIAUX}})
        print("DECOUPE_PIECE", nom, len(o.data.vertices), "sommets", sorted(cles))
    MANIFESTE.write_text(json.dumps(manifeste, indent=2), encoding="utf-8")
    print("DECOUPE_EXPORT_COMPLETE", len(manifeste), "pieces ->", MANIFESTE)


args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if "--exporter" in args:
    exporter()
else:
    atelier()
