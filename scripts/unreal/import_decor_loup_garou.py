"""Importe les decors du loup-garou et la carte de role dans l'ADK.

A executer dans la console Python de l'editeur (NanosWorldADK) :

    exec(open(r"C:\\Users\\ingam\\OneDrive\\Documents\\fate-games\\scripts\\unreal\\import_decor_loup_garou.py", encoding="utf-8").read())

Avant : python scripts/unreal/preparer_decor_loup_garou.py (FBX et textures
ranges dans art/werewolf/decor/<Nom>/), et pour la carte
blender -b --python scripts/blender/create_carte_role.py.

Chaque decor devient my-asset-pack::SM_WW_<Nom>, avec ses materiaux construits
a partir de ses vraies textures (couleur, normale, rugosite, metal, emissif,
opacite ; les cartes Unity MetallicSmoothness sont converties). Rien n'est
place dans la map : poser les decors a la main autour du repere du cercle
(scripts/unreal/repere_cercle_loup_garou.py), puis cuire my-asset-pack.
Attendre WW_DECOR_COMPLETE dans l'Output Log.
"""

from pathlib import Path
import unreal

ROOT = Path("C:/Users/ingam/OneDrive/Documents/fate-games")
SOURCE = ROOT / "art/werewolf/decor"
DEST = "/Game/MyAssetPack/Werewolf/Decor"
CARTES_IMG = ROOT / "Packages/fate-games/Client/loup_garou/img"
TOOLS = unreal.AssetToolsHelpers.get_asset_tools()
LIB = unreal.EditorAssetLibrary
MEL = unreal.MaterialEditingLibrary
MP = unreal.MaterialProperty


# Par decor : echelle a l'import (les FBX Sketchfab ont des unites farfelues,
# mesurees dans Blender) et, par emplacement de materiau (nom normalise :
# minuscules, sans espaces ni tirets), ses textures.
#   base, normal, rough, metal, emissive, opacity : fichiers de textures/
#   metal_smooth : carte Unity (metal en R, lissage en A)
#   verre : materiau translucide ; couleur : teinte constante (0-1)
DECORS = [
    {"nom": "Lantern", "echelle": 0.2, "collision": "exacte", "materiaux": {
        "lantern": {"base": "braziers_lantern_BaseColor.png", "normal": "braziers_lantern_Normal.png",
                    "rough": "braziers_lantern_Roughness.png", "metal": "braziers_lantern_Metallic.png"},
        "glass": {"verre": True, "couleur": (1.0, 0.72, 0.38), "emissif": 3.0},
    }},
    {"nom": "Campfire", "echelle": 1.0, "materiaux": {
        m.lower(): {"base": f"CfWood_{m}_AlbedoTransparency.png", "normal": f"CfWood_{m}_Normal.png",
                    "metal_smooth": f"CfWood_{m}_MetallicSmoothness.png", "emissive": f"CfWood_{m}_Emission.png"}
        for m in ("Ash", "Stone", "Wood")
    }},
    {"nom": "CrystalBall", "echelle": 0.1, "collision": "exacte", "materiaux": {
        "01default": {"base": "Stand.jpg"},
        "02default": {"base": "Stand2.jpg"},
        "07default": {"base": "Mist.png", "verre": True, "emissif": 1.5},
        "08default": {"verre": True, "couleur": (0.75, 0.82, 1.0)},
    }},
    {"nom": "CrystalBallTable", "echelle": 50.0, "collision": "exacte", "materiaux": {
        "mglass": {"base": "crystalball_table_m_glass_BaseColor.png", "normal": "crystalball_table_m_glass_Normal.png",
                   "rough": "crystalball_table_m_glass_Roughness.png", "emissive": "crystalball_table_m_glass_Emissive.png",
                   "opacity": "crystalball_table_m_glass_Opacity.png", "verre": True},
        "mwood": {"base": "crystalball_table_m_wood_BaseColor.png", "normal": "crystalball_table_m_wood_Normal.png",
                  "rough": "crystalball_table_m_wood_Roughness.png"},
    }},
    {"nom": "HuntingRifle", "echelle": 0.1, "materiaux": {
        "rifle": {"base": "Rifle.png"},
        "bullet": {"base": "Bullet.png"},
        "m2material0": {"base": "Rifle.png"},
    }},
    {"nom": "Candles", "echelle": 0.01, "materiaux": {
        "candlematerial": {"base": "Candle.jpeg"},
        "platematerial": {"base": "Clay Texture.jpeg"},
        "wickmaterial": {"base": "Wick Texture.png"},
    }},
    # Decor du tailleur : la cabine de Club Penguin Island (OBJ en metres, ~6 m
    # de large ; a l echelle 1 il sortait a 6 cm, 27/09). Pas de .mtl dans le zip :
    # materiaux relies par leur nom (usemtl).
    {"nom": "ClothingCustomizer", "echelle": 100.0, "collision": "exacte", "materiaux": {
        "clothingdesignerstatic": {"base": "ClothingDesigner.png"},
        "catalogchallengecurtains": {"base": "CatalogChallengeCurtain.png"},
        "lighteffects": {"verre": True, "couleur": (1.0, 0.95, 0.8), "emissif": 2.0},
    }},
]


