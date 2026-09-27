r"""Cherche ce qui bloque autour du cercle du loup-garou (mur invisible).

A executer dans la console Python de l'editeur (NanosWorldADK), la map du jeu ouverte :

    exec(open(r"C:\Users\ingam\OneDrive\Documents\fate-games\scripts\unreal\trouver_mur_invisible.py", encoding="utf-8").read())

Liste les acteurs a moins de RAYON du centre du cercle (loup_garou.json du
serveur) qui ont une collision, du plus gros au plus petit : nom, maillage,
echelle, taille de la collision. Un gros bloc invisible ressort en tete.
Rien n'est modifie. Les acteurs listes sont aussi selectionnes dans l'editeur.
"""

import json
from pathlib import Path

import unreal

RAYON = 2000.0   # cm
centre = json.loads(Path(r"C:\nanos-world-server\loup_garou.json").read_text(encoding="utf-8"))
cx, cy = centre["x"], centre["y"]

acteurs = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
trouves = []
for a in acteurs.get_all_level_actors():
    l = a.get_actor_location()
    if ((l.x - cx) ** 2 + (l.y - cy) ** 2) ** 0.5 > RAYON:
        continue
    for comp in a.get_components_by_class(unreal.PrimitiveComponent):
        if comp.get_collision_enabled() == unreal.CollisionEnabled.NO_COLLISION:
            continue
        origine, etendue = comp.get_local_bounds() if hasattr(comp, "get_local_bounds") else (None, None)
        b = a.get_actor_bounds(False)
        taille = b[1] * 2
        maillage = ""
        if isinstance(comp, unreal.StaticMeshComponent) and comp.static_mesh:
            maillage = comp.static_mesh.get_path_name()
        visible = comp.is_visible() if hasattr(comp, "is_visible") else True
        trouves.append((taille.x * taille.y * taille.z, a, comp, taille, maillage, visible))
        break

trouves.sort(key=lambda t: -t[0])
print("MUR_CENTRE", round(cx), round(cy), "rayon", RAYON, "acteurs avec collision :", len(trouves))


def ligne(a, taille, maillage, visible):
    e = a.get_actor_scale3d()
    print("MUR_ACTEUR", a.get_actor_label(), "| classe", a.get_class().get_name(),
          "| taille cm", tuple(round(v) for v in (taille.x, taille.y, taille.z)),
          "| echelle", tuple(round(v, 2) for v in (e.x, e.y, e.z)),
          "| visible", visible, "|", maillage)


# Les decors ajoutes (pack, Fab, imports) d'abord : le coupable est la,
# pas dans les murs de la carte d'origine.
ajoutes = [t for t in trouves if "/MyAssetPack/" in t[4] or "/Fab/" in t[4]]
print("MUR_AJOUTES", len(ajoutes), "decors ajoutes, du plus gros au plus petit :")
for volume, a, comp, taille, maillage, visible in ajoutes[:20]:
    ligne(a, taille, maillage, visible)
print("MUR_AUTRES les 8 plus gros objets de la carte d'origine :")
for volume, a, comp, taille, maillage, visible in [t for t in trouves if t not in ajoutes][:8]:
    ligne(a, taille, maillage, visible)
# Le vrai test : quelles boites contiennent un point ou marche un joueur, sur
# le cercle (au centre et a mi-rayon, a hauteur de hanche) ?
sol = centre.get("sol", 100.0)
points = [(cx, cy)] + [(cx + 250 * dx, cy + 250 * dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
coupables = []
for volume, a, comp, taille, maillage, visible in trouves:
    o, e = a.get_actor_bounds(False)
    for px, py in points:
        pz = sol + 90
        if abs(px - o.x) <= e.x and abs(py - o.y) <= e.y and abs(pz - o.z) <= e.z:
            coupables.append(a)
            l = a.get_actor_location()
            print("MUR_SUR_LE_CERCLE", a.get_actor_label(), "| position", tuple(round(v) for v in (l.x, l.y, l.z)),
                  "| boite cm", tuple(round(v * 2) for v in (e.x, e.y, e.z)), "|", maillage)
            break
print("MUR_SUR_LE_CERCLE_TOTAL", len(coupables))
acteurs.set_selected_level_actors(coupables or [t[1] for t in ajoutes[:10]])
print("MUR_FIN : les objets dont la boite couvre le cercle sont selectionnes (F pour les cadrer, Alt+C pour voir leur collision)")
