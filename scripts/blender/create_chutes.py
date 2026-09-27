"""Chutes du personnage Creative : reception dure et chute a plat.

    blender -b --python scripts/blender/create_chutes.py

Meme chaine que les danses (create_dance_emotes.py) : les FBX Mixamo de
Downloads, sur les os du squelette Creative, sont recopies sur la reference
puis cuits. Sorties dans art/animations/chutes/ (hors depot).

- ANIM_Chute_Reception (Hard Landing) : commence a l'image 3, quand les pieds
  touchent presque le sol ; le debut en l'air est retire, le jeu la lance a
  l'impact.
- ANIM_Chute_Au_Sol (Falling Flat Impact) : commence a l'image 1, 0,4 s
  avant l'impact (image 13) : le corps bascule vers l'avant en l'air
  (EN_L_AIR), le jeu la lance 0,4 s avant de toucher le sol. Allonge, il regarde a gauche
  puis a droite (REGARDS), puis la pose est tenue jusqu'a l'image 92
  (extrapolation constante des courbes), puis il se releve (Getting Up,
  RELEVER), le tout dans le meme clip.
Import : scripts/unreal/import_chutes.py.
"""

import json
from pathlib import Path

import bpy
from math import cos, pi, radians
from mathutils import Quaternion, Vector

ROOT = Path(__file__).resolve().parents[2]
DOWNLOADS = Path.home() / "Downloads"
REFERENCE = ROOT / "art/animations/seated_card_play.blend"
OUT = ROOT / "art/animations/chutes"
OUT.mkdir(parents=True, exist_ok=True)
FPS = 30
# fichier, asset, premiere image gardee, derniere image (None : la fin du clip)
CLIPS = (
    ("Hard Landing.fbx", "ANIM_Chute_Reception", 3, None),
    ("Falling Flat Impact.fbx", "ANIM_Chute_Au_Sol", 1, 42),
)

# Au sol, il regarde a gauche puis a droite ("quelqu'un m'a vu ?") avant de se
# relever : (image, angle en degres) ; la tete et le cou tournent autour de
# l'axe du cou (Y local des os Mixamo), 60 % pour la tete, 40 % pour le cou.
# ~1 s au sol (27/09 : 3 s, c'etait long) : un coup d'oeil rapide des deux cotes.
REGARDS = {"ANIM_Chute_Au_Sol": ((16, 0), (22, 55), (26, 55), (33, -55), (36, -55), (41, 0))}


def hanches(rig):
    return rig.matrix_world @ rig.pose.bones["Hips"].head


