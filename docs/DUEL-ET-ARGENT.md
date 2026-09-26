# Argent des modes et duel

Décidé le 26/09/2026.

## L'argent des modes

Chaque mode payant fonctionne pareil :

- tous les joueurs misent le même montant au lancement ;
- le serveur garde la mise de côté, dans un compte `sequestre:<partie>` du journal ;
- à la fin, le gagnant rafle la cagnotte ; en équipe, les gagnants se la partagent,
  le reste de la division allant au premier ;
- chaque partie terminée rapporte en plus un petit bonus à tous les joueurs,
  payé par la banque : c'est ce qui fait entrer de l'argent dans le jeu ;
- qui quitte en cours perd sa mise, qui reste dans la cagnotte ;
- une partie avec des bots ne rapporte rien.

Tout passe par le journal `ledger` (R6) : le solde n'est jamais écrit, il se
déduit des mouvements.

## Le duel

Une arène au sol sur la carte : un cercle, placé avec `/arene` (mode dev).

1. On entre dans le cercle : le panneau du duel s'ouvre. Le premier arrivé
   choisit le format (1v1 ou 2v2) et la mise, parmi 0, 50, 100 et 250.
2. Les autres voient format et mise avant d'entrer. Les camps se remplissent
   dans l'ordre d'arrivée.
3. Quand l'arène est pleine et que tout le monde est prêt, la mise est prélevée,
   puis décompte de 3 secondes. Un joueur sans assez d'argent bloque le départ
   et est signalé.
4. Pendant le combat, l'arène est fermée : un joueur extérieur qui entre est
   repoussé au bord, un combattant qui sort est ramené dedans.
5. Manches : chacun réapparaît à son bout de l'arène avec 100 points de vie. Une
   manche se gagne quand tout le camp adverse est mort. Premier à deux manches.
6. Les spectateurs qui s'approchent peuvent suivre la vue d'un combattant.

Armes : chacun porte l'arme équipée au vestiaire. Toutes font les mêmes dégâts,
on achète le look, pas un avantage.

Tir : la détection d'un tir par rayon n'existe que chez le client (doc Trace).
Le client annonce sa cible, le serveur vérifie la cadence, les balles, la
portée, que les deux sont dans le même duel, dans des camps opposés et vivants.
Il ne peut pas vérifier la ligne de vue : suffisant entre amis, pas contre un
tricheur déterminé.

Plus tard : inviter un joueur en le visant (nanos ne donne pas la liste d'amis
Steam), une vraie pose de visée, des sons d'armes propres à chaque modèle.
