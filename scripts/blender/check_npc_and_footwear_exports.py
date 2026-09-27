"""Round-trip the new NPC and footwear FBXs before ADK import."""

import json
from pathlib import Path

import bpy


ROOT = Path(__file__).resolve().parents[2]
NPC = ROOT / "art/animations/npc"
FEET = ROOT / "art/cosmetics/footwear"
bpy.ops.wm.open_mainfile(filepath=str(ROOT / "art/cosmetics/creative_modular_base.blend"))
expected = set(bpy.data.objects["Root"].data.bones.keys())
if len(expected) != 43:
    raise RuntimeError("Creative skeleton is not the expected 43 bones")
metrics = json.loads((NPC / "metrics.json").read_text(encoding="utf-8"))


def read(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(path))
    return ([obj for obj in bpy.data.objects if obj.type == "ARMATURE"],
            [obj for obj in bpy.data.objects if obj.type == "MESH"])


for name, info in metrics.items():
    rigs, meshes = read(NPC / (name + ".fbx"))
    if len(rigs) != 1 or meshes or set(rigs[0].data.bones.keys()) != expected:
        raise RuntimeError(f"{name}: expected animation-only Creative 43-bone rig")
    actions = [action for action in bpy.data.actions
               if action.frame_range[1] > action.frame_range[0]]
    if len(actions) != 1:
        raise RuntimeError(f"{name}: expected one action, got {len(actions)}")
    span = (actions[0].frame_range[1] - actions[0].frame_range[0]) / 30
    if abs(span - info["seconds"]) > .15:
        raise RuntimeError(f"{name}: duration {span:.3f}s")
    print("NPC_FBX_OK", name, "seconds", round(span, 3), "bones", len(expected))


for suffix in ("Ivory", "Charcoal", "BlackStripe", "Wood"):
    name = "SK_COS_Geta_Wood" if suffix == "Wood" else "SK_COS_Socks_" + suffix
    rigs, meshes = read(FEET / (name + ".fbx"))
    if len(rigs) != 1 or len(meshes) != 1:
        raise RuntimeError(f"{name}: expected one rig and one mesh")
    rig, mesh = rigs[0], meshes[0]
    if set(rig.data.bones.keys()) != expected or mesh.name != name:
        raise RuntimeError(f"{name}: skeleton or mesh name wrong")
    if any(not vertex.groups for vertex in mesh.data.vertices):
        raise RuntimeError(f"{name}: unweighted vertex")
    if suffix != "Wood" and len(mesh.data.uv_layers) != 1:
        raise RuntimeError(f"{name}: sock should have one design UV")
    print("FOOTWEAR_FBX_OK", name, "vertices", len(mesh.data.vertices),
          "materials", len(mesh.data.materials))


rigs, meshes = read(NPC / "SM_NPC_Spirit_Flute.fbx")
if rigs or len(meshes) != 1:
    raise RuntimeError("Flute export should be one static mesh without a rig")
flute = meshes[0]
triangles = sum(len(poly.vertices) - 2 for poly in flute.data.polygons)
if triangles > 65000 or len(flute.data.materials) != 9:
    raise RuntimeError("Flute triangle budget or color slots wrong")
print("FLUTE_FBX_OK", "triangles", triangles, "materials", len(flute.data.materials))
print("NPC_EXPORT_CHECK_COMPLETE")
