"""Export two timed parts of the existing seated revolver animation.

Run with Steam Blender using seated_revolver.blend as the background project.
Frames 1-26 end at the temple; frames 26-48 start there and return to idle.
The take clip can hold its last pose using PlayAnimation blend_out_time=-1.
"""

from pathlib import Path
import bpy


out = Path("C:/Users/ingam/OneDrive/Documents/fate-games/art/animations")
body = bpy.data.objects.get("Root")
if body is None or body.type != "ARMATURE":
    raise RuntimeError("Root armature missing from seated_revolver.blend")

scene = bpy.context.scene
scene.render.fps = 30

for name, start, end in (
    ("seated_revolver_take", 1, 26),
    ("seated_revolver_fire", 26, 48),
):
    scene.frame_start = start
    scene.frame_end = end
    scene.frame_set(start)
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    target = out / f"{name}.fbx"
    bpy.ops.export_scene.fbx(
        filepath=str(target),
        use_selection=True,
        object_types={"ARMATURE"},
        add_leaf_bones=False,
        bake_anim=True,
        bake_anim_use_all_bones=True,
        bake_anim_use_nla_strips=False,
        bake_anim_use_all_actions=False,
        bake_anim_step=1.0,
    )
    print("EXPORTED", name, start, end, target)
