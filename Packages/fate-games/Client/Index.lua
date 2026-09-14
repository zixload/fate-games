-- Point d'entree client.
--
-- Le client ne fait que de la presentation : UI, effets, camera, surbrillance. Aucune
-- decision de jeu ici (R1) — il envoie une intention et attend le verdict du serveur.

local SharedConfig = Package.Require("Shared/config.lua")

-- Cote client : CallRemote(evenement, fiabilite, ...). La fiabilite est un
-- parametre positionnel — l'omettre y fait glisser le nom de l'intention.
local function send_intent(name, payload)
    Events.CallRemote("zix:intent", Reliability.Reliable, name, payload)
end

Events.SubscribeRemote("zix:intent_result", function(name, ok, detail)
    if not ok then
        Console.Log(("intention refusee : %s (%s)"):format(tostring(name), tostring(detail)))
    end
end)

local Interaction = Package.Require("interaction/init.lua")(SharedConfig.interaction)
Interaction.Start()

-- En attendant une vraie interface, on ecrit l'invite dans la console. C'est le
-- point d'accroche ou se branchera la WebUI.
Events.Subscribe("zix:focus_changed", function(id, label)
    if label then
        Console.Log(("[ %s ]  (E)"):format(label))
    end
end)

Console.Log("[INFO][boot] Fate Games - client pret")

return {
    SendIntent = send_intent,
    Interaction = Interaction,
}
