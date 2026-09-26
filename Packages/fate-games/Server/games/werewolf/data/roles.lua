-- Registre des roles du loup-garou (docs/superpowers/specs/2026-09-15-loup-garou-design.md).
-- Donnees pures. Un role s'ajoute ici, avec au besoin sa phase de nuit dans
-- data/phases.lua ; le moteur n'a pas a changer.
--
--   camp        "village", "wolves" ou "white_wolf" (le loup blanc gagne seul)
--   loup        vu comme un loup par les autres loups, et vote avec eux la nuit
--   on_death    phase empilee a sa mort (le chasseur tire)

return {
    MIN_JOUEURS = 4,
    MAX_JOUEURS = 12,

    roles = {
        wolf       = { camp = "wolves", loup = true },
        white_wolf = { camp = "white_wolf", loup = true },
        villager   = { camp = "village" },
        seer       = { camp = "village" },
        hunter     = { camp = "village", on_death = "hunter_shot" },
        guard      = { camp = "village" },
        cupid      = { camp = "village" },
    },

    -- Bornes des reglages du salon, par role (les villageois completent).
    bornes = {
        wolf       = { 1, 4 },
        white_wolf = { 0, 1 },
        seer       = { 0, 1 },
        hunter     = { 0, 1 },
        guard      = { 0, 1 },
        cupid      = { 0, 1 },
    },

    -- Ordre des roles speciaux dans le salon et dans le tirage.
    speciaux = { "wolf", "white_wolf", "seer", "hunter", "guard", "cupid" },

    -- Composition par defaut selon le nombre de joueurs (spec, tableau
    -- Composition) : les autres roles sont a 0, le createur les ajoute.
    par_defaut = function(n)
        local loups = n <= 5 and 1 or (n <= 8 and 2 or 3)
        return { wolf = loups, white_wolf = 0, seer = 1, hunter = 0, guard = 0, cupid = 0 }
    end,
}
