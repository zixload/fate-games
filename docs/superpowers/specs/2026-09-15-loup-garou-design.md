# Loup-garou — conception du moteur serveur

15/09/2026. Validé section par section avec l'auteur du projet.

## Périmètre

Ce document couvre la **logique serveur** d'une partie de loup-garou : création, composition,
attribution secrète des rôles, déroulement des phases, vote, conditions de victoire.

Il ne couvre pas la carte, les animations, ni l'interface — cette dernière se limitant, par choix de
design, à l'invite d'interaction et à une zone de message transitoire.

**Rôles de cette version (mis à jour le 26/09/26) : loups, villageois, voyante, chasseur, gardien,
loup blanc, cupidon, sorcière**, un maire, et une composition réglable dans le salon. Voir « Rôles
ajoutés et réglages du salon » plus bas. L'architecture doit toujours permettre d'ajouter un rôle
sans refonte — c'est la contrainte principale qui a guidé le découpage.

---

## Le principe qui tient tout le reste

**Le moteur de jeu ne connaît pas nanos world.**

Il ne coupe pas un micro, n'illumine pas une silhouette, ne joue aucune animation. On lui donne un
état et une durée écoulée ; il rend un nouvel état et une **liste d'effets**. Un adaptateur mince
traduit ces effets en appels moteur.

Deux conséquences, et ce sont les raisons du choix :

* toute la logique se teste **sans un seul bouchon moteur**, donc entièrement, hors-jeu, en
  millisecondes ;
* le jour où un client est disponible, seul l'adaptateur peut être en cause.

---

## Découpage

```text
Server/games/werewolf/
  data/roles.lua      registre des rôles : ce que chacun apporte
  data/phases.lua     phases de base et durées par défaut
  match.lua           état d'une partie : joueurs, rôles, vivants, pile de phases
  voting.lua          enregistrement des désignations et dépouillement
  outcome.lua         conditions de victoire
  effects.lua         vocabulaire des effets et leur validation
  engine.lua          la machine : avance le temps, applique les règles, produit des effets
  adapter.lua         seul fichier qui connaît nanos world
```

**Tout sauf `adapter.lua` est du Lua pur** : aucun `Events`, `Player`, `Timer` ou `Character`.

Chaque module a une responsabilité qu'on peut énoncer en une phrase, et se teste seul. `voting` sait
dépouiller sans savoir ce qu'est une nuit ; `outcome` sait qui a gagné sans savoir comment on vote.

### Branchement avec l'existant

Minimal, et par les points déjà construits et testés :

| Ce qui existe | Ce qu'on en fait |
| --- | --- |
| Registre des objets interactifs | La cloche du village est une entrée, son `on_interact` appelle le moteur |
| Pipeline `intents/` | L'intention `designate` en hérite : revalidation de distance, audit, corrélation |
| `Server/Index.lua` | Trois lignes d'instanciation |

---

## La pile de phases

Le moteur ne déroule pas une séquence plate mais une **pile**. Une phase courante peut en empiler
une autre, qui se dépile ensuite pour rendre la main.

C'est ce qui rendra le **chasseur** possible plus tard : sa mort, survenue à n'importe quel moment,
empile une phase de tir que tout le monde attend, puis la partie reprend où elle en était. Une
séquence plate ne le permettrait pas sans réécriture.

Une phase déclare :

```text
id          identifiant
duration    durée en secondes, ou nil pour une phase qui attend un acte
enter       appelée à l'entrée, rend des effets
designate   appelée quand un joueur désigne quelqu'un, rend des effets
resolve     appelée à l'échéance ou à la complétion, rend des effets
```

---

## Le registre des rôles

Chaque rôle est une **donnée**. En ajouter un ne touche pas au moteur.

```lua
{
    id          = "seer",
    team        = "village",
    -- phase de nuit optionnelle ; l'ordre range les phases entre elles
    night_phase = { id = "night_seer", duration = 20, order = 20 },
    designate   = function(match, actor, target) end,  -- rend des effets
    resolve     = function(match) end,                 -- rend des effets
    composition = { min_players = 4, count = 1 },
}
```

Le champ `order` range les phases de nuit entre elles : **les loups sont à 10, la voyante à 20**. Un
rôle ajouté plus tard s'insère en choisissant son numéro, sans toucher aux autres.

