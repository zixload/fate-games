-- Apercu du ciel jour/nuit (Sky de nanos, Ultra Dynamic Sky), pas encore
-- branche sur la partie :
--   /lg ciel jour | nuit | aube | soir | <heure>[:<minutes>]
-- Le premier appel lance Sky.Spawn, qui remplace le soleil, le ciel et le
-- brouillard de la map chez ce joueur. Pour retrouver l'eclairage d'origine,
-- se reconnecter.

return function()
    local MOMENTS = { jour = { 12, 0 }, aube = { 7, 0 }, soir = { 19, 30 }, nuit = { 23, 0 } }
    local TRANSITION = 4   -- secondes
    local pret = false

    local function preparer()
        if pret then return true end
        local ok, trouve = pcall(Sky.Spawn, false, true)
        if not ok then
            Chat.AddMessage("ciel : Sky.Spawn a echoue : " .. tostring(trouve))
            return false
        end
        pcall(Sky.SetAnimateTimeOfDay, false)
        pcall(Sky.SetMoonPhase, 15)          -- pleine lune (0 a 30)
        pret = true
        Chat.AddMessage(trouve and "ciel : Ultra Dynamic Sky de la map repris"
            or "ciel : Ultra Dynamic Sky pose (eclairage de la map remplace, reconnecte-toi pour l'annuler)")
        return true
    end

    Chat.Subscribe("PlayerSubmit", function(message)
        local arg = tostring(message):match("^/lg ciel%s*(%S*)")
        if not arg then return end
        local h, m
        if MOMENTS[arg] then
            h, m = MOMENTS[arg][1], MOMENTS[arg][2]
        else
            h, m = arg:match("^(%d+):?(%d*)$")
            h, m = tonumber(h), tonumber(m) or 0
        end
        if not (h and h >= 0 and h <= 23 and m >= 0 and m <= 59) then
            Chat.AddMessage("/lg ciel jour | nuit | aube | soir | <heure>[:<minutes>]")
            return false
        end
        if preparer() then
            local ok, err = pcall(Sky.SetTimeOfDay, h, m, TRANSITION)
            Chat.AddMessage(ok and string.format("ciel : %02d:%02d", h, m) or ("ciel : " .. tostring(err)))
        end
        return false
    end)
end
