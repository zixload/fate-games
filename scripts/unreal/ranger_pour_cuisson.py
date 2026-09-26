"""Prepare la map ouverte a la cuisson de my-asset-pack.

A executer dans la console Python de l'editeur (NanosWorldADK), la map du jeu ouverte :

    exec(open(r"C:\\Users\\ingam\\OneDrive\\Documents\\fate-games\\scripts\\unreal\\ranger_pour_cuisson.py", encoding="utf-8").read())

1. Enregistre tout (map et assets).
2. Cherche tout ce que la map utilise reellement : les maillages des acteurs
   poses, leurs materiaux (ceux du maillage et ceux changes sur l'acteur), les
   parents de ces materiaux et leurs textures, plus les dependances du
   registre. Les assets importes mais jamais poses ne comptent pas.
3. Deplace dans /Game/MyAssetPack/Imports/ ceux qui vivent ailleurs dans
   /Game (Fab, Megascans...), references reparees : la doc nanos demande un
   asset pack par dossier cuit, tout doit donc etre dans le pack.
4. Copie dans le pack ce qui vient d'un plugin de l'editeur et rebranche les
   materiaux dessus. Les imports glTF de Fab heritent de
   /InterchangeAssets/gltf/... : jamais cuit, le jeu les montrait gris.
5. Decoche "Is Editor Only Actor" sur les vraies decos (le repere du cercle,
   WW_REPERE_*, reste en editeur seulement).
6. Enregistre de nouveau et affiche un bilan (lignes CUISSON_...).

Relancer le script ne refait que ce qui manque.
APPLIQUER = False : n'affiche que ce qui serait fait, sans rien changer.
"""

import unreal

PACK = "/Game/MyAssetPack"
RANGEMENT = "/Game/MyAssetPack/Imports"
REPERE = "WW_REPERE_"
APPLIQUER = True
# Racines deja fournies par nanos world ou le moteur : rien a deplacer ni copier.
FOURNIES = ("/Engine", "/Script", "/NanosWorld", "/Game/NanosWorld", "/Temp", "/Memory")

registre = unreal.AssetRegistryHelpers.get_asset_registry()
outils = unreal.AssetToolsHelpers.get_asset_tools()
bibli = unreal.EditorAssetLibrary
mat_lib = unreal.MaterialEditingLibrary
acteurs = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
monde = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem).get_editor_world()


def enregistrer():
    unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True, True)


def paquet_de(objet):
    return objet.get_outermost().get_name()


def fourni(paquet):
    return paquet.startswith(FOURNIES)


def dependances(paquet):
    options = unreal.AssetRegistryDependencyOptions(
        include_soft_package_references=True, include_hard_package_references=True,
        include_searchable_names=False, include_soft_management_references=False,
        include_hard_management_references=False)
    return [str(d) for d in (registre.get_dependencies(paquet, options) or [])]


def lire(objet, propriete, defaut=None):
    try:
        return objet.get_editor_property(propriete)
    except Exception:
        return defaut


enregistrer()
carte = paquet_de(monde)
print("CUISSON_MAP", carte)
if not carte.startswith(PACK):
    print("CUISSON_ATTENTION la map elle-meme est hors de", PACK, ": deplace-la dans le pack avant de cuire")

# --- 2. Ce que la map utilise -------------------------------------------------
utilises = {}          # chemin d'objet -> objet
composants = []        # (composant, liste de materiaux changes sur l'acteur)
editeur_seul = []


def ajouter(objet):
    if objet is None:
        return
    chemin = objet.get_path_name()
    if chemin in utilises or fourni(paquet_de(objet)):
        return
    utilises[chemin] = objet
    if isinstance(objet, unreal.StaticMesh):
        for m in lire(objet, "static_materials", []) or []:
            ajouter(m.material_interface)
    elif isinstance(objet, unreal.SkeletalMesh):
        for m in lire(objet, "materials", []) or []:
            ajouter(m.material_interface)
    elif isinstance(objet, unreal.MaterialInstance):
        ajouter(lire(objet, "parent"))
        for t in lire(objet, "texture_parameter_values", []) or []:
            ajouter(t.parameter_value)
    elif isinstance(objet, unreal.Material):
        try:
            for t in mat_lib.get_used_textures(objet) or []:
                ajouter(t)
        except Exception:
            pass


# Le registre d'abord (il voit les blueprints, sons, etc.), en partant de la
# map et du paquet de chaque acteur (une map "un fichier par acteur").
a_voir, vus = [carte], set()
for a in acteurs.get_all_level_actors():
    p = paquet_de(a)
    if p != carte:
        a_voir.append(p)
    try:
        if a.get_editor_property("is_editor_only_actor") and not a.get_actor_label().startswith(REPERE):
            editeur_seul.append(a)
    except Exception:
        pass
    # Puis les objets eux-memes : le registre a deja rate les materiaux Fab.
    for c in a.get_components_by_class(unreal.MeshComponent):
        if isinstance(c, unreal.StaticMeshComponent):
            ajouter(lire(c, "static_mesh"))
        elif isinstance(c, unreal.SkinnedMeshComponent):
            ajouter(lire(c, "skeletal_mesh_asset") or lire(c, "skeletal_mesh"))
        changes = lire(c, "override_materials", []) or []
        for m in changes:
            ajouter(m)
        composants.append(c)

while a_voir:
    p = a_voir.pop()
    # Le registre ne descend pas dans les plugins : il y ramasserait des
    # fonctions de materiau et autres pieces d'editeur sans interet en jeu.
    if p in vus or fourni(p) or not p.startswith("/Game/"):
        continue
    vus.add(p)
    if "__ExternalActors__" not in p and "__ExternalObjects__" not in p and p != carte:
        for donnees in registre.get_assets_by_package_name(p):
            ajouter(donnees.get_asset())
    a_voir.extend(dependances(p))

