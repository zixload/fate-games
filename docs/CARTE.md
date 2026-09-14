# Faire une map pour nanos world — ce qu'il faut savoir avant

Tout ce qui, si on l'ignore, coûte une soirée ou oblige à refaire. Classé par ordre de dégât.

---

## 1. Où travailler

| Règle | Pourquoi |
| --- | --- |
| Travailler **uniquement** dans `Content/MyAssetPack/` | C'est le dossier prévu pour ça |
| **Ne jamais toucher** à `Content/NanosWorld/` | Squelette Mannequin, matériaux physiques, blueprints officiels. Le casser, c'est casser l'export |
| **Ne pas travailler dans `NanosWorldEntryMap`** | C'est la map d'accueil de l'ADK, dans le dossier interdit |
| Partir d'une **copie de `NanosWorld/Maps/BlankMap`** | Elle est déjà configurée. Un `File → New Level` ne l'est pas |

## 2. L'échelle, l'erreur la plus chère

**1 unité = 1 centimètre.** Un personnage fait ~180, une porte ~220, un étage ~300.

Se tromper d'échelle ne se rattrape pas : tout est à refaire, parce que les proportions relatives
sont fausses partout. **Garde `SK_Mannequin` posé dans la scène pendant toute la construction.**

## 3. Ce que la map doit faire, pour le loup-garou

Ce n'est pas un problème de décoration, c'est un problème de lisibilité sociale.

* **Un espace fermé**, 30 à 40 mètres. Les joueurs ne doivent pas pouvoir s'éparpiller pendant le
  débat.
* **Des lignes de vue dégagées.** Le vote consiste à viser quelqu'un : il faut voir tout le monde
  depuis n'importe où. Rien de massif au centre.
* **Un contraste jour/nuit fort.** C'est une mécanique, pas une ambiance. La nuit doit être un
  événement.
* **8 à 16 points d'apparition en cercle**, tournés vers le centre.

## 4. Les pièges propres à nanos world

### Le Blueprint ne s'exécute pas

nanos world fait tourner du **Lua**, pas des Blueprints. La logique d'un acteur Blueprint posé dans
le niveau **ne tournera pas**. Préférer systématiquement les meshes `SM_` aux blueprints `BP_` quand
les deux existent. Ce qui est comportement se code côté serveur.

### Les deux Player Start n'ont rien à voir

| Acteur | Rôle |
| --- | --- |
| `BP_Placeholder_PlayerStart` (ADK) | Marqueur **exporté** par Forge pour nanos world |
| `Player Start` (Unreal) | Spawn du test **dans l'éditeur** uniquement |

Il faut les deux, pour deux usages différents.

### Retirer le GameMode Override avant l'export

Le `GameMode Override` posé dans World Settings pour tester en `Alt+P` n'a aucun sens dans nanos
world, et il sera cuit avec la map. À vider avant la cuisson finale.

### Le son vient du Lua

Un acteur `Ambient Sound` joue en test Unreal, mais rien ne garantit qu'il survive à la cuisson. Le
son se déclenche normalement depuis le serveur — ce qui est de toute façon mieux : la musique du
loup-garou doit changer selon la phase.

### Les matériaux physiques pilotent les bruits de pas

L'ADK déclare **21 surfaces physiques** — `PM_Grass`, `PM_Rock`, `PM_Wood`… Assigner le bon
matériau physique à chaque surface, c'est ce qui fait qu'un pas sur l'herbe sonne comme de l'herbe.
Gratuit si on le fait en construisant, pénible à rattraper après.

### La végétation a son profil de collision

Pour les types de Foliage, choisir le profil **`Foliage`** plutôt que `BlockAll` : les joueurs
traversent les buissons au lieu de rebondir dessus.

### PCG : figer avant de cuire

Si on utilise la génération procédurale, **convertir le résultat en géométrie statique** avant
l'export. Rien ne garantit que le client exécute PCG, et une map magnifique dans l'éditeur peut
arriver vide chez les joueurs.

### World Partition : le laisser désactivé

Pour une map de cette taille, il n'apporte rien et complique la cuisson.

## 5. Ce qui part chez les joueurs

**Tout ce que la map référence est cuit dans l'asset pack, et téléchargé par chaque joueur avant de
pouvoir se connecter.**

La cuisson suit les **références**, pas les dossiers : utiliser douze props d'un pack de 600 Mo
n'expédie que ces douze props et leurs textures. Mais les packs stylisés ont souvent des textures en
4K, donc peu d'objets peuvent peser lourd. Ça se mesure après cuisson.

Conséquences pratiques : préférer peu de gros meshes à des milliers de petits, utiliser l'outil
**Foliage** pour la végétation plutôt que des acteurs individuels, et ne pas mélanger cinq packs
pour trois props.

## 6. Direction artistique

**Choisir une source pour les bâtiments et s'y tenir.** Mélanger des packs aux directions
différentes produit l'effet catalogue, qui se voit immédiatement et décrédibilise plus qu'une map
pauvre mais cohérente.

## 7. Licences

| Source | Statut |
| --- | --- |
| Assets Epic / Fab | EULA Unreal : utilisables dans un jeu Unreal Engine — nanos world en est un |
| Quaternius, Poly Haven, Kenney | **CC0** : aucune restriction, le choix sûr pour tout ce qui est publié |

Le point de vigilance : publier un asset pack sur le Vault, c'est **redistribuer**. La plupart des
licences l'autorisent à l'intérieur d'un produit fini sous forme non modifiable, mais ça se vérifie
pack par pack.

## 8. L'ordre qui évite de perdre du temps

1. **Prouver le tuyau d'abord.** Un sol, une lumière, trois cubes, export Forge, vérifier que ça
   charge sur le serveur. Une heure. Tant que ce n'est pas fait, tout le travail de décoration est à
   risque.
2. **Blockout ensuite** : les volumes, les distances, les circulations, en formes grises. Se
   promener dedans avec un personnage à `Alt+P`.
3. **Habillage seulement après.** Les assets se remplacent sans toucher à la géométrie ; l'inverse
   n'est pas vrai.

## 9. Rappels de manipulation

```
mode           sélecteur en haut à gauche : Select / Landscape / Foliage / Modeling
naviguer       clic droit + WASD, molette pour la vitesse
               F recadre sur la sélection, Alt + clic gauche orbite
manipuler      W déplacer, E tourner, R redimensionner
tester         Alt+P, Échap pour sortir, F8 pour se détacher en cours de partie
               clic droit dans le viewport → Play From Here
export         Window → Nanos World Forge
```

Le dossier d'un asset pack doit être en **minuscules** : `gknight`, pas `GKnight`. Le nom du dossier
devient le préfixe de référence en Lua, sous la forme `<pack>::<NomDeclaré>`.
