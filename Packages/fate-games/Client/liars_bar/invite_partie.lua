-- En partie de Liar's Bar, l'invite d'interaction ne montre que ce qui sert :
-- son propre revolver, et seulement quand on doit tirer. Les chaises, les
-- revolvers des autres et le reste restent muets jusqu'a la fin de la partie.
-- Filtre d'affichage seulement : le serveur refuse de toute facon ce qui
-- n'est pas permis (games/liars_bar/adapter.lua).

return function(interaction)
    local en_partie = false
    local tireur = nil           -- chaise designee pour tirer, nil sinon

    Events.SubscribeRemote("liars:deal", function() en_partie = true end)
    Events.SubscribeRemote("liars:turn", function() en_partie = true end)
    Events.SubscribeRemote("liars:designated", function(chaise)
        en_partie = true
        tireur = chaise
    end)
    Events.SubscribeRemote("liars:shoot", function() tireur = nil end)
    Events.SubscribeRemote("liars:round_ended", function() tireur = nil end)
    Events.SubscribeRemote("liars:match_ended", function()
        en_partie = false
        tireur = nil
    end)

    local function ma_chaise()
        local player = Client.GetLocalPlayer()
        local perso = player and player:GetControlledCharacter()
        local chaise = perso and perso:GetValue("liars_chair", 0) or 0
        return chaise > 0 and chaise or nil
    end

    interaction.SetFiltre(function(entite)
        local chaise = ma_chaise()
        -- Pas assis a la table, ou pas de partie : tout reste visable.
        if not (en_partie and chaise) then return true end
        if not (entite and entite:IsValid()) then return false end
        return tireur == chaise and entite:GetValue("liars_revolver_chair", 0) == chaise
    end)
end
