# Werewolf : proposition d'assets pour la cour

La cour de la capture est large, sableuse, bordée de pierre ocre et ouverte
sur un escalier et une arche. J'y placerais une petite assemblée circulaire
dans la zone d'ombre centrale, en gardant les passages dégagés. Même langage
visuel que la table de Liar's Bar : bois foncé, bronze patiné, tissus rouges
profonds et touches de turquoise, avec des motifs géométriques inspirés des
frises déjà présentes sur la map.

| Asset Blender | Forme et usage | Variante prévue |
| --- | --- | --- |
| `WW_Firepit` | Brasero bas octogonal, pierre sculptée, grille bronze, bûches et braises. Centre de la réunion. | Allumé / éteint ; flamme et lumière pilotées dans Unreal. |
| `WW_Lantern` | Lanterne ancienne en bronze ajouré, verre ambré, anse solide. Éclaire les abords sans éblouir les cartes. | Sur pied court et posée au sol. |
| `WW_Rug` | Grand tapis circulaire tissé, bords brodés ocre et turquoise, centre neutre sous le brasero. | Modules de 8, 10 et 12 places. |
| `WW_Cushion` | Coussin épais avec frange discrète, forme adaptée à une pose assise au sol. | Trois couleurs alternées, pivot de siège identique. |
| `WW_SeatMarker` | Rosace de tissu cousue au bord du tapis pour chaque position ; repère discret de placement et d'orientation. | Emplacements numérotés côté données, sans numéro visible. |
| `WW_RoleCard` | Carte rigide au dos commun : lune, œil de bronze et cadre gravé. La face porte un grand pictogramme lisible sans texte en jeu. | Villageois, Loup, Voyante, Sorcière, Chasseur, Garde, Cupidon, Petite fille ; liste extensible. |
| `WW_CardBox` | Coffret bas en bois sculpté pour distribuer et ranger les cartes. | Couvercle ouvert / fermé. |
| `WW_VoteTokens` | Jetons en bronze et turquoise pour marquer un vote ou une cible au centre du tapis. | Icônes soleil / lune. |

## Implantation proposée

```text
                escalier
                   │
       lanternes   │   lanternes
            coussins 8–12
         ╭────────────────╮
         │    brasero     │   arche
         │ tapis circulaire│
         ╰────────────────╯
            coffret / votes
```

Les assises forment un anneau modulaire : chaque joueur voit le feu, les
autres visages et la zone de vote. Les cartes de rôle restent privées dans la
main ou dans une interface dédiée ; seul leur dos peut être exposé aux autres.
Les meshes seront séparés des flammes et des lumières pour garder un coût
faible en partie et permettre un cycle jour/nuit sans recréer le mobilier.

Avant placement définitif dans la map, relever le centre de la cour et la
hauteur du sol dans Unreal, puis vérifier le nombre maximal de joueurs voulu.
