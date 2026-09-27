-- Bruits du corps et musique de la place, chez chaque client.
--
-- Pas, saut et reception de tous les personnages proches, en 3D, lus a la
-- vitesse : un pas tous les N cm parcourus au sol (foulee plus longue en
-- courant), un saut quand la vitesse verticale depasse le seuil du saut, une
-- reception quand on touche le sol apres une vraie chute. La vitesse vaut
-- pour les autres joueurs aussi (GetVelocity : les deux cotes, doc Actor), la
-- ou les evenements Jump et Land du personnage sont cote client (doc
-- CharacterSimple). La poussee des petites marches (marche.lua) reste sous le
-- seuil du saut : monter un escalier ne crie pas.
--
-- Musique legere tant que mon personnage n'est dans aucun jeu (ni chaise de
-- Liar's Bar, ni salon du loup-garou, ni duel, ni combat) : ces jeux ont leur
-- propre ambiance. Sons de my-asset-pack (Client/son.lua), CC0 (docs/CREDITS-SONS.md).

return function(config)
    config = config or {}
    local chemin = Package.Require("son.lua")
    local PAS = config.pas or { "pas_1", "pas_2", "pas_3", "pas_4", "pas_5" }
    local CRIS = config.cris or { "saut_cri_1", "saut_cri_2" }
    local V = config.volumes or { marche = 0.07, course = 0.11, cri = 0.4, reception = 0.25, musique = 0.06 }
    local FOULEE_MARCHE = config.foulee_marche or 85     -- cm entre deux pas
    local FOULEE_COURSE = config.foulee_course or 170
    local COURSE = config.seuil_course or 300            -- cm/s : au-dela, on court
    local SEUIL_SAUT = config.seuil_saut or 330          -- cm/s vers le haut (saut : 400)
    local SEUIL_CHUTE = config.seuil_chute or 280        -- cm/s vers le bas avant la reception
    local PORTEE = config.portee or 2500                 -- cm : au-dela, on n'entend rien
    local PAS_TEMPS = 0.04

    local suivis = setmetatable({}, { __mode = "k" })    -- personnage -> etat

    local function au_hasard(liste) return liste[math.random(#liste)] end

    local function jouer(nom, lieu, volume, hauteur)
        pcall(function()
            Sound(lieu, chemin(nom), false, true, SoundType.SFX, volume, hauteur or 1,
                150, PORTEE, AttenuationFunction.Linear)
        end)
    end

    local function pieds(ch)
        local l = ch:GetLocation()
        return Vector(l.X, l.Y, l.Z - 70)
    end

    local function ecoute()
        local p = Client.GetLocalPlayer()
        return p and p:GetCameraLocation()
    end

    local avant = nil   -- heure du passage precedent (ms)

    Timer.SetInterval(function()
        -- Le vrai temps ecoule : un minuteur peut tourner moins vite que demande.
        local t = Client.GetTime()
        local dt = math.min(0.2, avant and (t - avant) / 1000 or PAS_TEMPS)
        avant = t
        local oreille = ecoute()
        if not oreille then return end
        for _, classe in ipairs({ CharacterSimple, Character }) do
            for _, ch in pairs(classe.GetAll()) do
                if ch:IsValid() and not ch:GetValue("assis", false) then
                    local e = suivis[ch]
                    if not e then e = { reste = 0, en_l_air = false, chute = 0 } suivis[ch] = e end
                    local l = ch:GetLocation()
                    if (l - oreille):Size() <= PORTEE then
                        local v = ch:GetVelocity()
                        local vitesse = math.sqrt(v.X * v.X + v.Y * v.Y)
                        if not e.en_l_air and v.Z > SEUIL_SAUT then
                            e.en_l_air, e.chute = true, 0
                            jouer(au_hasard(CRIS), pieds(ch), V.cri, 0.95 + math.random() * 0.1)
                        elseif v.Z < -60 then
                            e.en_l_air = true
                            e.chute = math.max(e.chute, -v.Z)
                        elseif e.en_l_air and math.abs(v.Z) < 30 then
                            -- Au sol : une reception seulement apres une vraie chute.
                            if e.chute >= SEUIL_CHUTE then
                                local force = math.min(1, e.chute / 900)
                                jouer("reception", pieds(ch), V.reception * (0.6 + 0.4 * force), 0.95 + math.random() * 0.1)
                            end
                            e.en_l_air, e.chute, e.reste = false, 0, 0
                        end
                        if not e.en_l_air and math.abs(v.Z) < 60 and vitesse > 40 then
                            e.reste = e.reste + vitesse * dt
                            local court = vitesse > COURSE
                            if e.reste >= (court and FOULEE_COURSE or FOULEE_MARCHE) then
                                e.reste = 0
                                jouer(au_hasard(PAS), pieds(ch), court and V.course or V.marche,
                                    0.92 + math.random() * 0.16)
                            end
                        elseif vitesse <= 40 then
                            e.reste = 0
                        end
                    end
                end
            end
        end
    end, math.floor(PAS_TEMPS * 1000))

    ---------------------------------------------------------------- musique

    local musique = nil

    local function en_jeu(perso)
        local chaise = perso:GetValue("liars_chair", 0)
        if type(chaise) == "number" and chaise > 0 then return true end
        if perso:GetValue("ww_joueur", false) == true then return true end
        local duel = perso:GetValue("duel", nil)
        if duel and duel ~= 0 then return true end
        local pvp = perso:GetValue("pvp", nil)
        if pvp and pvp ~= 0 then return true end
        return false
    end

    local function musique_on()
        if musique and musique:IsValid() then return end
        local ok, err = pcall(function()
            -- Le niveau de FadeIn multiplie le volume du son (doc Sound).
            musique = Sound(Vector(), chemin(config.musique or "musique_place"), true, false,
                SoundType.Music, V.musique, 1, 400, 3600, AttenuationFunction.Linear, true,
                SoundLoopMode.Forever, false)
            musique:FadeIn(config.fondu_entree or 5, 1)
        end)
        if not ok then musique = nil Console.Error("[bruits] musique : " .. tostring(err)) end
    end

    local function musique_off()
        if not (musique and musique:IsValid()) then musique = nil return end
        local m = musique
        musique = nil
        pcall(function() m:FadeOut(config.fondu_sortie or 3, 0, true) end)
    end

    if config.musique ~= false then
        Timer.SetInterval(function()
            local p = Client.GetLocalPlayer()
            local perso = p and p:GetControlledCharacter()
            if perso and perso:IsValid() and not en_jeu(perso) then musique_on() else musique_off() end
        end, 500)
    end
end
