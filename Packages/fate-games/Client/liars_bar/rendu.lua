-- Rendu 3D des cartes de Liar's Bar : ma main en eventail, des dos dans la
-- main des autres, le tas du centre et la derniere revelation, avec leurs
-- mouvements : la donne (du centre vers les mains), la pose (de la main au
-- tas, face cachee) et la revelation (du tas, retournees).
--
-- Tout ce qui est cree ici n'existe que chez ce client : il en a l'autorite
-- (doc Authority Concepts), il peut donc l'accrocher et le deplacer. Rien de
-- secret n'y entre : les faces viennent de ma main et de la revelation
-- publique, tout le reste est un dos. Un client ne recoit jamais les cartes
-- des autres : il ne peut pas les montrer, meme en vol.
--
-- Le rendu suit le journal. Chaque groupe (ma main, chaque autre main, la
-- table) a une cle ; quand sa cle change, le groupe est reconstruit. Aucune
-- regle du jeu ici, du placement seulement.
--
-- A REGLER EN JEU : axes et echelle du FBX des cartes, os et pose de la main.
-- Voir /fan.

return function(config, Cartes, journal, disposition)
    local Rendu = {}

    local function vec(t) return Vector(t.x, t.y, t.z) end
    local function rot(t) return Rotator(t.p, t.y, t.r) end

    local function detruire(objets)
        for _, o in ipairs(objets or {}) do
            if o and o:IsValid() then o:Destroy() end
        end
    end

    -- Rien de ce rendu ne doit arreter une trace : le support est un cube
    -- d'un metre autour de la main, et il masquait le revolver a la visee
    -- (E sans invite). Le constructeur recoit deja NoCollision ; on le
    -- redit, SetCollision est permis a qui a l'autorite (doc Actor).
    local function sans_collision(objet)
        objet:SetCollision(CollisionType.NoCollision)
        pcall(function() objet:SetCastShadow(false) end)
    end

    -- Support invisible accroche a parent (a un os si os_nom est donne).
    -- lifespan 0 : si le porteur disparait, le support et tout ce qu'il tient
    -- disparaissent avec lui.
    local function support(parent, os_nom)
        local s = StaticMesh(Vector(), Rotator(), config.pivot_mesh, CollisionType.NoCollision)
        sans_collision(s)
        s:SetVisibility(false)
        s:AttachTo(parent, AttachmentRule.SnapToTarget, os_nom or "", 0)
        return s
    end

    local function carte_accrochee(modele, parent)
        local c = StaticMesh(Vector(), Rotator(), modele, CollisionType.NoCollision)
        sans_collision(c)
        c:AttachTo(parent, AttachmentRule.SnapToTarget, "", 0)
        c:SetRelativeRotation(rot(config.fan.carte))
        local t = config.fan.taille
        c:SetScale(Vector(t, t, t))
        return c
    end

    -- Un eventail dans la main d'un personnage. modeles[i] : le modele de la
    -- carte i ; levees[i] : sa levee en cm. Rend les objets a detruire et les
    -- cartes seules, dans l'ordre de la main (pour les faire voler).
    local function eventail(personnage, os_nom, modeles, levees)
        local objets, cartes = {}, {}
        local pivot = support(personnage, os_nom)
        pivot:SetRelativeLocation(vec(config.fan.pos))
        pivot:SetRelativeRotation(rot(config.fan.rot))
        objets[#objets + 1] = pivot

        local n = #modeles
        for i, modele in ipairs(modeles) do
            local f = Cartes.Fente(n, i, config.fan, levees[i] or 0)
            local fente = support(pivot)
            fente:SetRelativeLocation(Vector(f.x, f.y, f.z))
            fente:SetRelativeRotation(Rotator(0, f.yaw, 0))
            objets[#objets + 1] = fente
            local c = carte_accrochee(modele, fente)
            objets[#objets + 1] = c
            cartes[i] = c
        end
        return objets, cartes
    end

    -- Le centre de la table. Le serveur le publie sur le revolver
    -- ("liars_home") quand sa place a ete deplacee a l'atelier ; sinon, la
    -- disposition partagee.
    local function centre_table()
        for _, p in pairs(Prop.GetPairs()) do
            local c = p:IsValid() and p:GetValue("liars_home", nil) or nil
            if type(c) == "table" and c.x and c.y and c.z then return c end
        end
        return disposition.revolver_home
    end

    -- Lieu et rotation monde d'une carte posee a plat sur la table.
    local function lieu_table(lieu, orientation, lacet, centre)
        return Vector(centre.x + lieu.x, centre.y + lieu.y, centre.z + lieu.z),
            Rotator(orientation.p, orientation.y + (lacet or 0), orientation.r)
    end

    local function carte_libre(modele, position, rotation)
        local c = StaticMesh(position, rotation, modele, CollisionType.NoCollision)
        sans_collision(c)
        local t = config.fan.taille
        c:SetScale(Vector(t, t, t))
        return c
    end

    local function carte_posee(modele, lieu, orientation, lacet, centre)
        local p, r = lieu_table(lieu, orientation, lacet, centre)
        return carte_libre(modele, p, r)
    end

    local function os_de(personnage)
        if personnage:IsA(CharacterSimple) then return config.bone_simple end
        return config.bone_mannequin
    end

    -- Le personnage assis a une chaise : le serveur publie la chaise sur lui
    -- ("liars_chair"), bots compris.
    local function personnage_de_chaise(chaise)
        for _, classe in ipairs({ CharacterSimple, Character }) do
            for _, c in pairs(classe.GetPairs()) do
                if c:IsValid() and c:GetValue("liars_chair", 0) == chaise then return c end
            end
        end
        return nil
    end

    local function mon_personnage()
        local player = Client.GetLocalPlayer()
        return player and player:GetControlledCharacter() or nil
    end

    ---------------------------------------------------------------- vols

    -- Une carte en vol : detachee, deplacee a chaque image d'un lieu a un
    -- autre, en arc, avec une rotation interpolee. a_l_arrivee() est appelee
    -- quand elle se pose. Les cartes attendent leur tour (retard) sans bouger.
    local vols = {}
    local anim = config.anim or {}

    local function angle(a) return (a + 180) % 360 - 180 end
    local function lisse(t) return t * t * (3 - 2 * t) end

    local function voler(modele, de, de_rot, vers, vers_rot, retard, a_l_arrivee)
        local ok, c = pcall(carte_libre, modele, de, de_rot)
        if not ok then return end
        vols[#vols + 1] = {
            c = c, de = de, vers = vers, de_rot = de_rot, vers_rot = vers_rot,
            t = -(retard or 0), duree = anim.duree or 0.45, arc = anim.arc or 18,
            fin = a_l_arrivee,
        }
    end

    Client.Subscribe("Tick", function(delta)
        for i = #vols, 1, -1 do
            local v = vols[i]
            v.t = v.t + delta
            if v.t >= v.duree or not v.c:IsValid() then
                if v.c:IsValid() then v.c:Destroy() end
                table.remove(vols, i)
                if v.fin then pcall(v.fin) end
            elseif v.t > 0 then
                local k = lisse(v.t / v.duree)
                local haut = math.sin(math.pi * k) * v.arc
                v.c:SetLocation(Vector(
                    v.de.X + (v.vers.X - v.de.X) * k,
                    v.de.Y + (v.vers.Y - v.de.Y) * k,
                    v.de.Z + (v.vers.Z - v.de.Z) * k + haut))
                v.c:SetRotation(Rotator(
                    v.de_rot.Pitch + angle(v.vers_rot.Pitch - v.de_rot.Pitch) * k,
                    v.de_rot.Yaw + angle(v.vers_rot.Yaw - v.de_rot.Yaw) * k,
                    v.de_rot.Roll + angle(v.vers_rot.Roll - v.de_rot.Roll) * k))
            end
        end
    end)

    ---------------------------------------------------------------- etat du rendu

    local ma_main = { objets = {}, cartes = {}, levees = {}, cle = nil }
    local autres  = {}    -- chaise -> { objets, cartes, cle, nombre }
    local tas     = { objets = {}, cle = nil }

    -- Cartes encore en l'air : le tas et la revelation les attendent avant de
    -- les dessiner a leur place.
    local vers_le_tas = 0
    local revelation_en_vol = false

    -- Donne en cours : les mains qui se remplissent font venir leurs cartes du
    -- centre de la table au lieu d'y apparaitre d'un coup.
    local donne_jusqu_a = 0

    local couleurs      = {}
    local derniere_main = ""

    -- Mode demo (/fan demo) : une main et un tas factices hors partie, pour
    -- regler l'eventail sans jouer.
    local demo = false
    local DEMO_MAIN = { "king", "queen", "ace", "joker", "king" }

    local function main_affichee()
        if #journal.hand > 0 then return journal.hand, false end
        if demo then return DEMO_MAIN, true end
        return {}, false
    end

    -- Nouvelle donne : nouvelles couleurs. Une main qui ne fait que retrecir
    -- garde les siennes, par position.
    local function suivre_couleurs(main)
        local sig = table.concat(main, ",")
        if sig ~= derniere_main and #main >= #couleurs then
            couleurs = Cartes.Couleurs(#main, function(n) return math.random(n) end)
        end
        derniere_main = sig
    end

    -- Les cartes d'une main qui vient d'etre donnee partent du centre de la
    -- table, face cachee, et prennent leur place dans l'eventail.
    local function faire_venir(cartes)
        if Client.GetTime() > donne_jusqu_a then return end
        local centre = centre_table()
        local de, de_rot = lieu_table(config.table.decalage, config.table.dos, 0, centre)
        for i, c in ipairs(cartes) do
            if c:IsValid() then
                local vers, vers_rot = c:GetLocation(), c:GetRotation()
                c:SetVisibility(false)
                voler(config.back_mesh, de, de_rot, vers, vers_rot, (i - 1) * (anim.ecart_donne or 0.09), function()
                    if c:IsValid() then c:SetVisibility(true) end
                end)
            end
        end
    end

    local function maj_ma_main()
        local main, factice = main_affichee()
        local perso = mon_personnage()
        if #main == 0 or not perso then
            if ma_main.cle then detruire(ma_main.objets); ma_main.objets, ma_main.cartes, ma_main.cle = {}, {}, nil end
            return
        end
        suivre_couleurs(main)

        local levees, modeles = {}, {}
        for i, rang in ipairs(main) do
            modeles[i] = Cartes.Mesh(rang, couleurs[i])
            if not factice and journal:IsSelected(i) then
                levees[i] = config.fan.levee
            elseif i == journal.cursor then
                levees[i] = config.fan.curseur
            else
                levees[i] = 0
            end
        end

        local cle = ("%d|%s|%s|%s"):format(perso:GetID(), table.concat(modeles, ","),
            table.concat(levees, ","), tostring(Rendu.reglage))
        if cle == ma_main.cle then return end
        local nouvelle = #ma_main.cartes == 0
        detruire(ma_main.objets)
        ma_main.objets, ma_main.cartes = eventail(perso, os_de(perso), modeles, levees)
        ma_main.levees, ma_main.modeles = levees, modeles
        ma_main.cle = cle
        if nouvelle then faire_venir(ma_main.cartes) end
    end

    -- Les mains a dessiner chez les autres : chaise -> nombre de cartes. En
    -- demo (hors partie), chaque chaise occupee recoit une main complete.
    local function mains_des_autres()
        if not demo or next(journal.counts) then return journal.counts end
        local mains = {}
        for _, classe in ipairs({ CharacterSimple, Character }) do
            for _, c in pairs(classe.GetPairs()) do
                local chaise = c:IsValid() and c:GetValue("liars_chair", 0) or 0
                if chaise > 0 then mains[chaise] = #DEMO_MAIN end
            end
        end
        return mains
    end

    local function maj_autres()
        local vues = {}
        for chaise, nombre in pairs(mains_des_autres()) do
            if chaise ~= journal.my_chair and nombre > 0 then
                local perso = personnage_de_chaise(chaise)
                if perso then
                    vues[chaise] = true
                    local cle = ("%d|%d|%s|%s"):format(perso:GetID(), nombre, tostring(Rendu.reglage), tostring(demo))
                    local groupe = autres[chaise] or { objets = {}, cartes = {}, cle = nil, nombre = 0 }
                    if groupe.cle ~= cle then
                        local nouvelle = (groupe.nombre or 0) == 0
                        detruire(groupe.objets)
                        local modeles = {}
                        for i = 1, nombre do
                            -- En demo, des faces : on voit dans quel sens la carte tient.
                            modeles[i] = demo and not next(journal.counts)
                                and Cartes.Mesh(DEMO_MAIN[i] or "king", (i % 4) + 1) or config.back_mesh
                        end
                        groupe.objets, groupe.cartes = eventail(perso, os_de(perso), modeles, {})
                        groupe.cle, groupe.nombre = cle, nombre
                        if nouvelle then faire_venir(groupe.cartes) end
                    end
                    autres[chaise] = groupe
                end
            end
        end
        for chaise, groupe in pairs(autres) do
            if not vues[chaise] then
                detruire(groupe.objets)
                autres[chaise] = nil
            end
        end
    end

    local function maj_tas()
        local total = 0
        for _, pose in ipairs(journal.pile) do total = total + pose.count end
        total = math.max(0, total - vers_le_tas)
        local revelees = journal.revealed and journal.revealed.cards or {}
        if revelation_en_vol then revelees = {} end
        if demo and total == 0 and #revelees == 0 then
            total, revelees = 4, { "king", "joker" }
        end

        local centre = centre_table()
        local cle = ("%d|%s|%s|%.1f,%.1f,%.1f"):format(total, table.concat(revelees, ","),
            tostring(Rendu.reglage), centre.x, centre.y, centre.z)
        if cle == tas.cle then return end
        detruire(tas.objets)
        tas.objets = {}

        -- La derniere pose est la seule qu'on revele : ses cartes quittent le
        -- tas face cachee et s'alignent face visible.
        local caches = math.max(0, total - #revelees)
        local tbl = config.table
        for k = 1, caches do
            local p = Cartes.Tas(k, tbl)
            tas.objets[#tas.objets + 1] = carte_posee(config.back_mesh, p, tbl.dos, p.yaw, centre)
        end
        for i, rang in ipairs(revelees) do
            local p = Cartes.Revelee(#revelees, i, tbl)
            tas.objets[#tas.objets + 1] = carte_posee(Cartes.Mesh(rang, (i % 4) + 1), p, tbl.face, p.yaw, centre)
        end
        tas.cle = cle
    end

    ---------------------------------------------------------------- mouvements du jeu

    -- Quelqu'un pose : ses cartes quittent sa main et volent au tas, face
    -- cachee. Chez moi ce sont celles que j'avais levees ; chez les autres, des
    -- dos pris au bout de leur eventail. Appele avant que la main soit
    -- redessinee sans elles.
    local function poser(chaise, nombre)
        if config.en_main == false or not nombre or nombre <= 0 then return end
        local depart = {}
        if chaise == journal.my_chair then
            for i, c in ipairs(ma_main.cartes) do
                if (ma_main.levees[i] or 0) >= config.fan.levee and c:IsValid() then
                    depart[#depart + 1] = { c = c, modele = ma_main.modeles[i] }
                end
            end
            if #depart ~= nombre then
                depart = {}
                for i = #ma_main.cartes, math.max(1, #ma_main.cartes - nombre + 1), -1 do
                    depart[#depart + 1] = { c = ma_main.cartes[i], modele = ma_main.modeles[i] }
                end
            end
        else
            local groupe = autres[chaise]
            local cartes = groupe and groupe.cartes or {}
            for i = #cartes, math.max(1, #cartes - nombre + 1), -1 do
                depart[#depart + 1] = { c = cartes[i], modele = config.back_mesh }
            end
        end

        -- Le tas compte deja cette pose (le journal l'a ajoutee) : ses cartes
        -- vont aux dernieres places.
        local total = 0
        for _, pose in ipairs(journal.pile) do total = total + pose.count end
        local premiere = total - nombre + 1
        local centre = centre_table()
        local tbl = config.table
        local perso = personnage_de_chaise(chaise)
        for n = 1, nombre do
            local p = Cartes.Tas(premiere + n - 1, tbl)
            local vers, vers_rot = lieu_table(p, tbl.dos, p.yaw, centre)
            local src = depart[n]
            local de, de_rot, modele
            if src and src.c and src.c:IsValid() then
                de, de_rot, modele = src.c:GetLocation(), src.c:GetRotation(), src.modele
                src.c:SetVisibility(false)
            elseif perso then
                de, de_rot, modele = perso:GetLocation() + Vector(0, 0, 40), perso:GetRotation(), config.back_mesh
            end
            if de then
                vers_le_tas = vers_le_tas + 1
                voler(modele, de, de_rot, vers, vers_rot, (n - 1) * (anim.ecart_pose or 0.07), function()
                    vers_le_tas = math.max(0, vers_le_tas - 1)
                    Rendu.Refresh()
                end)
            end
        end
    end

    -- Revelation : les cartes de la derniere pose se soulevent du tas et se
    -- retournent, face visible, a cote. Leurs valeurs sont publiques.
    local function reveler(cartes)
        if not cartes or #cartes == 0 then return end
        local total = 0
        for _, pose in ipairs(journal.pile) do total = total + pose.count end
        local centre = centre_table()
        local tbl = config.table
        revelation_en_vol = true
        local restantes = #cartes
        for i, rang in ipairs(cartes) do
            local src = Cartes.Tas(math.max(1, total - #cartes + i), tbl)
            local de, de_rot = lieu_table(src, tbl.dos, src.yaw, centre)
            local dst = Cartes.Revelee(#cartes, i, tbl)
            local vers, vers_rot = lieu_table(dst, tbl.face, dst.yaw, centre)
            voler(Cartes.Mesh(rang, (i % 4) + 1), de, de_rot, vers, vers_rot, (i - 1) * (anim.ecart_revelation or 0.12),
                function()
                    restantes = restantes - 1
                    if restantes <= 0 then
                        revelation_en_vol = false
                        Rendu.Refresh()
                    end
                end)
        end
        Rendu.Refresh()
    end

    Events.SubscribeRemote("liars:cards_played", function(chaise, nombre)
        local ok, err = pcall(poser, chaise, nombre)
        if not ok then Console.Error("[rendu cartes] pose : " .. tostring(err)) end
    end)
    Events.SubscribeRemote("liars:reveal", function(_, cartes)
        local ok, err = pcall(reveler, cartes)
        if not ok then Console.Error("[rendu cartes] revelation : " .. tostring(err)) end
    end)
    Events.SubscribeRemote("liars:deal", function()
        donne_jusqu_a = Client.GetTime() + (anim.fenetre_donne or 1.5)
    end)

    ---------------------------------------------------------------- boucle

    -- Une erreur de rendu ne doit ni casser le reste du client, ni inonder la
    -- console : on la journalise une fois par message distinct.
    local erreurs_vues = {}
    local function sans_echec(nom, fn)
        local ok, err = pcall(fn)
        if not ok then
            local texte = nom .. " : " .. tostring(err)
            if not erreurs_vues[texte] then
                erreurs_vues[texte] = true
                Console.Error("[rendu cartes] " .. texte)
            end
        end
    end

    -- Compteur de reglage : /fan l'incremente pour forcer la reconstruction.
    Rendu.reglage = 0

    -- Les cartes en main se coupent par la config (en_main) : la main passe
    -- alors au HUD, et ce qui etait deja pose disparait.
    local function couper_mains()
        if ma_main.cle then detruire(ma_main.objets); ma_main.objets, ma_main.cartes, ma_main.cle = {}, {}, nil end
        for chaise, groupe in pairs(autres) do
            detruire(groupe.objets)
            autres[chaise] = nil
        end
    end

    function Rendu.Refresh()
        if config.en_main == false then
            sans_echec("mains", couper_mains)
        else
            sans_echec("main", maj_ma_main)
            sans_echec("autres", maj_autres)
        end
        sans_echec("tas", maj_tas)
    end

    function Rendu.Reconstruire()
        Rendu.reglage = Rendu.reglage + 1
        Rendu.Refresh()
    end

    function Rendu.Demo(actif)
        demo = actif
        -- La pose « cartes en main » localement, pour regler dans la bonne
        -- posture. Le serveur ne la donne qu'en partie.
        local perso = mon_personnage()
        if perso and perso:IsA(CharacterSimple) then
            pcall(function() perso:SetAnimationBlueprintPropertyValue("Cartes", actif) end)
        end
        Rendu.Reconstruire()
    end

    function Rendu.IsDemo() return demo end

    -- Dix fois par seconde : les personnages des autres peuvent apparaitre
    -- apres les messages de la table, un simple suivi de version ne suffit pas.
    -- Chaque groupe ne se reconstruit que si sa cle change.
    Timer.SetInterval(Rendu.Refresh, 100)

    return Rendu
end
