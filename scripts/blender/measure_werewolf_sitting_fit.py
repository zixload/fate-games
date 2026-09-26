"""Measure deformed Creative proxy contact surfaces through each entire loop."""

from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art/werewolf"
for short, clip, offset in (
    ("idle", "ANIM_WW_Sitting_Idle", .110),
    ("lazy", "ANIM_WW_Sitting_Idle_Lazy", .128),
    ("dazed", "ANIM_WW_Sitting_Dazed", .116),
):
    bpy.ops.wm.open_mainfile(filepath=str(OUT / (clip + ".blend")))
    scene = bpy.context.scene
    parent = bpy.data.objects["SK_Animations"]
    parent.scale = (.008, .008, .008)
    parent.location.z = offset
    proxy = bpy.data.objects["SK_Animations.001"]
    indices = {n: proxy.vertex_groups[n].index for n in
               ("Hips", "LeftFoot", "RightFoot") if n in proxy.vertex_groups}
    print("GROUPS", short, indices)
    frame_values = []
    for frame in range(scene.frame_start, scene.frame_end + 1, 5):
        scene.frame_set(frame)
        depsgraph = bpy.context.evaluated_depsgraph_get()
        obj = proxy.evaluated_get(depsgraph)
        mesh = obj.to_mesh()
        points = {}
        for name, index in indices.items():
            matches = [(obj.matrix_world @ vert.co)
                       for vert in mesh.vertices
                       if any(g.group == index and g.weight > .35 for g in vert.groups)]
            if matches:
                lowest = min(matches, key=lambda p: p.z)
                points[name] = tuple(round(v,4) for v in lowest)
        obj.to_mesh_clear()
        frame_values.append((frame, points))
    for name in indices:
        values = [(frame, p[name]) for frame,p in frame_values if name in p]
        if values:
            print("CONTACT", short, name,
                  "z_cm_range", round(min(v[2] for _,v in values)*100,2),
                  round(max(v[2] for _,v in values)*100,2),
                  "start", values[0], "middle", values[len(values)//2])
