"""Importe les sons du jeu dans my-asset-pack.

A executer dans la console Python de l'editeur (NanosWorldADK) :

    exec(open(r"C:\\Users\\ingam\\OneDrive\\Documents\\fate-games\\scripts\\unreal\\import_sons.py", encoding="utf-8").read())

Chaque art/sons/<nom>.wav (dossier hors depot) devient le SoundWave
/Game/MyAssetPack/Sounds/A_<nom>, que le jeu joue par my-asset-pack::A_<nom>
(Packages/fate-games/Client/son.lua). Relancer remplace les sons existants.
Cuire my-asset-pack ensuite.

Les .ogg bruts lus par package:// se chargeaient au hasard en jeu (duree 0,
jamais joues) : les sons passent donc par l'asset pack, comme ceux de nanos.
"""

from pathlib import Path
import unreal

SOURCE = Path(r"C:\Users\ingam\OneDrive\Documents\fate-games\art\sons")
DESTINATION = "/Game/MyAssetPack/Sounds"

fichiers = sorted(SOURCE.glob("*.wav"))
if not fichiers:
    raise RuntimeError(f"Aucun .wav dans {SOURCE}")

taches = []
for f in fichiers:
    t = unreal.AssetImportTask()
    t.set_editor_property("filename", str(f))
    t.set_editor_property("destination_path", DESTINATION)
    t.set_editor_property("destination_name", "A_" + f.stem)
    t.set_editor_property("automated", True)
    t.set_editor_property("replace_existing", True)
    t.set_editor_property("save", True)
    taches.append(t)

unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks(taches)

manquants = 0
for f in fichiers:
    chemin = f"{DESTINATION}/A_{f.stem}"
    son = unreal.EditorAssetLibrary.load_asset(chemin)
    if isinstance(son, unreal.SoundWave):
        try:
            duree = round(son.get_editor_property("duration"), 2)
        except Exception:
            duree = "?"
        print("SON_IMPORTE", f"my-asset-pack::A_{f.stem}", duree, "s")
    else:
        print("SON_ATTENTION", f.name, "non importe, voir l'Output Log")
        manquants += 1
unreal.EditorAssetLibrary.save_directory(DESTINATION)
print("SONS_PRETS" if not manquants else f"SONS_INCOMPLETS ({manquants} manquant(s))", "- cuire my-asset-pack ensuite")
