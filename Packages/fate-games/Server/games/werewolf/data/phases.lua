-- Phases du loup-garou et durees par defaut, en secondes. Donnees pures.
-- La nuit se deroule dans l'ordre de `nuit` ; une phase n'y entre que si son
-- role est dans la composition de la partie, vivant ou non : sauter la phase
-- d'un role mort revelerait sa mort a tout le monde.

return {
    durees = {
        night_cupid      = 25,
        night_guard      = 20,
        night_wolves     = 45,
        night_white_wolf = 20,
        night_seer       = 20,
        dawn             = 10,
        hunter_shot      = 15,
        day_mayor        = 60,    -- election du maire : debat et vote
        mayor_succession = 15,    -- le maire mort designe son successeur
        day_debate       = 180,   -- reglable dans le salon
        day_vote         = 45,
        execution        = 8,
    },

    -- role : qui agit ; premiere_seulement : la 1re nuit ; une_sur : toutes les n nuits.
    nuit = {
        { id = "night_cupid",      role = "cupid", premiere_seulement = true },
        { id = "night_guard",      role = "guard" },
        { id = "night_wolves",     role = "wolf" },
        { id = "night_white_wolf", role = "white_wolf", une_sur = 2 },
        { id = "night_seer",       role = "seer" },
    },

    -- Le jour, toujours dans cet ordre, puis la nuit suivante.
    jour = { "dawn", "day_debate", "day_vote", "execution" },

    -- Le maire est elu ce jour-la (le jour qui suit la nuit n), avant le debat,
    -- s'il n'y en a pas encore. Sa voix compte double et departage.
    maire = { jour = 2 },
}
