"""Import the editable Blender furniture FBXs into MyAssetPack; do not cook."""

from pathlib import Path
import unreal


ROOT = Path("C:/Users/ingam/OneDrive/Documents/fate-games/art/furniture")
DEST = "/Game/MyAssetPack/Liars_Furniture"

unreal.EditorAssetLibrary.make_directory(DEST)
for name in ("SM_Liars_Table", "SM_Liars_Chair"):
    source = ROOT / f"{name}.fbx"
    if not source.is_file():
        raise RuntimeError(f"Missing Blender export: {source}")
    options = unreal.FbxImportUI()
    options.automated_import_should_detect_type = False
    options.mesh_type_to_import = unreal.FBXImportType.FBXIT_STATIC_MESH
    options.import_as_skeletal = False
    options.import_mesh = True
    options.import_materials = True
    options.import_textures = False
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
    imported = list(task.imported_object_paths)
    if not imported:
        raise RuntimeError(f"No asset imported from {source}")
    mesh = unreal.EditorAssetLibrary.load_asset(f"{DEST}/{name}")
    if not mesh:
        raise RuntimeError(f"Cannot load imported mesh {name}")
    bounds = mesh.get_bounds()
    print("FURNITURE_IMPORTED", name, imported,
          "extent_cm", tuple(round(v, 2) for v in
                             (bounds.box_extent.x, bounds.box_extent.y, bounds.box_extent.z)),
          "material_slots", len(mesh.get_editor_property("static_materials")))
