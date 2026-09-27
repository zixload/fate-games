"""Make a slow Creative musician idle and an optimized, hand-bound pan flute.

The supplied Sketchfab FBX and all generated binary media remain under ignored
art/.  The flute is exported in RightHandProp bone-local coordinates, allowing
SnapToTarget attachment without a second position/rotation guess in game.
"""

import json
import zipfile
from math import pi, radians, sin
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art/animations/npc"
SOURCE_BLEND = OUT / "ANIM_NPC_Tailor_Idle.blend"
FLUTE_SOURCE = ROOT / "art/cosmetics/npc/flute_source/source/flute_FIN.fbx"
FLUTE_ZIP = Path.home() / "Downloads/zelda-spirit-flute.zip"
FPS, FIRST, LAST = 30, 1, 181
NAME = "ANIM_NPC_Musician_Flute_Idle"


def point(rig, name):
    return rig.matrix_world @ rig.pose.bones[name].head


def import_flute():
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=str(FLUTE_SOURCE), use_anim=False)
    imported = [obj for obj in bpy.data.objects if obj not in before and obj.type == "MESH"]
    if not imported:
        raise RuntimeError("The supplied flute FBX contains no mesh")
    bbox = [Vector((axis(o.matrix_world @ v.co) for axis in (lambda p: p.x, lambda p: p.y, lambda p: p.z)))
            for o in imported for v in o.data.vertices]
    low = Vector(min(p[i] for p in bbox) for i in range(3))
    high = Vector(max(p[i] for p in bbox) for i in range(3))
    center = (low + high) / 2
    original_triangles = sum(len(o.data.polygons) for o in imported)
    # Material slots stay on their separate components through reduction/join.
    for obj in imported:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        count = len(obj.data.polygons)
        if count > 250:
            modifier = obj.modifiers.new("Game poly budget", "DECIMATE")
            modifier.ratio = min(1, max(250 / count, .045))
            bpy.ops.object.modifier_apply(modifier=modifier.name)
        transform = Matrix.Rotation(radians(90), 4, "X") @ Matrix.Scale(.012, 4)
        for vertex in obj.data.vertices:
            vertex.co = transform @ (obj.matrix_world @ vertex.co - center)
        obj.matrix_world = Matrix.Identity(4)
        # Sketchfab source has diffuse colors but no UVs. Give each component
        # a matte Creative-style material so its palette survives export.
        for mat in obj.data.materials:
            if mat:
                mat.use_nodes = True
                bsdf = mat.node_tree.nodes.get("Principled BSDF")
                if bsdf:
                    bsdf.inputs["Base Color"].default_value = tuple(mat.diffuse_color)
                    bsdf.inputs["Roughness"].default_value = .79
    bpy.ops.object.select_all(action="DESELECT")
    for obj in imported:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = imported[0]
    bpy.ops.object.join()
    flute = imported[0]
    flute.name = "SM_NPC_Spirit_Flute"
    flute.data.name = flute.name
    optimized_triangles = sum(len(poly.vertices) - 2 for poly in flute.data.polygons)
    if optimized_triangles > 65000:
        raise RuntimeError(f"Flute still too dense: {optimized_triangles} triangles")
    print("FLUTE_GEOMETRY", "source_polygons", original_triangles,
          "game_triangles", optimized_triangles, "materials", len(flute.data.materials))
    return flute, optimized_triangles


