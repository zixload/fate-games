-- PNJ d'ambiance, cote client (Server/domain/pnj.lua) : leurs repliques en
-- 3D, et leur tete qui suit le joueur qui s'approche.
--
-- Le regard est calcule par chaque client vers son propre personnage : chacun
-- voit le PNJ le regarder, lui. Memes proprietes du rig que le regard des
-- joueurs assis (LookNeck, LookHead, Client/regard_assis.lua), memes signes.

return function(config)
    config = config or {}
    local chemin = Package.Require("son.lua")
    local R = Package.Require("Shared/config.lua").regard_assis
    local PORTEE_REGARD = config.regard or 800       -- cm
    local VOLUME = config.volume_voix or 0.9
    local LACET_MAX, TANGAGE_MAX = 70, 25
    local courants = setmetatable({}, { __mode = "k" })

    local function angle(d)
        d = (d + 180) % 360 - 180
        return d
    end

    local function trouver(id)
        for _, c in pairs(CharacterSimple.GetAll()) do
            if c:IsValid() and c:GetID() == id then return c end
        end
    end

    Events.SubscribeRemote("pnj:parle", function(id, nom)
        local c = trouver(id)
        if not c then return end
        pcall(function()
            local l = c:GetLocation()
            Sound(Vector(l.X, l.Y, l.Z + 60), chemin(nom), false, true, SoundType.SFX, VOLUME, 1,
                300, 2500, AttenuationFunction.Linear)
        end)
    end)

    -- Musique jouee par un PNJ (le musicien et sa flute) : un son en boucle,
    -- en 3D a sa place, cree quand il apparait, detruit avec lui.
    local musiques = setmetatable({}, { __mode = "k" })
    Timer.SetInterval(function()
        for c, s in pairs(musiques) do
            if not c:IsValid() then
                if s and s:IsValid() then pcall(function() s:Destroy() end) end
                musiques[c] = nil
            end
        end
        for _, c in pairs(CharacterSimple.GetAll()) do
            local type_pnj = c:IsValid() and c:GetValue("pnj", nil)
            local def = type_pnj and config.types and config.types[type_pnj]
            local m = def and def.musique
            if m and not (musiques[c] and musiques[c]:IsValid()) then
                pcall(function()
                    local l = c:GetLocation()
                    musiques[c] = Sound(Vector(l.X, l.Y, l.Z + 40), chemin(m.son), false, false, SoundType.SFX,
                        m.volume or 0.5, 1, m.proche or 250, m.portee or 1600, AttenuationFunction.Linear, false,
                        SoundLoopMode.Forever)
                end)
            end
        end
    end, 1000)

    local function appliquer(c, yaw, pitch)
        c:SetAnimationBlueprintPropertyValue("LookNeck", Rotator(yaw * R.cou, 0, -pitch * R.cou))
        c:SetAnimationBlueprintPropertyValue("LookHead", Rotator(yaw * R.tete, 0, -pitch * R.tete))
    end

    Timer.SetInterval(function()
        local p = Client.GetLocalPlayer()
        local moi = p and p:GetControlledCharacter()
        local cible = moi and moi:IsValid() and moi:GetLocation()
        for _, c in pairs(CharacterSimple.GetAll()) do
            if c:IsValid() and c:GetValue("pnj", nil) then
                local voulu_yaw, voulu_pitch = 0, 0
                if cible then
                    local l = c:GetLocation()
                    local dx, dy, dz = cible.X - l.X, cible.Y - l.Y, cible.Z - l.Z
                    local d = math.sqrt(dx * dx + dy * dy)
                    if d < PORTEE_REGARD and d > 1 then
                        local rel = angle(math.deg(math.atan(dy, dx)) - c:GetRotation().Yaw)
                        -- Derriere lui : il ne se tord pas le cou, il regarde devant.
                        if math.abs(rel) <= LACET_MAX + 30 then
                            voulu_yaw = math.max(-LACET_MAX, math.min(LACET_MAX, rel))
                            voulu_pitch = math.max(-TANGAGE_MAX, math.min(TANGAGE_MAX, math.deg(math.atan(dz, d))))
                        end
                    end
                end
                local cur = courants[c] or { yaw = 0, pitch = 0 }
                cur.yaw = cur.yaw + (voulu_yaw - cur.yaw) * 0.12
                cur.pitch = cur.pitch + (voulu_pitch - cur.pitch) * 0.12
                courants[c] = cur
                pcall(appliquer, c, cur.yaw, cur.pitch)
            end
        end
    end, 33)
end