a_deplacer, a_copier = [], []
for chemin, objet in sorted(utilises.items()):
    p = paquet_de(objet)
    if p.startswith(PACK + "/") or p == carte or "__External" in p:
        continue
    if p.startswith("/Game/"):
        a_deplacer.append(objet)
    else:
        a_copier.append(objet)
print("CUISSON_ASSETS_UTILISES", len(utilises), "| a deplacer :", len(a_deplacer),
      "| venant d'un plugin, a copier :", len(a_copier))


def destination(paquet):
    dossier = paquet.rsplit("/", 1)[0]
    reste = dossier[len("/Game"):] if dossier.startswith("/Game/") else "/" + dossier.strip("/")
    return RANGEMENT + reste


# --- 3. Deplacements dans le pack ---------------------------------------------
renommages = []
for objet in a_deplacer:
    p = paquet_de(objet)
    print("CUISSON_DEPLACE", p, "->", destination(p))
    renommages.append(unreal.AssetRenameData(objet, destination(p), objet.get_name()))
if APPLIQUER and renommages:
    if not outils.rename_assets(renommages):
        print("CUISSON_ATTENTION certains deplacements ont echoue, voir l'Output Log")

# --- 4. Copies des assets de plugin, puis rebranchement -----------------------
copies = {}   # chemin d'objet d'origine -> copie dans le pack
for objet in a_copier:
    p = paquet_de(objet)
    cible = destination(p) + "/" + objet.get_name()
    print("CUISSON_COPIE", p, "->", cible)
    if not APPLIQUER:
        continue
    copie = bibli.load_asset(cible) if bibli.does_asset_exist(cible) else bibli.duplicate_asset(p, cible)
    if copie:
        copies[objet.get_path_name()] = copie
    else:
        print("CUISSON_ATTENTION copie impossible :", p)


def remplacant(objet):
    return copies.get(objet.get_path_name()) if objet else None


rebranches = 0
if APPLIQUER and copies:
    # Toutes les instances de materiau concernees, copies comprises.
    instances = [o for o in list(utilises.values()) + list(copies.values())
                 if isinstance(o, unreal.MaterialInstanceConstant)]
    for mi in instances:
        if not paquet_de(mi).startswith(PACK + "/"):
            continue
        nouveau = remplacant(lire(mi, "parent"))
        if nouveau:
            mat_lib.set_material_instance_parent(mi, nouveau)
            rebranches += 1
        for t in lire(mi, "texture_parameter_values", []) or []:
            nouvelle = remplacant(t.parameter_value)
            if nouvelle:
                mat_lib.set_material_instance_texture_parameter_value(mi, t.parameter_info.name, nouvelle)
                rebranches += 1
        mat_lib.update_material_instance(mi)
        bibli.save_loaded_asset(mi)
    for o in utilises.values():
        if isinstance(o, unreal.StaticMesh):
            for i, m in enumerate(lire(o, "static_materials", []) or []):
                nouveau = remplacant(m.material_interface)
                if nouveau:
                    o.set_material(i, nouveau)
                    rebranches += 1
    for c in composants:
        for i, m in enumerate(lire(c, "override_materials", []) or []):
            nouveau = remplacant(m)
            if nouveau:
                c.set_material(i, nouveau)
                rebranches += 1
    # Un materiau de base copie peut encore lire des textures du plugin par
    # defaut : sans gravite si les instances les remplacent, mais a signaler.
    for copie in copies.values():
        if isinstance(copie, unreal.Material):
            try:
                for t in mat_lib.get_used_textures(copie) or []:
                    tp = paquet_de(t)
                    if not tp.startswith(PACK + "/") and not fourni(tp):
                        print("CUISSON_ATTENTION", copie.get_name(), "lit encore la texture", tp)
            except Exception:
                pass
    print("CUISSON_REBRANCHES", rebranches)

# Les redirections laissees par les deplacements : la cuisson les suit, les
# reparer ne fait que nettoyer. L'API Python varie selon la version.
if APPLIQUER and renommages:
    try:
        filtre = unreal.ARFilter(class_paths=[unreal.TopLevelAssetPath("/Script/CoreUObject", "ObjectRedirector")],
                                 package_paths=["/Game"], recursive_paths=True)
    except Exception:
        filtre = unreal.ARFilter(class_names=["ObjectRedirector"], package_paths=["/Game"], recursive_paths=True)
    redirections = [r for r in (d.get_asset() for d in registre.get_assets(filtre)) if r]
    reparer = getattr(outils, "fixup_referencers", None) or getattr(outils, "fix_up_referencers", None)
    if redirections and reparer:
        reparer(redirections)
        print("CUISSON_REDIRECTIONS_REPAREES", len(redirections))
    elif redirections:
        print("CUISSON_INFO", len(redirections), "redirections restantes : sans gravite pour la cuisson ; "
              "pour nettoyer, clic droit sur Content > Fix Up Redirectors")

# --- 5. Acteurs "editeur seulement" -------------------------------------------
for a in editeur_seul:
    print("CUISSON_EDITEUR_SEUL_RETIRE", a.get_actor_label())
    if APPLIQUER:
        a.set_editor_property("is_editor_only_actor", False)

if APPLIQUER:
    enregistrer()
print("CUISSON_BILAN", "deplaces :", len(renommages), "| copies :", len(copies), "| rebranches :", rebranches,
      "| editeur seul retire :", len(editeur_seul), "| applique :", APPLIQUER)
print("CUISSON_PRET" if APPLIQUER else "CUISSON_SIMULATION (APPLIQUER = False)")