def normaliser(nom):
    return "".join(c for c in str(nom).lower() if c.isalnum())


def importer(fichier, nom, dossier, options=None):
    if not Path(fichier).is_file():
        raise FileNotFoundError(fichier)
    task = unreal.AssetImportTask()
    task.filename = str(fichier)
    task.destination_path = dossier
    task.destination_name = nom
    task.automated = True
    task.save = True
    task.replace_existing = True
    if options is not None:
        task.options = options
        task.factory = unreal.FbxFactory()
    TOOLS.import_asset_tasks([task])
    if not task.imported_object_paths:
        raise RuntimeError(f"Import rate : {fichier}")
    return LIB.load_asset(f"{dossier}/{nom}")


def texture(dossier_src, fichier, dossier, lineaire=False, normale=False):
    nom = "T_WW_" + normaliser(Path(fichier).stem)
    obj = importer(dossier_src / "textures" / fichier, nom, dossier)
    if normale:
        obj.set_editor_property("compression_settings", unreal.TextureCompressionSettings.TC_NORMALMAP)
        obj.set_editor_property("srgb", False)
    elif lineaire:
        obj.set_editor_property("compression_settings", unreal.TextureCompressionSettings.TC_MASKS)
        obj.set_editor_property("srgb", False)
    LIB.save_loaded_asset(obj)
    return obj


def materiau(nom, dossier, dossier_src, spec):
    chemin = f"{dossier}/{nom}"
    # does_asset_exist d'abord : load_asset sur un materiau absent ecrit une
    # « Error: LoadAsset failed » dans le journal (et une notification), sans gravite.
    obj = LIB.load_asset(chemin) if LIB.does_asset_exist(chemin) else \
        TOOLS.create_asset(nom, dossier, unreal.Material, unreal.MaterialFactoryNew())
    MEL.delete_all_material_expressions(obj)
    y = [-200]

    def echantillon(fichier, prop=None, sortie="RGB", **kw):
        tex = texture(dossier_src, fichier, dossier, **kw)
        e = MEL.create_material_expression(obj, unreal.MaterialExpressionTextureSample, -600, y[0])
        e.set_editor_property("texture", tex)
        if kw.get("normale"):
            e.set_editor_property("sampler_type", unreal.MaterialSamplerType.SAMPLERTYPE_NORMAL)
        elif kw.get("lineaire"):
            e.set_editor_property("sampler_type", unreal.MaterialSamplerType.SAMPLERTYPE_MASKS)
        y[0] += 260
        if prop is not None:
            MEL.connect_material_property(e, sortie, prop)
        return e

    def constante(valeur, prop):
        c = MEL.create_material_expression(obj, unreal.MaterialExpressionConstant, -400, y[0])
        c.set_editor_property("r", valeur)
        y[0] += 120
        MEL.connect_material_property(c, "", prop)

    if spec.get("base"):
        echantillon(spec["base"], MP.MP_BASE_COLOR)
    elif spec.get("couleur"):
        c = MEL.create_material_expression(obj, unreal.MaterialExpressionConstant3Vector, -400, y[0])
        r, g, b = spec["couleur"]
        c.set_editor_property("constant", unreal.LinearColor(r, g, b, 1))
        y[0] += 140
        MEL.connect_material_property(c, "", MP.MP_BASE_COLOR)
        if spec.get("emissif"):
            m = MEL.create_material_expression(obj, unreal.MaterialExpressionMultiply, -200, y[0])
            k = MEL.create_material_expression(obj, unreal.MaterialExpressionConstant, -400, y[0] + 80)
            k.set_editor_property("r", spec["emissif"])
            MEL.connect_material_expressions(c, "", m, "A")
            MEL.connect_material_expressions(k, "", m, "B")
            MEL.connect_material_property(m, "", MP.MP_EMISSIVE_COLOR)
            y[0] += 200
    if spec.get("normal"):
        echantillon(spec["normal"], MP.MP_NORMAL, normale=True)
    if spec.get("rough"):
        echantillon(spec["rough"], MP.MP_ROUGHNESS, "R", lineaire=True)
    if spec.get("metal"):
        echantillon(spec["metal"], MP.MP_METALLIC, "R", lineaire=True)
    if spec.get("metal_smooth"):
        e = echantillon(spec["metal_smooth"], MP.MP_METALLIC, "R", lineaire=True)
        un_moins = MEL.create_material_expression(obj, unreal.MaterialExpressionOneMinus, -300, y[0])
        MEL.connect_material_expressions(e, "A", un_moins, "")
        MEL.connect_material_property(un_moins, "", MP.MP_ROUGHNESS)
        y[0] += 120
    if not (spec.get("rough") or spec.get("metal_smooth")):
        constante(0.2 if spec.get("verre") else 0.8, MP.MP_ROUGHNESS)
    if spec.get("emissive"):
        e = echantillon(spec["emissive"])
        m = MEL.create_material_expression(obj, unreal.MaterialExpressionMultiply, -300, y[0])
        k = MEL.create_material_expression(obj, unreal.MaterialExpressionConstant, -500, y[0] + 80)
        k.set_editor_property("r", spec.get("emissif", 2.0))
        MEL.connect_material_expressions(e, "RGB", m, "A")
        MEL.connect_material_expressions(k, "", m, "B")
        MEL.connect_material_property(m, "", MP.MP_EMISSIVE_COLOR)
        y[0] += 200
    if spec.get("verre"):
        obj.set_editor_property("blend_mode", unreal.BlendMode.BLEND_TRANSLUCENT)
        if spec.get("opacity"):
            echantillon(spec["opacity"], MP.MP_OPACITY, "R", lineaire=True)
        else:
            constante(0.35, MP.MP_OPACITY)
    MEL.recompile_material(obj)
    LIB.save_loaded_asset(obj)
    return obj


