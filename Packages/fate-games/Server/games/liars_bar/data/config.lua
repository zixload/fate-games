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

    -- Salon (salon.lua) : mises proposees au premier humain assis, 0 = pour
    -- l'honneur ; bonus verse par la banque a chaque joueur en fin de partie.
    -- Une table avec un bot ne rapporte rien (docs/DUEL-ET-ARGENT.md).
    paliers = { 0, 50, 100, 250 },
    bonus_participation = 10,

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

    -- Prise reglee avec /posebot le 26/09/2026. /prise permet de l'affiner
    -- en direct ; verifier encore l'alignement du canon avec la tempe.
    revolver_prise = { x = 6.2, y = -3.0, z = -3.0, p = 142.1, ya = 35.6, r = 202.8 },
}