Le gardien, plus tard, sera une entrée de ce genre avec une mémoire du protégé précédent. Le
chasseur n'aura pas de phase de nuit mais un `on_death` qui empile sa phase de tir. La sorcière aura
deux ressources à usage unique et une révélation ciblée de la victime.

---

## Déroulement

```text
attente          la cloche est active ; le serveur refuse sous le seuil
répartition      rôles tirés, transmis à chacun et à lui seul
nuit · loups     ils se voient entre eux et désignent ensemble
nuit · voyante   elle vise, la silhouette s'illumine pour elle seule
aube             résolution des morts, annonce
jour · débat     voix ouverte à tous les vivants
jour · vote      bras tendus, public, modifiable jusqu'au terme
exécution        résolution, puis vérification de victoire
```

Durées par défaut, toutes configurables : loups 45 s, voyante 20 s, aube 10 s, débat 180 s,
vote 45 s. Elles se règleront à l'usage.

### Composition

| Joueurs | Loups | Voyante | Reste |
| --- | --- | --- | --- |
| 4 – 5 | 1 | 1 | villageois |
| 6 – 8 | 2 | 1 | villageois |
| 9 et plus | 3 | 1 | villageois |

Minimum **4 joueurs**. À quatre, c'est une configuration d'essai et non une vraie partie : le groupe
de test de l'auteur compte quatre personnes, et il faut pouvoir jouer.

### Égalités — deux règles différentes

**Au village, une égalité ne tue personne.** Le village n'a pas tranché, la nuit tombe. C'est une
issue légitime et une vraie pression.

**Chez les loups, égalité tranchée au hasard.** Une nuit sans victime bloquerait la partie ; ils sont
peu nombreux et leur temps est compté.

### Victoire

Vérifiée **après chaque résolution de mort**, jamais ailleurs.

* Le village gagne quand il ne reste aucun loup vivant.
* Les loups gagnent quand ils sont **aussi nombreux** que les autres vivants — à ce moment ils ne
  peuvent plus perdre un vote, la partie est décidée, et la prolonger ne serait que du temps perdu.

---

## Vocabulaire des effets

Le contrat entre le moteur et l'adaptateur. `effects.lua` les construit et les valide.

| Effet | Champs | Traduction |
| --- | --- | --- |
| `assign_role` | player, role | envoi privé **au seul destinataire** |
| `reveal` | viewer, target, tint | teinte visible du seul `viewer`, entité créée côté client |
| `voice_channel` | player, channel | `lobby`, `village`, `wolves` ou `dead` |
| `mute` | player, muted | coupure du micro |
| `point_at` | player, target, **audience** | montage bras tendu, slot `UpperBody`, joué pour la seule audience indiquée |
| `kill` | player, cause | corps au sol, détachement du joueur, bascule sur le canal des morts |
| `announce` | key, args | message transitoire ou son |
| `world_light` | phase | orientation du soleil, ambiance |
| `match_ended` | winner, summary | déclenche l'écriture du résultat en base |

Le champ **`audience`** est ce qui protège le jeu : `all`, `wolves`, `dead`, ou un joueur précis. Un
loup qui désigne sa victime la nuit tend le bras **pour les autres loups uniquement** ; le même effet
de jour a pour audience `all`. Sans ce champ, la nuit trahirait tout le monde.

## Intentions entrantes

Deux, pas plus.

**`ring_bell`**, via le registre des objets interactifs.

**`designate(target)`**, via le pipeline existant. Le moteur sait, **selon la phase en cours**, s'il
s'agit d'un vote du village, d'une désignation de loup ou d'une vision. Une seule intention pour
trois usages : moins de surface, et il devient impossible de voter la nuit ou de désigner une
victime en plein jour.

---

## Pannes et persistance

**Déconnexion en cours de partie** : le joueur est traité comme mort, son corps tombe, la partie
continue. Si le nombre de vivants passe **sous quatre**, le minimum requis pour composer une partie,
elle s'arrête **sans vainqueur** plutôt que de se traîner.

**Redémarrage du serveur** : l'état d'une partie en cours vit en mémoire et est perdu. C'est
acceptable et assumé — une partie interrompue ne se reprend pas.

**Ce qui est écrit en base** : uniquement le **résultat d'une partie terminée** — qui jouait, quel
rôle, qui a gagné, quand. C'est une donnée transactionnelle, écrite immédiatement, conformément à la
distinction déjà posée dans l'architecture entre état volatil et donnée transactionnelle.

