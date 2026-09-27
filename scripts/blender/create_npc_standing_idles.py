"""Retarget three supplied standing poses and give them subtle looping life.

No Lua or map changes. Sources stay in Downloads, generated FBX/blend/previews
stay in ignored art/animations/npc. Creative's 43 bones are the only export rig.
"""

import json
from math import pi, sin
from pathlib import Path

import bpy
from mathutils import Quaternion, Vector


ROOT = Path(__file__).resolve().parents[2]
DOWNLOADS = Path.home() / "Downloads"
REFERENCE = ROOT / "art/animations/seated_card_play.blend"
OUTPUT = ROOT / "art/animations/npc"
OUTPUT.mkdir(parents=True, exist_ok=True)
FPS = 30
FIRST, LAST = 1, 121
SPECS = (
    ("Male Standing Pose.fbx", "ANIM_NPC_Tailor_Idle", 1.5, 1.3),
    ("Armurier Pose.fbx", "ANIM_NPC_Armorer_Idle", 1.1, 1.8),
    ("Forain Pose.fbx", "ANIM_NPC_Showman_Idle", 2.2, 2.7),
)


def point(rig, name):
    return rig.matrix_world @ rig.pose.bones[name].head


def retarget(source_path):
    bpy.ops.wm.open_mainfile(filepath=str(REFERENCE))
    scene = bpy.context.scene
    scene.render.fps = FPS
    creative = bpy.data.objects["Root"]
    bpy.ops.import_scene.fbx(filepath=str(source_path), use_anim=True)
    source = next(obj for obj in bpy.context.selected_objects if obj.type == "ARMATURE")
    if set(creative.pose.bones.keys()) != set(source.pose.bones.keys()) - {"Root"}:
        raise RuntimeError("Source pose does not match the Creative rig: " + source_path.name)
    if not source.animation_data or not source.animation_data.action:
        raise RuntimeError("Source FBX has no animation: " + source_path.name)
    if creative.animation_data:
        creative.animation_data_clear()
    for bone in creative.pose.bones:
        constraint = bone.constraints.new("COPY_TRANSFORMS")
        constraint.target = source
        constraint.subtarget = bone.name
        constraint.target_space = "WORLD"
        constraint.owner_space = "WORLD"
    bpy.ops.object.select_all(action="DESELECT")
    creative.select_set(True)
    bpy.context.view_layer.objects.active = creative
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.nla.bake(frame_start=1, frame_end=2, step=1, only_selected=False,
                     visual_keying=True, clear_constraints=True,
                     use_current_action=False, bake_types={"POSE"})
    bpy.ops.object.mode_set(mode="OBJECT")
    scene.frame_set(1)
    for obj in (source, *source.children_recursive):
        obj.hide_render = True
    return scene, creative


def make_loop(scene, rig, name, breath_degrees, glance_degrees):
    # Save the exact source pose. Only upper-body joints get small periodic
    # offsets; the hips and both feet keep their world contacts.
    baseline = {}
    for bone in rig.pose.bones:
        bone.rotation_mode = "QUATERNION"
        baseline[bone.name] = (bone.location.copy(), bone.rotation_quaternion.copy(),
                               bone.scale.copy())
    before = {name: point(rig, name).copy() for name in ("Hips", "LeftFoot", "RightFoot")}
    if rig.animation_data:
        rig.animation_data_clear()
    action = bpy.data.actions.new(name)
    rig.animation_data_create()
    rig.animation_data.action = action
    rig.animation_data.action_slot = action.slots.new("OBJECT", name)

    scene.frame_start, scene.frame_end = FIRST, LAST
    for frame in range(FIRST, LAST + 1, 15):
        scene.frame_set(frame)
        phase = 2 * pi * (frame - FIRST) / (LAST - FIRST)
        breath = sin(phase) * breath_degrees * pi / 180
        glance = sin(phase + .35) * glance_degrees * pi / 180
        for bone in rig.pose.bones:
            location, rotation, scale = baseline[bone.name]
            bone.location = location
            bone.rotation_quaternion = rotation
            bone.scale = scale
            if bone.name == "Spine1":
                bone.rotation_quaternion = rotation @ Quaternion((1, 0, 0), breath)
            elif bone.name == "Neck":
                bone.rotation_quaternion = rotation @ Quaternion((0, 0, 1), glance * .40)
            elif bone.name == "Head":
                bone.rotation_quaternion = rotation @ Quaternion((0, 0, 1), glance * .60)
            bone.keyframe_insert("location", frame=frame)
            bone.keyframe_insert("rotation_quaternion", frame=frame)
            bone.keyframe_insert("scale", frame=frame)
    scene.frame_set(FIRST)
    start = {name: point(rig, name).copy() for name in before}
    scene.frame_set(LAST)
    seam = max((point(rig, name) - start[name]).length for name in before) * 100
    if seam > .1:
        raise RuntimeError(f"{name} loop seam {seam:.3f} cm")
    if max((start[name] - before[name]).length for name in before) > .01:
        raise RuntimeError(f"{name} altered the standing contact pose")
    print("NPC_LOOP", name, "seconds", (LAST - FIRST) / FPS,
          "seam_cm", round(seam, 5))


