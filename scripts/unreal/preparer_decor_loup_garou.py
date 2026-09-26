"""Prepare les decors du loup-garou pour l'import Unreal (hors de l'editeur).

    python scripts/unreal/preparer_decor_loup_garou.py

Ouvre les zips telecharges (Downloads), y compris le zip ou le rar qu'ils
contiennent parfois, convertit un .blend en FBX avec Blender, et range pour
chaque decor un FBX et ses textures dans art/werewolf/decor/<Nom>/ (dossier
ignore par git : ces fichiers sont sous licence, ils ne vont pas dans le depot).
Ensuite, dans l'editeur : scripts/unreal/import_decor_loup_garou.py.
"""

import io
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOWNLOADS = Path.home() / "Downloads"
SORTIE = ROOT / "art/werewolf/decor"
BLENDER = Path("C:/Program Files/Blender Foundation/Blender 4.5/blender.exe")
TAR_WINDOWS = Path("C:/Windows/System32/tar.exe")   # lit aussi les .rar (libarchive)

# Nom du decor -> zip telecharge
DECORS = {
    "Lantern": "lantern.zip",
    "Campfire": "campfire.zip",
    "CrystalBall": "crystal-ball.zip",
    "CrystalBallTable": "witchtember-day-6-crystal-ball.zip",
    "HuntingRifle": "hunting-rifle.zip",
    "Candles": "candles.zip",
}
IMAGES = {".png", ".jpg", ".jpeg", ".tga"}


def extraire(zip_path, dossier):
    """Extrait le zip, puis les archives qu'il contient (zip, rar)."""
    with zipfile.ZipFile(zip_path) as z:
        z.extractall(dossier)
    for archive in list(dossier.rglob("*")):
        if archive.suffix.lower() == ".zip":
            with zipfile.ZipFile(archive) as z:
                z.extractall(archive.parent / archive.stem)
        elif archive.suffix.lower() == ".rar":
            cible = archive.parent / archive.stem
            cible.mkdir(exist_ok=True)
            subprocess.run([str(TAR_WINDOWS), "-xf", str(archive), "-C", str(cible)], check=True)


def blend_vers_fbx(blend, fbx):
    script = (
        "import bpy\n"
        f"bpy.ops.export_scene.fbx(filepath=r'{fbx}', apply_scale_options='FBX_SCALE_UNITS', "
        "object_types={'MESH'}, use_mesh_modifiers=True, path_mode='COPY', embed_textures=False)\n"
    )
    subprocess.run([str(BLENDER), "-b", str(blend), "--python-expr", script], check=True,
                   stdout=subprocess.DEVNULL)


def preparer(nom, zip_nom):
    zip_path = DOWNLOADS / zip_nom
    if not zip_path.is_file():
        print(f"ABSENT {zip_nom}")
        return
    brut = SORTIE / "_brut" / nom
    if brut.exists():
        shutil.rmtree(brut)
    brut.mkdir(parents=True)
    extraire(zip_path, brut)

    fbx = sorted(p for p in brut.rglob("*") if p.suffix.lower() == ".fbx")
    dest = SORTIE / nom
    if dest.exists():
        shutil.rmtree(dest)
    (dest / "textures").mkdir(parents=True)
    if fbx:
        shutil.copy2(fbx[0], dest / f"{nom}.fbx")
    else:
        blends = sorted(p for p in brut.rglob("*.blend"))
        if not blends:
            print(f"AUCUN MODELE {nom}")
            return
        blend_vers_fbx(blends[0], dest / f"{nom}.fbx")

    # Les textures, sans doublon (un zip les range parfois deux fois).
    vues = set()
    for image in sorted(brut.rglob("*")):
        if image.suffix.lower() in IMAGES and image.name.lower() not in vues:
            vues.add(image.name.lower())
            shutil.copy2(image, dest / "textures" / image.name)
    print(f"PRET {nom} : {dest / (nom + '.fbx')} ({len(vues)} textures)")


if __name__ == "__main__":
    SORTIE.mkdir(parents=True, exist_ok=True)
    for nom, zip_nom in DECORS.items():
        if len(sys.argv) > 1 and nom not in sys.argv[1:]:
            continue
        preparer(nom, zip_nom)
