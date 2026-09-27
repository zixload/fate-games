"""Tuiles de motifs repetes (poussins, chauves-souris, toile, bananes,
pasteques, donuts), dessinees a plat avec Pillow.

    python scripts/blender/tuiles_motifs.py

Lance avec le Python du systeme (Pillow), avant create_pantalons.py qui les
repete sur les shorts. Sorties : art/cosmetics/pantalons/tuiles/<nom>.png,
512 px, fond transparent, deux motifs par tuile en quinconce.
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw

PROJECT = Path(__file__).resolve().parents[2]
OUT = PROJECT / "art/cosmetics/pantalons/tuiles"
OUT.mkdir(parents=True, exist_ok=True)
T = 512
ENCRE = (28, 33, 35, 255)
E = 6   # epaisseur du trait


def tourne(pts, cx, cy, a):
    c, s = math.cos(a), math.sin(a)
    return [(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in pts]


def poussin(d, cx, cy, a):
    jaune, orange = (255, 214, 64, 255), (255, 140, 30, 255)
    d.ellipse((cx - 62, cy - 30, cx + 50, cy + 70), fill=jaune, outline=ENCRE, width=E)
    d.ellipse((cx - 5, cy - 88, cx + 70, cy - 13), fill=jaune, outline=ENCRE, width=E)
    d.polygon(tourne([(cx + 66, cy - 58), (cx + 100, cy - 48), (cx + 66, cy - 38)], cx, cy, 0), fill=orange, outline=ENCRE)
    d.ellipse((cx + 32, cy - 66, cx + 46, cy - 52), fill=ENCRE)
    d.arc((cx - 40, cy - 5, cx + 20, cy + 45), 200, 340, fill=ENCRE, width=E)
    for dx in (-20, 10):
        d.line((cx + dx, cy + 68, cx + dx, cy + 92), fill=orange, width=E)
        d.line((cx + dx - 12, cy + 92, cx + dx + 12, cy + 92), fill=orange, width=E)
    d.ellipse((cx + 12, cy - 40, cx + 26, cy - 28), fill=(255, 150, 160, 255))


def chauve_souris(d, cx, cy, a):
    s = 1.25
    aile = [(0, 0), (30, -22), (52, -48), (74, -30), (96, -48), (120, -10), (104, 2), (88, 20), (70, 8),
            (52, 26), (34, 12)]
    droite = [(cx + x * s * 0.8, cy + y * s * 0.8) for x, y in aile]
    gauche = [(cx - x * s * 0.8, cy + y * s * 0.8) for x, y in aile]
    corps = [(cx - 16, cy - 18), (cx - 12, cy - 44), (cx - 4, cy - 30), (cx + 4, cy - 30), (cx + 12, cy - 44),
             (cx + 16, cy - 18), (cx + 12, cy + 30), (cx, cy + 40), (cx - 12, cy + 30)]
    for poly in (droite, gauche, corps):
        d.polygon(tourne(poly, cx, cy, a), fill=(22, 22, 30, 255))
    for dx in (-7, 7):
        d.ellipse((cx + dx - 3, cy - 22, cx + dx + 3, cy - 16), fill=(255, 220, 90, 255))


def toile(d, cx, cy, a):
    r = 120
    for k in range(10):
        t = a + k * math.pi / 5
        d.line((cx, cy, cx + r * math.cos(t), cy + r * math.sin(t)), fill=ENCRE, width=4)
    for i in range(1, 6):
        rr = r * i / 5
        pts = [(cx + rr * math.cos(a + k * math.pi / 5) * (0.92 if k % 2 else 1),
                cy + rr * math.sin(a + k * math.pi / 5) * (0.92 if k % 2 else 1)) for k in range(11)]
        d.line(pts, fill=ENCRE, width=4, joint="curve")


def banane(d, cx, cy, a):
    # Croissant : deux arcs de cercle, l'interieur decale vers le bas.
    ext = [(cx + 105 * math.cos(math.radians(t)), cy + 55 + 105 * math.sin(math.radians(t)))
           for t in range(205, 336, 5)]
    inte = [(cx + 92 * math.cos(math.radians(t)), cy + 90 + 92 * math.sin(math.radians(t)))
            for t in range(330, 209, -5)]
    poly = tourne(ext + inte, cx, cy, a)
    d.polygon(poly, fill=(255, 225, 70, 255), outline=ENCRE, width=E)
    # Queue a un bout, pointe brune a l'autre.
    x0, y0 = tourne([ext[0]], cx, cy, a)[0]
    x1, y1 = tourne([ext[-1]], cx, cy, a)[0]
    d.line((x1, y1, x1 + 14, y1 - 14), fill=(120, 90, 40, 255), width=10)
    d.ellipse((x0 - 8, y0 - 8, x0 + 8, y0 + 8), fill=(90, 60, 25, 255))


def pasteque(d, cx, cy, a):
    r = 105
    ecorce = [(cx, cy - 20)] + [(cx + r * math.cos(t), cy - 20 + r * math.sin(t))
                                 for t in [math.pi * (0.15 + 0.7 * i / 24) for i in range(25)]]
    d.polygon(tourne(ecorce, cx, cy, a), fill=(70, 160, 70, 255), outline=ENCRE, width=E)
    chair = [(cx, cy - 20)] + [(cx + (r - 18) * math.cos(t), cy - 20 + (r - 18) * math.sin(t))
                                for t in [math.pi * (0.17 + 0.66 * i / 24) for i in range(25)]]
    d.polygon(tourne(chair, cx, cy, a), fill=(240, 70, 90, 255))
    for px, py in ((-30, 30), (0, 45), (30, 30), (-12, 12), (14, 14)):
        x, y = tourne([(cx + px, cy - 20 + py + 10)], cx, cy, a)[0]
        d.ellipse((x - 5, y - 8, x + 5, y + 8), fill=ENCRE)


def donut(d, cx, cy, a):
    d.ellipse((cx - 90, cy - 90, cx + 90, cy + 90), fill=(214, 160, 100, 255), outline=ENCRE, width=E)
    glacage = [(cx + (72 + 8 * math.sin(k * 1.3)) * math.cos(k * math.pi / 12),
                cy + (72 + 8 * math.sin(k * 1.3)) * math.sin(k * math.pi / 12)) for k in range(24)]
    d.polygon(glacage, fill=(255, 120, 180, 255))
    d.ellipse((cx - 28, cy - 28, cx + 28, cy + 28), fill=(0, 0, 0, 0), outline=ENCRE, width=E)
    couleurs = [(255, 255, 255, 255), (80, 200, 255, 255), (255, 230, 60, 255), (120, 230, 120, 255)]
    for k in range(14):
        t = k * 2.3 + a
        rr = 45 + (k * 13) % 22
        x, y = cx + rr * math.cos(t), cy + rr * math.sin(t)
        d.line((x - 7 * math.cos(t + 1), y - 7 * math.sin(t + 1), x + 7 * math.cos(t + 1), y + 7 * math.sin(t + 1)),
               fill=couleurs[k % 4], width=5)


def tuile(nom, dessin):
    im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # Deux motifs en quinconce, un peu tournes : le motif respire, sans grille.
    for cx, cy, a in ((128, 128, -0.2), (384, 384, 0.25)):
        dessin(d, cx, cy, a)
    im = im.transpose(Image.FLIP_TOP_BOTTOM)   # Blender lit les images de bas en haut
    im.save(OUT / (nom + ".png"))
    print("TUILE", nom)


for nom, dessin in (("poussins", poussin), ("chauves_souris", chauve_souris), ("toile", toile),
                    ("bananes", banane), ("pasteques", pasteque), ("donuts", donut)):
    tuile(nom, dessin)
