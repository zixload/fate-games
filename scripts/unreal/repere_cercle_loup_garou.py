"""Pose dans la map ouverte un repere du cercle du loup-garou, pour decorer autour.

A executer dans la console Python de l'editeur (NanosWorldADK), la map du jeu ouverte :

    exec(open(r"C:\\Users\\ingam\\OneDrive\\Documents\\fate-games\\scripts\\unreal\\repere_cercle_loup_garou.py", encoding="utf-8").read())

En jeu, le tapis et les zabutons sont poses par le serveur autour du centre
enregistre par /lg centre (loup_garou.json, a cote du serveur). La map ne les
contient pas. Ce script en pose une copie au meme endroit, marquee "editeur
seulement" : elle n'est pas cuite, donc pas de doublon en jeu. Relancer le
script remplace l'ancien repere.

Memes valeurs que Server/games/werewolf/adapter.lua : rayon 424 cm, tapis a
l'echelle 2, 12 places, la premiere dans la direction enregistree.
"""

import json
import math
from pathlib import Path
import unreal

CENTRE = Path("C:/nanos-world-server/loup_garou.json")
RAYON, ECHELLE_TAPIS, PLACES, EPAISSEUR_TAPIS = 424.0, 2.0, 12, 0.8
TAPIS = "/Game/MyAssetPack/Werewolf/SM_WW_Carpet"
COUSSINS = ("Red", "Blue", "Yellow", "Green", "Purple", "White", "Brown")
DOSSIER = "LoupGarou_Repere"
PREFIXE = "WW_REPERE_"

acteurs = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)

c = json.loads(CENTRE.read_text(encoding="utf-8"))
x0, y0, sol, yaw = c["x"], c["y"], c["sol"], c.get("yaw", 0)

for a in acteurs.get_all_level_actors():
    if a.get_actor_label().startswith(PREFIXE):
        acteurs.destroy_actor(a)


def poser(chemin, x, y, z, lacet, echelle, etiquette):
    mesh = unreal.EditorAssetLibrary.load_asset(chemin)
    if not mesh:
        raise RuntimeError(f"Asset introuvable : {chemin}")
    a = acteurs.spawn_actor_from_object(mesh, unreal.Vector(x, y, z), unreal.Rotator(roll=0, pitch=0, yaw=lacet))
    a.set_actor_scale3d(echelle)
    a.set_actor_label(PREFIXE + etiquette)
    a.set_folder_path(DOSSIER)
    a.set_editor_property("is_editor_only_actor", True)
    return a


poser(TAPIS, x0, y0, sol, yaw, unreal.Vector(ECHELLE_TAPIS, ECHELLE_TAPIS, 1), "Tapis")
for i in range(PLACES):
    angle = yaw + 360.0 * i / PLACES
    r = math.radians(angle)
    poser(f"/Game/MyAssetPack/Werewolf/SM_WW_Zabuton_{COUSSINS[i % len(COUSSINS)]}",
          x0 + RAYON * math.cos(r), y0 + RAYON * math.sin(r), sol + EPAISSEUR_TAPIS,
          angle + 180, unreal.Vector(1, 1, 1), f"Coussin_{i + 1}")

print("WW_REPERE_POSE", "centre", (round(x0), round(y0), round(sol)), "dossier", DOSSIER)
