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

-- Invite minimale dessinee directement par le moteur. Elle reste legere et ne
-- depend pas encore de la future WebUI des cartes et de la partie.
local prompt_label = nil
local prompt = Canvas(false, Color.TRANSPARENT, -1, true, true)

prompt:Subscribe("Update", function(self, width, height)
    if not prompt_label then return end

    local box_width  = math.min(420, width - 40)
    local box_height = 56
    local box_x      = (width - box_width) / 2
    local box_y      = height * 0.72

    self:DrawRect(
        "",
        Vector2D(box_x, box_y),
        Vector2D(box_width, box_height),
        Color(0.02, 0.02, 0.02, 0.82),
        BlendMode.AlphaBlend
    )
    self:DrawText(
        ("[ E ]  %s"):format(prompt_label),
        Vector2D(width / 2, box_y + box_height / 2),
        FontType.Roboto,
        22,
        Color.WHITE,
        0,
        true,
        true,
        Color.BLACK,
        Vector2D(1, 1),
        true,
        Color.BLACK
    )
end)

Events.Subscribe("zix:focus_changed", function(id, label)
    prompt_label = label
    prompt:SetVisibility(label ~= nil)

    if label then
        prompt:Repaint()
        Console.Log(("[ %s ]  (E)"):format(label))
    end
end)

Console.Log("[INFO][boot] Fate Games - client pret")

return {
    SendIntent = send_intent,
    Interaction = Interaction,
}
