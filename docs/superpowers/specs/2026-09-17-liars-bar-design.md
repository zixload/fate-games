# Liar's Bar — conception du moteur serveur

17/09/2026. Validé section par section avec l'auteur du projet.

## Périmètre

Ce document couvre la **logique serveur** d'une partie de Liar's Bar : composition du paquet,
distribution, poses cachées, contestation, roulette russe, élimination et victoire.

Il ne couvre pas la carte. L'interface se limite, par choix de design, à l'invite d'interaction et
à une zone de message transitoire.

Liar's Bar est le **premier module de jeu** de fate-games. Il définit donc la forme du dossier
`Server/games/`, que le loup-garou reprendra.

---

## Le principe qui tient tout le reste

**Le moteur ne connaît pas nanos world, et il est piloté par les actes, pas par l'horloge.**

On lui passe un acte — « ce joueur pose trois cartes », « celui-là crie menteur » — et il rend un
nouvel état plus une **liste d'effets**. Un adaptateur mince traduit ces effets en appels moteur. Le
temps n'entre que par une temporisation de tour facultative, injectée. Le hasard est injecté aussi :
le mélange du paquet et la position de la balle, sinon rien n'est reproductible au banc de test.

Deux conséquences, et ce sont les raisons du choix :

* toute la logique se teste **sans un seul bouchon moteur**, donc entièrement, hors-jeu ;
* quand ça casse en partie, seul l'adaptateur peut être en cause.

### Pourquoi un moteur propre et non celui du loup-garou

Les deux jeux n'ont pas la même forme temporelle. Le loup-garou est piloté par le temps — nuit de
45 s, débat de 180 s, vote de 45 s — et sa conception s'articule autour d'une **pile de phases** que
l'horloge fait avancer. Liar's Bar est piloté par les tours : il ne s'écoule rien, on attend l'acte
du joueur actif, avec une contestation qui peut interrompre. Une pile de phases minutées
modéliserait cela de travers.

Liar's Bar a donc son propre moteur, mais adopte **la même discipline et le même découpage** :
moteur en Lua pur, adaptateur mince, vocabulaire d'effets avec champ `audience`. Ce vocabulaire sera
littéralement réutilisé par le loup-garou, qui doit lui aussi cacher de l'information. On duplique
une structure, pas du code, conformément à la règle du projet : on n'extrait qu'après deux usages
réels.

---

## Découpage

```text
Server/games/liars_bar/
  data/deck.lua     le paquet reduit, les correspondances, les jokers
  data/config.lua   taille de main, delais, barillet, places
  match.lua         la partie : joueurs, revolvers, ordre, vivants, resultat
  round.lua         la manche : carte de table, mains, depot, tour actif
  challenge.lua     le depouillement d'une contestation
  revolver.lua      le barillet et le tirage
  effects.lua       le vocabulaire des effets et leur validation
  engine.lua        la machine : un acte entre, un etat et des effets sortent
  adapter.lua       le seul fichier qui connait nanos world
```

**Tout sauf `adapter.lua` est du Lua pur** : aucun `Events`, `Player`, `Character` ni `Timer`.

Chaque module a une responsabilité qu'on peut énoncer en une phrase, et se teste seul. `challenge`
sait désigner un perdant sans savoir ce qu'est un barillet ; `revolver` sait tirer sans savoir
pourquoi.

### Branchement avec l'existant

Minimal, et par les points validés en jeu le 17/09/2026 :

| Ce qui existe | Ce qu'on en fait |
| --- | --- |
| Registre des objets interactifs | Une chaise est une entrée, le revolver du centre en est une |
| Pipeline `intents/` | `play_cards` et `challenge` en héritent : revalidation, audit, corrélation |
| `Server/Index.lua` | Trois lignes d'instanciation |
| `Shared/appearances.lua` | Les dix apparences jouables, déjà écrites |

---

## Les règles

### Le paquet

**Vingt cartes : six Rois, six Dames, six As, deux Jokers.** Le Joker vaut n'importe quelle valeur.

Cinq cartes par joueur. La carte de table est tirée parmi Roi, Dame et As.

