-- Adaptateur du loup-garou : le seul fichier du jeu qui connait nanos world.
-- Il tient le salon, fait avancer le moteur (engine.lua), traduit ses effets
-- en evenements du HUD (Client/loup_garou/hud.lua) et fait jouer les bots de
-- test. La logique du jeu n'est pas ici.
--
-- Comme au Liar's Bar : E sur un zabuton pour s'asseoir et rejoindre le salon,
-- Espace pour se lever et le quitter (hors partie). En dev : /lg entrer (la
-- premiere place libre), /lg sortir, /lg bots N, /lg centre, /lg passer.
-- Hors de cette version : bras tendus (effet recu, ignore).
--
-- Le resultat d'une partie terminee s'ecrit en base (werewolf_matches et
-- werewolf_participants, migration 5), sauf avec des bots.
--
-- Decor (docs/WEREWOLF-ASSETS-IMPORT.md) : le serveur pose le tapis et les
-- douze zabutons des le demarrage, sur un cercle autour du centre, symetriques
-- par calcul ; le reste du decor vit dans la map. /lg centre (dev) enregistre
-- le centre, mesure par le client (sol sous ses pieds), dans loup_garou.json a
-- cote de l'executable du serveur.

return function(Log, DB, Ids, Characters, Interactables, Engine, Roles, Match, config)
    local A = {}
    config = config or {}
    local TICK = config.tick or 0.25
    -- Cercle des places (cm) et echelle du tapis : double de l'implantation de
    -- reference (212 cm, tapis de 5,5 m), trop serree en jeu (26/09).
    local RAYON = config.rayon or 424
    local ECHELLE_TAPIS = config.echelle_tapis or 2

    local NOMS_ROLES = { wolf = "Loup-Garou", white_wolf = "Loup Blanc", villager = "Villageois",
        seer = "Voyante", hunter = "Chasseur", guard = "Gardien", cupid = "Cupidon", witch = "Sorcière" }
    local GAGNANTS = { village = "Le village gagne !", wolves = "Les loups-garous gagnent !",
        white_wolf = "Le loup blanc gagne seul !", lovers = "Les amoureux gagnent !",
        none = "Partie terminée sans vainqueur." }

    ---------------------------------------------------------------- voix

    -- La voix d'une partie passe par trois canaux globaux (doc Player :
    -- SetVOIPGlobalChannelSetting, 1 a 63) ; la voix de proximite est coupee
    -- pendant la partie. Un reglage par situation (effet voice_channel) :
    --   sleep    la nuit, qui n'est pas loup : ni parler ni entendre
    --   wolves   la nuit, les loups entre eux
    --   village  le jour, tout le monde, a volume egal quelle que soit la distance
    --   dead     les morts entre eux ; ils ecoutent les vivants sans leur parler
    --   normal   hors partie : la proximite, comme partout sur la map
    local CANAUX = config.canaux or { village = 10, wolves = 11, dead = 12 }
    local N, E, D = VOIPSetting.None, VOIPSetting.ListenOnly, VOIPSetting.Both
    local VOIX = {
        sleep   = { locale = N, village = N, wolves = N, dead = N },
        wolves  = { locale = N, village = N, wolves = D, dead = N },
        village = { locale = N, village = D, wolves = N, dead = N },
        dead    = { locale = N, village = E, wolves = E, dead = D },
        normal  = { locale = D, village = N, wolves = N, dead = N },
    }
    local MESSAGES_VOIX = {
        sleep  = "Tu dors : personne ne t'entend.",
        wolves = "Seuls les loups t'entendent.",
        dead   = "Seuls les morts t'entendent. Tu écoutes encore les vivants.",
    }
    local voix_actuelle = {}   -- id -> situation

    local function regler_voix(id, situation)
        if not id or id < 0 then return end   -- les bots n'ont pas de voix
        local p
        for _, pl in pairs(Player.GetPairs()) do
            if pl:IsValid() and pl:GetID() == id then p = pl break end
        end
        local v = VOIX[situation]
        if not (p and v) then return end
        local ok, err = pcall(function()
            p:SetVOIPLocalSetting(v.locale)
            for canal, numero in pairs(CANAUX) do p:SetVOIPGlobalChannelSetting(numero, v[canal]) end
            if config.volume then p:SetVOIPGlobalVolume(config.volume) end
        end)
        if not ok then Log.Warn("werewolf", "voix : " .. tostring(err)) return end
        if voix_actuelle[id] ~= situation then
            voix_actuelle[id] = situation
            if MESSAGES_VOIX[situation] then
                Events.CallRemote("ww:annonce", p, Reliability.Reliable, MESSAGES_VOIX[situation])
            end
        end
    end

    local s = Engine.nouveau()
    local salon = { ordre = {}, pret = {}, createur = nil, max = 10, debat = 180,
        compo = Roles.par_defaut(6) }
    local bots = {}          -- id negatif -> { nom, corps }
    -- sieges[i] : { x, y, yaw, occupant, repere } ; siege_de[id] : son numero.
    local decor = { centre = nil, objets = {}, sieges = {}, siege_de = {}, reperes = {} }
    local memoires = {}      -- id de bot -> ce qu'il retient (bots.lua)
    local cartes = {}        -- siege -> { role } : carte au sol, role une fois retournee
    local prochain_bot = -1

    local function rng(k) return math.random(k) end

    ---------------------------------------------------------------- joueurs et personnages

    local function membre(id)
        for _, m in ipairs(salon.ordre) do if m == id then return true end end
        return false
    end

    local function joueur(id)
        if not id or id < 0 then return nil end
        for _, p in pairs(Player.GetPairs()) do
            if p:IsValid() and p:GetID() == id then return p end
        end
    end

    local function personnage(id)
        if bots[id] then return bots[id].corps end
        local session = Characters.SessionByPlayer(id)
        return session and session.character or nil
    end

    local function nom(id)
        if bots[id] then return bots[id].nom end
        local p = joueur(id)
        return p and p:GetName() or ("Joueur " .. tostring(id))
    end

    local function id_personnage(id)
        local c = personnage(id)
        return c and c:IsValid() and c:GetID() or nil
    end

    local function par_personnage(cid)
        for _, id in ipairs(salon.ordre) do
            if id_personnage(id) == cid then return id end
        end
    end

    local function envoyer(id, evenement, ...)
        local p = joueur(id)
        if p then Events.CallRemote(evenement, p, Reliability.Reliable, ...) end
    end

    local function diffuser(evenement, ...)
        for _, id in ipairs(salon.ordre) do envoyer(id, evenement, ...) end
    end

    local function dire(player, texte)
        if player then Chat.SendMessage(player, texte) end
    end

    ---------------------------------------------------------------- decor et places

    local D = config.decor or {}
    local FICHIER = D.fichier or "loup_garou.json"
    local COUSSINS = D.coussins or { "Red", "Blue", "Yellow", "Green", "Purple", "White", "Brown" }
    local POSES = D.poses or {
        -- Hauteur du pivot du personnage au-dessus du sol sous le tapis (cm),
        -- mesuree par l'import (echelle 0,8).
        { anim = "my-asset-pack::ANIM_WW_Sitting_Idle", z = 11.0 },
        { anim = "my-asset-pack::ANIM_WW_Sitting_Idle_Lazy", z = 12.8 },
    }
    local MORT = D.mort or { anim = "my-asset-pack::ANIM_WW_Sitting_Dazed", z = 11.6 }
    local TAPIS = D.tapis or "my-asset-pack::SM_WW_Carpet"
    local EPAISSEUR_TAPIS = D.epaisseur_tapis or 0.8
    local AJUSTEMENT = D.ajustement_z or 0      -- retouche en jeu si les vetements depassent

    local function lire_centre()
        if not File.Exists(FICHIER) then return nil end
        local f = File(FICHIER)
        local texte = f:Read(0)
        f:Close()
        local ok, c = pcall(JSON.parse, texte)
        return ok and type(c) == "table" and c.x and c or nil
    end

    local function ecrire_centre(c)
        local f = File(FICHIER, true)
        f:Write(JSON.stringify(c))
        f:Close()
    end

    local function effacer_decor()
        for _, o in ipairs(decor.objets) do
            if o and o:IsValid() then o:Destroy() end
        end
        for _, rid in ipairs(decor.reperes) do pcall(Interactables.Unregister, rid) end
        decor.objets, decor.reperes = {}, {}
    end

    local S_ASSEOIR   -- defini avec le salon, appele par les reperes

    -- Le tapis au centre et les douze zabutons a intervalles egaux sur le
    -- cercle, tournes vers le feu, poses des le demarrage. Sur chacun, un
    -- repere invisible ou viser pour s'asseoir (comme les chaises du Liar's Bar).
    local function poser_decor()
        effacer_decor()
        local c = decor.centre
        if not c then return end
        local ok, err = pcall(function()
            local tapis = StaticMesh(Vector(c.x, c.y, c.sol), Rotator(0, c.yaw or 0, 0), TAPIS, CollisionType.NoCollision)
            tapis:SetScale(Vector(ECHELLE_TAPIS, ECHELLE_TAPIS, 1))
            decor.objets[#decor.objets + 1] = tapis
            local n = Roles.MAX_JOUEURS
            for i = 1, n do
                local angle = (c.yaw or 0) + 360 * (i - 1) / n
                local r = math.rad(angle)
                local x, y = c.x + RAYON * math.cos(r), c.y + RAYON * math.sin(r)
                local ancien = decor.sieges[i]
                decor.sieges[i] = { x = x, y = y, yaw = angle + 180, occupant = ancien and ancien.occupant }
                decor.objets[#decor.objets + 1] = StaticMesh(Vector(x, y, c.sol + EPAISSEUR_TAPIS), Rotator(0, angle + 180, 0),
                    "my-asset-pack::SM_WW_Zabuton_" .. COUSSINS[(i - 1) % #COUSSINS + 1], CollisionType.NoCollision)
                local repere = Prop(Vector(x, y, c.sol + 30), Rotator(0, angle + 180, 0), "nanos-world::SM_Cube",
                    CollisionType.IgnoreOnlyPawn, false, GrabMode.Disabled)
                repere:SetScale(Vector(0.6, 0.6, 0.6))
                repere:SetVisibility(false)
                -- En partie, le client ne propose plus ces places (loup_garou/hud.lua).
                repere:SetValue("ww_siege", i, true)
                decor.objets[#decor.objets + 1] = repere
                local numero = i
                decor.reperes[#decor.reperes + 1] = Interactables.Register(repere, {
                    label = "S'asseoir",
                    kind = "seat",
                    on_interact = function(player) S_ASSEOIR(player, numero) end,
                })
            end
        end)
        if not ok then Log.Error("werewolf", "decor : " .. tostring(err)) end
    end

    -- /lg centre : le client mesure le sol sous ses pieds (trace, cote client)
    -- et envoie ou il se tient ; on garde aussi la hauteur du personnage debout.
    function A.PoserCentre(player, x, y, sol, debout, yaw)
        if not (tonumber(x) and tonumber(y) and tonumber(sol) and tonumber(debout)) then return end
        decor.centre = { x = x, y = y, sol = sol, debout = debout, yaw = math.floor((tonumber(yaw) or 0) + 0.5) }
        local ok, err = pcall(ecrire_centre, decor.centre)
        if not ok then Log.Error("werewolf", "centre non enregistre : " .. tostring(err)) end
        if s.statut ~= "partie" then poser_decor() end
        dire(player, ("Centre du loup-garou enregistre (%d, %d), sol a %d."):format(x, y, sol))
    end

    -- Assoit un joueur (ou un bot) sur son siege, dans une pose.
    local function asseoir(id, pose)
        local siege = decor.sieges[decor.siege_de[id] or 0]
        local c = personnage(id)
        if not (siege and c and c:IsValid() and decor.centre) then return end
        local z = decor.centre.debout + pose.z + AJUSTEMENT
        if id > 0 then
            Characters.Sit(id, siege.x, siege.y, siege.yaw, z)
        else
            c:SetLocation(Vector(siege.x, siege.y, z))
            c:SetRotation(Rotator(0, siege.yaw, 0))
            pcall(function() c:SetGravityEnabled(false) end)
        end
        local ancienne = c:GetValue("ww_pose", nil)
        if ancienne and ancienne ~= pose.anim then pcall(function() c:StopAnimation(ancienne) end) end
        pcall(function() c:PlayAnimation(pose.anim, "DefaultSlot", true, 0.15, 0.15, 1.0, true) end)
        c:SetValue("ww_pose", pose.anim, true)
    end

    local function relever(id)
        local c = personnage(id)
        if c and c:IsValid() then
            local anim = c:GetValue("ww_pose", nil)
            if anim then pcall(function() c:StopAnimation(anim) end) end
            c:SetValue("ww_pose", nil, true)
        end
        if id > 0 then pcall(Characters.Stand, id) end
        local n = decor.siege_de[id]
        if n and decor.sieges[n] then decor.sieges[n].occupant = nil end
        decor.siege_de[id] = nil
    end

    -- Les cartes de role au sol, devant chaque place (Client/loup_garou/cartes.lua) :
    -- publiees a tous, le role seulement une fois la carte retournee.
    local RECUL_CARTE = config.recul_carte or 110    -- cm, de la place vers le feu
    local function publier_cartes()
        local liste, c = {}, decor.centre
        if c then
            for n, carte in pairs(cartes) do
                local siege = decor.sieges[n]
                if siege then
                    local k = (RAYON - RECUL_CARTE) / RAYON
                    liste[#liste + 1] = { n = n, x = c.x + (siege.x - c.x) * k, y = c.y + (siege.y - c.y) * k,
                        z = c.sol + EPAISSEUR_TAPIS + 0.4, yaw = siege.yaw, role = carte.role }
                end
            end
        end
        Events.BroadcastRemote("ww:cartes", Reliability.Reliable, liste)
    end

    local function retourner_carte(id, role)
        local n = decor.siege_de[id]
        if n and cartes[n] then
            cartes[n].role = role
            publier_cartes()
        end
    end

    -- La pose de repos d'un joueur : Idle ou Idle Lazy selon son siege.
    local function pose_de(id)
        local n = decor.siege_de[id] or 1
        return POSES[(n - 1) % #POSES + 1]
    end

    ---------------------------------------------------------------- salon

    local function envoyer_salon()
        if s.statut == "partie" then return end
        local joueurs = {}
        for _, id in ipairs(salon.ordre) do joueurs[#joueurs + 1] = { nom = nom(id), pret = salon.pret[id] == true } end
        for i, id in ipairs(salon.ordre) do
            local vue = { joueurs = {}, max = salon.max, compo = salon.compo, debat = salon.debat,
                createur = id == salon.createur }
            for k, j in ipairs(joueurs) do vue.joueurs[k] = { nom = j.nom, pret = j.pret, moi = k == i } end
            envoyer(id, "ww:salon", vue)
        end
    end

    local function lancer()
        local ids = {}
        for _, id in ipairs(salon.ordre) do ids[#ids + 1] = id end
        if #ids > salon.max then return diffuser("ww:annonce", "Trop de joueurs pour cette partie.") end
        s = Engine.nouveau({ debat = salon.debat })
        memoires = {}
        s.debut = os.date("!%Y-%m-%dT%H:%M:%SZ")
        local fx, raison = Engine.demarrer(s, ids, salon.compo, rng)
        if not fx then
            salon.pret = {}
            for id in pairs(bots) do salon.pret[id] = true end
            envoyer_salon()
            return diffuser("ww:annonce", "Impossible de lancer : " .. tostring(raison))
        end
        Log.Info("werewolf", ("partie lancee a %d joueurs"):format(#ids))
        diffuser("ww:salon", nil)
        -- Le client ne vise que les joueurs de la partie encore vivants.
        for _, id in ipairs(ids) do
            local c = personnage(id)
            if c and c:IsValid() then
                c:SetValue("ww_joueur", true, true)
                c:SetValue("ww_mort", false, true)
            end
        end
        -- Une carte face cachee devant chaque joueur.
        cartes = {}
        for _, id in ipairs(ids) do
            local n = decor.siege_de[id]
            if n then cartes[n] = {} end
        end
        publier_cartes()
        A.Appliquer(fx)
    end

    local function tous_prets()
        if #salon.ordre < Roles.MIN_JOUEURS then return false end
        for _, id in ipairs(salon.ordre) do if not salon.pret[id] then return false end end
        return true
    end

    local function premier_libre()
        for i, siege in ipairs(decor.sieges) do
            if not siege.occupant then return i end
        end
    end

    local function entrer_au_salon(id)
        if membre(id) then return end
        salon.ordre[#salon.ordre + 1] = id
        if id > 0 then salon.createur = salon.createur or id end
    end

    -- S'asseoir sur le zabuton n : rejoindre le salon (le HUD "pret" s'affiche).
    -- E sur sa propre place, hors partie : on se leve.
    S_ASSEOIR = function(player, n)
        local id = player:GetID()
        local siege = decor.sieges[n]
        if not siege then return end
        if decor.siege_de[id] == n and s.statut ~= "partie" then return A.Quitter(player) end
        -- En partie, E sert a designer : pas de message a chaque fois qu'on vise un coussin.
        if s.statut == "partie" then return end
        if siege.occupant then return dire(player, "Cette place est prise.") end
        local ancien = decor.siege_de[id]
        if ancien then decor.sieges[ancien].occupant = nil end
        siege.occupant, decor.siege_de[id] = id, n
        entrer_au_salon(id)
        asseoir(id, pose_de(id))
        envoyer_salon()
    end

    function A.Rejoindre(player)
        if not decor.centre then return dire(player, "Le cercle n'est pas pose : /lg centre d'abord.") end
        local n = premier_libre()
        if not n then return dire(player, "Le cercle est plein.") end
        S_ASSEOIR(player, n)
    end

    local function retirer(id)
        for i, m in ipairs(salon.ordre) do
            if m == id then table.remove(salon.ordre, i) break end
        end
        salon.pret[id] = nil
        if salon.createur == id then
            salon.createur = nil
            for _, m in ipairs(salon.ordre) do if m > 0 then salon.createur = m break end end
        end
    end

    -- Se lever (Espace, /lg sortir, E sur sa place) : hors partie seulement ;
    -- en partie, on reste a sa place jusqu'au bout.
    function A.Quitter(player)
        local id = player:GetID()
        if not membre(id) then return end
        if s.statut == "partie" then return end
        regler_voix(id, "normal")
        voix_actuelle[id] = nil
        relever(id)
        retirer(id)
        envoyer(id, "ww:fin")
        envoyer_salon()
    end

    A.Lever = A.Quitter

    function A.Pret(player)
        local id = player:GetID()
        if s.statut == "partie" or not membre(id) then return end
        salon.pret[id] = not salon.pret[id] or nil
        envoyer_salon()
        if tous_prets() then lancer() end
    end

    local BORNES_SALON = { max = { Roles.MIN_JOUEURS, Roles.MAX_JOUEURS, 1 }, debat = { 60, 300, 30 } }

    function A.Reglage(player, cle, sens)
        if s.statut == "partie" or player:GetID() ~= salon.createur then return end
        sens = (tonumber(sens) or 0) > 0 and 1 or -1
        local b = BORNES_SALON[cle]
        if b then
            salon[cle] = math.max(b[1], math.min(b[2], salon[cle] + sens * b[3]))
        elseif Roles.bornes[cle] then
            local r = Roles.bornes[cle]
            salon.compo[cle] = math.max(r[1], math.min(r[2], (salon.compo[cle] or 0) + sens))
        else
            return
        end
        -- Changer les regles remet les humains en "pas pret".
        for id in pairs(salon.pret) do if id > 0 then salon.pret[id] = nil end end
        envoyer_salon()
    end

    -- Une tenue au hasard pour un bot (Shared/appearances.lua), comme au Liar's
    -- Bar ; les tenues deja portees par un bot passent apres les autres.
    local Apparences = Package.Require("Shared/appearances.lua")
    local function habiller_bot(corps)
        if not (corps and corps:IsValid() and corps:IsA(CharacterSimple)) then return end
        local portees = {}
        for _, b in pairs(bots) do if b.look then portees[b.look] = true end end
        local libres = {}
        for _, a in ipairs(Apparences.list) do if not portees[a.id] then libres[#libres + 1] = a.id end end
        if #libres == 0 then for _, a in ipairs(Apparences.list) do libres[#libres + 1] = a.id end end
        local id = libres[math.random(#libres)]
        local look = Apparences.Resolve(id)
        if not look then return end
        pcall(function()
            corps:SetMesh(look.body)
            corps:RemoveAllSkeletalMeshesAttached()
            for i, mesh in ipairs(look.head) do corps:AddSkeletalMeshAttached("ww_tete_" .. i, mesh) end
            for i, mesh in ipairs(look.worn) do corps:AddSkeletalMeshAttached("ww_tenue_" .. i, mesh) end
        end)
        return id
    end

    -- Des pseudos ordinaires pour les bots, tires sans doublon.
    local PSEUDOS = config.pseudos_bots or { "Lilou", "Sacha", "Nino", "Jade", "Milo", "Inès", "Hugo", "Lina",
        "Enzo", "Zoé", "Noa", "Tom", "Kiwi", "Moka", "Pixel", "Bambou", "Nala", "Oscar", "Maé", "Léon" }
    local function pseudo_libre()
        local pris = {}
        for _, b in pairs(bots) do pris[b.nom] = true end
        local libres = {}
        for _, n in ipairs(PSEUDOS) do if not pris[n] then libres[#libres + 1] = n end end
        if #libres == 0 then return "Invité " .. math.random(100, 999) end
        return libres[math.random(#libres)]
    end

    -- Des bots sur les places libres, assis, habilles au hasard, deja prets.
    function A.AjouterBots(player, n)
        if s.statut == "partie" then return dire(player, "Une partie est en cours.") end
        if not decor.centre then return dire(player, "Le cercle n'est pas pose : /lg centre d'abord.") end
        for _ = 1, math.max(0, tonumber(n) or 0) do
            local place = premier_libre()
            if not place then break end
            local id = prochain_bot
            prochain_bot = prochain_bot - 1
            local siege = decor.sieges[place]
            local ok, corps = pcall(Characters.CorpsAssis, siege.x, siege.y,
                decor.centre.debout + POSES[1].z + AJUSTEMENT, siege.yaw)
            bots[id] = { nom = pseudo_libre(), corps = ok and corps or nil }
            bots[id].look = ok and habiller_bot(corps) or nil
            -- Les pseudos au-dessus des tetes (Client/pseudos.lua) le lisent.
            if ok and corps then corps:SetValue("pseudo", bots[id].nom, true) end
            siege.occupant, decor.siege_de[id] = id, place
            entrer_au_salon(id)
            salon.pret[id] = true
            asseoir(id, pose_de(id))
        end
        envoyer_salon()
    end

    ---------------------------------------------------------------- bots de test

    -- Les bots jouent avec bots.lua (le meme cerveau que les parties simulees
    -- des tests), quelques secondes apres le debut de chaque phase.
    local Bots = Package.Require("games/werewolf/bots.lua")(Match)

    local function faire_jouer_bots(phase)
        for id in pairs(bots) do
            for coup = 1, Bots.coups(s, id) do
                Timer.SetTimeout(function()
                    if s.statut ~= "partie" or Engine.phase(s) ~= phase then return end
                    memoires[id] = memoires[id] or {}
                    local cible = Bots.choisir(s, id, rng, memoires[id])
                    if not cible then return end
                    local fx = Engine.designer(s, id, cible)
                    if fx then A.Appliquer(fx) end
                end, math.random(2000, 6000) + coup * 900)
            end
        end
    end

    ---------------------------------------------------------------- effets

    local function destinataires(audience)
        if type(audience) == "number" then return { audience } end
        local out = {}
        for _, id in ipairs(salon.ordre) do
            local ok = audience == "all"
                or (audience == "wolves" and Match.est_loup(s.match, id))
                or (audience == "dead" and not Match.vivant(s.match, id))
            if ok then out[#out + 1] = id end
        end
        return out
    end

    local function liste_noms(ids)
        local t = {}
        for _, id in ipairs(ids or {}) do t[#t + 1] = nom(id) end
        return table.concat(t, ", ")
    end

    local ANNONCES = {
        aube_morts = function(a) return "Au lever du jour, on découvre : " .. liste_noms(a.morts) .. "." end,
        aube_personne = function() return "Personne n'est mort cette nuit." end,
        execution = function(a) return ("Le village élimine %s. C'était : %s."):format(nom(a.joueur), NOMS_ROLES[a.role] or "?") end,
        egalite = function() return "Égalité : le village ne tranche pas." end,
        chasseur = function(a) return ("%s tire en mourant et emporte %s."):format(nom(a.tireur), nom(a.joueur)) end,
        depart = function(a) return nom(a.joueur) .. " a quitté la partie." end,
        maire = function(a) return nom(a.joueur) .. " est élu maire : sa voix compte double." end,
        successeur = function(a) return nom(a.joueur) .. " devient maire." end,
    }

    local TRADUIRE = {}

    TRADUIRE.assign_role = function(e)
        local allies = {}
        for _, a in ipairs(e.allies) do allies[#allies + 1] = { id = id_personnage(a), nom = nom(a) } end
        envoyer(e.player, "ww:role", e.role, allies)
    end
    TRADUIRE.phase = function(e)
        diffuser("ww:phase", e.id, e.duree)
        faire_jouer_bots(e.id)
    end
    TRADUIRE.votes = function(e)
        local compte = {}
        for cible, n in pairs(e.compte) do
            local cid = id_personnage(cible)
            if cid then compte[cid] = n end
        end
        for _, id in ipairs(destinataires(e.audience)) do envoyer(id, "ww:votes", compte) end
    end
    TRADUIRE.reveal = function(e) envoyer(e.viewer, "ww:vision", nom(e.target), e.role) end
    TRADUIRE.lovers = function(e) envoyer(e.player, "ww:amoureux", id_personnage(e.partner), nom(e.partner)) end
    TRADUIRE.kill = function(e)
        envoyer(e.player, "ww:mort")
        local c = personnage(e.player)
        if c and c:IsValid() then c:SetValue("ww_mort", true, true) end
        -- Les morts restent assis, hebetes (ANIM_WW_Sitting_Dazed).
        if decor.siege_de[e.player] then asseoir(e.player, MORT) end
        -- Sa carte se retourne : tout le monde voit ce qu'il etait.
        if s.match then retourner_carte(e.player, Match.role(s.match, e.player)) end
    end
    TRADUIRE.voice_channel = function(e) regler_voix(e.player, e.channel) end
    TRADUIRE.chrono = function(e)
        for _, id in ipairs(destinataires(e.audience)) do envoyer(id, "ww:chrono", e.reste) end
    end
    TRADUIRE.mayor = function(e) diffuser("ww:maire", id_personnage(e.player), nom(e.player)) end
    TRADUIRE.victim = function(e) envoyer(e.player, "ww:victime", id_personnage(e.target), nom(e.target)) end
    TRADUIRE.potions = function(e) envoyer(e.player, "ww:potions", e.vie, e.mort) end
    TRADUIRE.announce = function(e)
        local f = ANNONCES[e.key]
        if f then diffuser("ww:annonce", f(e.args)) end
    end
    -- Gagne-t-il ? Selon son camp, ou pour les amoureux leur lien.
    local function a_gagne(gagnant, id, role, amoureux)
        if gagnant == "lovers" then return amoureux ~= nil and (amoureux[1] == id or amoureux[2] == id) end
        local camp = Roles.roles[role] and Roles.roles[role].camp
        return (gagnant == "village" and camp == "village") or (gagnant == "wolves" and camp == "wolves")
            or (gagnant == "white_wolf" and role == "white_wolf")
    end

    -- Le resultat d'une partie terminee : donnee transactionnelle, ecrite tout
    -- de suite (R3). Une partie avec des bots ne compte pas.
    local function enregistrer(gagnant, resume)
        if next(bots) then return Log.Info("werewolf", "partie avec bots : resultat non enregistre") end
        local id_partie = Ids.Next("werewolf_matches")
        local fin = os.date("!%Y-%m-%dT%H:%M:%SZ")
        DB.Execute([[INSERT INTO werewolf_matches (id, started_at, ended_at, nights, winner)
                     VALUES (:0, :1, :2, :3, :4)]],
            function(_, err) if err then Log.Error("werewolf", "resultat non ecrit : " .. tostring(err)) end end,
            id_partie, s.debut or fin, fin, resume.nuits or 0, tostring(gagnant))
        for id, role in pairs(resume.roles or {}) do
            local session = Characters.SessionByPlayer(id)
            DB.Execute([[INSERT INTO werewolf_participants (match_id, character_id, role, survived, won)
                         VALUES (:0, :1, :2, :3, :4)]],
                function(_, err) if err then Log.Error("werewolf", "participant non ecrit : " .. tostring(err)) end end,
                id_partie, session and session.character_id or 0, role,
                resume.vivants and resume.vivants[id] and 1 or 0,
                a_gagne(gagnant, id, role, resume.amoureux) and 1 or 0)
        end
    end

    TRADUIRE.match_ended = function(e)
        local texte = GAGNANTS[e.winner] or GAGNANTS.none
        diffuser("ww:victoire", e.winner)
        diffuser("ww:annonce", texte)
        Log.Info("werewolf", "partie terminee : " .. tostring(e.winner))
        local ok, err = pcall(enregistrer, e.winner, e.summary or {})
        if not ok then Log.Error("werewolf", "resultat : " .. tostring(err)) end
        -- Fin de partie : toutes les cartes se retournent.
        for id, role in pairs((e.summary or {}).roles or {}) do
            local n = decor.siege_de[id]
            if n and cartes[n] then cartes[n].role = role end
        end
        publier_cartes()
        Timer.SetTimeout(function()
            diffuser("ww:fin")
            cartes = {}
            publier_cartes()
            for _, id in ipairs(salon.ordre) do regler_voix(id, "normal") end
            -- On reste assis pour la partie suivante ; les morts se redressent.
            for _, id in ipairs(salon.ordre) do asseoir(id, pose_de(id)) end
            voix_actuelle = {}
            for _, id in ipairs(salon.ordre) do
                local c = personnage(id)
                if c and c:IsValid() then
                    c:SetValue("ww_mort", false, true)
                    c:SetValue("ww_joueur", false, true)
                end
            end
            s = Engine.nouveau({ debat = salon.debat })
            salon.pret = {}
            for id in pairs(bots) do salon.pret[id] = true end
            envoyer_salon()
        end, 8000)
    end

    function A.Appliquer(fx)
        for _, e in ipairs(fx or {}) do
            local f = TRADUIRE[e.kind]
            if f then
                local ok, err = pcall(f, e)
                if not ok then Log.Error("werewolf", ("effet %s : %s"):format(e.kind, tostring(err))) end
            end
        end
    end

    ---------------------------------------------------------------- entrees

    -- Pourquoi une designation est refusee, dit au joueur plutot que rien.
    local REFUS = {
        hors_phase = "Ce n'est pas le moment.",
        mort = "Tu es mort.",
        interdit = "Tu ne peux pas choisir ce joueur.",
        cible_invalide = "Ce joueur n'est plus en jeu.",
        deja_choisi = "Déjà choisi.",
    }

    function A.Designer(player, cid)
        if s.statut ~= "partie" then return end
        local cible = par_personnage(tonumber(cid))
        if not cible then return end
        local phase = Engine.phase(s)
        local fx, raison = Engine.designer(s, player:GetID(), cible)
        if fx then
            envoyer(player:GetID(), "ww:action", phase)   -- le son de son geste (loup_garou/sons.lua)
            return A.Appliquer(fx)
        end
        if REFUS[raison] then envoyer(player:GetID(), "ww:annonce", REFUS[raison]) end
    end

    function A.OnPlayerReady(player)
        if next(cartes) then publier_cartes() end
    end

    function A.OnPlayerLeave(player)
        local id = player:GetID()
        voix_actuelle[id] = nil
        if not membre(id) then return end
        if s.statut == "partie" then A.Appliquer(Engine.depart(s, id)) end
        local n = decor.siege_de[id]
        if n and decor.sieges[n] then decor.sieges[n].occupant = nil end
        decor.siege_de[id] = nil
        retirer(id)
        envoyer_salon()
    end

    -- /lg passer (dev) : la phase en cours se termine tout de suite, pour
    -- tester sans attendre le debat et les votes.
    function A.Passer(player)
        if s.statut ~= "partie" then return dire(player, "Aucune partie en cours.") end
        local phase = Engine.phase(s)
        A.Appliquer(Engine.avancer(s, math.max(s.reste, 0)))
        Log.Info("werewolf", ("phase %s passee par %s"):format(tostring(phase), player and player:GetName() or "?"))
    end

    function A.Init()
        local ok, c = pcall(lire_centre)
        decor.centre = ok and c or nil
        if decor.centre then
            Log.Info("werewolf", "centre du loup-garou relu dans " .. FICHIER)
            poser_decor()
        end
        Timer.SetInterval(function()
            if s.statut ~= "partie" then return end
            local ok, err = pcall(function() A.Appliquer(Engine.avancer(s, TICK)) end)
            if not ok then Log.Error("werewolf", "horloge : " .. tostring(err)) end
        end, math.floor(TICK * 1000))

        Events.SubscribeRemote("ww:designer", function(p, cid) A.Designer(p, cid) end)
        Events.SubscribeRemote("ww:pret", function(p) A.Pret(p) end)
        Events.SubscribeRemote("ww:reglage", function(p, cle, sens) A.Reglage(p, cle, sens) end)
        Events.SubscribeRemote("ww:centre", function(p, x, y, sol, debout, yaw)
            if config.bots then A.PoserCentre(p, x, y, sol, debout, yaw) end
        end)

        Chat.Subscribe("PlayerSubmit", function(message, player)
            local mots = {}
            for m in tostring(message):gmatch("%S+") do mots[#mots + 1] = m end
            if mots[1] ~= "/lg" then return end
            if mots[2] == "entrer" then A.Rejoindre(player)
            elseif mots[2] == "sortir" then A.Quitter(player)
            elseif mots[2] == "bots" and config.bots then A.AjouterBots(player, mots[3])
            elseif mots[2] == "passer" and config.bots then A.Passer(player)
            else return end
            return false
        end)
        Log.Info("werewolf", "loup-garou pret : E sur un zabuton pour s'asseoir")
    end

    return A
end
