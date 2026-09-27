"""Motifs de T-shirt : des textures pour le T-shirt Design de ChatGPT.

    blender -b --python scripts/blender/create_tshirt_motifs.py

Lit art/cosmetics/tshirts/creative_tshirt_rarities.blend (sans le modifier)
et reprend SK_COS_TShirt_Rare_Compass : sa geometrie, son skinning et ses UV
depliees (Design_UV). Chaque motif est dessine en 3D sur le T-shirt (coordonnees
du monde : x de cote, y vers l'arriere, z vers le haut, le personnage regarde vers
-y), puis cuit (bake) dans une texture 2048 : les rayures restent continues
d'un morceau d'UV a l'autre, un logo tombe au milieu de la poitrine.

Sorties dans art/cosmetics/tshirts_motifs/ (hors depot) : T_COS_TShirt_M_<nom>.png,
un apercu par motif et une planche. Meme piece 3D pour tous : un seul FBX
(celui de ChatGPT), une texture par motif.
"""

import json
import math
from pathlib import Path

import bpy

PROJECT = Path(__file__).resolve().parents[2]
SOURCE = PROJECT / "art/cosmetics/tshirts/creative_tshirt_rarities.blend"
OUT = PROJECT / "art/cosmetics/tshirts_motifs"
OUT.mkdir(parents=True, exist_ok=True)
MODELE = "SK_COS_TShirt_Rare_Compass"
TAILLE = 2048


def hexa(h):
    h = h.lstrip("#")
    return tuple((int(h[i:i + 2], 16) / 255) ** 2.2 for i in (0, 2, 4)) + (1.0,)


# ---------------------------------------------------------------- petit langage de noeuds

