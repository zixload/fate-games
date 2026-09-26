#!/bin/sh
# Rend les sprites du HUD de Liar's Bar (scripts/hud/sprites.html) en PNG,
# a l'echelle 2, dans Packages/fate-games/Client/liars_bar/hud/.
#     sh scripts/hud/rendre.sh
set -e
RACINE="$(cd "$(dirname "$0")/../.." && pwd -W 2>/dev/null || pwd)"
EDGE="/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
PAGE="file:///$RACINE/scripts/hud/sprites.html"
SORTIE="$RACINE/Packages/fate-games/Client/liars_bar/hud"
PROFIL="${TMPDIR:-/tmp}/edge-sprites"
mkdir -p "$SORTIE"

rendre() { # nom largeur hauteur parametres
    "$EDGE" --headless=new --disable-gpu --user-data-dir="$PROFIL" --allow-file-access-from-files \
        --hide-scrollbars --force-device-scale-factor=2 --default-background-color=00000000 \
        --window-size="$2,$3" --virtual-time-budget=2500 --screenshot="$SORTIE/$1.png" "$PAGE?$4" >/dev/null 2>&1
}

for n in 0 1 2 3 4 5 6; do rendre "barillet_$n" 64 64 "s=barillet&n=$n"; done
rendre fleche 28 24 "s=fleche"
rendre menteur 186 66 "s=menteur"
rendre carton 132 98 "s=carton"
for n in 1 2 3; do rendre "plus_$n" 60 34 "s=texte&t=%2B$n&taille=30&l=60&h=34"; done
for r in roi:Roi dame:Dame as:As joker:Joker; do
    rendre "table_${r%%:*}" 110 22 "s=texte&t=Table%20:%20${r#*:}&taille=17&l=110&h=22"
done
for n in $(seq 1 20); do rendre "tas_$n" 90 16 "s=texte&t=$n%20au%20tas&taille=13&l=90&h=16&pale=1"; done
echo "sprites rendus dans $SORTIE"