Cette composition n'est pas arbitraire, elle fait le jeu. À quatre joueurs, quatre fois cinq cartes
font vingt : **le paquet entier est distribué**. Au maximum huit cartes peuvent donc légitimement
être annoncées comme des Rois sur toute la table — six Rois plus deux Jokers. Dès que les
prétentions cumulées dépassent huit, quelqu'un ment avec certitude, et contester devient
mathématiquement fondé. C'est ce qui empêche la course à la main vide d'écraser le bluff.

À trois joueurs il reste cinq cartes non distribuées, donc le comptage redevient approximatif. Le
jeu est plus net à quatre.

### La déclaration est implicite

Puisque la valeur est imposée pour toute la manche, annoncer « deux Rois » en posant deux cartes
n'ajoute **aucune information au nombre de cartes**. L'annonce est entièrement déterminée par le
compte.

Le moteur ne manipule donc qu'un nombre. Le client dira « deux Rois » à voix haute par-dessus, mais
c'est de la mise en scène : il n'y a aucun champ de déclaration à valider, donc aucun moyen de le
falsifier.

### Le tour

```text
joueur avec des cartes  : poser 1 a 3 cartes face cachee, ou contester la derniere pose
joueur sans cartes      : il sort de la manche, on ne le compte plus
```

Le tour passe au vivant suivant **qui a encore des cartes**.

Se vider ne met pas à l'abri de son imprudence : **ta dernière pose reste accusable** par le joueur
suivant tant qu'il a des cartes. Comme tout le monde démarre à cinq, il y a presque toujours
quelqu'un derrière.

### La contestation

On révèle **uniquement la dernière pose**.

* Toutes ses cartes sont la carte de table ou des Jokers → la prétention était vraie, **l'accusateur
  tire**.
* Une seule carte est intruse → **le menteur tire**.

Un seul jugement, aucune ambiguïté.

### Le revolver

**Un revolver par joueur.** Six chambres, une balle à une position tirée au hasard à la création du
revolver. Le joueur tire une fois : clic, il survit ; balle, il est éliminé.

Le décompte du barillet **traverse les manches** — c'est le seul élément qui survit à une remise à
zéro. Le premier tir est à une chance sur six, le suivant sur cinq, puis sur quatre. La menace monte
à mesure qu'on survit, et le décompte de chacun est **public** : la table sait qui joue à une chance
sur deux.

Un revolver ne se recharge jamais. Au sixième tir la mort est certaine.

### Fin de manche

Trois façons d'en sortir :

| Cause | Conséquence |
| --- | --- |
| Une contestation résolue | Le perdant tire, la manche s'arrête quelle qu'en soit l'issue |
| Plus personne d'autre que l'auteur de la dernière pose n'a de cartes | **Manche nulle**, aucun tir — plus personne pour répondre à cette pose |
| Il ne reste qu'un vivant | Fin de partie |

**Qui ouvre la manche suivante** : le perdant du tir, s'il est vivant ; s'il est mort, le joueur
vivant suivant dans l'ordre des places. Après une manche nulle il n'y a pas de perdant, alors
l'ouverture passe au joueur vivant suivant **celui qui venait d'ouvrir**.

### Victoire

Vérifiée **après chaque résolution de tir, jamais ailleurs**. Le dernier joueur vivant gagne.

### Composition

**Trois joueurs minimum, quatre places maximum.** Ce n'est pas un choix de confort mais une conséquence arithmétique : vingt cartes et des mains de cinq ne servent que quatre joueurs, cinq en demanderaient vingt-cinq. La première rédaction de ce document annonçait six places tout en décrivant, quelques paragraphes plus haut, un paquet que quatre joueurs épuisent entièrement. Les deux ne pouvaient pas être vrais.

### Les apparences

**Attribuées au hasard au début de la partie, et distinctes entre elles.** Chaque joueur reçoit une
des dix apparences de `Shared/appearances.lua`, tirée **sans remise** — la distinction est donc
garantie par construction, et non par la chance.

Il y a dix apparences pour quatre places au maximum, donc le tirage ne peut jamais échouer.

Aucun choix, aucun menu, aucun vestibule : c'est la conséquence directe du parti pris « pas
d'interface ». Et ce qui compte réellement dans un jeu de bluff n'est pas de choisir sa tête, c'est
de **pouvoir distinguer les autres** — ce que l'attribution sans remise assure mieux qu'un choix
libre, où deux joueurs prendraient la même.