class N:
    """Construit un arbre de noeuds de shader avec des operations lisibles."""

    def __init__(self, mat):
        self.t = mat.node_tree
        self.t.nodes.clear()
        self.x = 0

    def node(self, kind, **props):
        n = self.t.nodes.new(kind)
        n.location = (self.x, 0)
        self.x += 180
        for k, v in props.items():
            setattr(n, k, v)
        return n

    def link(self, a, b):
        self.t.links.new(a, b)

    def math(self, op, a, b=None, clamp=False):
        n = self.node("ShaderNodeMath", operation=op, use_clamp=clamp)
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                n.inputs[i].default_value = v
            else:
                self.link(v, n.inputs[i])
        return n.outputs[0]

    def add(self, a, b): return self.math("ADD", a, b)
    def sub(self, a, b): return self.math("SUBTRACT", a, b)
    def mul(self, a, b): return self.math("MULTIPLY", a, b)
    def div(self, a, b): return self.math("DIVIDE", a, b)
    def frac(self, a): return self.math("FRACT", a)
    def absv(self, a): return self.math("ABSOLUTE", a)
    def lt(self, a, b): return self.math("LESS_THAN", a, b)
    def gt(self, a, b): return self.math("GREATER_THAN", a, b)
    def sin(self, a): return self.math("SINE", a)
    def atan2(self, a, b): return self.math("ARCTAN2", a, b)
    def minv(self, a, b): return self.math("MINIMUM", a, b)
    def maxv(self, a, b): return self.math("MAXIMUM", a, b)
    def lisse(self, bord, largeur, v):
        """0 sous bord, 1 au-dessus, fondu sur largeur."""
        return self.math("MULTIPLY_ADD", self.sub(v, bord), 1 / max(largeur, 1e-4), 0.5, clamp=True) \
            if False else self._smooth(bord, largeur, v)

    def _smooth(self, bord, largeur, v):
        n = self.node("ShaderNodeMapRange", data_type="FLOAT", interpolation_type="SMOOTHSTEP")
        self.link(v, n.inputs["Value"])
        n.inputs["From Min"].default_value = bord - largeur / 2
        n.inputs["From Max"].default_value = bord + largeur / 2
        return n.outputs["Result"]

    def coords(self):
        # Position dans le monde, en metres : les coordonnees "Object" du
        # modele importe sont en centimetres et tournees (tout tombait dans
        # le masque du col).
        geo = self.node("ShaderNodeNewGeometry")
        sep = self.node("ShaderNodeSeparateXYZ")
        self.link(geo.outputs["Position"], sep.inputs[0])
        return geo.outputs["Position"], sep.outputs[0], sep.outputs[1], sep.outputs[2]

    def bruit(self, vecteur, echelle, detail=2.0, rugo=0.5):
        n = self.node("ShaderNodeTexNoise", noise_dimensions="3D")
        self.link(vecteur, n.inputs["Vector"])
        n.inputs["Scale"].default_value = echelle
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rugo
        return n.outputs["Fac"]

    def voronoi(self, vecteur, echelle, sortie="Distance", feature="F1"):
        n = self.node("ShaderNodeTexVoronoi", voronoi_dimensions="3D", feature=feature)
        self.link(vecteur, n.inputs["Vector"])
        n.inputs["Scale"].default_value = echelle
        return n.outputs[sortie]

    def rampe(self, v, arrets, constant=False):
        n = self.node("ShaderNodeValToRGB")
        r = n.color_ramp
        r.interpolation = "CONSTANT" if constant else "LINEAR"
        while len(r.elements) > 1:
            r.elements.remove(r.elements[-1])
        r.elements[0].position, r.elements[0].color = arrets[0][0], hexa(arrets[0][1])
        for pos, col in arrets[1:]:
            e = r.elements.new(pos)
            e.color = hexa(col)
        self.link(v, n.inputs["Fac"])
        return n.outputs["Color"]

    def couleur(self, h):
        n = self.node("ShaderNodeRGB")
        n.outputs[0].default_value = hexa(h)
        return n.outputs[0]

    def melange(self, facteur, a, b):
        n = self.node("ShaderNodeMix", data_type="RGBA", blend_type="MIX")
        for sock, v in ((n.inputs[0], facteur), (n.inputs[6], a), (n.inputs[7], b)):
            if isinstance(v, (int, float)):
                sock.default_value = v
            elif isinstance(v, str):
                sock.default_value = hexa(v)
            else:
                self.link(v, sock)
        return n.outputs[2]

    def image(self, chemin, vecteur):
        n = self.node("ShaderNodeTexImage", extension="CLIP", interpolation="Cubic")
        n.image = bpy.data.images.load(str(chemin), check_existing=True)
        self.link(vecteur, n.inputs["Vector"])
        return n.outputs["Color"], n.outputs["Alpha"]

    def vecteur(self, x, y, z):
        n = self.node("ShaderNodeCombineXYZ")
        for i, v in enumerate((x, y, z)):
            if isinstance(v, (int, float)):
                n.inputs[i].default_value = v
            else:
                self.link(v, n.inputs[i])
        return n.outputs[0]

    def vop(self, op, a, b=None):
        n = self.node("ShaderNodeVectorMath", operation=op)
        self.link(a, n.inputs[0])
        if b is not None:
            self.link(b, n.inputs[1])
        return n.outputs["Value"] if op in ("LENGTH", "DOT_PRODUCT", "DISTANCE") else n.outputs["Vector"]

    def sep(self, v):
        n = self.node("ShaderNodeSeparateXYZ")
        self.link(v, n.inputs[0])
        return n.outputs[0], n.outputs[1], n.outputs[2]

    def cellules(self, vecteur, echelle, feature="F1"):
        """Voronoi : distance (espace mis a l'echelle), couleur aleatoire de la
        cellule, position de son centre (espace d'entree)."""
        n = self.node("ShaderNodeTexVoronoi", voronoi_dimensions="3D", feature=feature)
        self.link(vecteur, n.inputs["Vector"])
        n.inputs["Scale"].default_value = echelle
        return n.outputs["Distance"], n.outputs.get("Color"), n.outputs.get("Position")

    def sortie(self, couleur):
        em = self.node("ShaderNodeEmission")
        self.link(couleur, em.inputs["Color"])
        out = self.node("ShaderNodeOutputMaterial")
        self.link(em.outputs[0], out.inputs["Surface"])
        return em


# ---------------------------------------------------------------- reperes du T-shirt

POITRINE_Z = 1.20       # milieu de la poitrine
MANCHE_X = 0.175        # au-dela, les manches
BAS_Z, HAUT_Z = 0.82, 1.44


def devant(n, y):
    """1 sur le devant (y < 0), 0 derriere, fondu sur les flancs."""
    return n._smooth(0.02, 0.05, n.mul(y, -1))


def manches(n, x):
    return n._smooth(MANCHE_X, 0.02, n.absv(x))


