"""Prepare la map ouverte a la cuisson de my-asset-pack.

A executer dans la console Python de l'editeur (NanosWorldADK), la map du jeu ouverte :

    exec(open(r"C:\\Users\\ingam\\OneDrive\\Documents\\fate-games\\scripts\\unreal\\ranger_pour_cuisson.py", encoding="utf-8").read())

1. Enregistre tout (map et assets).
2. Cherche tout ce que la map utilise reellement : les assets des acteurs
   poses, et ce qu'ils utilisent a leur tour (materiaux, textures...). Les
   assets importes mais jamais poses ne comptent pas.
3. Deplace dans /Game/MyAssetPack/Imports/ ceux qui vivent hors du pack
   (Fab, Megascans...), references reparees : la doc nanos demande un asset
   pack par dossier cuit, tout doit donc etre dans le pack.
4. Decoche "Is Editor Only Actor" sur les vraies decos (le repere du cercle,
   WW_REPERE_*, reste en editeur seulement).
5. Enregistre de nouveau et affiche un bilan (lignes CUISSON_...).

APPLIQUER = False : n'affiche que ce qui serait fait, sans rien changer.
"""

import unreal

PACK = "/Game/MyAssetPack"
RANGEMENT = "/Game/MyAssetPack/Imports"
REPERE = "WW_REPERE_"
APPLIQUER = True
# Racines deja fournies par nanos world ou le moteur : rien a deplacer.
FOURNIES = ("/Engine", "/Script", "/NanosWorld", "/Game/NanosWorld", "/Temp", "/Memory")

registre = unreal.AssetRegistryHelpers.get_asset_registry()
outils = unreal.AssetToolsHelpers.get_asset_tools()
acteurs = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
monde = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem).get_editor_world()


def enregistrer():
    unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True, True)


def dependances(paquet):
    options = unreal.AssetRegistryDependencyOptions(
        include_soft_package_references=True, include_hard_package_references=True,
        include_searchable_names=False, include_soft_management_references=False,
        include_hard_management_references=False)
    return [str(d) for d in (registre.get_dependencies(paquet, options) or [])]


def fourni(paquet):
    return paquet.startswith(FOURNIES)


enregistrer()
carte = monde.get_outermost().get_name()
print("CUISSON_MAP", carte)
if not carte.startswith(PACK):
    print("CUISSON_ATTENTION la map elle-meme est hors de", PACK, ": deplace-la dans le pack avant de cuire")

# Points de depart : la map, et le paquet de chaque acteur (une map "un
# fichier par acteur" range ses acteurs a part).
a_voir, vus = [carte], set()
editeur_seul = []
for a in acteurs.get_all_level_actors():
    paquet = a.get_outermost().get_name()
    if paquet != carte:
        a_voir.append(paquet)
    try:
        if a.get_editor_property("is_editor_only_actor") and not a.get_actor_label().startswith(REPERE):
            editeur_seul.append(a)
    except Exception:
        pass

while a_voir:
    p = a_voir.pop()
    if p in vus or fourni(p):
        continue
    vus.add(p)
    a_voir.extend(dependances(p))

utilises = sorted(p for p in vus if p.startswith("/"))
dehors = [p for p in utilises if not p.startswith(PACK) and p != carte and "__ExternalActors__" not in p
          and "__ExternalObjects__" not in p]
print("CUISSON_ASSETS_UTILISES", len(utilises), "dont hors du pack :", len(dehors))

# Deplacement dans le pack, references reparees par l'editeur.
deplaces = 0
renommages = []
for p in dehors:
    for donnees in registre.get_assets_by_package_name(p):
        asset = donnees.get_asset()
        if not asset:
            continue
        chemin = p.rsplit("/", 1)[0]
        reste = chemin[len("/Game"):] if chemin.startswith("/Game") else "/" + chemin.strip("/")
        nouveau = RANGEMENT + reste
        print("CUISSON_DEPLACE", p, "->", nouveau)
        renommages.append(unreal.AssetRenameData(asset, nouveau, str(donnees.asset_name)))
        deplaces += 1
if APPLIQUER and renommages:
    if not outils.rename_assets(renommages):
        print("CUISSON_ATTENTION certains deplacements ont echoue, voir l'Output Log")

# Les redirections laissees par les deplacements : on repare ceux qui y
# pointent encore, puis elles disparaissent.
if APPLIQUER and renommages:
    try:
        filtre = unreal.ARFilter(class_paths=[unreal.TopLevelAssetPath("/Script/CoreUObject", "ObjectRedirector")],
                                 package_paths=["/Game"], recursive_paths=True)
    except Exception:
        filtre = unreal.ARFilter(class_names=["ObjectRedirector"], package_paths=["/Game"], recursive_paths=True)
    redirections = [d.get_asset() for d in registre.get_assets(filtre)]
    redirections = [r for r in redirections if r]
    if redirections:
        outils.fixup_referencers(redirections)
        print("CUISSON_REDIRECTIONS_REPAREES", len(redirections))

for a in editeur_seul:
    print("CUISSON_EDITEUR_SEUL_RETIRE", a.get_actor_label())
    if APPLIQUER:
        a.set_editor_property("is_editor_only_actor", False)

if APPLIQUER:
    enregistrer()
print("CUISSON_BILAN", "deplaces :", deplaces, "| editeur seul retire :", len(editeur_seul),
      "| applique :", APPLIQUER)
print("CUISSON_PRET" if APPLIQUER else "CUISSON_SIMULATION (APPLIQUER = False)")
