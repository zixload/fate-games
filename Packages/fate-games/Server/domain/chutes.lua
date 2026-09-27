-- Chutes : qui tombe de haut s'ecrase a l'arrivee. Le client du joueur voit
-- sa propre chute (Client/bruits.lua) et l'annonce a l'impact avec sa hauteur
-- en cm (du point le plus haut atteint en l'air au sol d'arrivee) ; le
-- serveur choisit l'animation selon cette hauteur, la joue et immobilise le
-- personnage le temps qu'elle dure.
--
--   reception dure (Hard Landing)              hauteur >= seuil_dure
--   chute a plat puis relevement (Falling Flat) hauteur >= seuil_sol
--
-- Pas de vrai ragdoll : SetRagdollMode n'existe que pour Character, et les
-- joueurs sont des CharacterSimple (doc Character, doc CharacterSimple). Le
-- relevement fait partie de l'animation (scripts/blender/create_chutes.py).
-- PlayAnimation n'existe que cote serveur pour CharacterSimple (doc
-- CharacterSimple).
--
-- La hauteur vient du client : elle ne decide que d'un effet sur son propre
-- personnage, bornee et limitee a une chute toutes les deux secondes.

return function(Log, Characters, config)
    local Chutes = {}
    config = config or {}
    local dernier = {}     -- player_id -> Server.GetTime() de la derniere chute
    local en_cours = {}    -- player_id -> true

    local function choisir(hauteur)
        if hauteur >= (config.seuil_sol or 230) then return config.sol end
        if hauteur >= (config.seuil_dure or 135) then return config.dure end
        return nil
    end

    local function chute(player, hauteur)
        if not config.actif then return end
        local id = player:GetID()
        if en_cours[id] then return end
        hauteur = tonumber(hauteur)   -- cm
        if not hauteur or hauteur ~= hauteur or hauteur < 0 or hauteur > 100000 then return end
        local maintenant = Server.GetTime()
        if maintenant - (dernier[id] or 0) < 2000 then return end
        local quoi = choisir(hauteur)
        if not quoi then return end
        local session = Characters.SessionByPlayer(id)
        local c = session and session.character
        if not (c and c:IsValid() and c:IsA(CharacterSimple)) or session.assis then return end

        dernier[id] = maintenant
        local ok, err = pcall(function()
            c:PlayAnimation(quoi.anim, "DefaultSlot", false, quoi.fondu_entree or 0.05,
                quoi.fondu_sortie or 0.6, 1.0, true)
        end)
        if not ok then return Log.Warn("chutes", tostring(err)) end
        en_cours[id] = true
        Characters.Immobiliser(id, true)
        Timer.SetTimeout(function()
            en_cours[id] = nil
            Characters.Immobiliser(id, false)
        end, math.floor((quoi.duree or 1) * 1000))
    end

    function Chutes.Init()
        Events.SubscribeRemote("zix:chute", chute)
    end

    function Chutes.OnPlayerLeave(player)
        dernier[player:GetID()] = nil
        en_cours[player:GetID()] = nil
    end

    return Chutes
end
