# Tapis, zabutons et animations assises du Loup-Garou

Ces assets remplacent le tapis `SM_WW_Rug` et les coussins `SM_WW_Cushion_*` du kit Blender précédent. Le script d'import n'édite pas la map ni le code Lua du Loup-Garou. Les sources sous licence, les FBX préparés, les fichiers Blender et les captures restent dans `art/werewolf/`, ignoré par Git.

## Préparer les sources

Sources attendues dans `C:\Users\ingam\Downloads` :

- `zabuton_7col_v22_2608_en.zip` : variante **Aged** des sept couleurs, géométrie, texture de base et normale d'origine ;
- `carpet.zip` : géométrie, base color, normale et roughness d'origine ;
- `Sitting Idle.fbx`, `Sitting Idle lazy.fbx` et `Sitting Dazed.fbx` : mouvements Mixamo.

Dans le dépôt, exécuter avec Blender de Steam :

```powershell
$blenderExe = 'C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe'
& $blenderExe -b -t 4 --python scripts/blender/inspect_werewolf_sources.py
& $blenderExe -b -t 4 --python scripts/blender/prepare_werewolf_external_assets.py
& $blenderExe -b -t 4 --python scripts/blender/retarget_werewolf_sitting.py
& $blenderExe -b -t 4 --python scripts/blender/measure_werewolf_sitting_fit.py
```

Le retarget prend comme référence le même rig Creative à 43 os que `ANIM_Seated_Card_Play`. L'ajustement des pieds est activé par défaut ; `WW_APPLY_FIT=0` sert uniquement à comparer la pose source. Les trois clips sont sans root motion et bouclent sur leur pose initiale.

## Import dans l'ADK

Dans **l'éditeur ADK déjà ouvert**, sélectionner `Python` dans le menu à gauche du champ de commande, puis coller :

```python
exec(open(r"C:\Users\ingam\OneDrive\Documents\fate-games\scripts\unreal\import_werewolf_assets.py", encoding="utf-8").read())
```

Le script importe et enregistre 8 meshes et 3 animations, crée leurs matériaux à partir des vraies textures, active la collision simple et vérifie les dimensions et le squelette. Il ne place rien dans la map. Ensuite enregistrer les assets et cuire `my-asset-pack` dans l'ADK. Attendre `WW_IMPORT_COMPLETE` dans l'Output Log avant de lancer le cook ; une exception signifie que l'import est incomplet.

Références à utiliser :

| Catégorie | Asset |
| --- | --- |
| Tapis | `my-asset-pack::SM_WW_Carpet` |
| Zabutons | `my-asset-pack::SM_WW_Zabuton_Blue`, `my-asset-pack::SM_WW_Zabuton_Brown`, `my-asset-pack::SM_WW_Zabuton_Green`, `my-asset-pack::SM_WW_Zabuton_Purple`, `my-asset-pack::SM_WW_Zabuton_Red`, `my-asset-pack::SM_WW_Zabuton_White`, `my-asset-pack::SM_WW_Zabuton_Yellow` |
| Animations | `my-asset-pack::ANIM_WW_Sitting_Idle`, `my-asset-pack::ANIM_WW_Sitting_Idle_Lazy`, `my-asset-pack::ANIM_WW_Sitting_Dazed` |

## Implantation et ajustement

Le tapis fait **550 cm de diamètre** et **0,8 cm d'épaisseur**. Centrer les zabutons sur un rayon de **212 cm** : `X = centre_X + 212 cos(angle)`, `Y = centre_Y + 212 sin(angle)`. Chaque assise fait **55 × 60 cm** hors cordages, et environ **66 × 71 cm** avec eux. Le pivot du tapis et des zabutons est au centre, au ras du sol. Poser les zabutons sur la face supérieure du tapis, donc leur origine à `Z_tapis + 0,8 cm`.

La surface textile du zabuton est à **13,141 cm au-dessus de son pivot** ; le nœud central dépasse jusqu'à **13,416 cm**. Une fois sur le tapis, la surface textile se trouve à **13,941 cm** au-dessus du sol sous le tapis.

Offsets du **pivot du personnage Creative à échelle 0,8**, mesurés depuis le sol sous le tapis :

| Pose | Z pivot personnage | Écart avec le dessus textile du zabuton | Durée de boucle |
| --- | ---: | ---: | ---: |
| Idle | 11,0 cm | −2,94 cm | 10,867 s |
| Idle Lazy | 12,8 cm | −1,14 cm | 10,267 s |
| Dazed | 11,6 cm | −2,34 cm | 8,333 s |

