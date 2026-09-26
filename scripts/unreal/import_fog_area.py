r"""Move the Fab FogArea assets into the Nanos World asset pack.

Run in the Python console of the ADK editor that is already open::

    exec(open(r"C:\Users\ingam\OneDrive\Documents\fate-games\scripts\unreal\import_fog_area.py", encoding="utf-8").read())

The Fab Overview map is deliberately left in its original folder. No level
actors, shield assets, or game scripts are modified by this script.
"""

import unreal


SOURCE = "/Game/FogArea"
TARGET = "/Game/MyAssetPack/Imports/FogArea"
BLUEPRINT = TARGET + "/Blueprints/BP_FogArea"
SKIP_DEPENDENCIES = ("/Engine/", "/Script/", "/NanosWorld/",
                     "/Game/NanosWorld/")

library = unreal.EditorAssetLibrary
registry = unreal.AssetRegistryHelpers.get_asset_registry()
asset_tools = unreal.AssetToolsHelpers.get_asset_tools()


def package_of(asset):
    return str(asset.get_outermost().get_name())


def assets_in(folder):
    if not library.does_directory_exist(folder):
        return {}
    result = {}
    for object_path in library.list_assets(folder, recursive=True,
                                           include_folder=False):
        path = str(object_path).split(".", 1)[0]
        if "/Maps/" in path or path.endswith("_BuiltData"):
            continue
        asset = library.load_asset(path)
        if asset and package_of(asset) == path:
            result[path] = asset
    return result


registry.scan_paths_synchronous([SOURCE, TARGET], True)
original = assets_in(SOURCE)
already_moved = assets_in(TARGET)

if not original and not library.does_asset_exist(BLUEPRINT):
    raise RuntimeError("FogArea introuvable dans l'ADK : /Game/FogArea")

options = unreal.AssetRegistryDependencyOptions(
    include_soft_package_references=True,
    include_hard_package_references=True,
    include_searchable_names=False,
    include_soft_management_references=False,
    include_hard_management_references=False,
)

# Validate before changing anything. This Fab package is self-contained; a
# newly added external project dependency must be inspected rather than lost.
unresolved = set()
for source_path in original:
    for dependency in registry.get_dependencies(source_path, options) or []:
        dep = str(dependency)
        if dep.startswith(SKIP_DEPENDENCIES):
            continue
        if dep.startswith(SOURCE + "/"):
            if "/Maps/" not in dep and dep not in original:
                # It may be a redirector from a previous interrupted run.
                moved = TARGET + dep[len(SOURCE):]
                if not library.does_asset_exist(moved):
                    unresolved.add(dep)
            continue
        if dep.startswith(TARGET + "/"):
            continue
        unresolved.add(dep)

if unresolved:
    for dep in sorted(unresolved):
        print("FOG_DEPENDANCE_A_VERIFIER", dep)
    raise RuntimeError("Dependances externes du fog : aucun asset deplace")

to_move = []
for source_path, asset in sorted(original.items()):
    destination = TARGET + source_path[len(SOURCE):]
    if destination in already_moved or library.does_asset_exist(destination):
        raise RuntimeError("Conflit source/destination : " + destination)
    folder, name = destination.rsplit("/", 1)
    to_move.append((source_path, destination, asset, folder, name))

print("FOG_PLAN", len(to_move), "assets a deplacer ;",
      len(already_moved), "deja dans le pack")
for old, new, _, _, _ in to_move:
    print("FOG_MOVE", old, "->", new)

for _, _, _, folder, _ in to_move:
    library.make_directory(folder)
renames = [unreal.AssetRenameData(asset, folder, name)
           for _, _, asset, folder, name in to_move]
if renames and not asset_tools.rename_assets(renames):
    raise RuntimeError("Le renommage Unreal a echoue ; voir l'Output Log")

missing = [new for _, new, _, _, _ in to_move
           if not library.does_asset_exist(new)]
if missing or not library.does_asset_exist(BLUEPRINT):
    raise RuntimeError("Import du fog incomplet : " + ", ".join(missing))

if not library.save_directory(TARGET, only_if_is_dirty=True, recursive=True):
    raise RuntimeError("Assets deplaces, mais enregistrement du pack echoue")

print("FOG_IMPORT_COMPLETE", len(to_move), "assets deplaces")
print("FOG_BLUEPRINT", BLUEPRINT)
print("FOG_NEXT enregistrer tout, puis cuire my-asset-pack")
