"""Apercus des pieces du kit Creative vendues chez le tailleur (celles qui n'ont
pas de script a elles : T-shirt, vestes, pantalons, chaussures, visages...).

    blender -b --python scripts/blender/apercus_kit.py

Chaque piece est posee sur le corps du kit, camera cadree sur sa zone (tete,
buste, jambes, pieds, main). Les pieces de tete portent le visage habituel.
Sorties dans art/cosmetics/kit/ (hors depot) : Apercu_<id>.png, que
scripts/tailleur_images.py reprend pour les cartes.
"""

import re
from pathlib import Path

import bpy
from mathutils import Vector

PROJECT = Path(__file__).resolve().parents[2]
SOURCE = PROJECT / "art/cosmetics/tshirts/creative_tshirt_rarities.blend"
KIT = Path("C:/ProgramData/Epic/EpicGamesLauncher/VaultCache/FabLibrary/"
           "Creative_Characters_FREE_-_Animated_Low_Poly_3D_Models-94fd60a2/obj/source_extracted/"
           "Separate_assets_obj_extracted/Separate_assets_obj")
OUT = PROJECT / "art/cosmetics/kit"
OUT.mkdir(parents=True, exist_ok=True)

# Cadrages : (point vise, direction de la camera, distance, focale).
CADRES = {
    "tete": (Vector((0, -0.01, 1.72)), Vector((0.45, -1, 0.05)), 1.1, 60),
    "buste": (Vector((0, 0, 1.15)), Vector((0.35, -1, 0.05)), 1.85, 50),
    "jambes": (Vector((0, 0, 0.52)), Vector((0.35, -1, 0.1)), 2.05, 50),
    "pieds": (Vector((0, -0.04, 0.07)), Vector((0.55, -1, 0.45)), 0.95, 50),
    "main": (Vector((0.6, -0.02, 0.97)), Vector((0.3, -1, 0.1)), 0.6, 50),
}
PAR_EMPLACEMENT = {"cheveux": "tete", "visage": "tete", "chapeau": "tete", "lunettes": "tete",
                   "barbe": "tete", "haut": "buste", "bas": "jambes", "chaussures": "pieds"}


def pieces_du_kit():
    """(id, emplacement, piece) des pieces du kit, lues dans Shared/cosmetiques.lua."""
    lua = (PROJECT / "Packages/fate-games/Shared/cosmetiques.lua").read_text(encoding="utf-8")
    motif = re.compile(r'id = "([^"]+)".*?emplacement = "([^"]+)".*?piece = "(SK_[^"]+)"')
    return [(i, e, p) for i, e, p in motif.findall(lua) if not p.startswith("SK_COS_")]


def importer(piece):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.wm.obj_import(filepath=str(KIT / (piece[3:] + ".obj")))
    objs = [o for o in bpy.context.selected_objects if o.type == "MESH"]
    for o in objs:
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return objs


def main():
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    scene = bpy.context.scene
    corps = bpy.data.objects["SK_Animations.001"]
    for o in bpy.data.objects:
        if o.type == "MESH" and o is not corps:
            o.hide_render = True
    visage = importer("SK_Male_emotion_usual_001")
    cam = bpy.data.objects.new("Camera kit", bpy.data.cameras.new("Camera kit"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = scene.render.resolution_y = 480

    for ident, emplacement, piece in pieces_du_kit():
        cadre = "main" if "Gloves" in piece else PAR_EMPLACEMENT.get(emplacement, "tete")
        objs = importer(piece)
        for o in visage:
            o.hide_render = emplacement == "visage" or cadre != "tete"
        vise, direction, distance, focale = CADRES[cadre]
        cam.location = vise + direction.normalized() * distance
        cam.rotation_euler = (vise - cam.location).to_track_quat("-Z", "Y").to_euler()
        cam.data.lens = focale
        scene.render.filepath = str(OUT / ("Apercu_" + ident + ".png"))
        bpy.ops.render.render(write_still=True)
        for o in objs:
            bpy.data.objects.remove(o)
        print("APERCU_KIT", ident, cadre)


main()
