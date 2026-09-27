"""Cases de couleur de l'atlas Creative (Textures_4.png) les plus proches de
teintes nommees : les pieces de tete (create_tete.py) posent leurs UV dessus
pour garder le materiau et le style du kit.

    python scripts/blender/palette_atlas.py

Sortie : art/cosmetics/tete/palette.json, { nom: [u, v] } en coordonnees UV
Blender (v = 0 en bas de l'image).
"""

import json
from pathlib import Path

from PIL import Image

PROJECT = Path(__file__).resolve().parents[2]
ATLAS = Path("C:/ProgramData/Epic/EpicGamesLauncher/VaultCache/FabLibrary/"
             "Creative_Characters_FREE_-_Animated_Low_Poly_3D_Models-94fd60a2/obj/source_extracted/"
             "Separate_assets_obj_extracted/Separate_assets_obj/Textures_4.png")
OUT = PROJECT / "art/cosmetics/tete/palette.json"

TEINTES = {
    "or": (232, 176, 40), "or_fonce": (160, 110, 20), "rouge": (220, 40, 40), "rouge_fonce": (130, 20, 25),
    "bleu": (40, 110, 220), "bleu_fonce": (25, 45, 110), "noir": (25, 25, 28), "gris": (120, 122, 125),
    "blanc": (245, 245, 242), "brun": (95, 55, 30), "blond": (235, 200, 110), "roux": (200, 85, 30),
    "rose": (240, 110, 170), "vert": (40, 170, 70), "violet": (130, 60, 190), "orange": (245, 130, 30),
    "paille": (225, 195, 120), "cyan": (40, 200, 220),
}

im = Image.open(ATLAS).convert("RGB")
w, h = im.size
px = im.load()
# Echantillonne une grille (evite les bords), garde la case la plus proche.
cases = [(x, y, px[x, y]) for x in range(8, int(w * 0.95), 6) for y in range(8, h - 8, 6)]
palette = {}
for nom, (r, g, b) in TEINTES.items():
    x, y, c = min(cases, key=lambda t: (t[2][0] - r) ** 2 + (t[2][1] - g) ** 2 + (t[2][2] - b) ** 2)
    palette[nom] = [round(x / w, 4), round(1 - y / h, 4)]
    print(nom, c, palette[nom])
OUT.write_text(json.dumps(palette, indent=1), encoding="utf-8")
