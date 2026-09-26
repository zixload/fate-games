-- Le duel dans le monde : les arenes, les camps, les armes, la sante,
-- l'argent. Les regles vivent dans logic.lua ; ici, on les branche sur le
-- moteur (docs/DUEL-ET-ARGENT.md).
--
-- Plusieurs arenes, chacune avec son duel. Elles viennent des cylindres
-- DUEL_* poses dans la map (data/arenes.lua, scripts/unreal/export_arenes.py) ;
-- /arene en ajoute une de test sous ses pieds.

return function(Log, Characters, Boutique, Catalogue, Duel, config, arenes_carte)
    local Adapter = {}

    local Z_PIEDS = 88           -- cm entre le centre du personnage et ses pieds
    local arenes = {}            -- liste des arenes : { nom, x, y, z, rayon, yaw, d, ... }
    local arene_de = {}          -- player_id -> arene ou il combat ou attend
    local armes = {}             -- player_id -> StaticMesh en main
    local tir = {}               -- player_id -> { balles, dernier, recharge }
    local comptes = {}           -- player_id -> account, fige au lancement
    local noms = {}              -- player_id -> nom, pour le HUD
    local spectateurs = {}       -- player_id -> { arene, cible }
    local dehors = {}            -- player_id -> derniere position hors de toute arene
    local choix_arme = {}        -- player_id -> arme choisie pour le duel
    local dernier_dedans = {}    -- player_id -> derniere position dans son arene
    -- Bots de test (/botduel) : identifiants negatifs, jamais ceux d'un joueur.
    local bots = {}              -- id -> { corps, arene, tir, pas }
    local prochain_bot = -1000

    local function maintenant() return Server.GetTime() end

    local function joueur(id)
        for _, p in pairs(Player.GetPairs()) do
            if p:GetID() == id then return p end
        end
        return nil
    end

    local function personnage(id)
        local b = bots[id]
        if b then return b.corps and b.corps:IsValid() and b.corps or nil end
        local s = Characters.SessionByPlayer(id)
        return s and s.character and s.character:IsValid() and s.character or nil
    end

    local function avec_bot(A)
        for id in pairs(A.d.joueurs) do
            if bots[id] then return true end
        end
        return false
    end

    local function actif(A)
        local p = A.d.phase
        return p == "decompte" or p == "combat" or p == "entre_manches"
    end

    ---------------------------------------------------------------- arenes

    local function distance_2d(A, loc)
        local dx, dy = loc.X - A.x, loc.Y - A.y
        return math.sqrt(dx * dx + dy * dy)
    end

    -- Position dans le repere de l'arene : x le long de l'axe des camps.
    local function repere(A, loc)
        local dx, dy = loc.X - A.x, loc.Y - A.y
        local a = math.rad(A.yaw)
        return dx * math.cos(a) + dy * math.sin(a), -dx * math.sin(a) + dy * math.cos(a)
    end

    -- Distance au bord de l'arene (0 dedans).
    local function distance_bord(A, loc)
        if A.forme == "cercle" then return math.max(0, distance_2d(A, loc) - A.demi_x) end
        local lx, ly = repere(A, loc)
        local ex, ey = math.max(0, math.abs(lx) - A.demi_x), math.max(0, math.abs(ly) - A.demi_y)
        return math.sqrt(ex * ex + ey * ey)
    end

    local function dedans(A, loc)
        if math.abs(loc.Z - Z_PIEDS - A.z) >= 400 then return false end
        if A.forme == "cercle" then return distance_2d(A, loc) <= A.demi_x end
        local lx, ly = repere(A, loc)
        return math.abs(lx) <= A.demi_x and math.abs(ly) <= A.demi_y
    end

    -- Du repere de l'arene au monde.
    local function monde(A, lx, ly, z)
        local a = math.rad(A.yaw)
        return Vector(A.x + lx * math.cos(a) - ly * math.sin(a), A.y + lx * math.sin(a) + ly * math.cos(a), z)
    end

    -- Le contour au sol est dessine par chaque client en decalques projetes
    -- sur le terrain (Client/duel/contour.lua) : Decal n'existe que chez lui,
    -- et un trait pose a plat flottait au-dessus des dunes.
    local function definitions()
        local liste = {}
        for _, A in ipairs(arenes) do
            liste[#liste + 1] = { nom = A.nom, forme = A.forme, x = A.x, y = A.y, z = A.z,
                demi_x = A.demi_x, demi_y = A.demi_y, yaw = A.yaw }
        end
        return liste
    end

    local function publier_arenes(player)
        if player then
            Events.CallRemote("duel:arenes", player, Reliability.Reliable, definitions())
        else
            Events.BroadcastRemote("duel:arenes", Reliability.Reliable, definitions())
        end
    end

    -- Murs invisibles et solides sur le bord de l'arene, le temps d'un duel :
    -- ni les combattants ne sortent, ni les autres n'entrent.
    local function murer(A, oui)
        for _, m in ipairs(A.murs or {}) do if m:IsValid() then m:Destroy() end end
        A.murs = {}
        if not oui then return end
        local M = config.murs
        local points = {}
        if A.forme == "cercle" then
            local n = math.max(16, math.floor(2 * math.pi * A.demi_x / 250))
            for k = 0, n do
                local ang = k / n * 2 * math.pi
                points[#points + 1] = { math.cos(ang) * A.demi_x, math.sin(ang) * A.demi_x }
            end
        else
            points = { { A.demi_x, A.demi_y }, { -A.demi_x, A.demi_y }, { -A.demi_x, -A.demi_y },
                { A.demi_x, -A.demi_y }, { A.demi_x, A.demi_y } }
        end
        for k = 1, #points - 1 do
            local a, b = points[k], points[k + 1]
            local longueur = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2) + M.epaisseur
            local cap = A.yaw + math.deg(math.atan(b[2] - a[2], b[1] - a[1]))
            local milieu = monde(A, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, A.z + M.hauteur / 2)
            local ok, mur = pcall(StaticMesh, milieu, Rotator(0, cap, 0), "nanos-world::SM_Cube", CollisionType.Normal)
            if ok and mur then
                mur:SetScale(Vector(longueur / 100, M.epaisseur / 100, M.hauteur / 100))
                mur:SetVisibility(false)
                A.murs[#A.murs + 1] = mur
            end
        end
    end

    -- Eclairage : une grille de lumieres dans la forme de l'arene.
    local function eclairer(A)
        for _, l in ipairs(A.lumieres or {}) do if l:IsValid() then l:Destroy() end end
        A.lumieres = {}
        local L = config.lumiere
        if not (L and L.enabled) then return end
        local nx = math.max(1, math.floor(2 * A.demi_x / L.espacement + 0.5))
        local ny = math.max(1, math.floor(2 * A.demi_y / L.espacement + 0.5))
        for i = 1, nx do
            for k = 1, ny do
                local lx = -A.demi_x + (i - 0.5) * 2 * A.demi_x / nx
                local ly = -A.demi_y + (k - 0.5) * 2 * A.demi_y / ny
                local garder = A.forme ~= "cercle" or (lx * lx + ly * ly <= A.demi_x * A.demi_x)
                if garder then
                    local pos = monde(A, lx, ly, A.z + L.hauteur)
                    local ok, lumiere = pcall(Light, pos, Rotator(0, 0, 0),
                        Color(L.couleur.r, L.couleur.g, L.couleur.b), LightType.Point,
                        L.intensite, L.rayon, 44, 0, 0, true, L.ombres == true, true)
                    if ok and lumiere then A.lumieres[#A.lumieres + 1] = lumiere
                    elseif not ok then Log.Warn("duel", "lumiere impossible : " .. tostring(lumiere)) end
                end
            end
        end
    end

    local function nouvelle_arene(def)
        local A = { nom = def.nom, forme = def.forme or "cercle", x = def.x, y = def.y, z = def.z,
            demi_x = def.demi_x or def.rayon, demi_y = def.demi_y or def.rayon,
            yaw = def.yaw or 0, d = Duel.Nouveau(), numero = 0,
            departs = (def.depart_a and def.depart_b) and { def.depart_a, def.depart_b } or nil }
        -- Le bas de la forme peut s'enfoncer sous le sol (DUEL_1 descend a -850) :
        -- les points d'apparition, poses sur le sol, donnent la vraie hauteur.
        if A.departs then A.z = math.min(A.departs[1].z, A.departs[2].z) end
        arenes[#arenes + 1] = A
        eclairer(A)
        return A
    end

    -- Depart d'un combattant : son camp a un bout de l'arene, face a l'autre.
    local function depart(A, camp, rang, nombre)
        -- Points poses dans la map (DUEL_n_A, DUEL_n_B) : chaque camp face a l'autre,
        -- les coequipiers cote a cote.
        if A.departs then
            local ici, la = A.departs[camp], A.departs[3 - camp]
            local dx, dy = la.x - ici.x, la.y - ici.y
            local n = math.sqrt(dx * dx + dy * dy)
            if n < 1 then dx, dy, n = 1, 0, 1 end
            local cote = (rang - (nombre + 1) / 2) * 120
            return Vector(ici.x - dy / n * cote, ici.y + dx / n * cote, ici.z + Z_PIEDS + 10),
                Rotator(0, math.deg(math.atan(dy, dx)), 0)
        end
        local sens = camp == 1 and -1 or 1
        local cote = (rang - (nombre + 1) / 2) * math.min(180, A.demi_y * 0.5)
        local face = A.yaw + (camp == 1 and 0 or 180)
        return monde(A, A.demi_x * 0.65 * sens, cote, A.z + Z_PIEDS + 10), Rotator(0, face, 0)
    end

    local function depart_de(A, id)
        local j = A.d.joueurs[id]
        local membres = Duel.Membres(A.d, j.camp)
        for rang, m in ipairs(membres) do
            if m == id then return depart(A, j.camp, rang, #membres) end
        end
    end

    ---------------------------------------------------------------- HUD

    local function vue(A)
        local d = A.d
        local v = {
            arene = A.nom, phase = d.phase, mise = d.mise, createur = d.createur,
            format = d.phase == "attente" and Duel.FormatAttendu(d) or d.format,
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

    -- L'etat d'une arene part a ses joueurs et a ceux qui regardent de pres.
    local function diffuser(A)
        local v = vue(A)
        for _, p in pairs(Player.GetPairs()) do
            local id = p:GetID()
            local c = personnage(id)
            local concerne = arene_de[id] == A
                or (not arene_de[id] and c and distance_bord(A, c:GetLocation()) <= config.rayon_spectateurs)
            if concerne then Events.CallRemote("duel:etat", p, Reliability.Reliable, v) end
        end
    end

    local function annoncer(A, evenement, ...)
        for id in pairs(A.d.joueurs) do
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

    -- Les armes qu'un joueur peut prendre en duel : achetees (ou gratuites) et
    -- avec un modele 3D fiable. Le pistolet a glace faisait planter le jeu.
    local function armes_de(id)
        local s = Characters.SessionByPlayer(id)
        local etat = s and s.account and Boutique.Etat(s.account)
        local liste = {}
        for _, article in ipairs(Catalogue.armes) do
            if etat and Boutique.Possede(etat, "armes", article.id) and Catalogue.en_3d(article.id) then
                liste[#liste + 1] = { id = article.id, rendu = article.rendu }
            end
        end
        return liste, etat
    end

    local function arme_de(id)
        local liste, etat = armes_de(id)
        local voulue = choix_arme[id] or (etat and etat.arme)
        for _, a in ipairs(liste) do
            if a.id == voulue then return voulue end
        end
        return Catalogue.arme_de_base
    end

    local function envoyer_armes(id)
        local p = joueur(id)
        if p then Events.CallRemote("duel:mes_armes", p, Reliability.Reliable, (armes_de(id)), arme_de(id)) end
    end

    -- L'arme choisie, dans la main : vue par les autres. Le joueur, lui, voit
    -- la sienne devant sa camera (Client/duel/duel.lua).
    local function donner_arme(id)
        retirer_arme(id)
        local c = personnage(id)
        if not c then return end
        local choix = arme_de(id)
        local article = Catalogue.article("armes", choix)
        local ok, err = pcall(function()
            local m = StaticMesh(c:GetLocation(), Rotator(0, 0, 0), article.mesh, CollisionType.NoCollision)
            local s = (article.taille or 30) / 100
            m:SetScale(Vector(s, s, s))
            local r = config.arme
            m:AttachTo(c, AttachmentRule.SnapToTarget, r.os, -1, false)
            m:SetRelativeLocation(Vector(r.position.x, r.position.y, r.position.z))
            m:SetRelativeRotation(Rotator(r.rotation.p, r.rotation.y, r.rotation.r))
            m:SetValue("duel_proprio", id, true)
            armes[id] = m
        end)
        if not ok then Log.Warn("duel", "arme en main impossible : " .. tostring(err)) end
    end

    ---------------------------------------------------------------- deroulement

    local function annuler_minuteur(A)
        if A.minuteur then Timer.ClearTimeout(A.minuteur) end
        A.minuteur = nil
    end

    local function plus_tard(A, ms, f)
        annuler_minuteur(A)
        A.minuteur = Timer.SetTimeout(function() A.minuteur = nil; f() end, ms)
    end

    local function remettre_en_etat(id)
        local c = personnage(id)
        if not c then return end
        pcall(function()
            if c:IsDead() then c:Respawn(c:GetLocation(), c:GetRotation()) end
            c:SetHealth(c:GetMaxHealth())
            c:SetValue("duel", nil, true)
        end)
        Characters.VuePremiere(id, false)
    end

    local function arreter_spectateurs(A)
        for id, s in pairs(spectateurs) do
            if s.arene == A then
                local p = joueur(id)
                if p then pcall(function() p:ResetCamera() end) end
                spectateurs[id] = nil
            end
        end
    end

    -- Fin du duel ou arene videe : tout revient comme avant.
    local function nettoyer(A)
        annuler_minuteur(A)
        for id in pairs(A.d.joueurs) do
            retirer_arme(id)
            remettre_en_etat(id)
            arene_de[id], tir[id], comptes[id], choix_arme[id], dernier_dedans[id] = nil, nil, nil, nil, nil
        end
        arreter_spectateurs(A)
        murer(A, false)
        for id, b in pairs(bots) do
            if b.arene == A then
                if b.corps and b.corps:IsValid() then b.corps:Destroy() end
                bots[id] = nil
            end
        end
        A.d = Duel.Nouveau()
        diffuser(A)
    end

    local function debut_manche(A)
        Duel.DebutManche(A.d)
        for id, j in pairs(A.d.joueurs) do
            if not j.parti then
                local c = personnage(id)
                local pos, rot = depart_de(A, id)
                if c then
                    -- Respawn pour tous, vivants compris : il remplit la vie (doc
                    -- Damageable) et place au depart. Un simple SetHealth laissait
                    -- au survivant la vie perdue a la manche d'avant.
                    local ok, err = pcall(function()
                        c:SetMaxHealth(config.sante)
                        c:Respawn(pos, rot)
                        c:SetHealth(config.sante)
                        c:SetValue("duel", { camp = j.camp, combat = true, arme = arme_de(id) }, true)
                    end)
                    if not ok then Log.Warn("duel", "remise en etat de manche : " .. tostring(err)) end
                    Characters.VuePremiere(id, true, config.camera)
                end
                tir[id] = { balles = config.chargeur, dernier = 0 }
                donner_arme(id)
                local p = joueur(id)
                if p then
                    p:SetCameraRotation(rot)
                    Events.CallRemote("duel:munitions", p, Reliability.Reliable, config.chargeur)
                end
            end
        end
        annoncer(A, "duel:manche", A.d.manche)
        diffuser(A)
    end

    local function terminer(A, gagnant)
        local partie = ("duel:%s:%d"):format(A.nom, A.numero)
        local participants, gagnants = {}, {}
        for id, j in pairs(A.d.joueurs) do
            local account = comptes[id]
            if account and not j.parti then
                participants[#participants + 1] = account
                if j.camp == gagnant then gagnants[#gagnants + 1] = account end
            end
        end
        local payes = 0
        for id in pairs(A.d.joueurs) do if comptes[id] then payes = payes + 1 end end
        local cagnotte = A.d.mise * payes
        local bonus = avec_bot(A) and 0 or config.bonus_participation
        Boutique.Solder(partie, participants, gagnants, cagnotte, bonus, nil, function()
            Log.Info("duel", ("partie %s : camp %d gagne %d"):format(partie, gagnant, cagnotte))
        end)
        annoncer(A, "duel:fin", gagnant, cagnotte)
        diffuser(A)
        plus_tard(A, config.fin_ms, function() nettoyer(A) end)
    end

    local function suite(A, r)
        if not r then return diffuser(A) end
        if r.fin then return terminer(A, r.gagnant) end
        if r.manche then
            annoncer(A, "duel:manche_gagnee", r.gagnant, A.d.scores)
            diffuser(A)
            plus_tard(A, config.entre_manches_ms, function()
                if A.d.phase == "entre_manches" then debut_manche(A) end
            end)
        end
    end

    local function lancer(A)
        -- Une partie avec un bot ne rapporte rien : pas de mise, pas de bonus.
        if avec_bot(A) then A.d.mise = 0 end
        local liste = {}
        for _, id in ipairs(A.d.ordre) do
            local s = Characters.SessionByPlayer(id)
            comptes[id] = s and s.account or nil
            if comptes[id] then liste[#liste + 1] = comptes[id] end
        end
        A.numero = A.numero + 1
        local partie = ("duel:%s:%d"):format(A.nom, A.numero)
        Boutique.Miser(liste, A.d.mise, partie, nil, function(ok, raison, fauches)
            if not ok then
                Duel.Annuler(A.d)
                local qui = {}
                for _, account in ipairs(fauches or {}) do
                    for id, a in pairs(comptes) do
                        if a == account then qui[#qui + 1] = noms[id] or "?" end
                    end
                end
                annoncer(A, "duel:refus", raison, qui)
                for id in pairs(A.d.joueurs) do comptes[id] = nil end
                return diffuser(A)
            end
            Duel.Lancer(A.d)
            murer(A, true)
            annoncer(A, "duel:decompte", config.decompte_ms)
            diffuser(A)
            plus_tard(A, config.decompte_ms, function()
                if A.d.phase == "decompte" then debut_manche(A) end
            end)
        end)
    end

    local function verifier_depart(A)
        if Duel.ToutPret(A.d) then lancer(A) end
    end

    ---------------------------------------------------------------- les zones

    -- Quatre fois par seconde : qui entre, qui sort, qui force la porte.
    local function surveiller()
        local changees = {}
        for _, p in pairs(Player.GetPairs()) do
            local id = p:GetID()
            local s = Characters.SessionByPlayer(id)
            local c = personnage(id)
            if c and s and not s.assis and not Characters.AuVestiaire(id) then
                noms[id] = p:GetName()
                local loc = c:GetLocation()
                local ici = nil
                for _, A in ipairs(arenes) do
                    if dedans(A, loc) then ici = A break end
                end
                local mienne = arene_de[id]

                if mienne and actif(mienne) and not mienne.d.joueurs[id].parti then
                    -- Les murs le retiennent ; s'il passe quand meme, il revient a
                    -- sa derniere position dans l'arene, pas au depart.
                    if ici == mienne then
                        dernier_dedans[id] = loc
                    else
                        c:SetLocation(dernier_dedans[id] or (depart_de(mienne, id)))
                    end
                elseif ici and actif(ici) then
                    -- Arene fermee : retour la ou l'on etait avant d'entrer.
                    local retour = dehors[id]
                    if retour then c:SetLocation(retour) end
                else
                    if not ici then dehors[id] = loc end
                    if mienne and mienne ~= ici then
                        Duel.Quitter(mienne.d, id)
                        arene_de[id] = nil
                        changees[mienne] = true
                        Events.CallRemote("duel:etat", p, Reliability.Reliable, vue(mienne))
                    end
                    if ici and not arene_de[id] then
                        if Duel.Entrer(ici.d, id) then
                            arene_de[id] = ici
                            changees[ici] = true
                            envoyer_armes(id)
                        end
                    end
                end
            end
        end
        for A in pairs(changees) do
            local humain = false
            for id in pairs(A.d.joueurs) do if not bots[id] then humain = true end end
            if not humain and A.d.phase == "attente" then
                nettoyer(A)
            else
                diffuser(A)
                verifier_depart(A)
            end
        end
    end

    ---------------------------------------------------------------- tirs

    local function tirer(id, cible_entite, os_touche, point)
        local A = arene_de[id]
        if not A then return end
        local d = A.d
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
        -- Le son et la trainee du tir chez tout le monde autour, sauf le tireur
        -- qui les a deja dessines chez lui. La trainee part de l'arme en main.
        if c then
            local arme = armes[id]
            local depart = (arme and arme:IsValid()) and arme:GetLocation() or (c:GetLocation() + Vector(0, 0, 60))
            local fin = nil
            if point ~= nil and type(point.X) == "number" then
                local dx, dy, dz = point.X - depart.X, point.Y - depart.Y, point.Z - depart.Z
                local n = math.sqrt(dx * dx + dy * dy + dz * dz)
                if n > config.portee then point = depart + Vector(dx, dy, dz) * (config.portee / n) end
                fin = point
            end
            for _, autre in pairs(Player.GetPairs()) do
                if autre:GetID() ~= id then
                    Events.CallRemote("duel:coup", autre, Reliability.Unreliable, depart, fin)
                end
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
            suite(A, Duel.Mort(d, cible))
        end
    end

    local function recharger(id)
        local A = arene_de[id]
        local etat = tir[id]
        if not (A and A.d.phase == "combat" and etat) or etat.recharge or etat.balles == config.chargeur then return end
        etat.recharge = true
        local p = joueur(id)
        if p then Events.CallRemote("duel:recharge", p, Reliability.Reliable, config.recharge_ms) end
        Timer.SetTimeout(function()
            if tir[id] ~= etat then return end
            etat.recharge = nil
            etat.balles = config.chargeur
            local p = joueur(id)
            if p then Events.CallRemote("duel:munitions", p, Reliability.Reliable, etat.balles) end
        end, config.recharge_ms)
    end

    ---------------------------------------------------------------- bots de test

    -- Un bot vise un adversaire vivant, se decale de temps en temps et tire
    -- avec une chance de toucher (config.bot). Meme degats qu'un joueur.
    local function penser_bot(id, b)
        local A = b.arene
        local d = A.d
        local j = d.joueurs[id]
        local corps = personnage(id)
        if d.phase ~= "combat" or not (j and j.vivant and corps) then return end
        -- Un adversaire vivant, de preference un qui le voit (ligne de vue
        -- rapportee par son client, "duel:vue") : on ne tire que sur ceux-la.
        local cible, cc, vu = nil, nil, false
        for autre, ja in pairs(d.joueurs) do
            if ja.camp ~= j.camp and ja.vivant then
                local c2 = personnage(autre)
                local v = b.vu_par[autre] == true
                if c2 and (not cible or (v and not vu)) then cible, cc, vu = autre, c2, v end
            end
        end
        if not cible then return end
        local a, v = corps:GetLocation(), cc:GetLocation()
        local cap = math.deg(math.atan(v.Y - a.Y, v.X - a.X))
        b.cap_voulu = cap

        local t = maintenant()
        local r = config.bot
        if t >= b.pas then
            b.pas = t + r.pas_ms
            local cote = (math.random() < 0.5 and -1 or 1) * r.pas
            local ang = math.rad(cap + 90)
            local depart = depart_de(A, id)
            b.but = Vector(depart.X + math.cos(ang) * cote, depart.Y + math.sin(ang) * cote, depart.Z)
            -- Avec une NavMesh dans l'arene, il marche (animation comprise) ;
            -- sans, bouger_bots le fait glisser jusqu'au meme point.
            pcall(function() corps:MoveTo(b.but, 30) end)
        end
        if t < b.tir or not vu then return end
        b.tir = t + math.random(r.tir_min_ms, r.tir_max_ms)

        local touche = math.random() < r.precision
        local arme = armes[id]
        local de = (arme and arme:IsValid()) and arme:GetLocation() or (a + Vector(0, 0, 60))
        local vers = v + Vector(0, 0, 40)
        if not touche then vers = vers + Vector(math.random(-120, 120), math.random(-120, 120), math.random(-40, 80)) end
        for _, p in pairs(Player.GetPairs()) do
            Events.CallRemote("duel:coup", p, Reliability.Unreliable, de, vers)
        end
        if touche then
            pcall(function() cc:ApplyDamage(config.degats, "", DamageType.Shot, v - a, nil) end)
            if cc:GetHealth() <= 0 then
                retirer_arme(cible)
                suite(A, Duel.Mort(d, cible))
            end
        end
    end

    local function angle(a) return (a + 180) % 360 - 180 end

    -- A chaque image serveur (33 ms) : le bot pivote vers son cap et, si
    -- MoveTo ne le fait pas marcher (pas de NavMesh), glisse vers son but.
    local function bouger_bots(delta)
        local r = config.bot
        for id, b in pairs(bots) do
            local corps = personnage(id)
            local j = b.arene.d.joueurs[id]
            if corps and j and j.vivant and b.arene.d.phase == "combat" then
                local rot = corps:GetRotation()
                if b.cap_voulu then
                    local ecart = angle(b.cap_voulu - rot.Yaw)
                    local pas = r.virage * delta
                    corps:SetRotation(Rotator(0, rot.Yaw + math.max(-pas, math.min(pas, ecart)), 0))
                end
                if b.but then
                    local loc, vel = corps:GetLocation(), corps:GetVelocity()
                    local dx, dy = b.but.X - loc.X, b.but.Y - loc.Y
                    local reste = math.sqrt(dx * dx + dy * dy)
                    local marche = vel.X * vel.X + vel.Y * vel.Y > 400
                    if reste < 20 then
                        b.but = nil
                    elseif not marche then
                        local pas = math.min(reste, r.vitesse * delta)
                        corps:SetLocation(Vector(loc.X + dx / reste * pas, loc.Y + dy / reste * pas, loc.Z))
                    end
                end
            end
        end
    end

    -- Ajoute un bot, pret, a l'arene ou attend le joueur. nil, raison sinon.
    function Adapter.AjouterBot(player)
        local A = arene_de[player:GetID()]
        if not A then return nil, "entre d'abord dans l'arene" end
        if A.d.phase ~= "attente" then return nil, "duel deja lance" end
        local id = prochain_bot
        prochain_bot = prochain_bot - 1
        if not Duel.Entrer(A.d, id) then return nil, "arene complete" end
        local pos, rot = depart_de(A, id)
        local corps = Characters.CorpsDebout(pos.X, pos.Y, pos.Z, rot.Yaw, "ronchon")
        if not corps then
            Duel.Quitter(A.d, id)
            return nil, "pas de corps Creative (dev.creative_character desactive)"
        end
        bots[id] = { corps = corps, arene = A, tir = 0, pas = 0, vu_par = {} }
        corps:SetValue("duel_bot", id, true)
        -- Ni face a un controleur (il n'en a pas) ni tourne vers son mouvement :
        -- son orientation vient seulement de bouger_bots. Sinon il tournait sur
        -- lui-meme, tire entre les deux.
        pcall(function() corps:SetRotationSettings(Rotator(0, 0, 0), false, false) end)
        noms[id] = "Bot " .. tostring(-id - 999)
        arene_de[id] = A
        Duel.Pret(A.d, id, true)
        diffuser(A)
        verifier_depart(A)
        return noms[id]
    end

    ---------------------------------------------------------------- spectateurs

    -- F : suivre le combattant suivant de l'arene la plus proche ; G : revenir.
    local function regarder(id, sens)
        local p = joueur(id)
        if not p or arene_de[id] then return end
        if sens == 0 then
            if spectateurs[id] then pcall(function() p:ResetCamera() end) end
            spectateurs[id] = nil
            return
        end
        local c = personnage(id)
        if not c then return end
        local A = spectateurs[id] and spectateurs[id].arene
        if not A then
            local mieux = nil
            for _, B in ipairs(arenes) do
                local dist = distance_bord(B, c:GetLocation())
                if actif(B) and dist <= config.rayon_spectateurs and (not mieux or dist < mieux) then
                    A, mieux = B, dist
                end
            end
        end
        if not (A and actif(A)) then return end
        local vivants = {}
        for _, autre in ipairs(A.d.ordre) do
            if not A.d.joueurs[autre].parti then vivants[#vivants + 1] = autre end
        end
        if #vivants == 0 then return end
        local i = 1
        local actuel = spectateurs[id] and spectateurs[id].cible
        for k, autre in ipairs(vivants) do
            if autre == actuel then i = k % #vivants + 1 end
        end
        local cible = joueur(vivants[i])
        if cible then
            spectateurs[id] = { arene = A, cible = vivants[i] }
            pcall(function() p:Spectate(cible) end)
        end
    end

    ---------------------------------------------------------------- entrees

    function Adapter.Init()
        for _, def in ipairs(arenes_carte or {}) do nouvelle_arene(def) end
        Log.Info("duel", ("%d arene(s) chargee(s)"):format(#arenes))

        Timer.SetInterval(function()
            local ok, err = pcall(surveiller)
            if not ok then Log.Warn("duel", "surveillance : " .. tostring(err)) end
            for id, b in pairs(bots) do
                local ok_bot, err_bot = pcall(penser_bot, id, b)
                if not ok_bot then Log.Warn("duel", "bot : " .. tostring(err_bot)) end
            end
        end, 250)

        Server.Subscribe("Tick", function(delta)
            local ok, err = pcall(bouger_bots, delta)
            if not ok then Log.Warn("duel", "mouvement des bots : " .. tostring(err)) end
        end)

        Events.SubscribeRemote("duel:mise", function(player, mise)
            local A = arene_de[player:GetID()]
            if A and Duel.ChoisirMise(A.d, player:GetID(), tonumber(mise)) then diffuser(A) end
        end)
        -- Choix de l'arme : dans l'arene, hors combat. Prise a la manche suivante.
        Events.SubscribeRemote("duel:arme", function(player, arme)
            local id = player:GetID()
            local A = arene_de[id]
            if not A or A.d.phase == "combat" or type(arme) ~= "string" then return end
            for _, a in ipairs((armes_de(id))) do
                if a.id == arme then
                    choix_arme[id] = arme
                    envoyer_armes(id)
                    return
                end
            end
        end)
        Events.SubscribeRemote("duel:pret", function(player, pret)
            local A = arene_de[player:GetID()]
            if A and Duel.Pret(A.d, player:GetID(), pret == true) then
                diffuser(A)
                verifier_depart(A)
            end
        end)
        Events.SubscribeRemote("duel:tir", function(player, cible, os_touche, point)
            local ok, err = pcall(tirer, player:GetID(), cible, os_touche, point)
            if not ok then Log.Warn("duel", "tir : " .. tostring(err)) end
        end)
        Events.SubscribeRemote("duel:vue", function(player, bot, visible)
            local b = type(bot) == "number" and bots[bot]
            if b then b.vu_par[player:GetID()] = visible == true end
        end)
        Events.SubscribeRemote("duel:recharger", function(player)
            recharger(player:GetID())
        end)
        Events.SubscribeRemote("duel:regarder", function(player, sens)
            regarder(player:GetID(), tonumber(sens) or 0)
        end)
    end

    -- Arene de test sous les pieds du joueur, face a son regard (/arene).
    -- Elle remplace la precedente de test et disparait au redemarrage : les
    -- vraies arenes se posent dans la map (scripts/unreal/export_arenes.py).
    function Adapter.PoserArene(player, rayon)
        local c = personnage(player:GetID())
        if not c then return nil, "pas de personnage" end
        for i, A in ipairs(arenes) do
            if A.nom == "TEST" then
                if actif(A) then return nil, "duel en cours" end
                nettoyer(A)
                for _, l in ipairs(A.lumieres or {}) do if l:IsValid() then l:Destroy() end end
                table.remove(arenes, i)
                break
            end
        end
        local loc, rot = c:GetLocation(), c:GetRotation()
        local r = rayon or config.rayon_test
        local A = nouvelle_arene({ nom = "TEST", forme = "cercle", x = math.floor(loc.X), y = math.floor(loc.Y),
            z = math.floor(loc.Z - Z_PIEDS), demi_x = r, demi_y = r, yaw = math.floor(rot.Yaw) })
        publier_arenes()
        return ("arene TEST : x = %d, y = %d, z = %d, rayon = %d, yaw = %d"):format(A.x, A.y, A.z, r, A.yaw)
    end

    -- A l'arrivee d'un joueur : la forme des arenes, pour son contour au sol.
    function Adapter.OnPlayerReady(player)
        publier_arenes(player)
    end

    function Adapter.OnPlayerLeave(player)
        local id = player:GetID()
        spectateurs[id], dehors[id], choix_arme[id] = nil, nil, nil
        local A = arene_de[id]
        if not A then return end
        arene_de[id] = nil
        retirer_arme(id)
        local r = Duel.Quitter(A.d, id)
        if A.d.phase == "vide" or A.d.phase == "attente" then return diffuser(A) end
        suite(A, r)
    end

    return Adapter
end