def col_et_ourlets(n, x, z, base, bord):
    """Bande de col et ourlets (bas, manches) dans la couleur `bord`."""
    ourlet_bas = n.lt(z, BAS_Z + 0.035)
    ourlet_manche = n.gt(n.absv(x), 0.285)
    col = n.gt(z, HAUT_Z - 0.03)
    m = n.maxv(n.maxv(ourlet_bas, ourlet_manche), col)
    return n.melange(m, base, bord)


# ---------------------------------------------------------------- les motifs

def mariniere(n):
    v, x, y, z = n.coords()
    raie = n.gt(n.frac(n.mul(z, 13.0)), 0.52)
    base = n.melange(raie, "#f4efe4", "#1f3a68")
    return col_et_ourlets(n, x, z, base, "#1f3a68")


def damier(n):
    v, x, y, z = n.coords()
    c = n.node("ShaderNodeTexChecker")
    n.link(v, c.inputs["Vector"])
    c.inputs["Scale"].default_value = 11.0
    c.inputs["Color1"].default_value = hexa("#f1ede4")
    c.inputs["Color2"].default_value = hexa("#1c2123")
    base = n.melange(manches(n, x), c.outputs["Color"], "#1c2123")
    return col_et_ourlets(n, x, z, base, "#c9372c")


def raglan(n):
    v, x, y, z = n.coords()
    # Manches et epaules en couleur, coupe en biais comme un raglan.
    epaule = n.sub(n.absv(x), n.mul(n.sub(HAUT_Z, z), 1.6))
    m = n._smooth(0.06, 0.012, epaule)
    base = n.melange(m, "#f3f0ea", "#2d5aa0")
    return col_et_ourlets(n, x, z, base, "#2d5aa0")


def delave(n):
    v, x, y, z = n.coords()
    marbre = n.mul(n.sub(n.bruit(v, 6.0, 5.0, 0.65), 0.5), 0.35)
    g = n._smooth(1.05, 0.7, n.add(n.mul(z, -1), n.add(2.3, marbre)))
    base = n.rampe(g, [(0.0, "#27496d"), (0.55, "#4f7ea8"), (1.0, "#9cc3dd")])
    return col_et_ourlets(n, x, z, base, "#1f3b57")


def camouflage(n):
    v, x, y, z = n.coords()
    w = n.vecteur(n.mul(x, 1.0), n.mul(y, 1.0), n.mul(z, 1.4))
    t = n.bruit(w, 5.5, 3.0, 0.55)
    base = n.rampe(t, [(0.0, "#2f3b24"), (0.42, "#556b2f"), (0.52, "#8a7a4f"), (0.61, "#3d2f1f"), (0.7, "#6b7a45")], True)
    return col_et_ourlets(n, x, z, base, "#2f3b24")


def peinture(n):
    v, x, y, z = n.coords()
    base = n.couleur("#f7f3ea")
    couleurs = ("#e63946", "#ffb703", "#219ebc", "#8ac926", "#7b2cbf")
    for i, c in enumerate(couleurs):
        dec = n.vecteur(n.add(x, i * 0.37), n.add(y, i * 0.21), n.add(z, i * 0.53))
        tache = n.bruit(dec, 5.5 + i * 1.3, 5.0, 0.72)
        m = n._smooth(0.6 + i * 0.01, 0.012, tache)
        base = n.melange(m, base, c)
    return col_et_ourlets(n, x, z, base, "#1c2123")


def tie_dye(n):
    v, x, y, z = n.coords()
    dz = n.sub(z, POITRINE_Z - 0.05)
    r = n.math("POWER", n.add(n.mul(x, x), n.mul(dz, dz)), 0.5)
    a = n.div(n.atan2(dz, x), 2 * math.pi)
    tourbillon = n.add(n.add(n.mul(a, 3.0), n.mul(r, 7.0)), n.mul(n.bruit(v, 6.0, 3.0), 0.35))
    t = n.frac(tourbillon)
    base = n.rampe(t, [(0.0, "#ff4f8b"), (0.2, "#ffb347"), (0.4, "#fff275"), (0.6, "#6ee7b7"),
                        (0.8, "#5b8cff"), (1.0, "#ff4f8b")])
    return col_et_ourlets(n, x, z, base, "#f7f3ea")


