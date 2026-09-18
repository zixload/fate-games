# Liar's Bar — HUD de suivi et bots de test

18/09/2026. Validé en conversation avec l'auteur du projet.

## Périmètre

Deux outils pour **jouer une partie complète seul** et comprendre chaque étape, avant l'éventail 3D.

* **Un HUD texte** qui raconte la partie et permet de jouer au clavier.
* **Des bots de test** qui occupent les places libres et jouent des coups légaux.

Tous deux sont provisoires. Le HUD sera remplacé par la mise en scène physique (éventail, cartes
posées), et les bots n'existent qu'en mode dev. Le moteur de règles n'est **pas modifié**.

---

## Les bots

**Rôle : un outil de test.** Ils sont actifs seulement si `dev.liars_bots = true` dans
`Server/core/config.lua`, ne jouent que des coups légaux, et une partie où un bot a joué n'est
jamais écrite en base.

**Appel.** Commande de chat `/bots N`, hors partie uniquement :

* N bots s'assoient aux places libres, par ordre croissant de chaise ;
* `/bots 0` retire tous les bots ;
* on lance ensuite la partie comme d'habitude, avec E sur le revolver.

La commande est lue côté serveur par `Chat.Subscribe("PlayerSubmit")`, qui retourne `false` pour
qu'elle ne s'affiche pas dans le chat (« Return false to prevent the message from being sent »,
doc Chat). Hors mode dev, elle ne fait rien et le message passe normalement.

**Un bot est un pseudo-joueur.** L'adaptateur manipule des joueurs par `GetID()` et `GetName()`. Un
bot est une petite table qui répond aux deux méthodes :

* son identifiant est **l'opposé de sa chaise** (−2 pour la chaise 2), donc jamais confondu avec un
  vrai joueur ;
* son nom est « Bot 2 » ;
* il porte la marque `bot = true`.

Il entre dans les tables de l'adaptateur comme n'importe quel joueur. L'adaptateur apprend trois
choses :

* `send` ignore en silence une audience qui désigne un bot : aucun message réseau ;
* l'écriture du résultat est sautée si un bot figure parmi les assis, avec une ligne de journal ;
* le corps d'un bot se retrouve par son entrée d'assise et non par une session, pour l'animation
  d'accusation.

**La décision vit dans `bots.lua`, pur.** `Bots.Decide(state, seat, rng)` rend un acte, ou `nil` :

1. si `state.pending.seat == seat` → `shoot` ;
2. sinon, si c'est son tour (`state.round.turn == seat`, sans tir en attente) :
   * s'il existe une pose précédente d'une autre place, `challenge` avec la probabilité
     `bots.accuse_percent` ;
   * sinon `play` de 1 à 3 indices distincts tirés dans sa main (jamais plus que sa main) ;
3. sinon `nil`.

**Déclenchement.** Après chaque lot d'effets, l'adaptateur incrémente un compteur de génération. Si
la place attendue, donnée par `Bots.Awaited(state)` (le tireur désigné, sinon le tour), est un bot, il arme un `Timer.SetTimeout` de `bots.delay` secondes
(3 par défaut). À l'échéance, le minuteur ne fait rien si la génération a changé. Sinon il
demande `Bots.Decide` sur l'état **courant** et passe l'acte par `Adapter.Act`, comme un joueur. Un
minuteur périmé ne peut donc jamais jouer deux fois.

**Le corps.** Un personnage `nanos-world::SK_Male` sans joueur, placé **debout derrière sa chaise**,
à 60 cm de la chaise dans l'axe table-chaise et tourné vers la table. Debout derrière la chaise, il
n'entre pas en collision avec la chaise cuite. Le corps est détruit quand le bot se lève : `/bots 0`,
ou fin de partie, qui lève tout le monde comme aujourd'hui.

---

## Le HUD

**Côté serveur, trois ajouts :**

* `liars:seated` porte un troisième argument, le nom (`Player:GetName()` ou « Bot N ») ;
* un nouvel événement `liars:started`, diffusé par `Adapter.Begin`, avec la liste
  `{ chaise, nom }` dans l'ordre du tour. Le moteur n'émet pas de « partie lancée » ;
* un nouvel événement `liars:refused(raison, contexte)`, envoyé au seul joueur concerné, quand
  s'asseoir, lancer ou tirer par E est refusé. Aujourd'hui ces refus se perdent : le registre
  d'interaction ignore le retour de `on_interact`, et le client reçoit « ok ». Pour
  `pas_assez_de_joueurs`, le contexte donne le nombre d'assis et le minimum.