La légère pénétration du pivot est normale : c'est le bassin du rig qui touche la surface, pas l'origine du personnage. Ces offsets proviennent des captures et mesures Blender ; les vêtements du personnage en jeu peuvent nécessiter un petit ajustement visuel. Les six captures de face et profil sont `art/werewolf/fit_{idle,lazy,dazed}_{front,profile}.png`. Aucun niveau de test séparé n'est nécessaire.

Pour la lecture en boucle, utiliser le slot du personnage Creative :

```lua
character:PlayAnimation("my-asset-pack::ANIM_WW_Sitting_Idle", "DefaultSlot", true, 0.15, 0.15, 1.0, true)
```

Remplacer le nom pour les deux variantes. Le troisième argument active la boucle ; les deux temps de fondu sont en secondes, puis vient la vitesse de lecture. Garder la position du personnage fixe pendant la lecture. L'intégration Lua reste à faire dans le travail du mode Loup-Garou.

## Gestes de vote et de nuit

Deux animations supplémentaires sont générées depuis la pose assise ajustée, sur le même squelette Creative :

| Asset | Usage prévu | Durée | Boucle | Z du pivot personnage |
| --- | --- | ---: | --- | ---: |
| `my-asset-pack::ANIM_WW_Seated_Vote` | Main droite levée puis reposée lors d'un vote | 1,767 s | Non | 11,0 cm |
| `my-asset-pack::ANIM_WW_Seated_Vote_Point` | Index tendu vers l'avant pour montrer le choix final | 2,200 s | Non | 11,0 cm |
| `my-asset-pack::ANIM_WW_Seated_Sleep` | Tête inclinée, respiration discrète durant la nuit | 10,867 s | Oui | 11,0 cm |

Le vote part de la pose assise normale et y revient : le jouer une fois dans `DefaultSlot`, puis relancer l'idle. La pose de nuit utilise le même contact avec le zabuton que l'idle ; la jouer en boucle dans `DefaultSlot`, puis revenir à l'idle au lever du jour. Aucun déplacement du personnage ou root motion n'est inclus. Les captures Blender sur tapis et coussin sont `art/werewolf/fit_{vote,sleep}_{front,profile}.png`. Les personnages du jeu peuvent porter des vêtements qui nécessitent une vérification visuelle après import.

Reproduire les FBX si nécessaire :

```powershell
$blenderExe = 'C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe'
& $blenderExe -b -t 4 --python scripts/blender/create_werewolf_gestures.py
```

Dans la console Python de **l'éditeur ADK déjà ouvert**, importer uniquement ces animations :

```python
exec(open(r"C:\Users\ingam\OneDrive\Documents\fate-games\scripts\unreal\import_werewolf_gestures.py", encoding="utf-8").read())
```

Attendre `WW_GESTURES_IMPORT_COMPLETE 7`, enregistrer, puis cuire `my-asset-pack`. Ce script ne relance pas l'import des textures ou des meshes. Le branchement aux événements du jeu est à faire dans le code du mode Loup-Garou.

### Variantes assises, mort et maire

Le script `scripts/blender/create_werewolf_seated_extras.py` crée cinq clips supplémentaires depuis les animations assises déjà ajustées. Les fichiers `.blend`, `.fbx` et captures restent dans `art/werewolf/`, ignoré par Git.

| Asset | Usage | Durée | Boucle | Z du pivot |
| --- | --- | ---: | --- | ---: |
| `my-asset-pack::ANIM_WW_Sitting_Idle_Glance` | Idle normal, petit regard circulaire | 10,867 s | Oui | 11,0 cm |
| `my-asset-pack::ANIM_WW_Sitting_Idle_Shift` | Idle avachi, léger changement d'appui | 10,267 s | Oui | 12,8 cm |
| `my-asset-pack::ANIM_WW_Seated_Mayor_Cheer` | Poing droit levé pour fêter l'élection | 2,467 s | Non | 11,0 cm |
| `my-asset-pack::ANIM_WW_Seated_Death` | Geste agacé inchangé, puis bascule en arrière sur le tapis | 2,000 s | Non | 11,0 cm |
| `my-asset-pack::ANIM_WW_Seated_Dead_Idle` | Pose allongée en arrière, bassin sur le coussin, jusqu'à la fin de la partie | 10,867 s | Oui | 11,0 cm |

Pour régénérer les FBX :

```powershell
$blenderExe = 'C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe'
& $blenderExe -b -t 4 --python scripts/blender/create_werewolf_seated_extras.py
```

