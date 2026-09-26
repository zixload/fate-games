"""Read the duel arenas placed in MapEgypt and write them for the game.

In the ADK, with MapEgypt open: place one Cube (a rectangular arena, best
for a room) or one Cylinder (a round one) per arena, from Place Actors >
Shapes. Scale it to the room, rotate it so its X axis runs from one camp to
the other, and name it DUEL_1, DUEL_2... Optionally add one small shape per
camp where its fighters appear, named DUEL_1_A and DUEL_1_B: its bottom is the
floor, and each camp faces the other. Then, in the Output Log (Python):
    exec(open(r"C:/Users/ingam/OneDrive/Documents/fate-games/scripts/unreal/export_arenes.py").read())
The shapes are set hidden in game and without collision (save the map,
then cook). Their shape, centre, half sizes, floor height and yaw go to
Packages/fate-games/Server/games/duel/data/arenes.lua.
"""

from pathlib import Path
import re
import unreal


OUT = Path("C:/Users/ingam/OneDrive/Documents/fate-games/Packages/fate-games/Server/games/duel/data/arenes.lua")

actors = unreal.get_editor_subsystem(unreal.EditorActorSubsystem).get_all_level_actors()
arenes = []
departs = {}                                  # ("DUEL_1", "A") -> (x, y, z)
for actor in actors:
    label = actor.get_actor_label().upper()
    spawn = re.fullmatch(r"(DUEL_\d+)_([AB])", label)
    if spawn:
        origin, extent = actor.get_actor_bounds(False)
        departs[(spawn.group(1), spawn.group(2))] = (round(origin.x), round(origin.y), round(origin.z - extent.z))
        actor.set_actor_hidden_in_game(True)
        actor.set_actor_enable_collision(False)
        continue
    if not re.fullmatch(r"DUEL_\d+", label):
        continue
    origin, extent = actor.get_actor_bounds(False)
    rot = actor.get_actor_rotation()
    scale = actor.get_actor_scale3d()
    # Half sizes in the shape's own frame (world bounds grow when rotated).
    comp = actor.get_component_by_class(unreal.StaticMeshComponent)
    mesh = comp.get_editor_property("static_mesh") if comp else None
    local = mesh.get_bounds().box_extent if mesh else unreal.Vector(50, 50, 50)
    rond = mesh is not None and "cylinder" in mesh.get_name().lower()
    arenes.append({
        "nom": label,
        "forme": "cercle" if rond else "boite",
        "x": round(origin.x), "y": round(origin.y),
        "z": round(origin.z - extent.z),          # the floor: bottom of the shape
        "demi_x": round(local.x * abs(scale.x)),
        "demi_y": round(local.y * abs(scale.y)),
        "yaw": round(rot.yaw),
    })
    actor.set_actor_hidden_in_game(True)
    actor.set_actor_enable_collision(False)

arenes.sort(key=lambda a: a["nom"])
for a in arenes:
    for camp in ("A", "B"):
        d = departs.get((a["nom"], camp))
        a["depart_" + camp.lower()] = "{{ x = {}, y = {}, z = {} }}".format(*d) if d else "nil"

lines = [
    "-- Arenes du duel, generees par scripts/unreal/export_arenes.py depuis",
    "-- les formes DUEL_* de MapEgypt. Ne pas editer a la main : deplacer",
    "-- la forme dans l'ADK et relancer le script.",
    "return {",
]
for a in arenes:
    lines.append('    {{ nom = "{nom}", forme = "{forme}", x = {x}, y = {y}, z = {z}, demi_x = {demi_x}, demi_y = {demi_y}, yaw = {yaw},'.format(**a))
    lines.append('      depart_a = {depart_a}, depart_b = {depart_b} }},'.format(**a))
lines.append("}")
OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")

for a in arenes:
    unreal.log("Arenes: {nom} {forme} centre ({x}, {y}, {z}) demi {demi_x} x {demi_y} yaw {yaw}, departs A {depart_a} B {depart_b}".format(**a))
if not arenes:
    unreal.log_warning("Arenes: aucun acteur nomme DUEL_* dans le niveau ouvert")
unreal.log(f"Arenes: {len(arenes)} arene(s) ecrite(s) dans {OUT}. Sauvegarde la map puis cuis.")
