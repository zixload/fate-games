-- Allure du personnage d'essai : marcher, courir avec Maj, et ralentir en
-- reculant.
--
-- Le client ne fixe aucune vitesse : il signale ce qu'il constate, le serveur
-- decide. "LeftShift" est le nom Unreal de la touche, la doc nanos ne liste
-- pas les touches de modification : verifie en jeu.
--
-- Le recul se voit a la vitesse, pas aux touches : depuis que le corps suit
-- la camera, reculer c'est s'eloigner de la direction regardee, quelle que
-- soit la touche utilisee et quel que soit le clavier. Les animations de
-- recul du pack ont une foulee plus lente que celles d'avancee : sans
-- ralentir, les pieds glissent.

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

---------------------------------------------------------------- recul

-- Vitesse minimale pour juger d'un sens (cm/s) : en dessous, on ne recule pas.
local SEUIL_VITESSE = 20
-- Cosinus de l'angle entre le regard et le deplacement. Deux seuils pour ne
-- pas papillonner a la limite : on entre en recul a 127 degres, on en sort a
-- 113.
local ENTRER, SORTIR = -0.6, -0.4

local recule = false

local function juger()
    local player = Client.GetLocalPlayer()
    local perso = player and player:GetControlledCharacter()
    if not (perso and perso:IsValid()) then return false end

    local v = perso:GetVelocity()
    local plan = math.sqrt(v.X * v.X + v.Y * v.Y)
    if plan < SEUIL_VITESSE then return false end

    local avant = perso:GetRotation():GetForwardVector()
    local cos = (v.X * avant.X + v.Y * avant.Y) / plan
    if recule then return cos < SORTIR end
    return cos < ENTRER
end

Timer.SetInterval(function()
    local ok, arriere = pcall(juger)
    if not ok then return end
    if arriere == recule then return end
    recule = arriere
    Events.CallRemote("zix:recul", Reliability.Reliable, recule)
end, 100)
