# Ergonomie de Liar's Bar

État au 25/09/2026. La logique de jeu est en place ; ce chantier concerne ce que
les joueurs voient et comprennent pendant une partie.

## Vue et lisibilité

- [x] Placer la caméra assise dans l'axe du buste, conserver le corps visible,
  masquer localement `Head` et `Neck` et limiter le regard à 55° vers le bas.
  Conserver `/cam` pour régler la position en jeu.
- [x] HUD B valide : petit barillet de six chambres près de la tête,
  tirs precedents en rouge, sans chiffre au centre. Un triangle rouge
  designe la personne qui joue ou doit tirer. Aucun pseudo dans ce HUD.
- [x] Invite d'interaction sans texte, assortie au barillet : pictogramme
  chaise, revolver ou objet ramassable. Aperçu : `art/interaction_hud_preview.png`.
- [ ] Valider en client les angles extrêmes de la caméra, la hauteur et la taille
  du barillet, avec plusieurs résolutions et plusieurs joueurs.
- [ ] Épurer le journal en haut à gauche après essai : garder les événements
  récents utiles, laisser le tour et le tir près des personnages concernés.

## Mouvement de la tête sur la chaise

- [ ] Ajouter `LookYaw` et `LookPitch` dans `ABP_Creative` (ADK), puis modifier
  `Neck` et `Head` de façon additive sur l'animation assise. Garder le buste
  orienté vers la table ; borner et lisser la rotation de la tête.
- [ ] Envoyer l'orientation du regard du joueur assis aux autres clients à une
  fréquence limitée. Remettre les valeurs à zéro quand il se lève, quitte la
  partie ou se déconnecte. Aucun envoi n'est nécessaire pour les bots immobiles.
- [ ] Recuire `my-asset-pack` et vérifier en jeu que les autres voient bien le
  mouvement, sans décaler la caméra du joueur local.

## Geste du revolver

- [x] Un Nagant par chaise, posé devant son propriétaire ; chaque interaction
  pointe vers le barillet individuel déjà géré par le moteur.
- [x] Créer dans Blender Steam une animation assise sur le squelette Creative :
  la main rejoint la table, monte vers la tempe, réagit au tir puis revient.
  Le même geste sert au tir à blanc et au tir fatal. Source :
  `art/animations/seated_revolver.blend`.
- [x] Importer et cuire `ANIM_Seated_Revolver` dans l'ADK et
  `my-asset-pack`. L'arme de la chaise s'attache à `RightHandProp` pendant le
  geste ; le coup est annoncé à 0,9 s, le prochain tour attend le retour.
- [ ] Valider en client que `DefaultSlot` du Blueprint joue bien le geste.
  Version Blender du 26/09 : paume corrigée vers la poignée, index qui se replie
  au tir, canon à 0,97 cm de la tempe sur le mannequin Creative. L'orientation
  du socket reste à confirmer après import Unreal et essai en jeu.
- [ ] Valider en jeu le geste en deux temps : E prend l'arme, la pose est
  maintenue à la tempe, puis clic gauche valide le tir. Les deux FBX sont
  exportés depuis `seated_revolver.blend` et le code du serveur/client est
  branché ; il reste à importer les deux animations dans l'ADK, cuire le pack
  et vérifier la prise. Le délai de sécurité résout toujours un joueur absent.
- [ ] Tester un tir à blanc, un tir fatal, un bot et une déconnexion au milieu
  du geste. Le résultat du jeu doit rester cohérent si l'animation échoue.

## Cartes et élimination

- [ ] Créer dans Blender les gestes pour prendre ses cartes, tenir l'éventail
  visible par soi et par les autres, puis déposer une à trois cartes sur la table.
  Synchroniser le retrait des cartes de la main et leur arrivée sur le tas.
- [ ] Sur un tir fatal, jouer une chute animée sur la chaise, sans ragdoll.
  Le corps reste visible à sa place jusqu'à la fin de la partie, puis la posture
  et les objets sont remis à zéro. Vérifier la vue du joueur éliminé.

## Mobilier de la table

- [x] Modéliser dans Blender une table et quatre chaises assorties, adaptées aux
  personnages assis et à la portée des mains. Prévoir le plateau pour les cartes
  et un revolver par place, avec quelques accessoires décoratifs qui ne masquent
  pas les actions.
- [x] Importer les modèles dans l'ADK et les placer dans MapEgypt. Coordonnées
  des cinq acteurs relevées dans Unreal ; points d'assise, barillet et tas de
  cartes recalés dans `Shared/liars_table.lua`.
- [ ] Vérifier en jeu l'assise, les cartes et les quatre revolvers sur les
  nouveaux meubles ; corriger après capture si un modèle traverse le plateau.
  Premier retour : assise légèrement trop reculée ; personnages avancés de
  8 cm vers la table, à recontrôler en jeu.

## Ambiance et apparence

- [ ] Choix du skin à la connexion, conservé pendant toute la partie.
- [x] Convertir `Downloads/gunshot.mp3` en OGG mono et jouer le tir fatal en
  3D ; un clic mécanique distinct indique une chambre vide. Les fichiers
  vivent dans le package et ne demandent pas de cook Unreal.
- [x] Activer la VOIP de proximité native de nanos world : voix positionnée
  sur les personnages, audible autour de la table sans canal global en double.
- [ ] Vérifier le son et la voix avec deux vrais joueurs et deux sorties audio.
- [ ] Ajouter les sons de pose des cartes, une musique d'ambiance et un
  éclairage qui renforce la tension.

## Critère de fin

Une partie complète à quatre places, avec au moins deux vrais joueurs, doit
rester lisible depuis la chaise et en spectateur. Aucun joueur ne voit son propre
cou en première personne ; un observateur perçoit vers qui regarde un joueur
assis et qui tire, sans devoir lire le journal.