---

## Tests

Toute la logique se teste hors-jeu, sans bouchon, puisqu'elle ne connaît aucune globale du moteur.

**Couverture attendue** : composition selon le nombre de joueurs, tirage et unicité des rôles,
dépouillement, les deux règles d'égalité, conditions de victoire aux bornes, transitions de la pile
de phases, déconnexion en cours de partie, arrêt sous le seuil.

**Le test central** : jouer une **partie entière** avec une horloge factice et vérifier qu'on atteint
une victoire. Puis des parties scénarisées — victoire des loups, victoire du village, égalité au
vote, départ d'un joueur.

**Le test de sécurité**, à écrire dès le départ : vérifier qu'**aucun effet ne transmet le rôle d'un
joueur à quelqu'un qui n'y a pas droit**. C'est la seule faille qui ruinerait le jeu, et elle doit
échouer au banc de test plutôt qu'en partie.

L'adaptateur n'est pas testable sans client. Il est donc **mince et bête** : aucune décision, de la
traduction uniquement. Tout ce qui juge reste dans le moteur.

---

## Rôles ajoutés et réglages du salon (26/09/26)

Décidés après la maquette du HUD (`Client/loup_garou/hud.lua`, qui les affiche déjà). Identifiants
du moteur entre parenthèses ; chacun est une entrée du registre des rôles plus, s'il agit, une phase.

| Rôle | Phase et ordre | Règle |
| --- | --- | --- |
| Cupidon (`cupid`) | `night_cupid`, 1re nuit seulement, ordre 5 | désigne deux joueurs, liés : si l'un meurt, l'autre meurt aussi. Chacun reçoit `ww:amoureux` avec l'autre. |
| Gardien (`guard`) | `night_guard`, chaque nuit, ordre 8 | protège un joueur de l'attaque des loups ; pas deux nuits de suite le même. |
| Loups (`wolf`) | `night_wolves`, ordre 10 | inchangé ; le loup blanc vote avec eux. |
| Loup blanc (`white_wolf`) | `night_white_wolf`, une nuit sur deux, ordre 12 | loup pour les autres loups ; peut dévorer un loup. Gagne seul s'il est le dernier vivant. |
| Sorcière (`witch`) | `night_witch`, chaque nuit, ordre 15 | apprend en privé la victime des loups (`victim`) ; une potion de vie (la sauver) et une de mort (empoisonner un autre joueur), chacune une fois par partie (`potions`). |
| Voyante (`seer`) | `night_seer`, ordre 20 | inchangé. |
| Chasseur (`hunter`) | `hunter_shot`, empilée par son `on_death` | en mourant, désigne un joueur qui meurt avec lui (la pile de phases, prévue plus haut). |

**Le maire.** Élu par le village le jour 2 (`Phases.maire.jour`), dans une phase `day_mayor`
avant le débat : chacun désigne un candidat, égalité tirée au sort, et sans vote un vivant au
hasard. Sa voix compte double au vote du jour et départage une égalité. S'il meurt, la phase
`mayor_succession` est empilée comme le tir du chasseur : il désigne son successeur, ou un vivant
au hasard. Effet public `mayor(player)`, traduit en `ww:maire` (médaille au-dessus de sa tête).

Victoire, en plus des règles existantes : le **loup blanc** gagne seul s'il reste le dernier vivant ;
deux **amoureux** de camps opposés gagnent ensemble s'ils sont les deux derniers vivants.

**Salon.** Le premier arrivé est le créateur ; lui seul règle, les autres voient. Réglages : nombre de
joueurs maximum (4 à 12), nombre de loups (1 à 4), loup blanc, voyante, chasseur, gardien, cupidon
(0 ou 1 chacun), durée du débat (60 à 300 s, pas de 30). Les villageois complètent au lancement. Le
serveur refuse une composition impossible (plus de rôles spéciaux que de joueurs, aucun loup).
Événements : le client envoie `ww:reglage(cle, +1 | -1)` et `ww:pret` ; le serveur renvoie
`ww:salon(vue)` à chaque changement.

**Résultat en base** (migration 5) : `werewolf_matches` (début, fin, nombre de nuits, gagnant) et
`werewolf_participants` (personnage, rôle, survivant, gagnant), écrits à la fin de la partie par
l'adaptateur. Une partie avec des bots de test n'est pas enregistrée.
