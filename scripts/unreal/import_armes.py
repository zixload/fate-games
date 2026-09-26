"""Import the six shop weapons into MyAssetPack/Armes; do not cook.

The FBXs come from scripts/blender/render_armes.py (mode fbx): 100 cm long,
centred, textures embedded. They sit in Saved/Armes, outside the repo
(Sketchfab models, licence to check before any publication).

Run it inside the open ADK editor: Output Log, input switched from Cmd to
Python, then
    exec(open(r"C:/Users/ingam/OneDrive/Documents/fate-games/scripts/unreal/import_armes.py").read())
Then cook my-asset-pack as usual and set Catalogue.armes_3d = true.
"""

from pathlib import Path
import unreal


ROOT = Path("C:/nanos-adk/Saved/Armes")
DEST = "/Game/MyAssetPack/Armes"
NAMES = ("revolver", "canon", "duel", "flammes", "glace", "physique")

unreal.EditorAssetLibrary.make_directory(DEST)
for short in NAMES:
    name = f"SM_Arme_{short}"
    source = ROOT / f"{name}.fbx"
    if not source.is_file():
        unreal.log_warning(f"Armes: missing Blender export {source}")
        continue
    options = unreal.FbxImportUI()
    options.automated_import_should_detect_type = False
    options.mesh_type_to_import = unreal.FBXImportType.FBXIT_STATIC_MESH
    options.import_as_skeletal = False
    options.import_mesh = True
    options.import_materials = True
    options.import_textures = True
    options.static_mesh_import_data.combine_meshes = True
    options.static_mesh_import_data.auto_generate_collision = False
    task = unreal.AssetImportTask()
    task.filename = str(source)
    task.destination_path = DEST
    task.destination_name = name
    task.automated = True
    task.save = True
    task.replace_existing = True
    task.options = options
    unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([task])
    mesh = unreal.EditorAssetLibrary.load_asset(f"{DEST}/{name}")
    if not mesh:
        unreal.log_warning(f"Armes: import failed for {name}")
        continue
    bounds = mesh.get_bounds()
    unreal.log("Armes: imported {} extent_cm {} material_slots {}".format(
        name,
        tuple(round(v, 1) for v in (bounds.box_extent.x, bounds.box_extent.y, bounds.box_extent.z)),
        len(mesh.get_editor_property("static_materials"))))

unreal.EditorAssetLibrary.save_directory(DEST)
unreal.log("Armes: done")
