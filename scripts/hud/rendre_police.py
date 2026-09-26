"""Rend la police bitmap des pseudos (scripts/hud/police.html).

    python scripts/hud/rendre_police.py

Sorties : Packages/fate-games/Client/liars_bar/hud/police.png (la planche) et
Packages/fate-games/Client/liars_bar/police.lua (cases et avances), lue par
Client/liars_bar/nametags.lua. Edge sans interface fait le rendu.
"""

import json
import os
import re
import subprocess
import tempfile

RACINE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
PAGE = "file:///" + os.path.join(RACINE, "scripts", "hud", "police.html").replace("\\", "/")
PNG = os.path.join(RACINE, "Packages", "fate-games", "Client", "liars_bar", "hud", "police.png")
LUA = os.path.join(RACINE, "Packages", "fate-games", "Client", "liars_bar", "police.lua")
PROFIL = os.path.join(tempfile.gettempdir(), "edge-police")
BASE = [EDGE, "--headless=new", "--disable-gpu", "--user-data-dir=" + PROFIL,
        "--allow-file-access-from-files", "--hide-scrollbars", "--virtual-time-budget=3000"]

# Les metriques d'abord (le DOM, apres le script), pour connaitre la taille.
dom = subprocess.run(BASE + ["--dump-dom", PAGE], capture_output=True, text=True, encoding="utf-8").stdout
brut = re.search(r'<pre id="metriques">(.*?)</pre>', dom, re.S).group(1)
brut = brut.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", '"')
m = json.loads(brut)

subprocess.run(BASE + ["--default-background-color=00000000",
                       "--window-size=%d,%d" % (m["largeur"], m["hauteur"]),
                       "--screenshot=" + PNG, PAGE], capture_output=True)


def lua_chaine(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


lignes = [
    "-- Police bitmap des pseudos : genere par scripts/hud/rendre_police.py, ne",
    "-- pas modifier a la main. Planche Client/liars_bar/hud/police.png, echelle 2 :",
    "-- cases de case_l x case_h pixels, glyphe dessine a marge du bord gauche,",
    "-- ligne de base a base ; avance en pixels de la planche.",
    "return {",
    "    colonnes = %d, case_l = %d, case_h = %d, marge = %d, base = %d," % (
        m["colonnes"], m["case_l"], m["case_h"], m["marge"], m["base"]),
    "    largeur = %d, hauteur = %d," % (m["largeur"], m["hauteur"]),
    "    glyphes = {",
]
for i, ch in enumerate(m["glyphes"]):
    lignes.append("        [%s] = { i = %d, a = %s }," % (lua_chaine(ch), i, m["avances"][ch]))
lignes += ["    },", "}", ""]
open(LUA, "w", encoding="utf-8", newline="\n").write("\n".join(lignes))
print("planche", PNG)
print("metriques", LUA, len(m["glyphes"]), "glyphes")
