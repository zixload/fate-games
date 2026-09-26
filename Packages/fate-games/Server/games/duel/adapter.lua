-- Le duel dans le monde : l'arene, les camps, les armes, la sante, l'argent.
-- Les regles vivent dans logic.lua ; ici, on les branche sur le moteur
-- (docs/DUEL-ET-ARGENT.md).

return function(Log, Characters, Boutique, Catalogue, Duel, config)
    local Adapter = {}

    local ARENE_Z_PIEDS = 88     -- cm entre le centre du personnage et ses pieds
    local d = Duel.Nouveau()
    local numero = 0             -- numero de partie, pour le sequestre de la mise
    local anneau = {}            -- segments du cercle au sol
    local armes = {}             -- player_id -> StaticMesh en main
    local tir = {}               -- player_id -> { balles, dernier, recharge }
    local comptes = {}           -- player_id -> account, fige au lancement
    local noms = {}              -- player_id -> nom, pour le HUD
    local spectateurs = {}       -- player_id -> player_id regarde
    local minuteur = nil

    local function maintenant() return Server.GetTime() end

    local function joueur(id)
        for _, p in pairs(Player.GetPairs()) do
            if p:GetID() == id then return p end
        end
        return nil
    end

    local function personnage(id)
        local s = Characters.SessionByPlayer(id)
        return s and s.character and s.character:IsValid() and s.character or nil
    end

    ---------------------------------------------------------------- l'arene

    local function centre()
        local a = config.arene
        return Vector(a.x, a.y, a.z)
    end

    local function distance_2d(loc)
        local a = config.arene
        local dx, dy = loc.X - a.x, loc.Y - a.y
        return math.sqrt(dx * dx + dy * dy)
    end

    -- Un cercle de segments plats couleur laiton, pose au sol.
    local function dessiner_anneau()
        for _, s in ipairs(anneau) do if s:IsValid() then s:Destroy() end end
        anneau = {}
        local a = config.arene
        if not a.placee then return end
        local n = 36
        local longueur = 2 * math.pi * a.rayon / n
        for i = 0, n - 1 do
            local ang = (i + 0.5) / n * 2 * math.pi
            local pos = Vector(a.x + math.cos(ang) * a.rayon, a.y + math.sin(ang) * a.rayon, a.z + 2)
            local s = StaticMesh(pos, Rotator(0, math.deg(ang) + 90, 0), "nanos-world::SM_Cube", CollisionType.NoCollision)
            s:SetScale(Vector(longueur / 100 * 0.7, 0.14, 0.03))
            pcall(function()
                s:SetMaterial("nanos-world::M_Default_Masked_Unlit")
                s:SetMaterialColorParameter("Tint", Color(0.72, 0.52, 0.16))
            end)
            anneau[#anneau + 1] = s
        end
    end

    -- Depart d'un combattant : son camp a un bout de l'arene, face a l'autre.
    local function depart(camp, rang, nombre)
        local a = config.arene
        local axe = math.rad(a.yaw)
        local sens = camp == 1 and -1 or 1
        local recul = a.rayon * 0.65
        local cote = (rang - (nombre + 1) / 2) * 180
        local x = a.x + math.cos(axe) * recul * sens - math.sin(axe) * cote
        local y = a.y + math.sin(axe) * recul * sens + math.cos(axe) * cote
        local face = a.yaw + (camp == 1 and 0 or 180)
        return Vector(x, y, a.z + ARENE_Z_PIEDS + 10), Rotator(0, face, 0)
    end

    local function depart_de(id)
        local j = d.joueurs[id]
        local membres = Duel.Membres(d, j.camp)
        for rang, m in ipairs(membres) do
            if m == id then return depart(j.camp, rang, #membres) end
        end
    end

    ---------------------------------------------------------------- HUD

    local function vue()
        local v = {
            phase = d.phase, format = d.format, mise = d.mise, createur = d.createur,
            scores = d.scores, manche = d.manche, capacite = Duel.Capacite(d),
            paliers = config.paliers, joueurs = {},
        }
        for _, id in ipairs(d.ordre) do
            local j = d.joueurs[id]
            v.joueurs[#v.joueurs + 1] = { id = id, nom = noms[id] or "?", camp = j.camp,
                pret = j.pret, vivant = j.vivant, parti = j.parti == true }
        end
        return v
    end

    -- Chaque joueur proche de l'arene recoit l'etat ; les autres, rien.
    local function diffuser()
        local v = vue()
        for _, p in pairs(Player.GetPairs()) do
            local c = personnage(p:GetID())
            local proche = d.joueurs[p:GetID()] ~= nil
                or (c and distance_2d(c:GetLocation()) <= config.rayon_spectateurs)
            if proche then
                Events.CallRemote("duel:etat", p, Reliability.Reliable, v)
            end
        end
    end

    local function annoncer(evenement, ...)
        for id in pairs(d.joueurs) do
            local p = joueur(id)
            if p then Events.CallRemote(evenement, p, Reliability.Reliable, ...) end
        end
    end

    ---------------------------------------------------------------- armes

    local function retirer_arme(id)
        local m = armes[id]
        if m and m:IsValid() then m:Destroy() end
        armes[id] = nil
    end

    -- L'arme equipee au vestiaire, dans la main. Une arme sans modele 3D fiable
    -- (Catalogue.en_3d) prend celle de base : son modele faisait planter le jeu.
    local function donner_arme(id)
        retirer_arme(id)
        local c = personnage(id)
        local account = comptes[id]
        if not (c and account) then return end
        local etat = Boutique.Etat(account)
        local choix = etat and etat.arme or Catalogue.arme_de_base
        if not Catalogue.en_3d(choix) then choix = Catalogue.arme_de_base end
        local article = Catalogue.article("armes", choix)
        local ok, err = pcall(function()
            local m = StaticMesh(c:GetLocation(), Rotator(0, 0, 0), article.mesh, CollisionType.NoCollision)
            local s = (article.taille or 30) / 100
            m:SetScale(Vector(s, s, s))
            local r = config.arme
            m:AttachTo(c, AttachmentRule.SnapToTarget, r.os, -1, false)
            m:SetRelativeLocation(Vector(r.position.x, r.position.y, r.position.z))
            m:SetRelativeRotation(Rotator(r.rotation.p, r.rotation.y, r.rotation.r))
            armes[id] = m
        end)
        if not ok then Log.Warn("duel", "arme en main impossible : " .. tostring(err)) end
    end

    ---------------------------------------------------------------- deroulement

    local function annuler_minuteur()
        if minuteur then Timer.ClearTimeout(minuteur) end
        minuteur = nil
    end

    local function remettre_en_etat(id)
        local c = personnage(id)
        if not c then return end
        pcall(function()
            if c:IsDead() then c:Respawn(c:GetLocation(), c:GetRotation()) end
            c:SetHealth(c:GetMaxHealth())
            c:SetValue("duel", nil, true)
        end)
    end

    local function arreter_spectateurs()
        for id in pairs(spectateurs) do
            local p = joueur(id)
            if p then pcall(function() p:ResetCamera() end) end
        end
        spectateurs = {}
    end

    -- Fin du duel ou arene videe : tout revient comme avant.
    local function nettoyer()
        annuler_minuteur()
        for id in pairs(d.joueurs) do
            retirer_arme(id)
            remettre_en_etat(id)
        end
        arreter_spectateurs()
        d = Duel.Nouveau()
        tir, comptes = {}, {}
        diffuser()
    end

    local function debut_manche()
        Duel.DebutManche(d)
        for id, j in pairs(d.joueurs) do
            if not j.parti then
                local c = personnage(id)
                if c then
                    local pos, rot = depart_de(id)
                    pcall(function()
                        if c:IsDead() then c:Respawn(pos, rot) else c:SetLocation(pos); c:SetRotation(rot) end
                        c:SetMaxHealth(config.sante)
                        c:SetHealth(config.sante)
                        c:SetValue("duel", { camp = j.camp, combat = true }, true)
                    end)
                    local p = joueur(id)
                    if p then p:SetCameraRotation(rot) end
                end
                tir[id] = { balles = config.chargeur, dernier = 0 }
                if not armes[id] then donner_arme(id) end
                local p = joueur(id)
                if p then Events.CallRemote("duel:munitions", p, Reliability.Reliable, config.chargeur) end
            end
        end
        annoncer("duel:manche", d.manche)
        diffuser()
    end

    local function terminer(gagnant)
        local partie = "duel:" .. numero
        local participants, gagnants = {}, {}
        for id, j in pairs(d.joueurs) do
            local account = comptes[id]
            if account and not j.parti then
                participants[#participants + 1] = account
                if j.camp == gagnant then gagnants[#gagnants + 1] = account end
            end
        end
        local cagnotte = d.mise * Duel.Effectif(d)
        Boutique.Solder(partie, participants, gagnants, cagnotte, config.bonus_participation, nil, function()
            -- Le HUD de la boutique n'est pas ouvert ici : le solde suivra au
            -- prochain passage au vestiaire.
            Log.Info("duel", ("partie %s : camp %d gagne %d"):format(partie, gagnant, cagnotte))
        end)
        annoncer("duel:fin", gagnant, cagnotte)
        diffuser()
        minuteur = Timer.SetTimeout(function() minuteur = nil; nettoyer() end, config.fin_ms)
    end

    local function suite(r)
        if not r then return diffuser() end
        if r.fin then return terminer(r.gagnant) end
        if r.manche then
            annoncer("duel:manche_gagnee", r.gagnant, d.scores)
            diffuser()
            minuteur = Timer.SetTimeout(function()
                minuteur = nil
                if d.phase == "entre_manches" then debut_manche() end
            end, config.entre_manches_ms)
        end
    end

    local function lancer()
        local liste = {}
        for _, id in ipairs(d.ordre) do
            local s = Characters.SessionByPlayer(id)
            comptes[id] = s and s.account or nil
            if comptes[id] then liste[#liste + 1] = comptes[id] end
        end
        numero = numero + 1
        local partie = "duel:" .. numero
        Boutique.Miser(liste, d.mise, partie, nil, function(ok, raison, fauches)
            if not ok then
                Duel.Annuler(d)
                local qui = {}
                for _, account in ipairs(fauches or {}) do
                    for id, a in pairs(comptes) do
                        if a == account then qui[#qui + 1] = noms[id] or "?" end
                    end
                end
                annoncer("duel:refus", raison, qui)
                comptes = {}
                return diffuser()
            end
            Duel.Lancer(d)
            annoncer("duel:decompte", config.decompte_ms)
            diffuser()
            minuteur = Timer.SetTimeout(function()
                minuteur = nil
                if d.phase == "decompte" then debut_manche() end
            end, config.decompte_ms)
        end)
    end

    local function verifier_depart()
        if Duel.ToutPret(d) then lancer() end
    end

    ---------------------------------------------------------------- la zone

    -- Quatre fois par seconde : qui entre, qui sort, qui force la porte.
    local function surveiller()
        if not config.arene.placee then return end
        local change = false
        local actif = d.phase == "decompte" or d.phase == "combat" or d.phase == "entre_manches"
        for _, p in pairs(Player.GetPairs()) do
            local id = p:GetID()
            local s = Characters.SessionByPlayer(id)
            local c = personnage(id)
            if c and s and not s.assis and not Characters.AuVestiaire(id) then
                noms[id] = p:GetName()
                local dedans = distance_2d(c:GetLocation()) <= config.arene.rayon
                local j = d.joueurs[id]
                if not actif then
                    if dedans and not j then
                        if Duel.Entrer(d, id) then change = true end
                    elseif not dedans and j then
                        Duel.Quitter(d, id); change = true
                    end
                elseif j and not j.parti then
                    -- Un combattant qui sort est ramene a son depart.
                    if not dedans then
                        local pos = depart_de(id)
                        c:SetLocation(pos)
                    end
                elseif dedans then
                    -- Arene fermee : repousse juste au-dela du cercle.
                    local loc = c:GetLocation()
                    local a = config.arene
                    local dx, dy = loc.X - a.x, loc.Y - a.y
                    local n = math.sqrt(dx * dx + dy * dy)
                    if n < 1 then dx, dy, n = 1, 0, 1 end
                    local r = a.rayon + 150
                    c:SetLocation(Vector(a.x + dx / n * r, a.y + dy / n * r, loc.Z))
                end
            end
        end
        if change then
            diffuser()
            verifier_depart()
        end
    end

    ---------------------------------------------------------------- tirs

    local function tirer(id, cible_entite, os_touche)
        local j = d.joueurs[id]
        local etat = tir[id]
        if d.phase ~= "combat" or not (j and j.vivant and etat) then return end
        local t = maintenant()
        if etat.recharge or etat.balles <= 0 then return end
        if t - etat.dernier < config.cadence_ms then return end
        etat.dernier = t
        etat.balles = etat.balles - 1

        local c = personnage(id)
        local p = joueur(id)
        if p then Events.CallRemote("duel:munitions", p, Reliability.Reliable, etat.balles) end
        -- Le son du tir, chez tout le monde autour, sauf le tireur qui l'a deja.
        for _, autre in pairs(Player.GetPairs()) do
            if autre:GetID() ~= id and c then
                Events.CallRemote("duel:coup", autre, Reliability.Unreliable, c:GetLocation())
            end
        end

        if type(cible_entite) ~= "number" or not c then return end
        local cible = nil
        for autre in pairs(d.joueurs) do
            local cc = personnage(autre)
            if cc and cc:GetID() == cible_entite then cible = autre end
        end
        if not cible or not Duel.PeutToucher(d, id, cible) then return end
        local cc = personnage(cible)
        local a, b = c:GetLocation(), cc:GetLocation()
        local dx, dy, dz = b.X - a.X, b.Y - a.Y, b.Z - a.Z
        if math.sqrt(dx * dx + dy * dy + dz * dz) > config.portee then return end

        local tete = type(os_touche) == "string" and os_touche:lower():find("head") ~= nil
        local degats = tete and config.degats_tete or config.degats
        pcall(function() cc:ApplyDamage(degats, os_touche or "", DamageType.Shot, Vector(dx, dy, dz), p) end)
        if p then Events.CallRemote("duel:touche", p, Reliability.Reliable, tete) end
        if cc:GetHealth() <= 0 then
            retirer_arme(cible)
            suite(Duel.Mort(d, cible))
        end
    end

    local function recharger(id)
        local etat = tir[id]
        if d.phase ~= "combat" or not etat or etat.recharge or etat.balles == config.chargeur then return end
        etat.recharge = true
        Timer.SetTimeout(function()
            if tir[id] ~= etat then return end
            etat.recharge = nil
            etat.balles = config.chargeur
            local p = joueur(id)
            if p then Events.CallRemote("duel:munitions", p, Reliability.Reliable, etat.balles) end
        end, config.recharge_ms)
    end

    ---------------------------------------------------------------- spectateurs

    local function regarder(id, sens)
        local actif = d.phase == "combat" or d.phase == "entre_manches" or d.phase == "decompte"
        local p = joueur(id)
        if not p or d.joueurs[id] then return end
        if sens == 0 or not actif then
            if spectateurs[id] then pcall(function() p:ResetCamera() end) end
            spectateurs[id] = nil
            return
        end
        local c = personnage(id)
        if not (c and distance_2d(c:GetLocation()) <= config.rayon_spectateurs) then return end
        local vivants = {}
        for _, autre in ipairs(d.ordre) do
            if not d.joueurs[autre].parti then vivants[#vivants + 1] = autre end
        end
        if #vivants == 0 then return end
        local i = 1
        for k, autre in ipairs(vivants) do
            if autre == spectateurs[id] then i = k % #vivants + 1 end
        end
        local cible = joueur(vivants[i])
        if cible then
            spectateurs[id] = vivants[i]
            pcall(function() p:Spectate(cible) end)
        end
    end

    ---------------------------------------------------------------- entrees

    function Adapter.Init()
        dessiner_anneau()
        Timer.SetInterval(function()
            local ok, err = pcall(surveiller)
            if not ok then Log.Warn("duel", "surveillance : " .. tostring(err)) end
        end, 250)

        Events.SubscribeRemote("duel:choisir", function(player, format, mise)
            if Duel.Choisir(d, player:GetID(), tonumber(format), tonumber(mise)) then diffuser() end
        end)
        Events.SubscribeRemote("duel:pret", function(player, pret)
            if Duel.Pret(d, player:GetID(), pret == true) then
                diffuser()
                verifier_depart()
            end
        end)
        Events.SubscribeRemote("duel:tir", function(player, cible, os_touche)
            local ok, err = pcall(tirer, player:GetID(), cible, os_touche)
            if not ok then Log.Warn("duel", "tir : " .. tostring(err)) end
        end)
        Events.SubscribeRemote("duel:recharger", function(player)
            recharger(player:GetID())
        end)
        Events.SubscribeRemote("duel:regarder", function(player, sens)
            regarder(player:GetID(), tonumber(sens) or 0)
        end)
    end

    -- Pose l'arene sous les pieds du joueur, face a son regard. Renvoie la
    -- ligne a recopier dans games/duel/data/config.lua.
    function Adapter.PoserArene(player, rayon)
        if d.phase ~= "vide" and d.phase ~= "attente" then return nil, "duel en cours" end
        local c = personnage(player:GetID())
        if not c then return nil, "pas de personnage" end
        local loc, rot = c:GetLocation(), c:GetRotation()
        local a = config.arene
        a.x, a.y, a.z = math.floor(loc.X), math.floor(loc.Y), math.floor(loc.Z - ARENE_Z_PIEDS)
        a.yaw = math.floor(rot.Yaw)
        a.rayon = rayon or a.rayon
        a.placee = true
        nettoyer()
        dessiner_anneau()
        return ("arene = { x = %d, y = %d, z = %d, rayon = %d, yaw = %d, placee = true },")
            :format(a.x, a.y, a.z, a.rayon, a.yaw)
    end

    function Adapter.OnPlayerLeave(player)
        local id = player:GetID()
        spectateurs[id] = nil
        if not d.joueurs[id] then return end
        retirer_arme(id)
        local r = Duel.Quitter(d, id)
        if d.phase == "vide" then return diffuser() end
        suite(r)
    end

    return Adapter
end
