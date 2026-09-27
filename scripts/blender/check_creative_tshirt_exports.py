"""Round-trip the T-shirt FBXs and verify their Creative skeleton and UVs."""

from pathlib import Path

import bpy


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "art/cosmetics/creative_modular_base.blend"
SOURCE = ROOT / "art/cosmetics/tshirts"
TIERS = ("Uncommon_Frayed", "Rare_Compass", "Epic_Eclipse", "Legendary_Sun")

bpy.ops.wm.open_mainfile(filepath=str(BASE))
expected_bones = set(bpy.data.objects["Root"].data.bones.keys())
if len(expected_bones) != 43:
    raise RuntimeError(f"Unexpected Creative skeleton: {len(expected_bones)} bones")

for tier in TIERS:
    name = "SK_COS_TShirt_" + tier
    path = SOURCE / (name + ".fbx")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(path))
    rigs = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]
    meshes = [obj for obj in bpy.data.objects if obj.type == "MESH"]
    if len(rigs) != 1 or len(meshes) != 1:
        raise RuntimeError(f"{name}: expected exactly one rig and one mesh")
    rig, mesh = rigs[0], meshes[0]
    if set(rig.data.bones.keys()) != expected_bones:
        raise RuntimeError(f"{name}: skeleton bone names differ from Creative")
    if mesh.name != name or not mesh.vertex_groups:
        raise RuntimeError(f"{name}: mesh name or skin weights missing")
    if any(not vertex.groups for vertex in mesh.data.vertices):
        raise RuntimeError(f"{name}: an unweighted vertex was found")
    if tier != "Uncommon_Frayed" and len(mesh.data.uv_layers) != 1:
        raise RuntimeError(f"{name}: expected one design UV channel")
    if tier == "Uncommon_Frayed" and len(mesh.data.materials) != 2:
        raise RuntimeError(f"{name}: the two frayed cloth materials are missing")
    print("TSHIRT_FBX_OK", name, "vertices", len(mesh.data.vertices),
          "bones", len(rig.data.bones), "UVs", len(mesh.data.uv_layers))

print("TSHIRT_FBX_CHECK_COMPLETE", len(TIERS))