def setup_preview(scene):
    # The seated reference blend can retain a stale absolute texture path.
    # Relink the original Creative atlas so the saved previews show the kit colors.
    atlas = next(Path("C:/ProgramData/Epic/EpicGamesLauncher/VaultCache/FabLibrary").glob(
        "Creative_Characters_FREE_*/obj/source_extracted/Separate_assets_obj_extracted/Separate_assets_obj/Textures_4.png"))
    image = bpy.data.images.load(str(atlas), check_existing=True)
    for material in bpy.data.materials:
        if material.use_nodes:
            for node in material.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image:
                    node.image = image
    world = bpy.data.worlds.new("NPC preview")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (.14, .16, .19, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = .7
    scene.world = world
    for name, loc, energy in (("Key", (3, -4, 5), 800), ("Fill", (-3, -3, 3), 450)):
        light = bpy.data.lights.new(name, "AREA")
        light.energy = energy
        light.size = 4
        obj = bpy.data.objects.new(name, light)
        scene.collection.objects.link(obj)
        obj.location = loc
        obj.rotation_euler = (Vector((0, 0, 1)) - obj.location).to_track_quat("-Z", "Y").to_euler()
    data = bpy.data.cameras.new("Preview camera")
    data.type = "ORTHO"
    data.ortho_scale = 2.45
    camera = bpy.data.objects.new("Preview camera", data)
    scene.collection.objects.link(camera)
    camera.location = (2.6, -5, 2.4)
    camera.rotation_euler = (Vector((0, 0, .98)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 850
    scene.render.resolution_y = 850
    scene.render.resolution_percentage = 100


def export(scene, rig, name):
    scene.frame_set(31)
    setup_preview(scene)
    scene.render.filepath = str(OUTPUT / (name + ".png"))
    bpy.ops.render.render(write_still=True)
    scene.frame_set(FIRST)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / (name + ".blend")))
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.fbx(
        filepath=str(OUTPUT / (name + ".fbx")), use_selection=True,
        object_types={"ARMATURE"}, add_leaf_bones=False, bake_anim=True,
        bake_anim_use_all_bones=True, bake_anim_use_nla_strips=False,
        bake_anim_use_all_actions=False, bake_anim_step=1.0)


metrics = {}
for source_name, name, breath, glance in SPECS:
    path = DOWNLOADS / source_name
    if not path.is_file():
        raise FileNotFoundError(path)
    scene, rig = retarget(path)
    make_loop(scene, rig, name, breath, glance)
    export(scene, rig, name)
    metrics[name] = {"source": source_name, "seconds": 4.0, "bones": 43,
                     "root_motion": False, "loop": True}

(OUTPUT / "metrics.json").write_text(json.dumps(metrics, indent=2), encoding="utf-8")
print("NPC_STANDING_COMPLETE", len(metrics))