def options_mesh(echelle, collision_auto=True):
    o = unreal.FbxImportUI()
    o.automated_import_should_detect_type = False
    o.mesh_type_to_import = unreal.FBXImportType.FBXIT_STATIC_MESH
    o.import_as_skeletal = False
    o.import_mesh = True
    o.import_materials = False
    o.import_textures = False
    o.static_mesh_import_data.combine_meshes = True
    o.static_mesh_import_data.auto_generate_collision = collision_auto
    o.static_mesh_import_data.import_uniform_scale = echelle
    return o


def importer_decor(d):
    nom = d["nom"]
    src = SOURCE / nom
    dossier = f"{DEST}/{nom}"
    LIB.make_directory(dossier)
    exacte = d.get("collision") == "exacte"
    mesh = importer(src / f"{nom}.fbx", f"SM_WW_{nom}", dossier, options_mesh(d["echelle"], not exacte))
    if not isinstance(mesh, unreal.StaticMesh):
        raise RuntimeError(f"Pas un StaticMesh : {nom}")
    # Collision exacte : la forme reelle sert de collision (Use Complex
    # Collision As Simple) ; les volumes generes a l'import faisaient des murs
    # invisibles autour du decor Club Penguin (27/09).
    if exacte:
        try:
            unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem).remove_collisions(mesh)
        except Exception as err:
            print("WW_DECOR_COLLISION", nom, "volumes non retires :", err)
        corps = mesh.get_editor_property("body_setup")
        corps.set_editor_property("collision_trace_flag", unreal.CollisionTraceFlag.CTF_USE_COMPLEX_AS_SIMPLE)
    slots = mesh.get_editor_property("static_materials")
    for i, slot in enumerate(slots):
        cle = normaliser(slot.get_editor_property("material_slot_name"))
        spec = d["materiaux"].get(cle)
        if spec is None:
            # Nom d'emplacement renomme par l'import : on cherche un voisin.
            spec = next((v for k, v in d["materiaux"].items() if k in cle or cle in k), None)
        if spec is None:
            print("WW_DECOR_SLOT_SANS_TEXTURE", nom, cle)
            continue
        mesh.set_material(i, materiau(f"M_WW_{nom}_{cle}", dossier, src, spec))
    LIB.save_loaded_asset(mesh)
    e = mesh.get_bounds().box_extent
    print("WW_DECOR", nom, f"my-asset-pack::SM_WW_{nom}", "taille_cm",
          tuple(round(v * 2, 1) for v in (e.x, e.y, e.z)))


