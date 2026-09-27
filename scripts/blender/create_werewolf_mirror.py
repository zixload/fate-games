"""Pose assise du loup-garou en miroir : ANIM_WW_Sitting_Idle inversee
gauche/droite, exportee en ANIM_WW_Sitting_Idle_Mirror.

    blender -b --python scripts/blender/create_werewolf_mirror.py

Part du .blend ajuste dans art/werewolf/ (hors depot) et y ecrit le .blend et
le .fbx du miroir. Chaque image est copiee puis collee inversee (Pose > Paste
Flipped), les os Left/Right echangeant leurs poses. Seule l'animation est
inversee : le regard des joueurs assis est ajoute en jeu par-dessus
(LookNeck/LookHead, Client/vue_assise.lua) et garde son sens.
Import : scripts/unreal/import_werewolf_mirror.py.
"""

from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art/werewolf"
SOURCE = "ANIM_WW_Sitting_Idle"
NAME = "ANIM_WW_Sitting_Idle_Mirror"
FPS = 30

bpy.ops.wm.open_mainfile(filepath=str(OUT / f"{SOURCE}.blend"))
scene = bpy.context.scene
scene.render.fps = FPS
rig = bpy.data.objects["Root"]
first, last = scene.frame_start, scene.frame_end

source = rig.animation_data.action
mirror = source.copy()
mirror.name = NAME


def use(action):
    rig.animation_data.action = action
    if hasattr(rig.animation_data, "action_slot") and getattr(action, "slots", None):
        rig.animation_data.action_slot = action.slots[0]


def feet():
    m = rig.matrix_world
    return {n: (m @ rig.pose.bones[n].head).copy() for n in ("LeftFoot", "RightFoot", "Hips")}


bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="POSE")

use(source)
scene.frame_set(first)
avant = feet()

for frame in range(first, last + 1):
    use(source)
    scene.frame_set(frame)
    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.pose.copy()
    use(mirror)
    scene.frame_set(frame)
    bpy.ops.pose.paste(flipped=True)
    bpy.context.view_layer.update()
    for bone in rig.pose.bones:
        bone.keyframe_insert("location", frame=frame)
        mode = bone.rotation_mode
        bone.keyframe_insert("rotation_quaternion" if mode == "QUATERNION" else "rotation_euler", frame=frame)

bpy.ops.object.mode_set(mode="OBJECT")
use(mirror)
scene.frame_set(first)
apres = feet()

# Controle : le pied gauche du miroir est la ou etait le pied droit, en
# symetrie par rapport au plan median (axe X du monde, le personnage regarde
# le long de Y), et le bassin ne s'est pas deplace de cote.
hx = avant["Hips"].x
ecart_g = abs((apres["LeftFoot"].x - hx) + (avant["RightFoot"].x - hx)) * 100
ecart_d = abs((apres["RightFoot"].x - hx) + (avant["LeftFoot"].x - hx)) * 100
bassin = abs(apres["Hips"].x - avant["Hips"].x) * 100
print("WW_MIRROR_CHECK_CM", "pied_gauche", round(ecart_g, 2), "pied_droit", round(ecart_d, 2),
      "bassin", round(bassin, 2))
if max(ecart_g, ecart_d, bassin) > 2:
    raise RuntimeError("miroir incoherent : voir WW_MIRROR_CHECK_CM")

bpy.ops.wm.save_as_mainfile(filepath=str(OUT / f"{NAME}.blend"))
bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.fbx(
    filepath=str(OUT / f"{NAME}.fbx"), use_selection=True,
    object_types={"ARMATURE"}, add_leaf_bones=False, bake_anim=True,
    bake_anim_use_all_bones=True, bake_anim_use_nla_strips=False,
    bake_anim_use_all_actions=False, bake_anim_step=1.0,
)
print("WW_MIRROR", NAME, "frames", first, last, "seconds", round((last - first) / FPS, 4))
