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

    -- Bots de test (voir bots.lua). Ils ne jouent que si dev.liars_bots est
    -- vrai dans Server/core/config.lua.
    bots = {
        delay          = 3.0,   -- secondes avant qu'un bot joue
        accuse_percent = 30,    -- chance d'accuser quand une pose le permet
        body_offset    = 60.0,  -- recul du corps derriere sa chaise, en cm
    },

    -- La table dans MapEgypt : reperes des chaises et centre du plateau. Dans
    -- Shared, parce que le client en a besoin pour poser les cartes au centre ;
    -- rien de secret dans ces coordonnees.
    layout = Package.Require("Shared/liars_table.lua"),

    -- Decalage initial du Nagant par rapport a RightHandProp. /posebot fige
    -- un mannequin hors partie et /prise permet d'affiner ces six valeurs.
    revolver_prise = { x = -1.8, y = 3.0, z = -9.0, p = 57.1, ya = -24.4, r = 160.8 },
}
