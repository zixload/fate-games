-- PNJ d'ambiance de la place : crieur, tailleur, forain, barman, conteuse,
-- musicien, touriste (Shared/config.lua, pnj.types).
--
-- Places posees en jeu (mode dev) et gardees dans pnj.json, a la racine du
-- serveur (File n'ecrit que la, doc File) :
--   /pnj poser <type>   ici, tourne comme moi
--   /pnj retirer        le plus proche (3 m)
--   /pnj deplacer <type> ce PNJ vient ici, tourne comme moi (le plus proche
--                       de moi s'il y en a plusieurs de ce type)
--   /pnj cabine         ici, tourne comme moi : la place d'essayage du
--                       tailleur le plus proche (le joueur y est pose, la
--                       camera le cadre toujours pareil)
--   /pnj liste          les types connus
--   /pnj cacher|montrer tous les PNJ caches (en attendant leurs tenues et
--                       animations) ; leurs interactions restent : E a la place
--                       du tailleur ouvre toujours le vestiaire.
--
-- Corps Creative habille d'une apparence existante (Shared/appearances.lua)
-- en attendant les tenues des PNJ ; debout, ou assis au sol avec une pose du
-- loup-garou. Quand un joueur passe pres de lui, il dit une de ses repliques
-- (sons de my-asset-pack, entendus en 3D par tous, Client/pnj.lua), puis se
-- tait un moment. Le regard vers les passants est calcule par chaque client.
--
-- Un type peut avoir une interaction (E, invite du client) : un repere
-- invisible devant lui, enregistre dans Interactables, qui appelle
-- actions[interaction.action](player). Le tailleur ouvre ainsi le vestiaire.

return function(Log, Characters, config, dev_pour, Interactables, actions)
    local Pnj = {}
    config = config or {}
    local Apparences = Package.Require("Shared/appearances.lua")
    local TYPES = config.types or {}
    local FICHIER = config.fichier or "pnj.json"
    local RAYON_VOIX = config.rayon_voix or 600      -- cm
    local PAUSE = (config.pause or 25) * 1000       -- ms entre deux repliques d'un PNJ

    local places = {}      -- { { type, x, y, z, yaw } }, tel qu'enregistre
    local caches = false   -- /pnj cacher : les corps ne sont pas crees
    local vivants = {}     -- index de place -> { corps, def, dernier }

    local function lire()
        if not File.Exists(FICHIER) then return {} end
        local f = File(FICHIER)
        local texte = f:Read(0)
        f:Close()
        local ok, t = pcall(JSON.parse, texte)
        if not (ok and type(t) == "table") then return {} end
        -- Ancien format : la liste seule ; nouveau : { places, caches }.
        if t.places then
            caches = t.caches == true
            return t.places
        end
        return t
    end

    local function ecrire()
        local f = File(FICHIER, true)
        f:Write(JSON.stringify({ places = places, caches = caches }))
        f:Close()
    end

    local function habiller(corps, look_id)
        local look = look_id and Apparences.Resolve(look_id)
        if not look then return end
        pcall(function()
            corps:SetMesh(look.body)
            corps:RemoveAllSkeletalMeshesAttached()
            for i, mesh in ipairs(look.head) do corps:AddSkeletalMeshAttached("pnj_tete_" .. i, mesh) end
            for i, mesh in ipairs(look.worn) do corps:AddSkeletalMeshAttached("pnj_tenue_" .. i, mesh) end
        end)
    end

    local function faire_apparaitre(i)
        local p = places[i]
        local def = p and TYPES[p.type]
        if not def then return end
        local corps
        if not caches then
            local ok, err = pcall(function()
                if def.assis then
                    corps = Characters.CorpsAssis(p.x, p.y, p.z + (def.assis.z or 11), p.yaw)
                else
                    corps = Characters.CorpsDebout(p.x, p.y, p.z, p.yaw)
                end
            end)
            if not (ok and corps) then return Log.Warn("pnj", ("%s : corps impossible (%s)"):format(p.type, tostring(err))) end
            habiller(corps, def.look)
            local anim = def.assis and def.assis.anim or def.anim
            if anim then
                pcall(function() corps:PlayAnimation(anim, "DefaultSlot", true, 0.2, 0.2, 1.0, true) end)
            end
            corps:SetValue("pnj", p.type, true)
        end
        -- Son interaction : un repere invisible a hauteur de buste (le client
        -- ne vise que des Props, Client/interaction/init.lua).
        local repere, inter
        local it = def.interaction
        if it and Interactables then
            pcall(function()
                repere = Prop(Vector(p.x, p.y, p.z + 10), Rotator(0, p.yaw, 0), "nanos-world::SM_Cube",
                    CollisionType.IgnoreOnlyPawn, false, GrabMode.Disabled)
                repere:SetScale(Vector(0.7, 0.7, 1.4))
                repere:SetVisibility(false)
                inter = Interactables.Register(repere, {
                    label = it.label or "Parler", kind = it.kind or "pickup",
                    max_distance = it.portee or 300,
                    on_interact = function(player)
                        local f = actions and actions[it.action]
                        local v = vivants[i]
                        if f then f(player, { corps = v and v.corps, place = p }) end
                    end,
                })
            end)
        end
        -- Le nom au-dessus de la tete (Client/pseudos.lua).
        if corps and def.nom then corps:SetValue("pseudo", def.nom, true) end
        vivants[i] = { corps = corps, def = def, dernier = 0, repere = repere, inter = inter }
    end

    local function tout_recreer()
        for _, v in pairs(vivants) do
            if v.inter and Interactables then pcall(Interactables.Unregister, v.inter) end
            if v.repere and v.repere:IsValid() then pcall(function() v.repere:Destroy() end) end
            if v.corps and v.corps:IsValid() then pcall(function() v.corps:Destroy() end) end
        end
        vivants = {}
        for i in ipairs(places) do faire_apparaitre(i) end
    end

    local function dire(player, texte) Chat.SendMessage(player, texte) end

    local function commande(message, player)
        local mots = {}
        for m in tostring(message):gmatch("%S+") do mots[#mots + 1] = m end
        if mots[1] ~= "/pnj" then return end
        if not dev_pour(player) then return end
        local c = player:GetControlledCharacter()
        if mots[2] == "poser" then
            local t = mots[3]
            if not (t and TYPES[t]) then dire(player, "/pnj poser <type> : /pnj liste pour les types") return false end
            if not c then return false end
            local l, r = c:GetLocation(), c:GetRotation()
            places[#places + 1] = { type = t, x = l.X, y = l.Y, z = l.Z, yaw = r.Yaw }
            ecrire()
            faire_apparaitre(#places)
            dire(player, ("%s pose ici (%d PNJ)"):format(TYPES[t].nom or t, #places))
        elseif mots[2] == "retirer" then
            if not c then return false end
            local l = c:GetLocation()
            local meilleur, d_min = nil, 300
            for i, p in ipairs(places) do
                local d = math.sqrt((p.x - l.X) ^ 2 + (p.y - l.Y) ^ 2 + (p.z - l.Z) ^ 2)
                if d < d_min then meilleur, d_min = i, d end
            end
            if not meilleur then dire(player, "Aucun PNJ a moins de 3 m.") return false end
            local t = places[meilleur].type
            table.remove(places, meilleur)
            ecrire()
            tout_recreer()
            dire(player, ("%s retire (%d PNJ)"):format(TYPES[t] and TYPES[t].nom or t, #places))
        elseif mots[2] == "deplacer" then
            local t = mots[3]
            if not (t and TYPES[t]) then dire(player, "/pnj deplacer <type> : /pnj liste pour les types") return false end
            if not c then return false end
            local l, r = c:GetLocation(), c:GetRotation()
            local meilleur, d_min = nil, math.huge
            for i, p in ipairs(places) do
                if p.type == t then
                    local d = (p.x - l.X) ^ 2 + (p.y - l.Y) ^ 2 + (p.z - l.Z) ^ 2
                    if d < d_min then meilleur, d_min = i, d end
                end
            end
            if not meilleur then dire(player, ("Aucun %s pose : /pnj poser %s"):format(t, t)) return false end
            local p = places[meilleur]
            p.x, p.y, p.z, p.yaw = l.X, l.Y, l.Z, r.Yaw
            ecrire()
            tout_recreer()
            dire(player, ("%s deplace ici"):format(TYPES[t].nom or t))
        elseif mots[2] == "cabine" then
            if not c then return false end
            local l, r = c:GetLocation(), c:GetRotation()
            local meilleur, d_min = nil, math.huge
            for i, p in ipairs(places) do
                if p.type == "tailleur" then
                    local d = (p.x - l.X) ^ 2 + (p.y - l.Y) ^ 2 + (p.z - l.Z) ^ 2
                    if d < d_min then meilleur, d_min = i, d end
                end
            end
            if not meilleur then dire(player, "Aucun tailleur pose : /pnj poser tailleur") return false end
            places[meilleur].cabine = { x = l.X, y = l.Y, z = l.Z, yaw = r.Yaw }
            ecrire()
            tout_recreer()
            dire(player, "Place d'essayage du tailleur enregistree ici.")
        elseif mots[2] == "cacher" or mots[2] == "montrer" then
            caches = mots[2] == "cacher"
            ecrire()
            tout_recreer()
            dire(player, caches and "PNJ caches (le vestiaire reste a la place du tailleur)." or "PNJ de retour.")
        else
            local noms = {}
            for t in pairs(TYPES) do noms[#noms + 1] = t end
            table.sort(noms)
            dire(player, "/pnj poser|deplacer <" .. table.concat(noms, "|") .. "> | /pnj retirer | /pnj cabine | /pnj cacher | /pnj montrer")
        end
        return false
    end

    -- Un joueur pres d'un PNJ qui a des repliques : il parle, puis se tait.
    local function voix()
        local maintenant = Server.GetTime()
        local positions = {}
        for _, pl in pairs(Player.GetPairs()) do
            local c = pl:GetControlledCharacter()
            if c and c:IsValid() then positions[#positions + 1] = c:GetLocation() end
        end
        if #positions == 0 then return end
        for _, v in pairs(vivants) do
            local phrases = v.def.phrases
            if phrases and #phrases > 0 and v.corps and v.corps:IsValid() and maintenant - v.dernier >= PAUSE then
                local l = v.corps:GetLocation()
                for _, pos in ipairs(positions) do
                    if (pos - l):Size() <= RAYON_VOIX then
                        v.dernier = maintenant
                        Events.BroadcastRemote("pnj:parle", Reliability.Reliable, v.corps:GetID(),
                            phrases[math.random(#phrases)])
                        break
                    end
                end
            end
        end
    end

    function Pnj.Init()
        places = lire()
        tout_recreer()
        Chat.Subscribe("PlayerSubmit", commande)
        Timer.SetInterval(voix, 1000)
        if #places > 0 then Log.Info("pnj", ("%d PNJ sur la place"):format(#places)) end
    end

    return Pnj
end
