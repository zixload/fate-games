"""Chutes du personnage Creative : reception dure et chute a plat.

    blender -b --python scripts/blender/create_chutes.py

Meme chaine que les danses (create_dance_emotes.py) : les FBX Mixamo de
Downloads, sur les os du squelette Creative, sont recopies sur la reference
puis cuits. Sorties dans art/animations/chutes/ (hors depot).

- ANIM_Chute_Reception (Hard Landing) : commence a l'image 3, quand les pieds
  touchent presque le sol ; le debut en l'air est retire, le jeu la lance a
  l'impact.
- ANIM_Chute_Au_Sol (Falling Flat Impact) : commence a l'image 9, le corps a
  ~50 cm du sol, l'impact tombe a l'image 13. Allonge, il regarde a gauche
  puis a droite (REGARDS), puis la pose est tenue jusqu'a l'image 92
  (extrapolation constante des courbes) ; le relevement est le fondu de
  sortie joue en jeu, en attendant une animation "Getting Up".
Import : scripts/unreal/import_chutes.py.
"""

import json
from pathlib import Path

import bpy
from math import cos, pi, radians
from mathutils import Quaternion

ROOT = Path(__file__).resolve().parents[2]
DOWNLOADS = Path.home() / "Downloads"
REFERENCE = ROOT / "art/animations/seated_card_play.blend"
OUT = ROOT / "art/animations/chutes"
OUT.mkdir(parents=True, exist_ok=True)
FPS = 30
# fichier, asset, premiere image gardee, derniere image (None : la fin du clip)
CLIPS = (
    ("Hard Landing.fbx", "ANIM_Chute_Reception", 3, None),
    ("Falling Flat Impact.fbx", "ANIM_Chute_Au_Sol", 9, 92),
)

# Au sol, il regarde a gauche puis a droite ("quelqu'un m'a vu ?") avant de se
# relever : (image, angle en degres) ; la tete et le cou tournent autour de
# l'axe du cou (Y local des os Mixamo), 60 % pour la tete, 40 % pour le cou.
REGARDS = {"ANIM_Chute_Au_Sol": ((24, 0), (38, 60), (48, 60), (64, -60), (74, -60), (86, 0))}


def ease(t):
    return 0.5 - 0.5 * cos(pi * max(0.0, min(1.0, t)))


def angle_a(points, frame):
    if frame <= points[0][0] or frame >= points[-1][0]:
        return 0.0
    for (f0, a0), (f1, a1) in zip(points, points[1:]):
        if f0 <= frame <= f1:
            return a0 + (a1 - a0) * ease((frame - f0) / (f1 - f0))
    return 0.0


def regarder(scene, rig, points, fin):
    debut, dernier = points[0][0], points[-1][0]
    os_regard = (("Head", 0.6), ("Neck", 0.4))
    # Les poses d'origine d'abord : une fois une cle posee, l'image suivante
    # (au-dela de la fin du clip) repartirait de la rotation deja ajoutee.
    base = {}
    for frame in range(debut, dernier + 1):
        scene.frame_set(frame)
        base[frame] = {nom: rig.pose.bones[nom].rotation_quaternion.copy() for nom, _ in os_regard}
    for frame in range(debut, dernier + 1):
        a = angle_a(points, frame)
        for nom, part in os_regard:
            bone = rig.pose.bones[nom]
            bone.rotation_mode = "QUATERNION"
            bone.rotation_quaternion = base[frame][nom] @ Quaternion((0, 1, 0), radians(a * part))
            bone.keyframe_insert("rotation_quaternion", frame=frame)

metrics = {}
for filename, asset, debut, fin in CLIPS:
    source_file = DOWNLOADS / filename
    if not source_file.is_file():
        raise FileNotFoundError(source_file)
    bpy.ops.wm.open_mainfile(filepath=str(REFERENCE))
    scene = bpy.context.scene
    scene.render.fps = FPS
    creative = bpy.data.objects["Root"]
    bpy.ops.import_scene.fbx(filepath=str(source_file), use_anim=True)
    source = next(obj for obj in bpy.context.selected_objects if obj.type == "ARMATURE")
    action = source.animation_data.action
    first, last = (int(round(v)) for v in action.frame_range)
    if set(creative.pose.bones.keys()) != set(source.pose.bones.keys()) - {"Root"}:
        raise RuntimeError("Les os ne correspondent pas au squelette Creative : " + filename)

    if creative.animation_data:
        creative.animation_data_clear()
    for bone in creative.pose.bones:
        c = bone.constraints.new("COPY_TRANSFORMS")
        c.target = source
        c.subtarget = bone.name
        c.target_space = "WORLD"
        c.owner_space = "WORLD"
    scene.frame_start, scene.frame_end = first, last
    bpy.ops.object.select_all(action="DESELECT")
    creative.select_set(True)
    bpy.context.view_layer.objects.active = creative
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.nla.bake(frame_start=first, frame_end=last, step=1, only_selected=False,
                     visual_keying=True, clear_constraints=True, use_current_action=False,
                     bake_types={"POSE"})
    bpy.ops.object.mode_set(mode="OBJECT")
    creative.animation_data.action.name = asset
    for fc in creative.animation_data.action.fcurves if hasattr(creative.animation_data.action, "fcurves") else []:
        fc.extrapolation = "CONSTANT"

    if asset in REGARDS:
        regarder(scene, creative, REGARDS[asset], fin)

    # Plage exportee : on coupe le debut, et on tient la derniere pose.
    scene.frame_start = debut
    scene.frame_end = fin or last
    scene.frame_set(scene.frame_start)
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
        bake_anim_use_all_actions=False, bake_anim_step=1.0,
        bake_anim_force_startend_keying=True)
    metrics[asset] = {"source": filename, "frames": [scene.frame_start, scene.frame_end],
                      "seconds": round((scene.frame_end - scene.frame_start) / FPS, 4)}
    print("CHUTE_PRETE", asset, json.dumps(metrics[asset]))

(OUT / "metrics.json").write_text(json.dumps(metrics, indent=2), encoding="utf-8")
