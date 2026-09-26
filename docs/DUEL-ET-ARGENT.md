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

Une seule arène, derrière les trois portes du temple de MapEgypt : un cube nommé
`DUEL_1` posé dans la map depuis l'ADK, à la taille de la salle, lu par
`scripts/unreal/export_arenes.py`. `/arene` (mode dev) pose une arène ronde de test
sous ses pieds.

1. On entre dans l'arène : le panneau du duel s'ouvre. Le premier arrivé
   choisit la mise, parmi 0, 50, 100 et 250 (← →).
2. Le format suit le nombre de joueurs présents : deux font un 1v1, quatre un
   2v2, un cinquième ne peut pas entrer, un nombre impair attend. Les camps se
   remplissent dans l'ordre d'arrivée.
3. Chacun choisit son arme à la molette parmi celles qu'il possède, jusqu'au
   décompte et entre les manches.
4. Quand tout le monde est prêt (R), la mise est prélevée, puis décompte de 5
   secondes. Un joueur sans assez d'argent bloque le départ et est signalé.
5. Pendant le combat, l'arène est fermée : un joueur extérieur qui entre est
   renvoyé là où il était avant d'entrer, un combattant qui sort est ramené à
   son départ.
6. Manches : chacun réapparaît à son bout de l'arène avec 100 points de vie. Une
   manche se gagne quand tout le camp adverse est mort. Premier à deux manches.
7. Les spectateurs qui s'approchent peuvent suivre la vue d'un combattant.

Armes : toutes font les mêmes dégâts, on achète le look, pas un avantage. Le
combat se joue en première personne : le tireur voit son arme devant sa caméra
(le personnage n'a pas encore de pose de visée), les autres la voient dans sa
main. Chaque tir laisse une traînée du canon au point touché, visible de tous.

Tir : la détection d'un tir par rayon n'existe que chez le client (doc Trace).
Le client annonce sa cible, le serveur vérifie la cadence, les balles, la
portée, que les deux sont dans le même duel, dans des camps opposés et vivants.
Il ne peut pas vérifier la ligne de vue : suffisant entre amis, pas contre un
tricheur déterminé.

Plus tard : inviter un joueur en le visant (nanos ne donne pas la liste d'amis
Steam), une vraie pose de visée, des sons d'armes propres à chaque modèle.
