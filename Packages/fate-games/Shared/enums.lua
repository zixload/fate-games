-- Enums partages client/serveur.
--
-- Shared/ est envoye au client : donnees et constantes uniquement, jamais de logique
-- ni de secret (cf. docs/ARCHITECTURE.md section 2).
--
-- Module de donnees : retourne directement une table, pas une fabrique.

local Enums = {}

Enums.LogLevel = {
    DEBUG = 1,
    INFO  = 2,
    WARN  = 3,
    ERROR = 4,
}

Enums.Need = {
    HUNGER  = "hunger",
    THIRST  = "thirst",
    FATIGUE = "fatigue",
    HYGIENE = "hygiene",
    SLEEP   = "sleep",
}

return Enums
