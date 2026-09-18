-- Marcher par defaut, courir avec Maj (personnage d'essai).
--
-- Le client signale seulement la touche ; c'est le serveur qui fixe la
-- vitesse. "LeftShift" est le nom Unreal de la touche, la doc nanos ne liste
-- pas les touches de modification : a verifier en jeu.

local TOUCHES = { LeftShift = true, RightShift = true }
local enfoncee = false

local function signaler(course)
    if course == enfoncee then return end
    enfoncee = course
    Events.CallRemote("zix:course", Reliability.Reliable, course)
end

Input.Subscribe("KeyPress", function(key_name)
    if TOUCHES[key_name] then signaler(true) end
end)

Input.Subscribe("KeyUp", function(key_name)
    if TOUCHES[key_name] then signaler(false) end
end)