def flammes(n):
    v, x, y, z = n.coords()
    langues = n.add(n.mul(n.sin(n.mul(x, 30.0)), 0.055), n.mul(n.sub(n.bruit(v, 4.0, 2.0), 0.5), 0.24))
    hauteur = n.add(1.13, langues)
    feu = n.sub(hauteur, z)               # positif dans les flammes
    c = n.rampe(n.add(n.mul(feu, 3.2), 0.5), [(0.0, "#141414"), (0.5, "#141414"), (0.53, "#c1121f"),
                                               (0.62, "#f77f00"), (0.78, "#fcbf49"), (1.0, "#fff3b0")])
    return col_et_ourlets(n, x, z, c, "#141414")


def galaxie(n):
    v, x, y, z = n.coords()
    nebuleuse = n.bruit(v, 3.2, 6.0, 0.62)
    base = n.rampe(nebuleuse, [(0.0, "#0b0d2b"), (0.45, "#1b1f5e"), (0.58, "#5a2a82"), (0.68, "#c0427a"),
                               (0.76, "#3fb6c9"), (1.0, "#0b0d2b")])
    etoiles = n.lt(n.voronoi(v, 70.0), 0.045)
    grosses = n.lt(n.voronoi(n.vecteur(n.add(x, 3.1), y, z), 18.0), 0.035)
    base = n.melange(n.maxv(etoiles, grosses), base, "#fffbe6")
    return col_et_ourlets(n, x, z, base, "#0b0d2b")


def soleil_retro(n):
    v, x, y, z = n.coords()
    ciel = n.rampe(n._smooth(1.12, 0.62, z), [(0.0, "#ff8c42"), (0.45, "#d8347f"), (1.0, "#2b1055")])
    dz = n.sub(z, POITRINE_Z)
    disque = n.lt(n.math("POWER", n.add(n.mul(x, x), n.mul(dz, dz)), 0.5), 0.115)
    # Le bas du soleil tranche en bandes, facon annees 80.
    bandes = n.maxv(n.gt(z, POITRINE_Z - 0.01), n.gt(n.frac(n.mul(z, 55.0)), n.add(0.25, n.mul(n.sub(POITRINE_Z, z), 5.0))))
    soleil = n.mul(n.mul(disque, bandes), devant(n, y))
    grad_soleil = n.rampe(n._smooth(POITRINE_Z, 0.19, z), [(0.0, "#ff3d7f"), (1.0, "#ffe66d")])
    base = n.melange(soleil, ciel, grad_soleil)
    return col_et_ourlets(n, x, z, base, "#2b1055")


def pois(n):
    v, x, y, z = n.coords()
    k = 12.0
    du = n.sub(n.frac(n.mul(n.add(x, 0.5), k)), 0.5)
    dv = n.sub(n.frac(n.mul(z, k)), 0.5)
    rond = n.lt(n.add(n.mul(du, du), n.mul(dv, dv)), 0.065)
    base = n.melange(rond, "#ee7fa6", "#fff7ef")
    return col_et_ourlets(n, x, z, base, "#c9587f")


def bucheron(n):
    v, x, y, z = n.coords()
    h = n.lt(n.frac(n.mul(z, 8.0)), 0.5)
    w = n.lt(n.frac(n.mul(n.add(x, 0.5), 8.0)), 0.5)
    deux = n.mul(h, w)
    un = n.sub(n.maxv(h, w), deux)
    fil = n.lt(n.absv(n.sub(n.frac(n.mul(z, 16.0)), 0.5)), 0.03)
    base = n.melange(un, "#a3161d", "#5a0d10")
    base = n.melange(deux, base, "#1a1113")
    base = n.melange(n.mul(fil, 0.35), base, "#e9c46a")
    return col_et_ourlets(n, x, z, base, "#1a1113")


def vagues(n):
    v, x, y, z = n.coords()
    ondule = n.add(n.mul(n.sin(n.add(n.mul(x, 24.0), n.mul(y, 18.0))), 0.35), n.mul(n.bruit(v, 6.0, 2.0), 0.6))
    w = n.frac(n.add(n.mul(z, 16.0), ondule))
    base = n.rampe(w, [(0.0, "#0b2545"), (0.45, "#134074"), (0.75, "#3e7cb1"), (0.9, "#a9d6e5"), (0.94, "#fdfcf5"), (1.0, "#0b2545")])
    return col_et_ourlets(n, x, z, base, "#0b2545")


