-- Invite d'interaction sans texte, dans la palette du barillet.
-- Le serveur fournit seulement le type visuel ; la validation reste cote serveur.

return function(interaction)
    local page = WebUI("interaction-invite", "file://interaction/invite.html",
        WidgetVisibility.VisibleNotHitTestable, true, true)
    local pret = false
    local kind = nil
    local gun_state = nil

    local function afficher()
        if pret then
            page:CallEvent("interaction:focus",
                gun_state and "revolver" or (kind or ""), gun_state == "ready")
        end
    end

    page:Subscribe("Ready", function()
        pret = true
        page:BringToFront()
        afficher()
    end)
    page:Subscribe("pret", function()
        pret = true
        afficher()
    end)
    page:Subscribe("Fail", function(_, code, message)
        Console.Error(("[interaction] invite WebUI impossible (%s) : %s")
            :format(tostring(code), tostring(message)))
    end)

    Events.Subscribe("zix:focus_changed", function(id, _, type_visuel)
        kind = id and (type_visuel or "pickup") or nil
        afficher()
    end)

    Events.Subscribe("liars:gun_state", function(state)
        gun_state = state
        afficher()
    end)

    if interaction.GetFocus() then kind = "pickup" end
end