def place_hands(scene, rig):
    """Main droite placee par IK et doigts replies, puis tout le bras droit
    recopie en miroir sur le gauche (epaule, bras, avant-bras, main, doigts).

    27/09 : la flute etait decalee a droite de la bouche et seule la main
    gauche etait recopiee, avec un decalage de 13,5 cm : le poignet se
    detachait de l'avant-bras. Flute centree devant la bouche (x = 0), les
    deux bras symetriques par rapport a l'axe du corps."""
    wrist = bpy.data.objects.new("Right flute wrist", None)
    pole = bpy.data.objects.new("Right flute elbow", None)
    scene.collection.objects.link(wrist)
    scene.collection.objects.link(pole)
    wrist.location = Vector((-.1525, -.265, 1.365))
    pole.location = point(rig, "RightForeArm") + Vector((-.22, -.10, -.08))
    constraint = rig.pose.bones["RightForeArm"].constraints.new("IK")
    constraint.target = wrist
    constraint.pole_target = pole
    constraint.chain_count = 2
    constraint.use_stretch = False
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.nla.bake(frame_start=FIRST, frame_end=2, step=1,
                     only_selected=False, visual_keying=True,
                     clear_constraints=True, use_current_action=False,
                     bake_types={"POSE"})
    bpy.ops.object.mode_set(mode="OBJECT")
    for obj in (wrist, pole):
        bpy.data.objects.remove(obj, do_unlink=True)

    fingers = ("Index", "Middle", "Ring", "Pinky")
    chain = ["Shoulder", "Arm", "ForeArm", "Hand",
             "HandIndex1", "HandIndex2", "HandMiddle1", "HandMiddle2",
             "HandPinky1", "HandPinky2", "HandRing1", "HandRing2",
             "HandThumb1", "HandThumb2", "HandProp"]
    reflect = Matrix.Diagonal((-1, 1, 1, 1))
    for frame in (FIRST, 2):
        scene.frame_set(frame)
        # Les quatre doigts droits se replient sur les tuyaux exterieurs.
        for finger in fingers:
            for joint, degrees in (("1", 72), ("2", 28)):
                bone = rig.pose.bones["RightHand" + finger + joint]
                head = rig.matrix_world @ bone.head
                spin = (Matrix.Translation(head)
                        @ Matrix.Rotation(radians(degrees), 4, "Y")
                        @ Matrix.Translation(-head))
                bone.matrix = rig.matrix_world.inverted() @ spin @ rig.matrix_world @ bone.matrix
                bpy.context.view_layer.update()
                bone.keyframe_insert("rotation_quaternion", frame=frame)
        # Miroir de toute la chaine, de l'epaule aux doigts, par rapport au
        # plan x = 0 : parents d'abord, pour que chaque os suive le precedent.
        for suffix in chain:
            right = rig.pose.bones["Right" + suffix]
            left = rig.pose.bones["Left" + suffix]
            left.rotation_mode = "QUATERNION"
            left.matrix = reflect @ right.matrix @ reflect
            bpy.context.view_layer.update()
            left.keyframe_insert("location", frame=frame)
            left.keyframe_insert("rotation_quaternion", frame=frame)
            left.keyframe_insert("scale", frame=frame)
    scene.frame_set(FIRST)
    print("MUSICIAN_HANDS", tuple(round(v, 3) for v in point(rig, "LeftHand")),
          tuple(round(v, 3) for v in point(rig, "RightHand")))


def make_loop(scene, rig):
    scene.frame_set(FIRST)
    baseline = {}
    for bone in rig.pose.bones:
        bone.rotation_mode = "QUATERNION"
        baseline[bone.name] = (bone.location.copy(), bone.rotation_quaternion.copy(), bone.scale.copy())
    if rig.animation_data:
        rig.animation_data_clear()
    action = bpy.data.actions.new(NAME)
    rig.animation_data_create()
    rig.animation_data.action = action
    rig.animation_data.action_slot = action.slots.new("OBJECT", NAME)
    scene.frame_start, scene.frame_end, scene.render.fps = FIRST, LAST, FPS
    for frame in range(FIRST, LAST + 1, 10):
        scene.frame_set(frame)
        phase = 2 * pi * (frame - FIRST) / (LAST - FIRST)
        sway = sin(phase)
        breathe = sin(phase * 2 - .4)
        for bone in rig.pose.bones:
            loc, rot, scale = baseline[bone.name]
            bone.location = loc.copy()
            bone.rotation_quaternion = rot.copy()
            bone.scale = scale.copy()
            if bone.name == "Spine1":
                bone.rotation_quaternion = rot @ Matrix.Rotation(radians(1.6 * sway), 4, "Y").to_quaternion()
            elif bone.name == "Neck":
                bone.rotation_quaternion = rot @ Matrix.Rotation(radians(.9 * sway), 4, "Z").to_quaternion()
            elif bone.name == "Head":
                bone.rotation_quaternion = rot @ Matrix.Rotation(radians(1.4 * sway + .5 * breathe), 4, "Z").to_quaternion()
            elif bone.name == "Hips":
                bone.location.z += .0025 * (1 - (1 + breathe) / 2)
            elif bone.name in ("LeftUpLeg", "RightUpLeg"):
                bone.rotation_quaternion = rot @ Matrix.Rotation(radians(.65 * breathe), 4, "X").to_quaternion()
            elif bone.name in ("LeftLeg", "RightLeg"):
                bone.rotation_quaternion = rot @ Matrix.Rotation(radians(-.85 * breathe), 4, "X").to_quaternion()
            bone.keyframe_insert("location", frame=frame)
            bone.keyframe_insert("rotation_quaternion", frame=frame)
            bone.keyframe_insert("scale", frame=frame)
    scene.frame_set(FIRST)
    contacts = {name: point(rig, name).copy() for name in ("Hips", "LeftFoot", "RightFoot", "LeftHand", "RightHand")}
    scene.frame_set(LAST)
    seam = max((point(rig, name) - value).length for name, value in contacts.items()) * 100
    if seam > .1:
        raise RuntimeError(f"Musician loop seam {seam:.3f} cm")
    max_foot_drift = 0.0
    for frame in range(FIRST, LAST + 1, 10):
        scene.frame_set(frame)
        max_foot_drift = max(max_foot_drift, *(
            (point(rig, name) - contacts[name]).length * 100
            for name in ("LeftFoot", "RightFoot")))
    if max_foot_drift > 1.0:
        raise RuntimeError(f"Musician foot sliding {max_foot_drift:.3f} cm")
    print("MUSICIAN_LOOP", (LAST - FIRST) / FPS, "seconds", "seam_cm",
          round(seam, 5), "max_foot_drift_cm", round(max_foot_drift, 3))
    scene.frame_set(FIRST)


