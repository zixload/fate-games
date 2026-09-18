-- Constantes de gameplay partagees client/serveur.
--
-- Ce fichier part chez le client : rien ici ne doit etre secret, et le serveur ne doit
-- jamais faire confiance a une valeur que le client pourrait avoir modifiee de son cote.
-- La configuration serveur (base, intervalles de flush) vit dans Server/core/config.lua.

return {
    interaction = {
        -- Portee de la visee, en centimetres. Plus longue que la portee serveur :
        -- on peut lire l'invite d'un peu plus loin qu'on ne peut agir.
        reach = 400.0,
        -- Periode du balayage. Viser n'a pas besoin de 60 traces par seconde.
        scan_interval_ms = 150,
        key = "E",
    },

    -- HUD provisoire de Liar's Bar (Client/liars_bar/). Noms de touches de la
    -- doc Input. Pas Enter pour poser : il risque de servir au chat.
    liars_hud = {
        journal_lines = 8,
        -- Miroir du plafond serveur (games/liars_bar/data/config.lua), qui
        -- seul fait foi : ici il ne sert qu'a ne pas proposer l'impossible.
        max_play = 3,
        keys = {
            -- Une liste de noms par carte, le premier sert d'etiquette dans le
            -- HUD. Des lettres plutot que des chiffres : Unreal nomme une touche
            -- d'apres le caractere qu'elle tape, et en AZERTY la touche 1 tape
            -- "&". Une lettre porte le meme nom sur tous les claviers.
            select = { { "W" }, { "X" }, { "C" }, { "V" }, { "B" } },
            play   = "P",
            accuse = "M",
        },
    },

    scheduler = {
        -- duree d'un tour de roue : chaque entite inscrite est traitee une fois par tour
        wheel_seconds = 60,
        -- periode d'un tick ; le plus court utile est le tick rate serveur, ~33 ms
        tick_ms       = 1000,
    },
}
