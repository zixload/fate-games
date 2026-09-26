-- Se lever de sa chaise hors partie : Espace. Assis, on vise la table ou son
-- revolver, jamais sa propre chaise, donc E ne suffisait pas. Le serveur
-- decide : en partie, il refuse et l'on reste assis jusqu'au bout.

local chat_ouvert = false
Chat.Subscribe("Open", function() chat_ouvert = true end)
Chat.Subscribe("Close", function() chat_ouvert = false end)

Input.Subscribe("KeyPress", function(key_name)
    if key_name ~= "SpaceBar" or chat_ouvert then return end
    local player = Client.GetLocalPlayer()
    local character = player and player:GetControlledCharacter()
    -- "assis" est publie par le serveur sur le personnage (Client/posture.lua).
    if not (character and character:GetValue("assis")) then return end
    Events.CallRemote("liars:lever", Reliability.Reliable)
end)