Les refus de pose et d'accusation arrivent déjà par `zix:intent_result` ; le HUD les écoute pour
`liars_play` et `liars_challenge`.

**Côté client, deux fichiers dans `Client/liars_bar/` :**

* `journal.lua`, **pur** : il reçoit les événements et tient l'état affiché. Cet état comprend :
  * ma chaise, déduite de `liars:seated` en comparant l'identifiant au joueur local ;
  * les noms par chaise ;
  * la carte de table et le tour ;
  * ma main et ma sélection ;
  * les dernières lignes du journal, chacune de type `info` ou `refus`.

  Il ne touche à aucune globale nanos.
* `hud.lua` : un `Canvas` qui dessine l'état, et l'écoute des touches. C'est le seul fichier du
  HUD qui touche au moteur.

**Affichage, trois blocs :**

* **le journal**, sur le côté : les `journal_lines` dernières étapes (8 par défaut), en phrases
  courtes. Par exemple : « zix s'assoit, chaise 1 », « Partie lancée : 4 joueurs », « Carte de
  table : Roi », « Chaise 2 pose 2 cartes », « Chaise 3 accuse chaise 2 », « Révélé chez Bot 2 : Roi, Dame », « Bot 2 doit tirer », « Chaise 2 tire… à blanc », « Victoire : chaise 4 ». Les refus s'affichent en rouge ;
* **l'état**, en haut : ma chaise, la carte de table, le tour, et « À toi ! » quand c'est le mien ;
* **ma main**, en bas, seulement si j'en ai une : `[W] Roi [X] Dame [C] As`, sélection marquée.

Le HUD ne juge pas une révélation : c'est le serveur qui désigne le tireur, et la ligne suivante le
dit.

**Touches**, réglables dans `Shared/config.lua` sous `liars_hud`, noms tirés de la doc Input :

* `W` `X` `C` `V` `B` : choisir ou retirer une carte, seulement pendant son tour. Des lettres et
  non des chiffres : en AZERTY, la touche 1 s'appelle `Ampersand` pour Unreal ;
* `P` : envoyer `liars_play` avec les indices choisis, puis vider la sélection. Pas `Enter`, qui
  risque de servir au chat ; le HUD ignore aussi ses touches tant que le chat est ouvert ;
* `M` : envoyer `liars_challenge` ;
* E sur le revolver : lancer et tirer, sans changement.

**Spectateurs.** Le journal et l'état s'affichent pour tout joueur connecté : l'information publique
est déjà diffusée à tous. La main n'apparaît qu'à son propriétaire, conformément à `docs/VISION.md`.

Les raisons de refus connues sont traduites en français. Une raison inconnue s'affiche telle quelle.

---

## Tests

* **`bots.lua`**, cas par cas : il tire quand il est désigné, n'accuse jamais sans pose précédente
  ni sa propre pose, et ne pose que des indices valides et distincts, de 1 à 3.
* **`bots.lua`, simulation** : quatre bots jouent 50 parties avec un hasard à graine fixe, jusqu'au
  vainqueur, sans une seule erreur du moteur et en un nombre d'actes borné. Ce test éprouve aussi le
  moteur de règles.
* **`journal.lua`** : chaque événement produit la bonne ligne et le bon état ; la sélection est
  refusée hors de son tour et plafonnée à 3 ; un spectateur n'a pas de main ; un refus produit une
  ligne `refus`.
* **L'adaptateur, `hud.lua` et la commande de chat** restent hors banc, comme aujourd'hui. On les
  vérifie en jeu : `/bots 3`, E sur le revolver, puis une partie jusqu'au vainqueur.

---

## Hors de cette version

* L'éventail 3D et les cartes physiques. Les assets sont en préparation : les Rois, Dames et As
  d'un jeu de 52 cartes, importés en modèles statiques (une carte = un modèle), plus un Joker à
  fabriquer, car ce jeu n'en a pas.
* L'animation assise, le blocage du joueur sur sa chaise, et la caméra de table.
* Un HUD limité aux joueurs proches de la table : pour l'instant, tous les connectés le voient.
* Les messages d'erreur du moteur qui citent des numéros de place moteur au lieu des chaises.
  C'est un défaut connu : le HUD les affiche tels quels.
