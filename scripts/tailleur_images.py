"""Images des cartes de la boutique du tailleur, decoupees dans les apercus
rendus par les scripts Blender (art/cosmetics/*).

    python scripts/tailleur_images.py

Sortie : Packages/fate-games/Client/tailleur/img/<id>.png (hors depot : les
rendus montrent le corps du kit Creative, sous licence Fab).
"""

import json
from pathlib import Path

from PIL import Image

PROJECT = Path(__file__).resolve().parents[1]
ART = PROJECT / "art/cosmetics"
OUT = PROJECT / "Packages/fate-games/Client/tailleur/img"
OUT.mkdir(parents=True, exist_ok=True)
T = 220


def carte(source, cadre, ident):
    if not source.is_file():
        print("MANQUE", source.name)
        return
    im = Image.open(source).convert("RGB")
    w, h = im.size
    x0, y0, x1, y1 = cadre
    im = im.crop((int(w * x0), int(h * y0), int(w * x1), int(h * y1)))
    im.thumbnail((T, T))
    fond = Image.new("RGB", (T, T), im.getpixel((2, 2)))
    fond.paste(im, ((T - im.width) // 2, (T - im.height) // 2))
    fond.save(OUT / (ident + ".png"))


BUSTE = (0.18, 0.1, 0.82, 0.64)
for m in json.loads((ART / "tshirts_motifs/manifeste.json").read_text(encoding="utf-8")):
    suf = m["texture"].replace("T_COS_TShirt_M_", "")
    carte(ART / "tshirts_motifs" / ("Apercu_" + suf + ".png"), BUSTE, "haut_" + suf.lower())
for ident, fichier in (("haut_effiloche", "Uncommon_Frayed"), ("haut_eclaireur", "Rare_Compass"),
                       ("haut_eclipse", "Epic_Eclipse"), ("haut_soleil_or", "Legendary_Sun")):
    carte(ART / "tshirts" / ("Preview_" + fichier + ".png"), BUSTE, ident)
for m in json.loads((ART / "pantalons/manifeste.json").read_text(encoding="utf-8")):
    suf = m["texture"].replace("T_COS_Pants_", "")
    carte(ART / "pantalons" / ("Apercu_" + suf + ".png"), (0.05, 0.3, 0.95, 0.95), "bas_" + suf.lower())
for m in json.loads((ART / "tete/manifeste.json").read_text(encoding="utf-8")):
    carte(ART / "tete" / ("Apercu_" + m["piece"] + ".png"), (0.08, 0.05, 0.92, 0.9),
          m["piece"].replace("SK_COS_", "").lower())
# Coiffures, manches longues, chapeaux et lunettes (ajouts du 27/09).
for m in json.loads((ART / "cheveux/manifeste.json").read_text(encoding="utf-8")):
    style = m["piece"].replace("SK_COS_Cheveux_", "")
    carte(ART / "cheveux" / ("Apercu_" + style + "_face.png"), (0.08, 0.05, 0.92, 0.9), "cheveux_" + style.lower())
for m in json.loads((ART / "manches_longues/manifeste.json").read_text(encoding="utf-8")):
    suf = m["texture"].replace("T_COS_ML_", "")
    carte(ART / "manches_longues" / ("Apercu_" + suf + ".png"), (0.1, 0.08, 0.9, 0.72), "haut_ml_" + suf.lower())
IDS_ACCESSOIRES = {"LunettesCoeur": "lunettes_coeur"}
for m in json.loads((ART / "accessoires/manifeste.json").read_text(encoding="utf-8")):
    nom = m["piece"].replace("SK_COS_", "")
    carte(ART / "accessoires" / ("Apercu_" + nom + "_face.png"), (0.0, 0.0, 1.0, 0.85),
          IDS_ACCESSOIRES.get(nom, m["emplacement"] + "_" + nom.lower()))
# Pieces du kit (scripts/blender/apercus_kit.py), deja cadrees.
for source in sorted((ART / "kit").glob("Apercu_*.png")):
    carte(source, (0.0, 0.0, 1.0, 1.0), source.stem.replace("Apercu_", ""))
print("images :", len(list(OUT.glob("*.png"))))
