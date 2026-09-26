"""Read the current Liar's Bar furniture layout without changing MapEgypt."""

import unreal


MAP = "/Game/MyAssetPack/MapEgypt"
if not unreal.EditorLevelLibrary.load_level(MAP):
    raise RuntimeError(f"Could not open {MAP}")

for actor in unreal.EditorLevelLibrary.get_all_level_actors():
    loc = actor.get_actor_location()
    if not (-3650 < loc.x < -3200 and -230 < loc.y < 270 and 250 < loc.z < 550):
        continue
    mesh = None
    for component in actor.get_components_by_class(unreal.StaticMeshComponent):
        asset = component.get_editor_property("static_mesh")
        if asset:
            mesh = asset.get_path_name()
            break
    rot = actor.get_actor_rotation()
    scale = actor.get_actor_scale3d()
    bounds = actor.get_actor_bounds(False)
    print("FURNITURE_ACTOR", actor.get_actor_label(), actor.get_class().get_name(),
          tuple(round(v, 2) for v in (loc.x, loc.y, loc.z)),
          tuple(round(v, 2) for v in (rot.pitch, rot.yaw, rot.roll)),
          tuple(round(v, 3) for v in (scale.x, scale.y, scale.z)), mesh,
          "hidden", actor.get_editor_property("hidden"),
          "extent", tuple(round(v, 2) for v in (bounds[1].x, bounds[1].y, bounds[1].z)))
