"""Compare the two Mixamo clips to the Creative reference rig and report contact points."""

from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
DOWNLOADS = Path.home() / "Downloads"
REFERENCE = ROOT / "art/animations/seated_card_play.blend"

for filename in ("Sitting Idle.fbx", "Sitting Idle lazy.fbx", "Sitting Dazed.fbx"):
    bpy.ops.wm.open_mainfile(filepath=str(REFERENCE))
    references = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    print("REFERENCE_ARMATURES", [(o.name, len(o.data.bones)) for o in references])
    ref = references[0]
    print("REFERENCE_BONES", list(ref.data.bones.keys()))
    ref_bones = {b.name: b.matrix_local.copy() for b in ref.data.bones}
    bpy.ops.import_scene.fbx(filepath=str(DOWNLOADS / filename), use_anim=True)
    rigs = [o for o in bpy.context.selected_objects if o.type == "ARMATURE"]
    rig = rigs[0]
    print("CLIP", filename, "RIG", rig.name, "FPS", bpy.context.scene.render.fps,
          "BONES", len(rig.data.bones))
    print("RIG_TRANSFORM", tuple(rig.location), tuple(rig.rotation_euler), tuple(rig.scale))
    for name in ("Root", "Hips", "Spine", "LeftUpLeg", "LeftFoot", "RightFoot", "Head"):
        if name not in ref_bones or name not in rig.data.bones:
            print("MISSING_BONE", name)
            continue
        a, b = ref_bones[name], rig.data.bones[name].matrix_local
        print("REST_DIFF", name, max(abs(a[i][j]-b[i][j])
                                     for i in range(4) for j in range(4)))
    action = rig.animation_data.action
    print("ACTION", action.name, tuple(action.frame_range))
    for frame in (action.frame_range[0], action.frame_range[0]+1,
                  (action.frame_range[0]+action.frame_range[1])/2,
                  action.frame_range[1]-1, action.frame_range[1]):
        bpy.context.scene.frame_set(int(frame))
        points = {}
        for name in ("Root", "Hips", "LeftFoot", "RightFoot"):
            bone = rig.pose.bones.get(name)
            points[name] = tuple(round(x, 4) for x in
                                 (rig.matrix_world @ bone.matrix).translation)
        print("FRAME", frame, points)
