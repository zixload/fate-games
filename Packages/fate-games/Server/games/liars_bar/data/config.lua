-- Reglages de Liar's Bar. Valeurs a ajuster a l'usage : elles ont ete posees
-- sur le papier et n'ont encore jamais ete jouees a quatre.
return {
    -- cartes distribuees a chacun en debut de manche
    hand_size = 5,

    -- nombre maximal de cartes posables en un tour
    max_play = 3,

    -- Quatre places, pas six : le paquet de vingt cartes et les mains de cinq
    -- ne servent que quatre joueurs. C'est la table canonique du jeu, et la
    -- seule compatible avec l'arithmetique decrite dans data/deck.lua.
    min_players = 3,
    max_seats   = 4,

    -- chambres du barillet ; une seule balle, position tiree au hasard
    chambers = 6,

    -- delai avant qu'un tir se resolve tout seul, si le joueur designe se
    -- deconnecte ou reste inerte : sans lui la partie se bloque
    shoot_timeout = 15.0,
}