Le tirage utilise le hasard injecté, donc il est reproductible au banc de test. Rien n'est persisté :
une nouvelle partie redistribue les apparences.

### Durée attendue

À quatre joueurs il faut trois morts. La balle étant à une position uniforme parmi six, un joueur
meurt à son N-ième tir avec une espérance de 3,5 tirs. Chaque manche produisant au plus un tir, il
faut compter **une quinzaine à une vingtaine de manches**, soit de **quinze à trente minutes** de
partie. À redimensionner à l'usage : c'est plus long qu'un loup-garou.

---

## Vocabulaire des effets

Le contrat entre le moteur et l'adaptateur. `effects.lua` les construit et les valide.

| Effet | Champs | Traduction |
| --- | --- | --- |
| `appearance` | player, body, head, worn | montage du personnage : `AddStaticMeshAttached` pour la tête, `AddSkeletalMeshAttached` pour les vêtements |
| `deal` | player, cards | envoi privé **au seul destinataire** |
| `table_card` | rank | annonce publique de la manche |
| `cards_played` | player, **count** | N dos glissent vers le dépôt |
| `reveal` | player, cards | la dernière pose se retourne, pour tous |
| `designated` | seat | le revolver glisse devant le tireur désigné |
| `accuse` | accuser, target | bras tendu, slot `UpperBody` |
| `shoot` | player, chamber, fatal | la mise en scène du tir |
| `eliminated` | player | revolver retiré, bascule sur le canal des éliminés |
| `turn` | player | à qui la main |
| `round_ended` | reason | `challenged` ou `exhausted` |
| `match_ended` | winner, summary | déclenche l'écriture du résultat en base |

L'effet décisif est **`cards_played`, qui ne transporte qu'un nombre**. Si le moteur y mettait les
cartes, un client curieux lirait le paquet et le jeu serait mort. C'est la seule fuite qui
compterait, et elle a son test dédié.

Le champ `audience` suit la même logique que dans le loup-garou, mais il est ici plus simple :
`deal` va à un seul joueur, tout le reste est public.

---

## Intentions entrantes

**Quatre, et pas une de plus.** Moins de surface, moins de triche possible.

```text
sit(place)          via le registre d'objets interactifs : la chaise
start()             E sur le revolver pose au centre, si le minimum est assis
play_cards(indices) 1 a 3 indices de sa propre main
challenge()         uniquement s'il existe une pose precedente
```

Un point qui découle de la règle R1 et qui gouverne toute la sécurité du jeu : **l'éventail de
cartes, la molette qui fait défiler, la carte qui se soulève — tout cela est purement côté client.**

Le serveur ne reçoit jamais « je pose le Roi de cœur », il reçoit « les indices 2 et 4 ». C'est lui
qui sait ce qu'il y a dans la main, lui qui vérifie que les indices existent, que le compte est
entre un et trois, que c'est bien le tour du demandeur. Un client modifié ne peut donc rien
inventer : au mieux désigner ses propres cartes.

---

## Mise en scène du revolver

C'est le moment que les joueurs retiendront, et le seul qui exige un travail d'animation que Mixamo
ne fournit pas.

```text
la revelation tombe      les cartes se retournent au centre
le perdant est designe   le revolver glisse devant lui
il doit agir lui-meme    E sur le revolver — personne ne tire a sa place
temps suspendu           tout le monde muet sauf lui, deux secondes
clic                     il survit ; le decompte de SON barillet avance
balle                    il est elimine, il garde la parole, il reste assis
```

**C'est le perdant qui appuie.** Le serveur a déjà décidé de l'issue au moment de la révélation — la
position de la balle était fixée à la création du revolver, rien ne se joue à cet instant — mais lui
faire accomplir le geste transforme une notification en épreuve.

L'animation de tir sur soi-même n'existe pas au catalogue Mixamo et ne s'obtiendra pas par
retargeting. **Pour la première version : une coupe caméra** au moment du coup. C'est la solution la
plus économique, une animation de moins à produire, et celle qui rend le mieux. Un montage manuel
dans Blender reste possible plus tard.