def hawai(n):
    v, x, y, z = n.coords()
    base = n.couleur("#0e7c86")
    # Feuilles : une ellipse allongee par cellule, orientee au hasard.
    d, c, pos = n.cellules(n.vecteur(n.add(x, 1.7), n.add(y, 0.9), z), 6.5)
    dx, dy, dz = n.sep(n.vop("SUBTRACT", n.vecteur(n.add(x, 1.7), n.add(y, 0.9), z), pos))
    cr, cg, cb = n.sep(c)
    phi = n.mul(cg, math.pi)
    cp, sp = n.math("COSINE", phi), n.math("SINE", phi)
    lat = n.add(dx, dy)
    u = n.add(n.mul(lat, cp), n.mul(dz, sp))
    w = n.sub(n.mul(dz, cp), n.mul(lat, sp))
    ell = n.add(n.mul(n.div(u, 0.075), n.div(u, 0.075)), n.mul(n.div(w, 0.028), n.div(w, 0.028)))
    feuille = n.lt(ell, 1.0)
    nervure = n.mul(feuille, n.lt(n.absv(w), 0.0025))
    vert = n.rampe(cr, [(0.0, "#1b7a4a"), (0.5, "#2a9d5c"), (1.0, "#57cc99")], True)
    base = n.melange(feuille, base, vert)
    base = n.melange(nervure, base, "#bff5c9")
    # Hibiscus : cinq petales autour du centre de chaque cellule.
    d2, c2, pos2 = n.cellules(v, 8.0)
    ex, ey, ez = n.sep(n.vop("SUBTRACT", v, pos2))
    r = n.vop("LENGTH", n.vop("SUBTRACT", v, pos2))
    q1, q2, q3 = n.sep(c2)
    th = n.add(n.atan2(ez, n.add(ex, ey)), n.mul(q2, 6.283))
    petale = n.mul(0.05, n.add(0.45, n.mul(0.55, n.absv(n.math("COSINE", n.mul(th, 2.5))))))
    fleur = n.mul(n.lt(r, petale), n.gt(q3, 0.35))
    coeur = n.mul(n.lt(r, 0.009), n.gt(q3, 0.35))
    rose = n.rampe(q1, [(0.0, "#e63946"), (0.35, "#ff70a6"), (0.7, "#ff9f1c"), (0.9, "#fff1e6")], True)
    ombre = n.melange(n._smooth(0.02, 0.03, r), "#7d0f1d", rose)
    base = n.melange(fleur, base, ombre)
    base = n.melange(coeur, base, "#ffd23f")
    return col_et_ourlets(n, x, z, base, "#0a5a61")


def leopard(n):
    v, x, y, z = n.coords()
    tord = n.mul(n.sub(n.bruit(v, 14.0, 3.0), 0.5), 0.05)
    dist = n.vop("ADD", v, n.vecteur(tord, n.mul(tord, 0.5), n.mul(tord, -1)))
    d, c, pos = n.cellules(dist, 23.0)
    cr, cg, cb = n.sep(c)
    taille = n.add(0.2, n.mul(cr, 0.14))
    anneau = n.mul(n.gt(d, taille), n.lt(d, n.add(taille, 0.12)))
    coeur = n.lt(d, taille)
    base = n.couleur("#d9a441")
    base = n.melange(coeur, base, "#b5651d")
    base = n.melange(anneau, base, "#2b1a0e")
    return col_et_ourlets(n, x, z, base, "#2b1a0e")


def dark(n):
    v, x, y, z = n.coords()
    fumee = n.bruit(v, 4.0, 6.0, 0.6)
    base = n.rampe(fumee, [(0.0, "#0c0c0f"), (0.5, "#15131b"), (0.7, "#2a2236"), (1.0, "#0c0c0f")])
    # Felures qui rougeoient a peine.
    d, c, pos = n.cellules(n.vop("ADD", v, n.vecteur(n.mul(fumee, 0.05), 0, 0)), 9.0, "DISTANCE_TO_EDGE")
    felure = n.lt(d, 0.018)
    base = n.melange(n.mul(felure, 0.55), base, "#4a0d18")
    # Une toile d'araignee sur le devant, en bas a gauche.
    ax = n.add(x, 0.13)
    az = n.sub(z, 0.9)
    r = n.math("POWER", n.add(n.mul(ax, ax), n.mul(az, az)), 0.5)
    th = n.atan2(az, ax)
    rayons = n.gt(n.absv(n.sub(n.frac(n.mul(th, 16 / (2 * math.pi))), 0.5)), 0.465)
    cercles = n.gt(n.absv(n.sub(n.frac(n.add(n.mul(r, 30.0), n.mul(n.sin(n.mul(th, 16.0)), 0.12))), 0.5)), 0.44)
    toile = n.mul(n.mul(n.maxv(rayons, cercles), n.lt(r, 0.22)), devant(n, y))
    base = n.melange(toile, base, "#9b98a6")
    return col_et_ourlets(n, x, z, base, "#060608")