def importer_carte():
    """La carte de role : face (parametre Texture, change en jeu), dos, tranche."""
    dossier = f"{DEST}/RoleCard"
    LIB.make_directory(dossier)
    mesh = importer(SOURCE / "RoleCard/RoleCard.fbx", "SM_WW_RoleCard", dossier, options_mesh(1.0))
    dos_tex = importer(CARTES_IMG / "dos_nuit.png", "T_WW_RoleCard_Dos", dossier)

    face = LIB.load_asset(f"{dossier}/M_WW_RoleCard_Face") or TOOLS.create_asset(
        "M_WW_RoleCard_Face", dossier, unreal.Material, unreal.MaterialFactoryNew())
    MEL.delete_all_material_expressions(face)
    p = MEL.create_material_expression(face, unreal.MaterialExpressionTextureSampleParameter2D, -500, 0)
    p.set_editor_property("parameter_name", "Texture")
    p.set_editor_property("texture", dos_tex)
    MEL.connect_material_property(p, "RGB", MP.MP_BASE_COLOR)
    r = MEL.create_material_expression(face, unreal.MaterialExpressionConstant, -400, 260)
    r.set_editor_property("r", 0.75)
    MEL.connect_material_property(r, "", MP.MP_ROUGHNESS)
    MEL.recompile_material(face)
    LIB.save_loaded_asset(face)

    dos = LIB.load_asset(f"{dossier}/M_WW_RoleCard_Dos") or TOOLS.create_asset(
        "M_WW_RoleCard_Dos", dossier, unreal.Material, unreal.MaterialFactoryNew())
    MEL.delete_all_material_expressions(dos)
    t = MEL.create_material_expression(dos, unreal.MaterialExpressionTextureSample, -500, 0)
    t.set_editor_property("texture", dos_tex)
    MEL.connect_material_property(t, "RGB", MP.MP_BASE_COLOR)
    MEL.recompile_material(dos)
    LIB.save_loaded_asset(dos)

    tranche = LIB.load_asset(f"{dossier}/M_WW_RoleCard_Tranche") or TOOLS.create_asset(
        "M_WW_RoleCard_Tranche", dossier, unreal.Material, unreal.MaterialFactoryNew())
    MEL.delete_all_material_expressions(tranche)
    c = MEL.create_material_expression(tranche, unreal.MaterialExpressionConstant3Vector, -400, 0)
    c.set_editor_property("constant", unreal.LinearColor(0.86, 0.79, 0.65, 1))
    MEL.connect_material_property(c, "", MP.MP_BASE_COLOR)
    MEL.recompile_material(tranche)
    LIB.save_loaded_asset(tranche)

    par_slot = {"face": face, "dos": dos, "tranche": tranche}
    for i, slot in enumerate(mesh.get_editor_property("static_materials")):
        cle = normaliser(slot.get_editor_property("material_slot_name"))
        mat = next((m for k, m in par_slot.items() if k in cle), None)
        if mat:
            mesh.set_material(i, mat)
    LIB.save_loaded_asset(mesh)
    print("WW_DECOR RoleCard my-asset-pack::SM_WW_RoleCard")


# Pieces decoupees dans le decor Club Penguin (scripts/blender/decoupe_decor.py).
_decoupe = SOURCE / "decoupe.json"
if _decoupe.is_file():
    import json
    for _piece in json.loads(_decoupe.read_text(encoding="utf-8")):
        _piece["materiaux"] = {k: (dict(v, couleur=tuple(v["couleur"])) if "couleur" in v else v)
                               for k, v in _piece["materiaux"].items()}
        DECORS.append(_piece)

# 27/09 : le script reimportait TOUS les decors a chaque fois, et chaque
# reimport ecrasait les reglages faits a la main dans l'editeur (taille,
# collision, materiaux ; la carte de role redevenait minuscule). Desormais,
# seuls les decors absents sont importes. Pour en reimporter un exprès,
# mettre son nom dans FORCER, par exemple FORCER = ["ClothingCustomizer"].
FORCER = []


def deja_la(nom):
    return LIB.does_asset_exist(f"{DEST}/{nom}/SM_WW_{nom}")


for decor in DECORS:
    if deja_la(decor["nom"]) and decor["nom"] not in FORCER:
        print("WW_DECOR_GARDE", decor["nom"], "(deja importe, FORCER pour le refaire)")
        continue
    try:
        importer_decor(decor)
    except Exception as err:  # un decor rate ne doit pas empecher les autres
        print("WW_DECOR_ECHEC", decor["nom"], err)
if deja_la("RoleCard") and "RoleCard" not in FORCER:
    print("WW_DECOR_GARDE RoleCard (deja importee, FORCER pour la refaire)")
else:
    try:
        importer_carte()
    except Exception as err:
        print("WW_DECOR_ECHEC RoleCard", err)
print("WW_DECOR_COMPLETE")
