-- Commande /fan : regler en jeu l'eventail et la table, sans redemarrer.
--
-- Cote client seulement : le message n'est jamais envoye (retour false, doc
-- Chat PlayerSubmit). Les reglages vivent le temps de la session ; les bonnes
-- valeurs sont ensuite reportees dans Shared/config.lua (liars_cards).
--
--   /fan                   affiche tous les reglages, a recopier tels quels
--   /fan demo              main et tas factices hors partie (bascule)
--   /fan pos x y z         pivot de l'eventail, depuis l'os de la main
--   /fan rot p y r         rotation du pivot
--   /fan carte p y r       rotation de chaque carte dans sa fente
--   /fan table x y z       tas, depuis le centre du plateau
--   /fan dos p y r         carte face cachee sur la table
--   /fan face p y r        carte revelee sur la table
--   /fan os <nom>          os qui tient l'eventail (LeftHand, RightHand...)
--   /fan <nombre> n        ecart, rayon, taille, levee, curseur, profondeur,
--                          epaisseur, dispersion

return function(config, Rendu)
    local VECTEURS = {
        pos   = { config.fan,   "pos",      { "x", "y", "z" } },
        rot   = { config.fan,   "rot",      { "p", "y", "r" } },
        carte = { config.fan,   "carte",    { "p", "y", "r" } },
        table = { config.table, "decalage", { "x", "y", "z" } },
        dos   = { config.table, "dos",      { "p", "y", "r" } },
        face  = { config.table, "face",     { "p", "y", "r" } },
    }
    local NOMBRES = {
        ecart = config.fan, rayon = config.fan, taille = config.fan,
        levee = config.fan, curseur = config.fan, profondeur = config.fan,
        epaisseur = config.table, dispersion = config.table,
    }
    local ORDRE_V = { "pos", "rot", "carte", "table", "dos", "face" }
    local ORDRE_N = { "ecart", "rayon", "taille", "levee", "curseur", "profondeur",
        "epaisseur", "dispersion" }

    local function afficher()
        for _, cle in ipairs(ORDRE_V) do
            local d = VECTEURS[cle]
            local t = d[1][d[2]]
            Chat.AddMessage(("/fan %s %s %s %s"):format(cle,
                tostring(t[d[3][1]]), tostring(t[d[3][2]]), tostring(t[d[3][3]])))
        end
        for _, cle in ipairs(ORDRE_N) do
            Chat.AddMessage(("/fan %s %s"):format(cle, tostring(NOMBRES[cle][cle])))
        end
    end

    Chat.Subscribe("PlayerSubmit", function(message)
        local mots = {}
        for m in tostring(message):gmatch("%S+") do mots[#mots + 1] = m end
        if mots[1] ~= "/fan" then return end

        local cle = mots[2]
        if not cle then
            afficher()
        elseif cle == "demo" then
            -- Le serveur assoit des bots sur toutes les chaises (mode dev) ; le
            -- rendu leur donne un eventail de demonstration a chacun.
            Rendu.Demo(not Rendu.IsDemo())
            Events.CallRemote("liars:fan_demo", Reliability.Reliable, Rendu.IsDemo())
            Chat.AddMessage("demo : " .. (Rendu.IsDemo() and "active" or "coupee"))
        elseif cle == "os" then
            if mots[3] then
                config.bone_simple = mots[3]
                Rendu.Reconstruire()
            end
            Chat.AddMessage("/fan os " .. tostring(config.bone_simple))
        elseif VECTEURS[cle] then
            local a, b, c = tonumber(mots[3]), tonumber(mots[4]), tonumber(mots[5])
            if a and b and c then
                local d = VECTEURS[cle]
                local t = d[1][d[2]]
                t[d[3][1]], t[d[3][2]], t[d[3][3]] = a, b, c
                Rendu.Reconstruire()
                Chat.AddMessage(("/fan %s %s %s %s"):format(cle, mots[3], mots[4], mots[5]))
            else
                Chat.AddMessage(("/fan %s attend trois nombres"):format(cle))
            end
        elseif NOMBRES[cle] then
            local v = tonumber(mots[3])
            if v then
                NOMBRES[cle][cle] = v
                Rendu.Reconstruire()
                Chat.AddMessage(("/fan %s %s"):format(cle, mots[3]))
            else
                Chat.AddMessage(("/fan %s attend un nombre"):format(cle))
            end
        else
            Chat.AddMessage("reglage inconnu : " .. cle .. " (taper /fan pour la liste)")
        end
        return false
    end)
end
