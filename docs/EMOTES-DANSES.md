# Danses du personnage Creative

Les sept FBX fournis dans `C:\Users\ingam\Downloads` sont adaptés au même squelette Creative que le personnage du jeu. Les sources Mixamo, les `.blend`, les FBX générés et les aperçus restent hors Git.

| Touche dans la roue `T` | Animation dans `my-asset-pack` | Durée d'une boucle |
| --- | --- | ---: |
| 1 · Step Hip Hop | `my-asset-pack::ANIM_Dance_StepHipHop` | 7,800 s |
| 2 · Chicken | `my-asset-pack::ANIM_Dance_Chicken` | 4,767 s |
| 3 · Wave Hip Hop | `my-asset-pack::ANIM_Dance_WaveHipHop` | 15,967 s |
| 4 · Tut Hip Hop | `my-asset-pack::ANIM_Dance_TutHipHop` | 16,933 s |
| 5 · Booty Hip Hop | `my-asset-pack::ANIM_Dance_BootyHipHop` | 4,900 s |
| 6 · Salsa | `my-asset-pack::ANIM_Dance_Salsa` | 11,967 s |
| 7 · Jazz | `my-asset-pack::ANIM_Dance_Jazz` | 5,433 s |

La roue est ouverte avec `T`, puis on choisit de `1` à `7` (rangée supérieure QWERTY/AZERTY ou pavé numérique). Le serveur joue la danse en boucle sur `DefaultSlot`. Marcher l'arrête ; les emotes sont refusées lorsque le joueur est assis. Le client utilise `Client/emotes/img/{step,chicken,wave,tut,booty,salsa,jazz}.png` comme aperçus.

Les sept boucles ont un écart de pose de moins de 0,04 cm entre début et fin sur les principaux os. Step et Booty avaient respectivement 230 et 122 cm d'avancée cumulée dans les FBX source : cette dérive est retirée du bassin à l'export. Les mouvements de Salsa sont maintenus dans un rayon maximal de 45 cm autour de la place de l'emote. Les autres pas et mouvements des bras sont conservés. Aucun root motion n'est activé à l'import Unreal.

## Régénérer les FBX et les aperçus

Depuis la racine du dépôt :

```powershell
$blenderExe = 'C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe'
& $blenderExe -b -t 4 --python scripts/blender/create_dance_emotes.py
& $blenderExe -b -t 4 --python scripts/blender/render_dance_emote_icons.py
```

Les FBX sont créés dans `art/animations/dances/`. Les aperçus sont créés dans `Packages/fate-games/Client/emotes/img/`. Ces deux dossiers sont ignorés par Git.

## Import dans l'ADK

Dans la console **Python** de l'éditeur ADK déjà ouvert :

```python
exec(open(r"C:\Users\ingam\OneDrive\Documents\fate-games\scripts\unreal\import_dance_emotes.py", encoding="utf-8").read())
```

Attendre `DANCE_IMPORT_COMPLETE 7` dans l'Output Log, faire **Save All**, puis cuire `my-asset-pack`. Le script importe uniquement les sept séquences d'animation sur `SKEL_Animations_Skeleton` et vérifie leur durée. Le serveur doit être relancé après la cuisson pour charger la nouvelle liste de danses.
