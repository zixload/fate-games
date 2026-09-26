"""List the pivot offset of every playing card mesh, as a Lua table.

Each card mesh keeps the pivot of the original 52-card file, far from the
card itself (about -927, y, 406 in mesh units) and a different y per card.
Liar's Bar compensates it in the 3D fan (Shared/config.lua,
liars_cards.pivots). Read-only on the project.

Run it inside the open ADK editor (Output Log, input switched to Python):
    exec(open(r"C:/Users/ingam/OneDrive/Documents/fate-games/scripts/unreal/export_cartes.py").read())
Then copy the "Cartes:" lines.
"""

import unreal


DOSSIER = "/Game/MyAssetPack/Cartes"
lignes = []
for chemin in sorted(unreal.EditorAssetLibrary.list_assets(DOSSIER, recursive=False)):
    asset = unreal.EditorAssetLibrary.load_asset(chemin.split(".")[0])
    if not isinstance(asset, unreal.StaticMesh):
        continue
    o = asset.get_bounds().origin
    lignes.append('["{}"] = {{ x = {:.2f}, y = {:.2f}, z = {:.2f} }},'.format(asset.get_name(), o.x, o.y, o.z))

for l in lignes:
    unreal.log("Cartes: " + l)
unreal.log(f"Cartes: {len(lignes)} cartes")
