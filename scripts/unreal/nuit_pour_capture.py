r"""Met la map ouverte de nuit pour une capture, puis remet tout comme avant.

A executer dans la console Python de l'editeur (NanosWorldADK), la map ouverte :

    exec(open(r"C:\Users\ingam\OneDrive\Documents\fate-games\scripts\unreal\nuit_pour_capture.py", encoding="utf-8").read())

Premier lancement : note l'eclairage actuel (soleil, ciel, brouillard,
exposition) dans Saved/nuit_capture.json, puis passe en nuit : soleil sous
l'horizon, lumiere de lune bleutee, ciel et brouillard assombris, exposition
fixe. Second lancement : remet exactement les valeurs notees et efface le
fichier. Ne rien sauvegarder de nuit (sinon la map cuite resterait de nuit).

Capture 4K ensuite, dans la barre Cmd de l'Output Log :  HighResShot 3840x2160
(image dans C:\nanos-adk\Saved\Screenshots\WindowsEditor\).
"""

import json
from pathlib import Path

import unreal

FICHIER = Path(unreal.Paths.project_saved_dir()) / "nuit_capture.json"
acteurs = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
tous = acteurs.get_all_level_actors()


def premier(classe):
    return [a for a in tous if isinstance(a, classe)]


def composant(acteur, classe):
    c = acteur.get_components_by_class(classe)
    return c[0] if c else None


soleils = premier(unreal.DirectionalLight)
ciels = premier(unreal.SkyLight)
brumes = premier(unreal.ExponentialHeightFog)
volumes = premier(unreal.PostProcessVolume)

if FICHIER.is_file():
    # ---------------------------------------------------------------- retour au jour
    note = json.loads(FICHIER.read_text(encoding="utf-8"))
    for a in soleils:
        n = note["soleils"].get(a.get_path_name())
        if n:
            a.set_actor_rotation(unreal.Rotator(*n["rotation"]), False)
            c = composant(a, unreal.DirectionalLightComponent)
            c.set_intensity(n["intensite"])
            c.set_light_color(unreal.LinearColor(*n["couleur"]))
    for a in ciels:
        n = note["ciels"].get(a.get_path_name())
        if n:
            c = composant(a, unreal.SkyLightComponent)
            c.set_intensity(n)
            c.recapture_sky()
    for a in brumes:
        n = note["brumes"].get(a.get_path_name())
        if n:
            c = composant(a, unreal.ExponentialHeightFogComponent)
            c.set_fog_density(n["densite"])
            c.set_fog_inscattering_color(unreal.LinearColor(*n["couleur"]))
    for a in volumes:
        n = note["volumes"].get(a.get_path_name())
        if n is not None:
            s = a.get_editor_property("settings")
            s.set_editor_property("override_auto_exposure_bias", n["exposition_active"])
            s.set_editor_property("auto_exposure_bias", n["exposition"])
            a.set_editor_property("settings", s)
    FICHIER.unlink()
    print("NUIT_CAPTURE jour remis (valeurs d'origine)")
else:
    # ---------------------------------------------------------------- passage en nuit
    note = {"soleils": {}, "ciels": {}, "brumes": {}, "volumes": {}}
    for a in soleils:
        c = composant(a, unreal.DirectionalLightComponent)
        r = a.get_actor_rotation()
        col = c.get_editor_property("light_color")
        note["soleils"][a.get_path_name()] = {
            "rotation": [r.roll, r.pitch, r.yaw], "intensite": c.get_editor_property("intensity"),
            "couleur": [col.r / 255.0, col.g / 255.0, col.b / 255.0, 1.0]}
        # Lune : haute, faible, bleutee (la lumiere garde ses ombres).
        a.set_actor_rotation(unreal.Rotator(r.roll, -35.0, r.yaw + 140.0), False)
        c.set_intensity(0.6)
        c.set_light_color(unreal.LinearColor(0.55, 0.65, 1.0, 1.0))
    for a in ciels:
        c = composant(a, unreal.SkyLightComponent)
        note["ciels"][a.get_path_name()] = c.get_editor_property("intensity")
        c.set_intensity(0.15)
        c.recapture_sky()
    for a in brumes:
        c = composant(a, unreal.ExponentialHeightFogComponent)
        col = c.get_editor_property("fog_inscattering_luminance")
        note["brumes"][a.get_path_name()] = {"densite": c.get_editor_property("fog_density"),
                                              "couleur": [col.r, col.g, col.b, col.a]}
        c.set_fog_density(c.get_editor_property("fog_density") * 0.5)
        c.set_fog_inscattering_color(unreal.LinearColor(0.02, 0.03, 0.07, 1.0))
    for a in volumes:
        s = a.get_editor_property("settings")
        note["volumes"][a.get_path_name()] = {"exposition_active": s.get_editor_property("override_auto_exposure_bias"),
                                               "exposition": s.get_editor_property("auto_exposure_bias")}
        s.set_editor_property("override_auto_exposure_bias", True)
        s.set_editor_property("auto_exposure_bias", -0.5)
        a.set_editor_property("settings", s)
    FICHIER.write_text(json.dumps(note, indent=1), encoding="utf-8")
    print("NUIT_CAPTURE nuit posee :", len(soleils), "soleil(s),", len(ciels), "ciel(s),", len(brumes),
          "brouillard(s),", len(volumes), "volume(s) post-process. Relancer le script pour remettre le jour.")
