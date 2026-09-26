"""Print seated rig landmarks and Nagant bounds for grip alignment."""

from pathlib import Path
import bpy


ROOT = Path("C:/Users/ingam/OneDrive/Documents/fate-games")
bpy.ops.wm.open_mainfile(filepath=str(ROOT / "art/animations/seated_revolver.blend"))
body = next(obj for obj in bpy.data.objects if obj.type == "ARMATURE")

bpy.ops.import_scene.fbx(filepath="C:/nanos-adk/Saved/CodexAnimation/nagant.fbx")
guns = [obj for obj in bpy.context.selected_objects if obj.type == "MESH"]
for gun in guns:
    bounds = [gun.matrix_world @ __import__("mathutils").Vector(corner) for corner in gun.bound_box]
    print("GUN", gun.name, "location", tuple(round(v, 4) for v in gun.location),
          "dimensions", tuple(round(v, 4) for v in gun.dimensions))
    for axis in range(3):
        print("GUN_BOUNDS", axis, round(min(v[axis] for v in bounds), 4),
              round(max(v[axis] for v in bounds), 4))
    if gun.name == "SM_Nagant_M1895":
        for lo, hi in ((-.12, -.08), (-.08, -.04), (-.04, 0), (0, .04), (.04, .08), (.08, .12)):
            section = [v.co for v in gun.data.vertices if lo <= (gun.matrix_world @ v.co).y < hi]
            if section:
                print("GUN_SECTION", lo, hi, len(section),
                      "x", tuple(round(v, 4) for v in (min(p.x for p in section), max(p.x for p in section))),
                      "z", tuple(round(v, 4) for v in (min(p.z for p in section), max(p.z for p in section))))

for frame in (1, 10, 23, 28, 31, 48):
    bpy.context.scene.frame_set(frame)
    print("FRAME", frame)
    for name in ("RightHand", "RightHandProp", "RightHandIndex1", "RightHandIndex2",
                 "RightHandMiddle1", "RightHandMiddle2", "RightHandRing1", "RightHandPinky1",
                 "RightHandThumb1", "Head"):
        bone = body.pose.bones[name]
        print("BONE", name, "head", tuple(round(v, 4) for v in body.matrix_world @ bone.head),
              "tail", tuple(round(v, 4) for v in body.matrix_world @ bone.tail))
        if frame == 23 and name == "RightHandProp":
            matrix = body.matrix_world @ bone.matrix
            print("PROP_AXES", tuple(tuple(round(v, 4) for v in matrix.to_3x3() @ __import__("mathutils").Vector(axis))
                                     for axis in ((1, 0, 0), (0, 1, 0), (0, 0, 1))))
    if frame == 23:
        depsgraph = bpy.context.evaluated_depsgraph_get()
        mesh = next(o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith("SK_Animations"))
        evaluated = mesh.evaluated_get(depsgraph)
        vertices = [evaluated.matrix_world @ vertex.co for vertex in evaluated.to_mesh().vertices]
        for z0, z1 in ((1.43, 1.48), (1.48, 1.53), (1.53, 1.58), (1.58, 1.63)):
            face = [v for v in vertices if z0 <= v.z < z1 and -.38 < v.y < -.08]
            print("HEAD_SLICE", z0, z1, "x", round(min(v.x for v in face), 4),
                  round(max(v.x for v in face), 4), "y", round(min(v.y for v in face), 4),
                  round(max(v.y for v in face), 4))