def bind_flute(scene, rig, flute):
    # Shift the pipes' center up in front of the face and export their vertices
    # in the actual RightHandProp bone frame. This also makes the preview exact.
    grip = rig.matrix_world @ rig.pose.bones["RightHandProp"].matrix
    # Keep the top pipes at the mouth while swinging the lower ends toward
    # the spread hands. Moving the whole instrument would miss the lips.
    # Centree devant la bouche, entre les deux mains symetriques.
    world = Matrix.Translation(Vector((0.0, -.245, 1.325)))
    flute.data.transform(grip.inverted() @ world)
    flute.parent = rig
    flute.parent_type = "BONE"
    flute.parent_bone = "RightHandProp"
    flute.matrix_parent_inverse = Matrix.Identity(4)
    bpy.context.view_layer.update()
    flute.hide_render = False
    # Keep an unparented export copy, since FBX static import should not gain
    # the Creative armature as a dependency.
    export = flute.copy()
    export.data = flute.data.copy()
    # Le squelette Creative porte une echelle 0,01 dans Blender : exportee dans
    # le repere de l'os avec cette echelle, la flute sortait 100 fois trop
    # grande dans Unreal (27/09). L'export garde position et rotation de l'os,
    # sans son echelle ; l'apercu Blender, lui, reste parente a l'os.
    sans_echelle = Matrix.LocRotScale(grip.to_translation(), grip.to_quaternion(), None)
    export.data.transform(sans_echelle.inverted() @ grip)
    scene.collection.objects.link(export)
    export.name = "SM_NPC_Spirit_Flute_EXPORT"
    export.parent = None
    export.matrix_world = Matrix.Identity(4)
    bpy.ops.object.select_all(action="DESELECT")
    export.select_set(True)
    bpy.context.view_layer.objects.active = export
    bpy.ops.export_scene.fbx(mesh_smooth_type="FACE", filepath=str(OUT / "SM_NPC_Spirit_Flute.fbx"),
                             use_selection=True, object_types={"MESH"},
                             bake_anim=False, path_mode="AUTO")
    bpy.data.objects.remove(export, do_unlink=True)


def save(scene, rig):
    # L'import FBX de la flute remet la cadence de la scene a 25 i/s : 181
    # images duraient alors 7,2 s dans Unreal au lieu de 6 (27/09).
    scene.render.fps, scene.render.fps_base = FPS, 1.0
    # The camera and lights come from the NPC standing reference blend.
    scene.frame_set(91)
    scene.render.filepath = str(OUT / (NAME + ".png"))
    bpy.ops.render.render(write_still=True)
    scene.frame_set(FIRST)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / (NAME + ".blend")))
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.fbx(mesh_smooth_type="FACE", filepath=str(OUT / (NAME + ".fbx")),
                             use_selection=True, object_types={"ARMATURE"},
                             add_leaf_bones=False, bake_anim=True,
                             bake_anim_use_all_bones=True,
                             bake_anim_use_nla_strips=False,
                             bake_anim_use_all_actions=False, bake_anim_step=1.0)


def main():
    if not FLUTE_SOURCE.is_file():
        if not FLUTE_ZIP.is_file():
            raise FileNotFoundError(FLUTE_ZIP)
        with zipfile.ZipFile(FLUTE_ZIP) as archive:
            member = "source/flute_FIN.fbx"
            if member not in archive.namelist():
                raise RuntimeError("Supplied flute ZIP does not contain " + member)
            FLUTE_SOURCE.parent.mkdir(parents=True, exist_ok=True)
            FLUTE_SOURCE.write_bytes(archive.read(member))
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE_BLEND))
    scene = bpy.context.scene
    rig = bpy.data.objects["Root"]
    scene.frame_set(FIRST)
    place_hands(scene, rig)
    make_loop(scene, rig)
    flute, triangles = import_flute()
    bind_flute(scene, rig, flute)
    save(scene, rig)
    metrics_path = OUT / "metrics.json"
    metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
    metrics[NAME] = {"source": "custom on Creative rig + CC BY flute by Tom Johnson",
                     "seconds": 6.0, "bones": 43, "root_motion": False,
                     "loop": True, "prop_triangles": triangles,
                     "attachment_bone": "RightHandProp"}
    metrics_path.write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    (OUT / "flute_attribution.json").write_text(json.dumps({
        "asset": "SM_NPC_Spirit_Flute",
        "source_title": "Zelda Spirit Flute",
        "author": "Tom Johnson (Brigyon)",
        "source_url": "https://sketchfab.com/3d-models/zelda-spirit-flute-9ba664e2efe54d3298a92d6c4ba1a576",
        "license": "CC Attribution (reported by user; verify on source page before release)",
        "modifications": "Reduced geometry, scaled to Creative, preserved palette, bound to RightHandProp",
    }, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
