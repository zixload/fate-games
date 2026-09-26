"""Print mesh and action metadata for the four user-supplied Werewolf sources."""

import json
import zipfile
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
DOWNLOADS = Path.home() / "Downloads"
OUT = ROOT / "art" / "werewolf" / "source"
OUT.mkdir(parents=True, exist_ok=True)

for archive in ("zabuton_7col_v22_2608_en.zip", "carpet.zip"):
    with zipfile.ZipFile(DOWNLOADS / archive) as zf:
        folder = OUT / archive.removesuffix(".zip")
        folder.mkdir(exist_ok=True)
        for member in zf.infolist():
            target = (folder / member.filename).resolve()
            if not target.is_relative_to(folder.resolve()):
                raise RuntimeError(f"Unsafe archive member: {member.filename}")
            if member.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                if not target.exists() or target.stat().st_size != member.file_size:
                    with zf.open(member) as source, target.open("wb") as dest:
                        while block := source.read(1024 * 1024):
                            dest.write(block)

sources = (
    OUT / "zabuton_7col_v22_2608_en" / "Zabuton_7col_AllMesh_v2.2_2608.fbx",
    OUT / "carpet" / "source" / "libraryCarpetFBX.fbx",
    DOWNLOADS / "Sitting Idle.fbx",
    DOWNLOADS / "Sitting Idle lazy.fbx",
    DOWNLOADS / "Sitting Dazed.fbx",
)

for source in sources:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.fbx(filepath=str(source), use_anim=True)
    print("SOURCE", source)
    print("FPS", bpy.context.scene.render.fps)
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH":
            points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
            lo = [min(p[i] for p in points) for i in range(3)]
            hi = [max(p[i] for p in points) for i in range(3)]
            print("MESH", json.dumps({"name": obj.name, "min": lo, "max": hi,
                                     "materials": [m.name for m in obj.data.materials],
                                     "polygons": len(obj.data.polygons)}))
        elif obj.type == "ARMATURE":
            print("ARMATURE", obj.name, len(obj.data.bones),
                  "ROOT_BONES", [b.name for b in obj.data.bones if b.parent is None])
            print("BONES", [b.name for b in obj.data.bones])
        elif obj.type == "EMPTY":
            print("EMPTY", obj.name, tuple(obj.location))
    for action in bpy.data.actions:
        print("ACTION", action.name, tuple(action.frame_range))
