-- Commande /fan : regler en jeu l'eventail et la table, sans redemarrer.
--
-- Cote client seulement : le message n'est jamais envoye (retour false, doc
-- Chat PlayerSubmit). Les reglages vivent le temps de la session ; les bonnes
-- valeurs sont ensuite reportees dans Shared/config.lua (liars_cards).
--
--   /fan                   affiche tous les reglages, a recopier tels quels
--   /fan demo              main et tas factices hors partie (bascule)
--   /fan pos x -1          deplace petit a petit : un axe et un pas
--   /fan rot p 5           (x, y, z pour pos et table ; p, ya, r pour les
--                          rotations, ya = lacet)
--   /fan pos x y z         ou trois valeurs absolues d'un coup :
--   /fan rot p y r           pos (pivot de l'eventail, depuis l'os de la main),
--   /fan carte p y r         rot (rotation du pivot), carte (chaque carte dans
--   /fan table x y z         sa fente), table (tas, depuis le centre du
--   /fan dos p y r           plateau), dos (carte face cachee sur la table),
--   /fan face p y r          face (carte revelee sur la table)
--   /fan os <nom>          os qui tient l'eventail (LeftHand, RightHand...)
--   /fan axe z|zy|y|x      axe autour duquel les cartes s'ouvrent
--   /fan sens              inverse le sens de rotation de l'eventail
--   /fan empilement        inverse quelle carte passe devant
--   /fan coin -0.5         deplace le pivot en largeur (negatif : a gauche)
--   /fan ecart -1          ajuste un nombre (avec signe), ou /fan ecart 3 le
--                          remplace, ou /fan ecart l'affiche :
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
        echelle = config.table, ecart_revelation = config.table,
        coin = config.fan,
    }
    local ORDRE_V = { "pos", "rot", "carte", "table", "dos", "face" }
    local ORDRE_N = { "ecart", "rayon", "coin", "taille", "levee", "curseur", "profondeur",
        "epaisseur", "dispersion", "echelle", "ecart_revelation" }

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
        Chat.AddMessage("/fan axe " .. tostring(config.fan.axe))
        Chat.AddMessage(("/fan sens %s   /fan empilement %s"):format(tostring(config.fan.sens), tostring(config.fan.empilement)))
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
        elseif cle == "sens" or cle == "empilement" then
            -- Bascule : les cartes tournent dans l'autre sens, ou l'autre carte
            -- passe devant.
            config.fan[cle] = -(config.fan[cle] or 1)
            Rendu.Reconstruire()
            Chat.AddMessage(("/fan %s %d"):format(cle, config.fan[cle]))
        elseif cle == "axe" then
            -- L'axe autour duquel les cartes pivotent (Client/liars_bar/cartes.lua).
            -- Le bon : les cartes s'ouvrent en eventail au lieu de glisser en ligne.
            if mots[3] then config.fan.axe = mots[3]; Rendu.Reconstruire() end
            Chat.AddMessage("/fan axe " .. tostring(config.fan.axe) .. "   (essayer z, zy, y, x)")
        elseif cle == "os" then
            if mots[3] then
                config.bone_simple = mots[3]
                Rendu.Reconstruire()
            end
            Chat.AddMessage("/fan os " .. tostring(config.bone_simple))
            -- Diagnostic : ou sont les os des mains sur un personnage assis
            -- (un bot de la demo, sinon soi). Un os introuvable fait accrocher
            -- les cartes a l'origine du personnage, pres des pieds.
            local cible = nil
            for _, c in pairs(CharacterSimple.GetPairs()) do
                if c:IsValid() and c:GetValue("liars_chair", 0) > 0 then cible = c break end
            end
            local player = Client.GetLocalPlayer()
            cible = cible or (player and player:GetControlledCharacter())
            if cible then
                local o = cible:GetLocation()
                for _, os_nom in ipairs({ "LeftHand", "RightHand", "LeftHandProp", "RightHandProp", "Head" }) do
                    local ok, tr = pcall(function() return cible:GetSocketTransform(os_nom) end)
                    local l = ok and tr and tr.Location
                    if l and l.X then
                        local dx, dy, dz = l.X - o.X, l.Y - o.Y, l.Z - o.Z
                        Chat.AddMessage(("  %s : %.0f cm du centre (hauteur %+.0f)"):format(
                            os_nom, math.sqrt(dx * dx + dy * dy + dz * dz), dz))
                    else
                        Chat.AddMessage("  " .. os_nom .. " : introuvable")
                    end
                end
            end
        elseif VECTEURS[cle] and mots[3] and not tonumber(mots[3]) then
            -- Reglage relatif : /fan pos x -1, /fan rot ya 5.
            local d = VECTEURS[cle]
            local t = d[1][d[2]]
            local axe = ({ x = "x", y = d[3][2], z = "z", p = "p", ya = "y", yaw = "y", r = "r" })[mots[3]]
            local pas = tonumber(mots[4])
            local connu = false
            for _, k in ipairs(d[3]) do if k == axe then connu = true end end
            if connu and pas then
                t[axe] = (t[axe] or 0) + pas
                Rendu.Reconstruire()
                Chat.AddMessage(("/fan %s %s %s %s"):format(cle,
                    tostring(t[d[3][1]]), tostring(t[d[3][2]]), tostring(t[d[3][3]])))
            else
                Chat.AddMessage(("/fan %s <axe> <pas> : axes %s"):format(cle,
                    d[3][1] == "x" and "x, y, z" or "p, ya, r"))
            end
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
            -- Avec un signe (+1, -0.5) : ajoute a la valeur actuelle. Sans signe :
            -- remplace. Ces reglages sont tous positifs, le signe ne prete pas a
            -- confusion.
            local brut = mots[3]
            local v = tonumber(brut)
            if v then
                local relatif = brut:sub(1, 1) == "+" or brut:sub(1, 1) == "-"
                NOMBRES[cle][cle] = relatif and (NOMBRES[cle][cle] or 0) + v or v
                Rendu.Reconstruire()
                Chat.AddMessage(("/fan %s %s"):format(cle, tostring(NOMBRES[cle][cle])))
            elseif not brut then
                Chat.AddMessage(("/fan %s %s"):format(cle, tostring(NOMBRES[cle][cle])))
            else
                Chat.AddMessage(("/fan %s attend un nombre (+1 ou -1 pour ajuster)"):format(cle))
            end
        else
            Chat.AddMessage("reglage inconnu : " .. cle .. " (taper /fan pour la liste)")
        end
        return false
    end)
end