MOTIFS = [
    # nom, fonction, rarete, nom affiche
    ("Delave", delave, "common", "Délavé"),
    ("Pois", pois, "common", "Pois pastel"),
    ("Mariniere", mariniere, "uncommon", "Marinière"),
    ("Bucheron", bucheron, "uncommon", "Bûcheron"),
    ("Camouflage", camouflage, "rare", "Camouflage"),
    ("Peinture", peinture, "rare", "Éclaboussures"),
    ("Vagues", vagues, "rare", "Grande vague"),
    ("TieDye", tie_dye, "epic", "Tie & Dye"),
    ("Hawai", hawai, "epic", "Hawaï"),
    ("Leopard", leopard, "epic", "Léopard"),
    ("Flammes", flammes, "epic", "Flammes"),
    ("Dark", dark, "legendary", "Nuit noire"),
    ("Galaxie", galaxie, "legendary", "Galaxie"),
    ("SoleilRetro", soleil_retro, "legendary", "Soleil rétro"),
]


# ---------------------------------------------------------------- cuisson et apercus

def main():
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    scene = bpy.context.scene
    modele = bpy.data.objects[MODELE]
    for o in bpy.data.objects:
        if o.name.startswith("SK_COS_TShirt_") or o.name.startswith("DESIGN_"):
            o.hide_render = o is not modele
            o.hide_set(o is not modele)
    modele.hide_render = False
    modele.hide_set(False)

    manifeste = []
    for nom, fonction, rarete, affiche in MOTIFS:
        img = bpy.data.images.new("T_COS_TShirt_M_" + nom, TAILLE, TAILLE, alpha=False)
        mat = bpy.data.materials.new("M_COS_TShirt_M_" + nom)
        mat.use_nodes = True
        n = N(mat)
        n.sortie(fonction(n))
        cible = n.node("ShaderNodeTexImage")
        cible.image = img
        n.t.nodes.active = cible
        modele.data.materials.clear()
        modele.data.materials.append(mat)

        scene.render.engine = "CYCLES"
        scene.cycles.samples = 4
        scene.cycles.device = "CPU"
        scene.render.bake.margin = 12
        bpy.ops.object.select_all(action="DESELECT")
        modele.select_set(True)
        bpy.context.view_layer.objects.active = modele
        bpy.ops.object.bake(type="EMIT", use_clear=True)
        img.filepath_raw = str(OUT / (img.name + ".png"))
        img.file_format = "PNG"
        img.save()

        # Apercu : le T-shirt avec sa texture cuite, sous la lumiere de la scene.
        apercu = bpy.data.materials.new("Apercu_" + nom)
        apercu.use_nodes = True
        t = apercu.node_tree
        bsdf = t.nodes.get("Principled BSDF")
        tex = t.nodes.new("ShaderNodeTexImage")
        tex.image = img
        uv = t.nodes.new("ShaderNodeUVMap")
        uv.uv_map = "Design_UV"
        t.links.new(uv.outputs[0], tex.inputs["Vector"])
        t.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.85
        modele.data.materials.clear()
        modele.data.materials.append(apercu)
        scene.render.engine = "BLENDER_EEVEE"
        scene.render.resolution_x, scene.render.resolution_y = 700, 900
        scene.render.filepath = str(OUT / ("Apercu_" + nom + ".png"))
        bpy.ops.render.render(write_still=True)
        manifeste.append({"nom": affiche, "rarete": rarete,
                          "texture": "T_COS_TShirt_M_" + nom, "piece": "SK_COS_TShirt_Rare_Compass"})
        print("MOTIF_PRET", nom, rarete)

    (OUT / "manifeste.json").write_text(json.dumps(manifeste, indent=2, ensure_ascii=False), encoding="utf-8")


main()
