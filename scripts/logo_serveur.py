"""Logo Fate's Gale : capture de nuit + titre facon croquis + de esquisse."""
import math
import random
import sys
from pathlib import Path

import numpy as np
from fontTools.pens.basePen import BasePen
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFilter, ImageChops

ICI = Path(__file__).parent
SOURCE = Path(r"C:\Users\ingam\OneDrive\Images\Screenshots\Screenshot 2026-09-27 213759.png")
POLICE = r"C:\Windows\Fonts\Inkfree.ttf"
TEXTE = "Fate's Games"
W, H = 2400, 1200                     # travail (2x l'apercu 1200x600)
ENCRE = (28, 18, 12, 255)
CREME = (246, 234, 206, 255)
OCRE = (176, 132, 70, 255)
random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 7)


# ------------------------------------------------------------------ fond
def fond():
    img = Image.open(SOURCE).convert("RGB")
    # Cadre 2:1 : un peu de ciel, les domes, la place et le tapis.
    x0, y0, w = 0, 30, 1914
    img = img.crop((x0, y0, x0 + w, y0 + w // 2)).resize((W, H), Image.LANCZOS)
    img = img.filter(ImageFilter.GaussianBlur(2.2))        # a peine : le titre ressort
    a = np.asarray(img).astype(np.float32) / 255.0
    yy, xx = np.mgrid[0:H, 0:W]
    # Vignette, et une bande plus sombre derriere le titre (haut de l'image).
    r = np.hypot((xx - W / 2) / (W / 2), (yy - H / 2) / (H / 2))
    vign = 1.0 - 0.45 * np.clip(r - 0.55, 0, 1) ** 1.5
    bande = 1.0 - 0.42 * np.exp(-((yy - H * 0.36) / (H * 0.24)) ** 2)
    a = a * (vign * bande)[..., None]
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).convert("RGBA")


# ------------------------------------------------------------------ contours de la police
class Plat(BasePen):
    def __init__(self, gs):
        super().__init__(gs)
        self.contours, self.cur = [], []

    def _moveTo(self, p):
        self.cur = [p]

    def _lineTo(self, p):
        self.cur.append(p)

    def _curveToOne(self, p1, p2, p3):
        p0 = self.cur[-1]
        for i in range(1, 9):
            t = i / 8
            self.cur.append(tuple((1 - t) ** 3 * a + 3 * (1 - t) ** 2 * t * b + 3 * (1 - t) * t * t * c + t ** 3 * d
                                  for a, b, c, d in zip(p0, p1, p2, p3)))

    def _qCurveToOne(self, p1, p2):
        p0 = self.cur[-1]
        for i in range(1, 7):
            t = i / 6
            self.cur.append(tuple((1 - t) ** 2 * a + 2 * (1 - t) * t * b + t * t * c for a, b, c in zip(p0, p1, p2)))

    def _closePath(self):
        if len(self.cur) > 2:
            self.contours.append(self.cur)
        self.cur = []

    _endPath = _closePath


TROU_BOITE = None


def texte_epais(texte, taille_police, epaisseur, x_centre, y_centre, taille, police_=None, trou=None):
    """Le texte en feutre (Ink Free), epaissi, et ses contours pour le
    crayon (courbes de niveau du masque). Rend aussi le cadre du G."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from PIL import ImageFont
    police = ImageFont.truetype(police_ or POLICE, taille_police)
    m = Image.new("L", taille, 0)
    d = ImageDraw.Draw(m)
    x0, y0, x1, y1 = d.textbbox((0, 0), texte, font=police, stroke_width=epaisseur)
    ox, oy = x_centre - (x0 + x1) / 2, y_centre - (y0 + y1) / 2
    d.text((ox, oy), texte, font=police, fill=255, stroke_width=epaisseur, stroke_fill=255)
    global TROU_BOITE
    if trou:
        # Une lettre laissee vide (la boule de cristal prend sa place).
        tx = ox + d.textlength(texte[:texte.index(trou)], font=police)
        d.text((tx, oy), trou, font=police, fill=0, stroke_width=epaisseur + 2, stroke_fill=0)
        TROU_BOITE = d.textbbox((tx, oy), trou, font=police, stroke_width=epaisseur)
    m = m.filter(ImageFilter.GaussianBlur(1.5))
    avant = texte[:texte.index("G")]
    gx0 = ox + d.textlength(avant, font=police)
    g = d.textbbox((gx0, oy), "G", font=police, stroke_width=epaisseur)
    # Contours : courbes de niveau a mi-hauteur du masque, sur une grille reduite.
    red = 2
    a = np.asarray(m.resize((taille[0] // red, taille[1] // red), Image.LANCZOS)).astype(float)
    fig = plt.figure()
    cs = plt.contour(a, levels=[128])
    contours = []
    for chemin in cs.allsegs[0]:
        if len(chemin) > 12:
            contours.append([(float(x) * red, float(y) * red) for x, y in chemin[::2]])
    plt.close(fig)
    return m, contours, g


def glyphes(texte, hauteur_px, x_centre, y_base):
    f = TTFont(POLICE)
    gs = f.getGlyphSet()
    cmap = f.getBestCmap()
    upm = f["head"].unitsPerEm
    cap = f["OS/2"].sCapHeight or upm * 0.7
    k = hauteur_px / cap
    noms = [cmap[ord(c)] for c in texte]
    largeur = sum(gs[n].width for n in noms) * k * 0.97
    x = x_centre - largeur / 2
    lettres = []
    for c, n in zip(texte, noms):
        pen = Plat(gs)
        gs[n].draw(pen)
        cont = [[(x + px * k, y_base - py * k) for px, py in ct] for ct in pen.contours]
        lettres.append((c, cont))
        x += gs[n].width * k * 0.97
    return lettres


# ------------------------------------------------------------------ trait de crayon
def densifier(pts, pas=6.0, ferme=True):
    out = []
    seq = pts + [pts[0]] if ferme else pts
    for (x1, y1), (x2, y2) in zip(seq, seq[1:]):
        n = max(1, int(math.hypot(x2 - x1, y2 - y1) / pas))
        out += [(x1 + (x2 - x1) * i / n, y1 + (y2 - y1) * i / n) for i in range(n)]
    if not ferme:
        out.append(seq[-1])
    return out


def trembler(pts, ampl, ferme=True, depasse=0.0):
    """Deforme doucement un trace (deux sinus au hasard), et le fait deborder
    au debut et a la fin comme un trait fait a main levee."""
    pts = densifier(pts, ferme=ferme)
    if ferme and depasse:
        n = int(len(pts) * depasse)
        pts = pts[-n:] + pts + pts[:n]
    ph = [random.uniform(0, 6.3) for _ in range(4)]
    fr = [random.uniform(0.004, 0.012), random.uniform(0.02, 0.05)]
    out, s = [], 0.0
    for i, (x, y) in enumerate(pts):
        if i:
            s += math.hypot(x - pts[i - 1][0], y - pts[i - 1][1])
        dx = ampl * (0.7 * math.sin(s * fr[0] + ph[0]) + 0.3 * math.sin(s * fr[1] + ph[1]))
        dy = ampl * (0.7 * math.sin(s * fr[0] + ph[2]) + 0.3 * math.sin(s * fr[1] + ph[3]))
        out.append((x + dx, y + dy))
    return out


def trait(d, pts, largeur, couleur, ampl=4.0, passes=3, ferme=True, depasse=0.04):
    for p in range(passes):
        t = trembler(pts, ampl * (1 + 0.4 * p), ferme, depasse)
        lw = max(1, int(largeur * (1.0 if p == 0 else 0.55)))
        d.line(t, fill=couleur, width=lw, joint="curve")


def hachures(taille, angle, ecart, largeur, couleur, ampl=1.5):
    calque = Image.new("RGBA", taille, (0, 0, 0, 0))
    d = ImageDraw.Draw(calque)
    w, h = taille
    ca, sa = math.cos(angle), math.sin(angle)
    diag = math.hypot(w, h)
    k = -diag
    while k < diag:
        a = (w / 2 + ca * -diag - sa * k, h / 2 + sa * -diag + ca * k)
        b = (w / 2 + ca * diag - sa * k, h / 2 + sa * diag + ca * k)
        d.line(trembler([a, b], ampl, ferme=False), fill=couleur, width=largeur)
        k += ecart * random.uniform(0.8, 1.2)
    return calque


def aire(ct):
    return sum(x1 * y2 - x2 * y1 for (x1, y1), (x2, y2) in zip(ct, ct[1:] + ct[:1])) / 2


def masque_de(contours, taille):
    """Remplissage par orientation (pas pair-impair : les traits de Segoe
    Print se chevauchent, le recouvrement se creusait). Les contours dans le
    sens du plus grand remplissent, les autres sont des trous."""
    sens = 1 if aire(max(contours, key=lambda c: abs(aire(c)))) > 0 else -1
    plein, trous = Image.new("L", taille, 0), Image.new("L", taille, 0)
    for ct in contours:
        ImageDraw.Draw(plein if aire(ct) * sens > 0 else trous).polygon(ct, fill=255)
    return ImageChops.subtract(plein, trous)


# ------------------------------------------------------------------ de
def de(centre, taille, rot):
    """Un de en 3D (projection orthographique) : faces visibles, contours
    tremblants, faces a l'ombre hachurees, points en petites ellipses."""
    ax, ay, az = rot
    def R(p):
        x, y, z = p
        y, z = y * math.cos(ax) - z * math.sin(ax), y * math.sin(ax) + z * math.cos(ax)
        x, z = x * math.cos(ay) + z * math.sin(ay), -x * math.sin(ay) + z * math.cos(ay)
        x, y = x * math.cos(az) - y * math.sin(az), x * math.sin(az) + y * math.cos(az)
        return (x, y, z)
    def P(p):
        x, y, z = R(p)
        return (centre[0] + x * taille, centre[1] - y * taille), z
    # face : (normale, axes u v, valeur)
    faces = [((0, 0, 1), (1, 0, 0), (0, 1, 0), 1), ((0, 0, -1), (1, 0, 0), (0, 1, 0), 6),
             ((1, 0, 0), (0, 1, 0), (0, 0, 1), 3), ((-1, 0, 0), (0, 1, 0), (0, 0, 1), 4),
             ((0, 1, 0), (1, 0, 0), (0, 0, 1), 2), ((0, -1, 0), (1, 0, 0), (0, 0, 1), 5)]
    pips = {1: [(0, 0)], 2: [(-.5, -.5), (.5, .5)], 3: [(-.5, -.5), (0, 0), (.5, .5)],
            4: [(-.5, -.5), (.5, -.5), (-.5, .5), (.5, .5)],
            5: [(-.5, -.5), (.5, -.5), (0, 0), (-.5, .5), (.5, .5)],
            6: [(-.5, -.5), (.5, -.5), (-.5, 0), (.5, 0), (-.5, .5), (.5, .5)]}
    visibles = []
    for n, u, v, val in faces:
        nz = R(n)[2]
        if nz <= 0.02:
            continue
        # Coins arrondis : on parcourt le carre avec un petit rayon.
        coins = []
        for cu, cv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            for i in range(5):
                t = math.atan2(cv, cu) - math.pi / 4 + i * math.pi / 8
                pu, pv = cu * 0.82 + 0.18 * math.cos(t), cv * 0.82 + 0.18 * math.sin(t)
                coins.append(P(tuple(0.5 * (n[k] + pu * u[k] + pv * v[k]) for k in range(3)))[0])
        lum = 0.35 + 0.65 * max(0.0, 0.3 * R(n)[0] + 0.8 * R(n)[1] + 0.5 * nz)
        pts_pips = []
        for pu, pv in pips[val]:
            cercle = [P(tuple(0.5 * (n[k] + (pu + 0.16 * math.cos(a)) * u[k] + (pv + 0.16 * math.sin(a)) * v[k])
                              for k in range(3)))[0] for a in np.linspace(0, 2 * math.pi, 18, endpoint=False)]
            pts_pips.append(cercle)
        visibles.append((coins, lum, pts_pips))
    return visibles


def dessiner_de(calque, visibles, taille):
    d = ImageDraw.Draw(calque)
    for coins, lum, pips in visibles:
        d.polygon(coins, fill=CREME)
        if lum < 0.75:
            m = Image.new("L", calque.size, 0)
            ImageDraw.Draw(m).polygon(coins, fill=255)
            h = hachures(calque.size, random.uniform(0.6, 1.0), taille * 0.07, max(2, int(taille / 55)), OCRE)
            calque.paste(h, (0, 0), ImageChops.multiply(m, h.getchannel("A")))
        for c in pips:
            d.polygon(c, fill=ENCRE)
    for coins, lum, pips in visibles:
        trait(d, coins, taille * 0.06, ENCRE, ampl=taille * 0.012, passes=2, depasse=0.05)
        for c in pips:
            trait(d, c, taille * 0.02, ENCRE, ampl=taille * 0.004, passes=1, depasse=0.0)


# ------------------------------------------------------------------ boule de cristal
def etoile(d, x, y, s, coul):
    pts = [(x + (s if k % 2 == 0 else s * 0.28) * math.cos(k * math.pi / 4 - math.pi / 2),
            y + (s if k % 2 == 0 else s * 0.28) * math.sin(k * math.pi / 4 - math.pi / 2)) for k in range(8)]
    d.polygon(pts, fill=coul)


def boule(base, calque, c, r, pieds_a=False):
    """Boule de voyante en croquis : halo violet (le tapis de la place),
    verre creme teinte, brume en spirale et etoiles dedans, ombre hachuree,
    reflet, sur un socle de bois."""
    cx, cy = c
    taille = calque.size
    halo = Image.new("L", taille, 0)
    ImageDraw.Draw(halo).ellipse((cx - r * 1.6, cy - r * 1.6, cx + r * 1.6, cy + r * 1.6), fill=255)
    base.paste(Image.new("RGBA", taille, (120, 90, 210, 255)), (0, 0),
               halo.filter(ImageFilter.GaussianBlur(r * 0.55)).point(lambda v: int(v * 0.55)))
    d = ImageDraw.Draw(calque)
    if pieds_a:
        # Trepied en A : deux pieds ecartes jusqu'a la ligne de base et une
        # barre, pour que la boule se lise comme la lettre A.
        bois = (150, 104, 52, 255)
        pieds = []
        for sgn in (-1, 1):
            haut_i, haut_e = cx + sgn * 0.30 * r, cx + sgn * 0.62 * r
            bas_i, bas_e = cx + sgn * 0.78 * r, cx + sgn * 1.12 * r
            pieds.append([(haut_i, cy + 0.72 * r), (haut_e, cy + 0.62 * r), (bas_e, cy + 1.62 * r), (bas_i, cy + 1.62 * r)])
        barre = [(cx - 0.72 * r, cy + 1.10 * r), (cx + 0.72 * r, cy + 1.10 * r),
                 (cx + 0.78 * r, cy + 1.30 * r), (cx - 0.78 * r, cy + 1.30 * r)]
        for poly in pieds + [barre]:
            d.polygon(poly, fill=bois)
            m = Image.new("L", taille, 0)
            ImageDraw.Draw(m).polygon(poly, fill=255)
            h = hachures(taille, 0.9, r * 0.13, 3, (70, 44, 20, 255))
            calque.paste(h, (0, 0), ImageChops.multiply(m, h.getchannel("A")))
            trait(d, poly, 7, ENCRE, ampl=2.5, passes=2)
        socle = None
    # Socle.
    socle = None if pieds_a else [(cx - 0.62 * r, cy + 0.80 * r), (cx + 0.62 * r, cy + 0.80 * r),
             (cx + 0.86 * r, cy + 1.24 * r), (cx - 0.86 * r, cy + 1.24 * r)]
    if socle:
        d.polygon(socle, fill=(150, 104, 52, 255))
        m = Image.new("L", taille, 0)
        ImageDraw.Draw(m).polygon(socle, fill=255)
        h = hachures(taille, 0.9, r * 0.13, 3, (70, 44, 20, 255))
        calque.paste(h, (0, 0), ImageChops.multiply(m, h.getchannel("A")))
        trait(d, socle, 7, ENCRE, ampl=2.5, passes=2)
        trait(d, [(cx - 0.72 * r, cy + 1.00 * r), (cx + 0.72 * r, cy + 1.00 * r)], 4, ENCRE, ampl=1.5,
              passes=1, ferme=False)
    # Verre.
    cercle = [(cx + r * math.cos(a), cy + r * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 90, endpoint=False)]
    d.polygon(cercle, fill=(232, 224, 244, 255))
    verre = Image.new("L", taille, 0)
    ImageDraw.Draw(verre).polygon(cercle, fill=255)
    # Brume : une spirale violette dans la boule.
    brume = Image.new("RGBA", taille, (0, 0, 0, 0))
    db = ImageDraw.Draw(brume)
    spir = [(cx + r * 0.62 * (1 - t * 0.8) * math.cos(t * 9 + 0.6), cy + r * 0.5 * (1 - t * 0.8) * math.sin(t * 9 + 0.6) + r * 0.12)
            for t in np.linspace(0, 1, 120)]
    db.line(trembler(spir, 2.0, ferme=False), fill=(128, 92, 200, 255), width=int(r * 0.12), joint="curve")
    brume = brume.filter(ImageFilter.GaussianBlur(r * 0.06))
    calque.paste(brume, (0, 0), ImageChops.multiply(verre, brume.getchannel("A")))
    for x, y, s_ in ((0.30, -0.35, 0.13), (-0.38, 0.18, 0.09), (0.12, 0.38, 0.07)):
        etoile(d, cx + x * r, cy + y * r, s_ * r, ENCRE)
    # Ombre en croissant (bas droite), hachuree.
    lune = ImageChops.subtract(verre, ImageChops.offset(verre, int(-r * 0.28), int(-r * 0.28)))
    h = hachures(taille, -0.8, r * 0.09, 3, (60, 40, 110, 255))
    calque.paste(h, (0, 0), ImageChops.multiply(lune, h.getchannel("A")))
    # Reflet.
    reflet = [(cx + r * 0.68 * math.cos(a), cy + r * 0.68 * math.sin(a)) for a in np.linspace(3.5, 4.5, 20)]
    d.line(trembler(reflet, 1.5, ferme=False), fill=(255, 255, 255, 255), width=int(r * 0.11), joint="curve")
    trait(d, cercle, 9, ENCRE, ampl=3.0, passes=3)


# ------------------------------------------------------------------ assemblage
def logo(texte=TEXTE, police=None, taille_police=370, epaisseur=8, sortie="", objet="de", trou=None, pieds_a=False):
    base = fond()
    taille = base.size
    masque, contours, (g0, g1, g2, g3) = texte_epais(texte, taille_police, epaisseur, W * 0.49, H * 0.43, taille, police, trou)

    # Ombre portee douce, pour la lisibilite sur la photo.
    ombre = masque.filter(ImageFilter.MaxFilter(31)).filter(ImageFilter.GaussianBlur(26))
    base.paste(Image.new("RGBA", taille, (8, 6, 16, 255)), (0, 0), ombre.point(lambda v: int(v * 0.85)))

    # Remplissage creme + hachures ocre en diagonale (moitie basse plus dense).
    encre = Image.new("RGBA", taille, (0, 0, 0, 0))
    encre.paste(Image.new("RGBA", taille, CREME), (0, 0), masque)
    h = hachures(taille, -0.85, 17, 4, OCRE + (0,) if False else (176, 132, 70, 170))
    yy = np.linspace(0, 1, taille[1])[:, None] * np.ones((1, taille[0]))
    _, t0, _, t1 = masque.getbbox()
    y_h0, y_h1 = (t0 + 0.58 * (t1 - t0)) / taille[1], (t0 + 0.80 * (t1 - t0)) / taille[1]
    bas = Image.fromarray((np.clip((yy - y_h0) / (y_h1 - y_h0), 0, 1) * 255).astype(np.uint8))
    encre.paste(h, (0, 0), ImageChops.multiply(ImageChops.multiply(masque, h.getchannel("A")), bas))
    d = ImageDraw.Draw(encre)
    for ct in contours:
        trait(d, ct, 9, ENCRE, ampl=3.5, passes=3)
    base.alpha_composite(encre)

    # Le G : une boucle de vent l'entoure, le de roule au bout.
    cx, cy = (g0 + g2) / 2, (g1 + g3) / 2
    rx, ry = (g2 - g0) * 0.78, (g3 - g1) * 0.66
    vent = []
    for i in range(160):
        t = i / 159
        a = math.radians(110) + t * math.radians(290)        # haut gauche, dessous, puis s'envole en haut a droite
        r = 1.0 + 0.45 * t ** 2.2
        vent.append((cx + rx * r * math.cos(a), cy - ry * r * math.sin(a) - 10))
    calque = Image.new("RGBA", taille, (0, 0, 0, 0))
    dv = ImageDraw.Draw(calque)
    for k, (dec, lw) in enumerate(((0, 7), (16, 4), (30, 3))):
        pts = [(x, y + dec) for x, y in vent[k * 18: 160 - k * 10]]
        t = trembler(pts, 3.0, ferme=False)
        dv.line(t, fill=ENCRE, width=lw + 7, joint="curve")
        dv.line(t, fill=(246, 234, 206, 255), width=lw, joint="curve")
    fin = vent[-1]
    tdé = 74
    centre_de = (fin[0] + tdé * 1.0, fin[1] - tdé * 0.8)
    ombre_de = Image.new("L", taille, 0)
    ImageDraw.Draw(ombre_de).ellipse((centre_de[0] - tdé * 1.1, centre_de[1] - tdé * 1.1,
                                      centre_de[0] + tdé * 1.1, centre_de[1] + tdé * 1.1), fill=255)
    base.paste(Image.new("RGBA", taille, (8, 6, 16, 255)), (0, 0),
               ombre_de.filter(ImageFilter.GaussianBlur(22)).point(lambda v: int(v * 0.7)))
    # Deux traits de mouvement entre le bout de la boucle et le de.
    for k, dec in enumerate((-18, 16)):
        a0 = (fin[0] + 8, fin[1] + dec)
        a1 = (centre_de[0] - tdé * 0.95, centre_de[1] + dec * 0.6 + tdé * 0.35)
        dv.line(trembler([a0, a1], 2.0, ferme=False), fill=(246, 234, 206, 220), width=5 - k)
    base.alpha_composite(calque)
    cd = Image.new("RGBA", taille, (0, 0, 0, 0))
    if objet == "boule_lettre":
        # La boule a la place de la lettre videe : socle sur la ligne de base.
        a0, a1, a2, a3 = TROU_BOITE
        if pieds_a:
            r = (a3 - a1) * 0.37
            boule(base, cd, ((a0 + a2) / 2, a3 - 1.62 * r), r, pieds_a=True)
        else:
            r = (a3 - a1) * 0.47
            boule(base, cd, ((a0 + a2) / 2, a3 - 1.22 * r), r)
        dessiner_de(cd, de(centre_de, tdé * 2, (0.55, 0.7, 0.35)), tdé * 2)
    elif objet == "les_deux":
        # Le de au depart de la boucle (haut gauche du G), la boule au bout.
        boule(base, cd, (centre_de[0] + 10, centre_de[1] - 10), tdé * 1.05)
        debut = vent[0]
        c_de = (debut[0] - tdé * 0.55, debut[1] - tdé * 1.05)
        o = Image.new("L", taille, 0)
        ImageDraw.Draw(o).ellipse((c_de[0] - tdé, c_de[1] - tdé, c_de[0] + tdé, c_de[1] + tdé), fill=255)
        base.paste(Image.new("RGBA", taille, (8, 6, 16, 255)), (0, 0),
                   o.filter(ImageFilter.GaussianBlur(20)).point(lambda v: int(v * 0.6)))
        dessiner_de(cd, de(c_de, tdé * 1.7, (0.5, -0.65, -0.3)), tdé * 1.7)
    elif objet == "boule":
        boule(base, cd, (centre_de[0] + 10, centre_de[1] - 10), tdé * 1.05)
    else:
        dessiner_de(cd, de(centre_de, tdé * 2, (0.55, 0.7, 0.35)), tdé * 2)
    base.alpha_composite(cd)

    out = base.convert("RGB")
    apercu = out.resize((1200, 600), Image.LANCZOS)
    apercu.save(ICI / f"logo{sortie}_1200.png")
    out.resize((300, 150), Image.LANCZOS).save(ICI / f"Server{sortie}.jpg", quality=95)
    out.resize((300, 150), Image.LANCZOS).resize((600, 300), Image.NEAREST).save(ICI / f"Server{sortie}_x2.png")
    print("ok")


if __name__ == "__main__":
    logo()
