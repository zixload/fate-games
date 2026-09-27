"""Retarget seven Mixamo dances to the Creative character skeleton.

Source FBX files are read from Downloads. Licensed source and generated FBX,
blend, and metric files stay under ignored art/animations/dances/.
"""

import json
import os
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
DOWNLOADS = Path.home() / "Downloads"
REFERENCE = ROOT / "art/animations/seated_card_play.blend"
OUT = ROOT / "art/animations/dances"
OUT.mkdir(parents=True, exist_ok=True)
CLIPS = (
    ("Step Hip Hop Dance.fbx", "ANIM_Dance_StepHipHop", "step"),
    ("Chicken Dance.fbx", "ANIM_Dance_Chicken", "chicken"),
    ("Wave Hip Hop Dance.fbx", "ANIM_Dance_WaveHipHop", "wave"),
    ("Tut Hip Hop Dance.fbx", "ANIM_Dance_TutHipHop", "tut"),
    ("Booty Hip Hop Dance.fbx", "ANIM_Dance_BootyHipHop", "booty"),
    ("Salsa Dancing.fbx", "ANIM_Dance_Salsa", "salsa"),
    ("Jazz Dancing.fbx", "ANIM_Dance_Jazz", "jazz"),
)
SELECT = set(os.environ.get("DANCE_CLIPS", "all").split(","))
MAX_RADIUS_M = .45


def world_point(rig, bone):
    return rig.matrix_world @ rig.pose.bones[bone].head


def move_hips_xy(rig, delta, frame):
    hips = rig.pose.bones["Hips"]
    local = rig.matrix_world.to_3x3().inverted() @ Vector((delta.x, delta.y, 0))
    matrix = hips.matrix.copy()
    matrix.translation += local
    hips.matrix = matrix
    bpy.context.view_layer.update()
    hips.keyframe_insert("location", frame=frame)


def xy(vector):
    return Vector((vector.x, vector.y, 0))


metrics = {}
for filename, asset, short in CLIPS:
    if "all" not in SELECT and short not in SELECT:
        continue
    source_file = DOWNLOADS / filename
    if not source_file.is_file():
        raise FileNotFoundError(source_file)
    bpy.ops.wm.open_mainfile(filepath=str(REFERENCE))
    scene = bpy.context.scene
    scene.render.fps = 30
    creative = bpy.data.objects["Root"]
    bpy.ops.import_scene.fbx(filepath=str(source_file), use_anim=True)
    source = next(obj for obj in bpy.context.selected_objects
                  if obj.type == "ARMATURE")
    action = source.animation_data.action
    first, last = (int(round(value)) for value in action.frame_range)
    if set(creative.pose.bones.keys()) != set(source.pose.bones.keys()) - {"Root"}:
        raise RuntimeError("Creative bone names do not match " + filename)

    if creative.animation_data:
        creative.animation_data_clear()
    for bone in creative.pose.bones:
        constraint = bone.constraints.new("COPY_TRANSFORMS")
        constraint.target = source
        constraint.subtarget = bone.name
        constraint.target_space = "WORLD"
        constraint.owner_space = "WORLD"
    scene.frame_start, scene.frame_end = first, last
    bpy.ops.object.select_all(action="DESELECT")
    creative.select_set(True)
    bpy.context.view_layer.objects.active = creative
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.nla.bake(frame_start=first, frame_end=last, step=1,
                     only_selected=False, visual_keying=True,
                     clear_constraints=True, use_current_action=False,
                     bake_types={"POSE"})
    bpy.ops.object.mode_set(mode="OBJECT")
    creative.animation_data.action.name = asset

    # Strip only the cumulative trajectory. Keep local steps and body sway.
    scene.frame_set(first)
    initial = xy(world_point(creative, "Hips"))
    scene.frame_set(last)
    drift = xy(world_point(creative, "Hips")) - initial
    if drift.length > .005:
        for frame in range(first, last + 1):
            scene.frame_set(frame)
            alpha = (frame - first) / (last - first)
            move_hips_xy(creative, -drift * alpha, frame)

    scene.frame_set(first)
    initial = xy(world_point(creative, "Hips"))
    maximum = 0.0
    for frame in range(first, last + 1):
        scene.frame_set(frame)
        maximum = max(maximum, (xy(world_point(creative, "Hips"))
                                - initial).length)
    if maximum > MAX_RADIUS_M:
        factor = MAX_RADIUS_M / maximum
        for frame in range(first, last + 1):
            scene.frame_set(frame)
            offset = xy(world_point(creative, "Hips")) - initial
            move_hips_xy(creative, -offset * (1 - factor), frame)

    scene.frame_set(first)
    bones_to_check = ("Hips", "LeftFoot", "RightFoot", "Head",
                      "LeftHand", "RightHand")
    beginning = {name: world_point(creative, name).copy()
                 for name in bones_to_check}
    scene.frame_set(last)
    seam_cm = max((world_point(creative, name) - value).length
                  for name, value in beginning.items()) * 100
    if seam_cm > .5:
        raise RuntimeError(f"{asset} loop seam {seam_cm:.3f} cm")
    scene.frame_set(first)

    source.hide_render = True
    for child in source.children_recursive:
        child.hide_render = True
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / (asset + ".blend")))
    bpy.ops.object.select_all(action="DESELECT")
    creative.select_set(True)
    bpy.context.view_layer.objects.active = creative
    bpy.ops.export_scene.fbx(
        filepath=str(OUT / (asset + ".fbx")), use_selection=True,
        object_types={"ARMATURE"}, add_leaf_bones=False, bake_anim=True,
        bake_anim_use_all_bones=True, bake_anim_use_nla_strips=False,
        bake_anim_use_all_actions=False, bake_anim_step=1.0)
    metrics[asset] = {
        "source": filename,
        "frames": [first, last],
        "seconds": round((last - first) / 30, 4),
        "removed_drift_cm": round(drift.length * 100, 2),
        "loop_seam_cm": round(seam_cm, 4),
    }
    print("DANCE_READY", asset, json.dumps(metrics[asset]))

if metrics:
    (OUT / "metrics.json").write_text(
        json.dumps(metrics, indent=2), encoding="utf-8")
