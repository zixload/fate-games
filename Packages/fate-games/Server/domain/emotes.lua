-- Emotes : la roue du client (Client/emotes.lua) demande un emplacement, le
-- serveur joue l'animation sur le personnage. Refuse assis (la posture de la
-- chaise casserait) et pour un emplacement encore sans animation. Bouger
-- l'arrete (le client l'annonce).
--
-- PlayAnimation n'existe que cote serveur pour CharacterSimple (doc
-- CharacterSimple) ; l'ancien Character a un autre ordre de parametres.

return function(Log, Characters, config)
    local Emotes = {}
    local en_cours = {}      -- player_id -> chemin de l'animation jouee
    local dernier = {}       -- player_id -> Server.GetTime() du dernier emote

    local function arreter(player_id, character)
        local anim = en_cours[player_id]
        en_cours[player_id] = nil
        if anim and character and character:IsValid() then
            pcall(function() character:StopAnimation(anim) end)
        end
    end

    local function jouer(player, i)
        local id = player:GetID()
        local slot = type(i) == "number" and config.liste[math.floor(i)]
        if not (slot and slot.anim ~= "") then return end
        local session = Characters.SessionByPlayer(id)
        local character = session and session.character
        if not (character and character:IsValid()) or session.assis then return end
        local maintenant = Server.GetTime()
        if maintenant - (dernier[id] or 0) < 400 then return end
        dernier[id] = maintenant

        arreter(id, character)
        local ok, err = pcall(function()
            if character:IsA(CharacterSimple) then
                character:PlayAnimation(slot.anim, "DefaultSlot", slot.boucle ~= false, 0.2, 0.3, 1.0, true)
            else
                character:PlayAnimation(slot.anim, "DefaultSlot", 0.2, 0.3, 1.0, slot.boucle ~= false, true)
            end
        end)
        if ok then
            en_cours[id] = slot.anim
        else
            Log.Warn("emotes", ("%s : %s"):format(tostring(slot.titre), tostring(err)))
        end
    end

    function Emotes.Init()
        Events.SubscribeRemote("emote:jouer", function(player, i) jouer(player, tonumber(i)) end)
        Events.SubscribeRemote("emote:stop", function(player)
            local session = Characters.SessionByPlayer(player:GetID())
            arreter(player:GetID(), session and session.character)
        end)
    end

    function Emotes.OnPlayerLeave(player)
        en_cours[player:GetID()] = nil
        dernier[player:GetID()] = nil
    end

    return Emotes
end