---

## Pannes et persistance

**Déconnexion en cours de partie** : le joueur est traité comme éliminé, la manche continue entre
les vivants. S'il ne reste qu'un vivant, il gagne par forfait ; s'il n'en reste aucun, la partie
s'arrête sans vainqueur.

**Le joueur désigné pour tirer se déconnecte** : le tir se résout tout seul après un délai, sans
lui. Sans cette règle la partie se bloque. Le hasard était déjà fixé, personne n'y perd rien.

**Redémarrage du serveur** : l'état d'une partie en cours vit en mémoire et est perdu. C'est
acceptable et assumé — une partie interrompue ne se reprend pas.

**Ce qui est écrit en base** : uniquement le **résultat d'une partie terminée** — qui jouait, à
quelle place, qui a gagné, combien de manches, quand. Donnée transactionnelle, donc écriture
immédiate, conformément à la distinction déjà posée dans l'architecture entre état volatil et donnée
transactionnelle.

Rien des mains, rien des barillets : tout cela meurt avec la partie.

**Deux numérotations, une seule visible.** Le moteur numérote ses places de 1 à n sans trou ; les chaises sont physiques. L'adaptateur traduit toute place en chaise à la sortie : les clients comme la base ne voient que des numéros de chaise, et le vainqueur est enregistré par son personnage, pas par un numéro de place.

---

## Tests

Toute la logique se teste hors-jeu, sans bouchon, puisqu'elle ne connaît aucune globale du moteur.

**Couverture attendue** : composition du paquet et distribution ; validation d'une pose — de une à
trois cartes, indices réellement en main, c'est bien le tour du demandeur ; dépouillement d'une
contestation dans les deux sens ; traitement du Joker ; progression du barillet et mort certaine au
sixième tir ; condition de manche nulle ; ouverture de la manche suivante dans les trois cas ;
élimination ; victoire aux bornes ; déconnexion ; **attribution d'apparences distinctes** à
toutes les tailles de table.

**Le test central** : jouer une **partie entière** avec une horloge factice et un hasard injecté, et
vérifier qu'on atteint un vainqueur. Puis des parties scénarisées — victoire par élimination, manche
nulle, menteur démasqué, accusateur qui se trompe, départ d'un joueur.

**Le test de sécurité**, à écrire dès le départ : vérifier qu'**aucun effet ne transporte l'identité
d'une carte vers quelqu'un d'autre que son propriétaire**, hors révélation. C'est la seule faille
qui ruinerait le jeu, et elle doit échouer au banc de test plutôt qu'en partie.

L'adaptateur n'est pas testable sans client. Il est donc **mince et bête** : aucune décision, de la
traduction uniquement. Tout ce qui juge reste dans le moteur.

---

## Assets

Tous disponibles, aucun rigging requis pour le mobilier et les objets :

| Élément | Source |
| --- | --- |
| Table | `nanos-world::SM_WoodenTable` — intégré, téléchargement nul |
| Chaises | `nanos-world::SM_WoodenChair` — même famille de textures |
| Décor | `SM_Bottle_01`, `SM_OilLamp`, `SM_Crate_01`, `SM_Carpet_01` — intégrés |
| Revolver | Nagant M1895, `m1895.fbx` — à cuire |
| Cartes | pack Playing_Cards — à cuire |
| Personnages | dix apparences, voir `Shared/appearances.lua` |
| Animations assises | cinq FBX Mixamo sans skin, à retargeter sur le squelette nanos world |

---

## Hors de cette version

**La salle.** Liar's Bar n'a pas besoin d'une carte égyptienne de 856 Mo. Quatre joueurs assis
voient une pièce, quatre murs et une lumière. Une petite salle dédiée coûterait quelques
mégaoctets.

**L'éventail qui masque les visages.** Un éventail tenu devant la caméra cache les autres joueurs,
or on lit les visages dans un jeu de bluff. À régler par le placement — éventail tenu bas, ou
relevé seulement quand c'est son tour. Ce n'est pas un problème de conception mais de réglage en
jeu.

**Le loup-garou**, dont la spec et le plan existent déjà et attendent leur tour.
