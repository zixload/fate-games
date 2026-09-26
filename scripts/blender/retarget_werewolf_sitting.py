"""Bake the three supplied Mixamo seated clips onto the Creative 43-bone rig.

The Mixamo FBXs add an extra Root bone. The Creative animation assets use the
armature object as root instead. World-space pose transfer keeps the actual
Creative rest pose and bakes all child bones, without actor/root motion.
Sources and generated FBX files remain in ignored art/werewolf/.
"""

import json
import os
from pathlib import Path
import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art/werewolf"
REFERENCE = ROOT / "art/animations/seated_card_play.blend"
DOWNLOADS = Path.home() / "Downloads"
CLIPS = (
    ("Sitting Idle.fbx", "ANIM_WW_Sitting_Idle", "idle"),
    ("Sitting Idle lazy.fbx", "ANIM_WW_Sitting_Idle_Lazy", "lazy"),
    ("Sitting Dazed.fbx", "ANIM_WW_Sitting_Dazed", "dazed"),
)
selection = os.environ.get("WW_CLIPS", "all")
APPLY_FIT = os.environ.get("WW_APPLY_FIT", "1") == "1"
METRICS = {}


def pose_point(rig, name):
    return rig.matrix_world @ rig.pose.bones[name].head


for filename, asset_name, short in CLIPS:
    if selection != "all" and short not in selection.split(","):
        continue
    bpy.ops.wm.open_mainfile(filepath=str(REFERENCE))
    scene = bpy.context.scene
    scene.render.fps = 30
    creative = bpy.data.objects["Root"]
    source_file = DOWNLOADS / filename
    if not source_file.is_file():
        raise FileNotFoundError(source_file)
    bpy.ops.import_scene.fbx(filepath=str(source_file), use_anim=True)
    source = next(obj for obj in bpy.context.selected_objects if obj.type == "ARMATURE")
    source_action = source.animation_data.action
    first, last = (int(round(f)) for f in source_action.frame_range)
    if set(creative.pose.bones.keys()) != set(source.pose.bones.keys()) - {"Root"}:
        raise RuntimeError(f"Bone mismatch in {filename}")

    # The source's added Root is excluded. Its world-space transform has
    # already been incorporated in each sampled child's matrix.
    if creative.animation_data:
        creative.animation_data_clear()
    for target_bone in creative.pose.bones:
        constraint = target_bone.constraints.new("COPY_TRANSFORMS")
        constraint.target = source
        constraint.subtarget = target_bone.name
        constraint.target_space = "WORLD"
        constraint.owner_space = "WORLD"

    scene.frame_start, scene.frame_end = first, last
    scene.frame_set(first)
    bpy.context.view_layer.update()
    before = {n: tuple(round(v, 5) for v in pose_point(creative, n))
              for n in ("Hips", "LeftFoot", "RightFoot")}
    bpy.ops.object.select_all(action="DESELECT")
    creative.select_set(True)
    bpy.context.view_layer.objects.active = creative
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.nla.bake(frame_start=first, frame_end=last, step=1,
                     only_selected=False, visual_keying=True,
                     clear_constraints=True, use_current_action=False,
                     bake_types={"POSE"})
    bpy.ops.object.mode_set(mode="OBJECT")
    action = creative.animation_data.action
    action.name = asset_name
    scene.frame_set(first)
    bpy.context.view_layer.update()
    after = {n: tuple(round(v, 5) for v in pose_point(creative, n))
             for n in ("Hips", "LeftFoot", "RightFoot")}
    if max(abs(before[n][i]-after[n][i]) for n in before for i in range(3)) > .005:
        raise RuntimeError(f"Retarget bake moved contacts for {asset_name}: {before} -> {after}")

    # Verify first/last pose continuity for the transform that matters in game.
    scene.frame_set(last)
    end = {n: tuple(pose_point(creative, n)) for n in before}
    scene.frame_set(first)
    start = {n: tuple(pose_point(creative, n)) for n in before}
    seam_cm = max((Vector(start[n])-Vector(end[n])).length for n in before) * 100
    if seam_cm > .1:
        raise RuntimeError(f"Loop seam > 1 mm in {asset_name}: {seam_cm:.3f} cm")

    if APPLY_FIT:
        # Desired ankle displacement, in world metres on the 0.8-scale body.
        # Measurements come from measure_werewolf_sitting_fit.py. The test
        # actor's Z placement is .11/.128/.116 m for idle/lazy/dazed; the
        # carpet top is .008 m. The idle right foot also moves outside the
        # cushion footprint so it can meet the carpet.
        feet = {
            "idle": {"LeftFoot": (0, 0, -.105),
                     "RightFoot": (0, -.16, -.082)},
            "lazy": {"LeftFoot": (0, 0, -.168),
                     "RightFoot": (0, 0, -.142)},
            "dazed": {"LeftFoot": (0, 0, -.122),
                      "RightFoot": (0, 0, -.118)},
        }[short]
        targets = {}
        for foot in feet:
            target = bpy.data.objects.new(f"{foot}_carpet_target", None)
            scene.collection.objects.link(target)
            targets[foot] = target
        planted_z = {}
        for frame in range(first, last + 1):
            scene.frame_set(frame)
            bpy.context.view_layer.update()
            for foot, displacement in feet.items():
                current = pose_point(creative, foot)
                point = current + Vector(displacement) / .8
                if foot not in planted_z:
                    planted_z[foot] = point.z
                point.z = planted_z[foot]
                targets[foot].location = point
                targets[foot].keyframe_insert("location", frame=frame)
        for leg, foot in (("LeftLeg", "LeftFoot"),
                          ("RightLeg", "RightFoot")):
            ik = creative.pose.bones[leg].constraints.new("IK")
            ik.target = targets[foot]
            ik.chain_count = 2
            ik.use_stretch = False
        scene.frame_set(first)
        bpy.context.view_layer.update()
        print("FIT_BEFORE_BAKE", asset_name,
              {n: tuple(round(v,4) for v in pose_point(creative,n))
               for n in feet})
        bpy.ops.object.select_all(action="DESELECT")
        creative.select_set(True)
        bpy.context.view_layer.objects.active = creative
        bpy.ops.object.mode_set(mode="POSE")
        bpy.ops.nla.bake(frame_start=first, frame_end=last, step=1,
                         only_selected=False, visual_keying=True,
                         clear_constraints=True, use_current_action=True,
                         bake_types={"POSE"})
        bpy.ops.object.mode_set(mode="OBJECT")
        for target in targets.values():
            bpy.data.objects.remove(target, do_unlink=True)
        scene.frame_set(first)
        bpy.context.view_layer.update()
        print("FIT_AFTER_BAKE", asset_name,
              {n: tuple(round(v,4) for v in pose_point(creative,n))
               for n in feet})
        end = {n: tuple(pose_point(creative, n)) for n in feet}
        scene.frame_set(last)
        start = {n: tuple(pose_point(creative, n)) for n in feet}
        corrected_seam_cm = max((Vector(start[n])-Vector(end[n])).length
                                for n in feet) * 100
        if corrected_seam_cm > .1:
            raise RuntimeError(f"Corrected feet loop seam in {asset_name}: "
                               f"{corrected_seam_cm:.3f} cm")
        seam_cm = max(seam_cm, corrected_seam_cm)

    # The reference mesh is retained in the .blend for pose review, but only
    # the armature is exported. Clothing stays in the Unreal Creative pack.
    source.hide_render = True
    for obj in source.children_recursive:
        obj.hide_render = True
    blend = OUT / f"{asset_name}.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    bpy.ops.object.select_all(action="DESELECT")
    creative.select_set(True)
    bpy.context.view_layer.objects.active = creative
    fbx = OUT / f"{asset_name}.fbx"
    bpy.ops.export_scene.fbx(
        filepath=str(fbx), use_selection=True, object_types={"ARMATURE"},
        add_leaf_bones=False, bake_anim=True,
        bake_anim_use_all_bones=True, bake_anim_use_nla_strips=False,
        bake_anim_use_all_actions=False, bake_anim_step=1,
    )
    METRICS[asset_name] = {"frames": [first, last],
                           "duration_seconds": round((last-first)/30, 4),
                           "loop_seam_cm": round(seam_cm, 4),
                           "contact_points_m": after,
                           "fbx": str(fbx)}
    print("WW_ANIMATION", asset_name, json.dumps(METRICS[asset_name]))

if METRICS:
    (OUT / "sitting_animation_metrics.json").write_text(
        json.dumps(METRICS, indent=2), encoding="utf-8")
