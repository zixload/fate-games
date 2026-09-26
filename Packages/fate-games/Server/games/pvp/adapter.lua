-- Adaptateur du systeme de combat (docs/COMBAT.md) : relie le moteur pur
-- (combat/) au jeu. Le joueur qui entre recoit un personnage natif (Character,
-- squelette du mannequin), qui porte les armes natives ; son personnage
-- habituel est cache et rendu a la sortie.
--
-- Le moteur decide ; ici on traduit :
--   - entrees du client (pvp:attaque, pvp:garde...) -> intentions du moteur ;
--   - degats natifs (balles, chute) -> TakeDamage reecrit par le moteur ;
--   - effets du moteur -> sante, vitesse, impulsions, stances, animations, et
--     diffusion aux clients (pvp:fx) pour le HUD et les indicateurs.
--
-- Mode d'essai (dev) : /pvp pour entrer ou sortir, /pvp arme <id>,
-- /pvp armure <id>, /pvp bot [arme] [niveau], /pvp bots (les retirer),
-- /pvp aterre (a terre au lieu de mourir), /pvp soin.

return function(Log, Characters, Combat, Armes, config)
    config = config or {}
    local A = {}
    local w = Combat.nouveau(config.regles)
    local G = Combat.geometrie
    local TICK = 0.05
    local MESH = config.mesh or "nanos-world::SK_Mannequin"
    local REAPPARITION = config.reapparition or 4
    local ARME_DEFAUT = config.arme or "epee_longue"
    local VITESSE_BOT = config.vitesse_bot or 320   -- cm/s avant armure, arme et statuts

    local P = {}            -- id de personnage -> participant
    local par_joueur = {}   -- id de joueur -> id de personnage

    local function vec(v) return { x = v.X, y = v.Y, z = v.Z } end
    local function V(t) return Vector(t.x, t.y, t.z) end
    local function dire(player, texte) if player then Chat.SendMessage(player, texte) end end

    local function participant_de(player)
        local cid = player and par_joueur[player:GetID()]
        return cid and P[cid], cid
    end

    ---------------------------------------------------------------- armes

    local function equiper(p, arme)
        if p.objet and p.objet:IsValid() then p.objet:Destroy() end
        p.objet = nil
        local fx, raison = Combat.equiper(w, p.id, arme)
        if not fx then return nil, raison end
        local objet, err = Armes.creer(arme, Combat.armes[arme], p.perso:GetLocation(), p.perso:GetRotation())
        if err then Log.Warn("pvp", ("arme %s : %s"):format(arme, tostring(err))) end
        if objet then
            local ok, e = pcall(function() p.perso:PickUp(objet) end)
            if ok then p.objet = objet else
                Log.Warn("pvp", "PickUp : " .. tostring(e))
                objet:Destroy()
            end
        end
        p.perso:SetValue("pvp_arme", arme, true)
        return fx
    end

    ---------------------------------------------------------------- effets

    local IMPULSION_ESQUIVE = { avant = 0, arriere = 180, gauche = -90, droite = 90 }

    local function appliquer(fx)
        if not fx or #fx == 0 then return end
        for _, e in ipairs(fx) do
            local id = e.id or e.cible
            local p = id and P[id]
            local c = p and p.perso
            if c and c:IsValid() then
                local ok, err = pcall(function()
                    if e.kind == "degats" then
                        c:SetHealth(math.max(e.sante, e.sante > 0 and 1 or 0))
                    elseif e.kind == "mort" then
                        c:SetHealth(0)
                        if REAPPARITION then
                            Timer.SetTimeout(function() A.Reapparaitre(e.id) end, math.floor(REAPPARITION * 1000))
                        end
                    elseif e.kind == "a_terre" then
                        c:SetHealth(1)
                        c:SetStanceMode(StanceMode.Proning)
                    elseif e.kind == "releve" then
                        c:SetStanceMode(StanceMode.Standing)
                        c:SetHealth(w.combattants[id].sante)
                    elseif e.kind == "vitesse" then
                        c:SetSpeedMultiplier(math.max(0.01, e.mult))
                    elseif e.kind == "sprint" and not e.actif then
                        c:SetGaitMode(GaitMode.Walking)
                    elseif e.kind == "repousse" then
                        c:AddImpulse(Vector(e.direction.x, e.direction.y, 0.35) * e.force, true)
                    elseif e.kind == "esquive" then
                        local yaw = w.combattants[id].yaw + (IMPULSION_ESQUIVE[e.dir] or 180)
                        local d = G.direction(yaw, 0)
                        c:AddImpulse(Vector(d.x, d.y, 0.1) * (e.distance * 4), true)
                    elseif e.kind == "bond" then
                        local z = c:GetLocation().Z
                        c:SetLocation(Vector(e.destination.x, e.destination.y, z))
                    elseif e.kind == "attaque" then
                        local anim = Armes.anim_attaque(e.arme, e.dir)
                        if anim then c:PlayAnimation(anim, AnimationSlotType.UpperBody, false, 0.1, 0.2, 1, true) end
                    end
                end)
                if not ok then Log.Warn("pvp", ("effet %s : %s"):format(e.kind, tostring(err))) end
            end
        end
        -- Tout le monde voit : indicateurs d'attaque, garde, impacts, projectiles.
        Events.BroadcastRemote("pvp:fx", fx)
    end

    ---------------------------------------------------------------- personnages

    -- Zone touchee d'apres l'os que l'arme native a touche.
    local function zone_os(os_)
        local b = tostring(os_ or ""):lower()
        if b:find("head") or b:find("neck") then return "tete" end
        if b:find("thigh") or b:find("calf") or b:find("foot") or b:find("ball") then return "jambes" end
        if b:find("arm") or b:find("hand") or b:find("finger") or b:find("thumb") then return "bras" end
        return "torse"
    end

    local function configurer(c, cid)
        c:SetCanPunch(false)
        c:SetCanDrop(false)
        c:SetRagdollOnHitEnabled(false)
        pcall(function() c:SetHitReactionEnabled(true) end)
        c:SetMaxHealth(w.combattants[cid] and w.combattants[cid].sante_max or 100)
        c:SetHealth(c:GetMaxHealth())
        c:SetValue("pvp", true, true)
        -- Tous les degats natifs passent par le moteur, qui les reecrit.
        c:Subscribe("TakeDamage", function(self, degats, os_, type_, _, instigateur)
            local ok, err = pcall(function()
                if type_ == DamageType.Shot and instigateur then
                    local tireur = par_joueur[instigateur:GetID()]
                    local pt = tireur and P[tireur]
                    if pt and pt.perso:IsValid() then
                        local d = pt.perso:GetLocation():Distance(self:GetLocation())
                        appliquer(Combat.balle(w, tireur, self:GetID(), zone_os(os_), d))
                    end
                elseif type_ == DamageType.Fall then
                    appliquer(Combat.degats(w, self:GetID(), degats, "chute", "jambes"))
                end
            end)
            if not ok then Log.Warn("pvp", "TakeDamage : " .. tostring(err)) end
            return 0
        end)
        -- Le sprint natif coute de l'endurance.
        c:Subscribe("GaitModeChange", function(self, _, nouveau)
            local fx = Combat.sprinter(w, self:GetID(), nouveau == GaitMode.Sprinting)
            if not fx and nouveau == GaitMode.Sprinting then self:SetGaitMode(GaitMode.Walking) end
            appliquer(fx)
        end)
    end

    local function inscrire(perso, o)
        local cid = perso:GetID()
        Combat.ajouter(w, cid, { camp = o.camp or cid, arme = "poings", armure = o.armure or "aucune",
            pos = vec(perso:GetLocation()), yaw = perso:GetRotation().Yaw })
        local p = { id = cid, perso = perso, player = o.player, ancien = o.ancien, niveau = o.niveau, memoire = {} }
        P[cid] = p
        configurer(perso, cid)
        -- Le client distingue allies et ennemis (indicateurs, relever, achever).
        perso:SetValue("pvp_camp", tostring(o.camp or cid), true)
        equiper(p, o.arme or ARME_DEFAUT)
        return p
    end

    local function oublier(p)
        Combat.retirer(w, p.id)
        P[p.id] = nil
        if p.objet and p.objet:IsValid() then p.objet:Destroy() end
        if p.perso and p.perso:IsValid() then p.perso:Destroy() end
    end

    function A.Entrer(player, arme)
        local pid = player:GetID()
        if par_joueur[pid] then return nil, "deja" end
        local ancien = player:GetControlledCharacter()
        local loc = ancien and ancien:GetLocation() or Vector()
        local yaw = ancien and ancien:GetRotation().Yaw or 0
        local perso = Character(loc + Vector(0, 0, 30), Rotator(0, yaw, 0), MESH)
        if ancien then
            ancien:SetVisibility(false)
            pcall(function() ancien:SetCollision(CollisionType.NoCollision) end)
        end
        player:Possess(perso)
        par_joueur[pid] = perso:GetID()
        inscrire(perso, { player = player, ancien = ancien, arme = arme })
        Events.CallRemote("pvp:entree", player, perso:GetID())
        return true
    end

    function A.Quitter(player)
        local p, cid = participant_de(player)
        if not p then return nil, "dehors" end
        par_joueur[player:GetID()] = nil
        local ancien = p.ancien
        oublier(p)
        if ancien and ancien:IsValid() then
            ancien:SetVisibility(true)
            pcall(function() ancien:SetCollision(CollisionType.Auto) end)
            player:Possess(ancien)
        end
        Events.CallRemote("pvp:sortie", player, cid)
        return true
    end

    function A.Reapparaitre(cid)
        local p = P[cid]
        if not (p and p.perso:IsValid()) then return end
        local loc, rot = p.perso:GetLocation(), p.perso:GetRotation()
        pcall(function() p.perso:Respawn(loc + Vector(0, 0, 50), Rotator(0, rot.Yaw, 0)) end)
        p.perso:SetStanceMode(StanceMode.Standing)
        Combat.reinitialiser(w, cid, vec(p.perso:GetLocation()), rot.Yaw)
        p.perso:SetHealth(p.perso:GetMaxHealth())
        equiper(p, w.combattants[cid].arme)
        Events.BroadcastRemote("pvp:fx", { { kind = "reapparition", id = cid } })
    end

    local niveau_bot = 0
    function A.AjouterBot(player, arme, niveau)
        local p = participant_de(player)
        local base = p and p.perso or player:GetControlledCharacter()
        if not base then return nil, "personne" end
        niveau_bot = niveau_bot + 1
        local d = G.direction(base:GetRotation().Yaw + (niveau_bot % 3 - 1) * 25, 0)
        local loc = base:GetLocation() + Vector(d.x, d.y, 0) * 500 + Vector(0, 0, 30)
        local perso = Character(loc, Rotator(0, base:GetRotation().Yaw + 180, 0), MESH)
        inscrire(perso, { arme = arme or ARME_DEFAUT, niveau = niveau or "normal", camp = "bots" })
        return true
    end

    function A.RetirerBots()
        local n = 0
        for _, p in pairs(P) do
            if not p.player then oublier(p) n = n + 1 end
        end
        return n
    end

    ---------------------------------------------------------------- bots

    local function rng(k) return math.random(k) end

    local function faire_jouer(p)
        local dec = Combat.ia.decider(Combat, w, p.id, rng, p.memoire, p.niveau)
        local c = p.perso
        if dec.regard and w.combattants[p.id].etat == "vivant" then
            local f = w.combattants[p.id]
            local lacet = G.lacet_vers(f.pos, dec.regard)
            c:SetRotation(Rotator(0, lacet, 0))
            -- Pas de NavMesh dans la map (MoveTo ne marche pas, cf. le bot du
            -- duel) : le bot glisse vers sa distance de combat, a sa vitesse.
            if dec.aller_vers then
                local vers = G.moins(dec.aller_vers, f.pos)
                local dist = math.sqrt(vers.x * vers.x + vers.y * vers.y)
                local reste = dist - (dec.distance or 0)
                if reste > 10 and dist > 0 then
                    local pas = math.min(reste, VITESSE_BOT * Combat.vitesse(w, p.id) * TICK)
                    local loc = c:GetLocation()
                    c:SetLocation(Vector(loc.X + vers.x / dist * pas, loc.Y + vers.y / dist * pas, loc.Z))
                end
            end
        end
        appliquer(Combat.ia.executer(Combat, w, p.id, dec, rng, p.niveau))
    end

    ---------------------------------------------------------------- temps

    local compteur_hud = 0
    local function pas()
        for cid, p in pairs(P) do
            local c = p.perso
            if c and c:IsValid() then
                local rot = p.player and c:GetControlRotation() or c:GetRotation()
                Combat.placer(w, cid, vec(c:GetLocation()), rot.Yaw, rot.Pitch)
            else
                P[cid] = nil
                Combat.retirer(w, cid)
            end
        end
        for _, p in pairs(P) do
            if not p.player then
                local ok, err = pcall(faire_jouer, p)
                if not ok then Log.Warn("pvp", "bot : " .. tostring(err)) end
            end
        end
        appliquer(Combat.avancer(w, TICK))
        -- Le HUD de chacun, dix fois par seconde.
        compteur_hud = compteur_hud + 1
        if compteur_hud % 2 == 0 then
            for cid, p in pairs(P) do
                if p.player and p.player:IsValid() then
                    Events.CallRemote("pvp:etat", p.player, Combat.etat(w, cid))
                end
            end
        end
    end

    ---------------------------------------------------------------- entrees

    local function relayer(nom, fn)
        Events.SubscribeRemote(nom, function(player, ...)
            local p, cid = participant_de(player)
            if not p then return end
            local ok, fx, raison = pcall(fn, cid, ...)
            if not ok then return Log.Warn("pvp", ("%s : %s"):format(nom, tostring(fx))) end
            if fx then appliquer(fx) elseif raison then Events.CallRemote("pvp:refus", player, nom, raison) end
        end)
    end

    function A.Init()
        Timer.SetInterval(function()
            local ok, err = pcall(pas)
            if not ok then Log.Error("pvp", "pas : " .. tostring(err)) end
        end, math.floor(TICK * 1000))

        relayer("pvp:attaque", function(cid, force, dir) return Combat.attaquer(w, cid, force, dir) end)
        relayer("pvp:feinte", function(cid) return Combat.feinter(w, cid) end)
        relayer("pvp:bousculer", function(cid) return Combat.bousculer(w, cid) end)
        relayer("pvp:garde", function(cid, dir)
            if dir then return Combat.garder(w, cid, dir) end
            return Combat.lacher_garde(w, cid)
        end)
        relayer("pvp:esquive", function(cid, dir) return Combat.esquiver(w, cid, dir) end)
        relayer("pvp:bander", function(cid) return Combat.bander(w, cid) end)
        relayer("pvp:decocher", function(cid, origine, direction)
            return Combat.decocher(w, cid, vec(origine), vec(direction))
        end)
        relayer("pvp:sort", function(cid, sort, cible) return Combat.incanter(w, cid, sort, cible) end)
        relayer("pvp:impact", function(cid, pid, pos) return Combat.impact_decor(w, cid, pid, pos and vec(pos)) end)
        relayer("pvp:relever", function(cid, cible) return Combat.relever(w, cid, cible) end)
        relayer("pvp:achever", function(cid, cible) return Combat.achever(w, cid, cible) end)

        if config.dev then
            Chat.Subscribe("PlayerSubmit", function(message, player)
                local mots = {}
                for m in tostring(message):gmatch("%S+") do mots[#mots + 1] = m end
                if mots[1] ~= "/pvp" then return end
                local p = participant_de(player)
                local quoi = mots[2]
                if not quoi then
                    if p then A.Quitter(player) dire(player, "PvP : sorti.")
                    else A.Entrer(player) dire(player, "PvP : entre (/pvp pour sortir, /pvp arme <id>, /pvp bot).") end
                elseif quoi == "arme" and p then
                    local fx, raison = equiper(p, mots[3] or "")
                    dire(player, fx and ("Arme : " .. mots[3]) or ("Arme refusee : " .. tostring(raison)
                        .. " (poings, dague, epee_courte, epee_longue, hache, masse, lance, epee_bouclier, baton, pistolet, revolver, fusil, fusil_pompe, fusil_precision, arc, arbalete)"))
                elseif quoi == "armure" and p then
                    local fx = Combat.armure(w, p.id, mots[3] or "")
                    dire(player, fx and ("Armure : " .. mots[3]) or "Armure : aucune, tissu, cuir, mailles, plaques")
                elseif quoi == "bot" then
                    local ok, raison = A.AjouterBot(player, mots[3], mots[4])
                    dire(player, ok and "Bot ajoute." or ("Bot impossible : " .. tostring(raison)))
                elseif quoi == "bots" then
                    dire(player, ("%d bot(s) retire(s)."):format(A.RetirerBots()))
                elseif quoi == "aterre" then
                    w.R.a_terre.actif = not w.R.a_terre.actif
                    dire(player, "A terre : " .. (w.R.a_terre.actif and "oui" or "non"))
                elseif quoi == "soin" and p then
                    Combat.reinitialiser(w, p.id)
                    p.perso:SetHealth(p.perso:GetMaxHealth())
                    dire(player, "Remis a neuf.")
                else
                    dire(player, "/pvp | /pvp arme <id> | /pvp armure <id> | /pvp bot [arme] [facile|normal|difficile] | /pvp bots | /pvp aterre | /pvp soin")
                end
                return false
            end)
        end
        Log.Info("pvp", "systeme de combat pret" .. (config.dev and " (/pvp en dev)" or ""))
    end

    function A.OnPlayerLeave(player)
        if participant_de(player) then A.Quitter(player) end
    end

    return A
end