def relever(scene, creative, r, fin):
    """Ajoute le relevement apres l'image `fin` ; rend la nouvelle fin."""
    depart = fin + 1
    duree = r["fin"] - r["debut"]
    nouvelle_fin = depart + duree

    # La pose allongee a raccorder, os par os (valeurs locales).
    scene.frame_set(fin)
    allonge = {b.name: (b.location.copy(), b.rotation_quaternion.copy()) for b in creative.pose.bones}
    hanches_fin = hanches(creative).copy()

    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.import_scene.fbx(filepath=str(DOWNLOADS / r["fichier"]), use_anim=True)
    source = next(o for o in bpy.context.selected_objects if o.type == "ARMATURE")
    action = source.animation_data.action
    source.animation_data.action = None
    piste = source.animation_data.nla_tracks.new()
    bande = piste.strips.new("relever", depart, action)
    bande.action_frame_start, bande.action_frame_end = r["debut"], r["fin"]
    bande.frame_start, bande.frame_end = depart, nouvelle_fin
    scene.frame_set(depart)
    ecart = hanches_fin - hanches(source)
    source.location += Vector((ecart.x, ecart.y, 0))
    bpy.context.view_layer.update()

    for bone in creative.pose.bones:
        c = bone.constraints.new("COPY_TRANSFORMS")
        c.target = source
        c.subtarget = bone.name
        c.target_space = "WORLD"
        c.owner_space = "WORLD"
    bpy.ops.object.select_all(action="DESELECT")
    creative.select_set(True)
    bpy.context.view_layer.objects.active = creative
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.nla.bake(frame_start=depart, frame_end=nouvelle_fin, step=1, only_selected=False,
                     visual_keying=True, clear_constraints=True, use_current_action=True,
                     bake_types={"POSE"})
    bpy.ops.object.mode_set(mode="OBJECT")

    # Fondu depuis la pose allongee : pas de saut a la jointure.
    for frame in range(depart, depart + r["fondu"]):
        t = ease((frame - fin) / (r["fondu"] + 1))
        scene.frame_set(frame)
        for bone in creative.pose.bones:
            loc, rot = allonge[bone.name]
            bone.location = loc.lerp(bone.location, t)
            bone.rotation_quaternion = rot.slerp(bone.rotation_quaternion, t)
            bone.keyframe_insert("location", frame=frame)
            bone.keyframe_insert("rotation_quaternion", frame=frame)

    # L'avancee du relevement retiree peu a peu : debout, le bassin revient
    # au-dessus de sa place de repos (celle du personnage debout).
    repos = creative.matrix_world @ creative.data.bones["Hips"].head_local
    scene.frame_set(nouvelle_fin)
    derive = hanches(creative) - repos
    derive.z = 0
    debut_correction = depart + r["fondu"]
    for frame in range(debut_correction, nouvelle_fin + 1):
        scene.frame_set(frame)
        alpha = ease((frame - debut_correction) / (nouvelle_fin - debut_correction))
        bone = creative.pose.bones["Hips"]
        local = creative.matrix_world.to_3x3().inverted() @ (-derive * alpha)
        m = bone.matrix.copy()
        m.translation += local
        bone.matrix = m
        bpy.context.view_layer.update()
        bone.keyframe_insert("location", frame=frame)
    scene.frame_set(nouvelle_fin)
    reste = hanches(creative) - repos
    print("CHUTE_RELEVER", "images", depart, nouvelle_fin, "ecart_depart_cm", round(ecart.length * 100, 1),
          "derive_retiree_cm", round(derive.length * 100, 1),
          "reste_cm", round(Vector((reste.x, reste.y)).length * 100, 1))
    source.hide_render = True
    for child in source.children_recursive:
        child.hide_render = True
    return nouvelle_fin


# Puis il se releve (Getting Up, Mixamo), colle a la suite dans le meme clip :
# de GU_DEBUT a GU_FIN du clip source (le debut immobile et la fin debout sont
# coupes), place juste apres la derniere image de la chute, fondu de FONDU
# images depuis la pose allongee. Il commence allonge sur le ventre, tete du
# meme cote que la fin de la chute : seul le bassin est recale en XY. Son
# avancee est retiree peu a peu pour qu'il finisse debout a sa place.
# En l'air, le corps bascule a l'horizontale pendant les 12 images avant
# l'impact (image 13). Dans le clip source il descend aussi de 1,5 m : en jeu
# le personnage chute deja, le corps flotterait. Le bassin est donc recale de
# BASSIN_DEPART (hauteur debout) jusqu'a sa hauteur a l'impact : le corps
# chute avec le personnage et touche le sol pile a l'image 13.
EN_L_AIR = {"ANIM_Chute_Au_Sol": {"impact": 13, "depart": 0.75}}


def recaler_en_l_air(scene, rig, r, debut):
    impact = r["impact"]
    scene.frame_set(impact)
    z_impact = hanches(rig).z
    for frame in range(debut, impact):
        scene.frame_set(frame)
        voulu = r["depart"] + (z_impact - r["depart"]) * ease((frame - debut) / (impact - debut))
        bone = rig.pose.bones["Hips"]
        delta = rig.matrix_world.to_3x3().inverted() @ Vector((0, 0, voulu - hanches(rig).z))
        m = bone.matrix.copy()
        m.translation += delta
        bone.matrix = m
        bpy.context.view_layer.update()
        bone.keyframe_insert("location", frame=frame)
    print("CHUTE_EN_L_AIR", "images", debut, impact, "bassin", r["depart"], "->", round(z_impact, 3))


RELEVER = {"ANIM_Chute_Au_Sol": {"fichier": "Getting Up.fbx", "debut": 30, "fin": 185, "fondu": 8}}


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

    if asset in EN_L_AIR:
        recaler_en_l_air(scene, creative, EN_L_AIR[asset], debut)
    if asset in REGARDS:
        regarder(scene, creative, REGARDS[asset], fin)
    if asset in RELEVER:
        fin = relever(scene, creative, RELEVER[asset], fin)

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