Le choix actuel de l'idle dans `Server/games/werewolf/adapter.lua` alterne selon le numéro du coussin. Pour obtenir l'aléatoire demandé, tirer une animation parmi les deux clips à **11,0 cm** (`Sitting_Idle`, `Sitting_Idle_Glance`) ou parmi les deux à **12,8 cm** (`Sitting_Idle_Lazy`, `Sitting_Idle_Shift`). Choisir une fois par prise de place, puis conserver ce choix jusqu'au changement de phase ; éviter de relancer le clip à chaque tick. Les deux nouveaux idles partagent exactement la pose d'assise et les contacts de leur source.

À l'élimination, jouer `Seated_Death` une seule fois dans `DefaultSlot`, puis `Seated_Dead_Idle` en boucle. Le geste agacé du poing ne change pas ; ensuite le bassin recule de 10 cm et le torse bascule derrière le coussin, les bras retombant de chaque côté. Le personnage reste visiblement allongé jusqu'à la fin de la partie. La dernière image du premier clip correspond à la première du second (écart mesuré inférieur à 0,001 cm) et la boucle se referme avec le même écart. La racine et la place du personnage ne bougent pas. À l'élection du maire, jouer `Seated_Mayor_Cheer` une fois puis reprendre l'idle choisi. Les clips de vote et de maire partent de l'idle normal : si le joueur est dans l'idle avachi, le repasser temporairement à 11,0 cm pour ces gestes.

Le nouveau `Seated_Vote_Point` sert **à la fin du minuteur de vote**, après la main levée de `Seated_Vote`. Il pointe dans l'axe avant du personnage. Le code de jeu doit conserver la cible choisie et orienter le haut du corps vers elle avant de jouer le clip, afin que l'index désigne réellement ce joueur ; le FBX seul ne connaît pas la cible. Ne pas le déclencher lors de chaque événement `ww:pointe` émis au changement de choix. Cette intégration Lua reste à faire séparément.

Les captures Blender sont `fit_mayor_{front,profile}.png`, `fit_death_raised_{front,profile}.png`, `fit_death_strike_{front,profile}.png`, `fit_death_reclined_{front,profile}.png` et `fit_point_{front,profile}.png`. Les sources `.blend` et `.fbx` restent dans `art/werewolf/`, hors Git.

Pour régénérer uniquement les deux clips d'élimination, puis le pointage :

```powershell
$env:WW_EXTRA_ONLY = 'death'
& 'C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe' -b -t 4 --python scripts/blender/create_werewolf_seated_extras.py
Remove-Item Env:WW_EXTRA_ONLY
& 'C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe' -b -t 4 --python scripts/blender/create_werewolf_point_vote.py
```

Dans la console Python de l'éditeur ADK déjà ouvert, importer **seulement ces trois clips**, puis enregistrer et cuire `my-asset-pack` :

```python
exec(open(r"C:\Users\ingam\OneDrive\Documents\fate-games\scripts\unreal\import_werewolf_vote_point_and_death.py", encoding="utf-8").read())
```

Attendre `WW_DEATH_AND_POINT_IMPORT_COMPLETE 3`. Le script ne relance aucun autre import et ne change pas le code Lua du Loup-Garou.

Pour réimporter **uniquement la mort et la pose allongée** après cette modification, utiliser dans la console Python du même éditeur :

```python
exec(open(r"C:\Users\ingam\OneDrive\Documents\fate-games\scripts\unreal\import_werewolf_death_only.py", encoding="utf-8").read())
```

Attendre `WW_DEATH_IMPORT_COMPLETE 2`, enregistrer et cuire `my-asset-pack`. Le timing de `Seated_Death` reste à 2 secondes, comme dans le code de jeu actuel.

## Licences et crédits

- **Zabuton** : Hato Wahara, [fiche Fab](https://www.fab.com/listings/c1fb1c0f-20de-4766-b267-2a959765be64). Le README inclus autorise l'usage commercial, la modification et l'usage en jeu, et interdit la redistribution des fichiers originaux ou modifiés et la revendication de propriété. Les sources restent hors du dépôt public. Vérifier les conditions de distribution du pack cuit avant toute publication aux joueurs.
- **Carpet** : demidrew, [modèle Sketchfab](https://sketchfab.com/3d-models/carpet-66e06c1857814fd2a60e3ecfdba36ae0), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Créditer l'auteur, le lien source et la licence dans les crédits du jeu ; signaler le redimensionnement du tapis à 5,5 m. La licence autorise l'usage en jeu et la redistribution avec attribution.
- **Animations Mixamo** : FBX fournis localement par le projet ; conserver les fichiers source hors Git et vérifier leurs conditions de licence avant distribution.

Ne commiter que les scripts et ce document : ni ZIP, ni textures, ni FBX, ni `.blend`, ni `.uasset`, ni captures contenant les assets sous licence.
