"""Check the actual keyframe ranges in the two exported FBX files."""

from pathlib import Path
import bpy


base = Path("C:/Users/ingam/OneDrive/Documents/fate-games/art/animations")
boundary = {}
for name in ("seated_revolver_take", "seated_revolver_fire"):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    bpy.ops.import_scene.fbx(filepath=str(base / f"{name}.fbx"))
    ranges = [(action.name, tuple(round(v, 2) for v in action.frame_range))
              for action in bpy.data.actions]
    print("SEGMENT_RANGE", name, ranges)
    if not ranges:
        raise RuntimeError(f"No animation in {name}.fbx")
    body = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    frame = int(ranges[0][1][1] if name.endswith("take") else ranges[0][1][0])
    bpy.context.scene.frame_set(frame)
    boundary[name] = {
        bone: body.matrix_world @ body.pose.bones[bone].head
        for bone in ("RightHand", "RightHandProp", "RightHandIndex2", "Head")
    }

for bone, take_position in boundary["seated_revolver_take"].items():
    gap_cm = (take_position - boundary["seated_revolver_fire"][bone]).length * 100
    print("SEGMENT_JOIN", bone, round(gap_cm, 3), "cm")
    if gap_cm > 0.2:
        raise RuntimeError(f"Animation jump at {bone}: {gap_cm:.2f} cm")
