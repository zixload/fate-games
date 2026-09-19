-- Rendu 3D des cartes de Liar's Bar : ma main en eventail, des dos dans la
-- main des autres, le tas du centre et la derniere revelation.
--
-- Tout ce qui est cree ici n'existe que chez ce client : il en a l'autorite
-- (doc Authority Concepts), il peut donc l'accrocher et le deplacer. Rien de
-- secret n'y entre : les faces viennent de ma main et de la revelation
-- publique, tout le reste est un dos.
--
-- Le rendu suit le journal. Chaque groupe (ma main, chaque autre main, la
-- table) a une cle ; quand sa cle change, le groupe est reconstruit. Aucune
-- regle du jeu ici, du placement seulement.
--
-- A REGLER EN JEU : axes et echelle du FBX des cartes inconnus. Voir /fan.

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
    -- carte i ; levees[i] : sa levee en cm.
    local function eventail(personnage, os_nom, modeles, levees)
        local objets = {}
        local pivot = support(personnage, os_nom)
        pivot:SetRelativeLocation(vec(config.fan.pos))
        pivot:SetRelativeRotation(rot(config.fan.rot))
        objets[#objets + 1] = pivot

        local n = #modeles
        for i, modele in ipairs(modeles) do
            local f = Cartes.Fente(n, i, config.fan, levees[i] or 0)
            local fente = support(pivot)
            fente:SetRelativeLocation(Vector(f.x, f.y, f.z))
            fente:SetRelativeRotation(Rotator(f.pitch, 0, 0))
            objets[#objets + 1] = fente
            objets[#objets + 1] = carte_accrochee(modele, fente)
        end
        return objets
    end

    -- Une carte posee a plat sur la table, en coordonnees monde.
    local function carte_posee(modele, lieu, orientation, lacet)
        local centre = disposition.revolver_home
        local c = StaticMesh(
            Vector(centre.x + lieu.x, centre.y + lieu.y, centre.z + lieu.z),
            Rotator(orientation.p, orientation.y + (lacet or 0), orientation.r),
            modele,
            CollisionType.NoCollision
        )
        sans_collision(c)
        local t = config.fan.taille
        c:SetScale(Vector(t, t, t))
        return c
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

    ---------------------------------------------------------------- etat du rendu

    local ma_main = { objets = {}, cle = nil }
    local autres  = {}    -- chaise -> { objets, cle }
    local tas     = { objets = {}, cle = nil }

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

    local function maj_ma_main()
        local main, factice = main_affichee()
        local perso = mon_personnage()
        if #main == 0 or not perso then
            if ma_main.cle then detruire(ma_main.objets); ma_main.objets, ma_main.cle = {}, nil end
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
        detruire(ma_main.objets)
        ma_main.objets = eventail(perso, os_de(perso), modeles, levees)
        ma_main.cle = cle
    end

    local function maj_autres()
        local vues = {}
        for chaise, nombre in pairs(journal.counts) do
            if chaise ~= journal.my_chair and nombre > 0 then
                local perso = personnage_de_chaise(chaise)
                if perso then
                    vues[chaise] = true
                    local cle = ("%d|%d|%s"):format(perso:GetID(), nombre, tostring(Rendu.reglage))
                    local groupe = autres[chaise] or { objets = {}, cle = nil }
                    if groupe.cle ~= cle then
                        detruire(groupe.objets)
                        local dos = {}
                        for i = 1, nombre do dos[i] = config.back_mesh end
                        groupe.objets = eventail(perso, os_de(perso), dos, {})
                        groupe.cle = cle
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
        local revelees = journal.revealed and journal.revealed.cards or {}
        if demo and total == 0 and #revelees == 0 then
            total, revelees = 4, { "king", "joker" }
        end

        local cle = ("%d|%s|%s"):format(total, table.concat(revelees, ","), tostring(Rendu.reglage))
        if cle == tas.cle then return end
        detruire(tas.objets)
        tas.objets = {}

        -- La derniere pose est la seule qu'on revele : ses cartes quittent le
        -- tas face cachee et s'alignent face visible.
        local caches = math.max(0, total - #revelees)
        local tbl = config.table
        for k = 1, caches do
            local p = Cartes.Tas(k, tbl)
            tas.objets[#tas.objets + 1] = carte_posee(config.back_mesh, p, tbl.dos, p.yaw)
        end
        for i, rang in ipairs(revelees) do
            local p = Cartes.Revelee(#revelees, i, tbl)
            tas.objets[#tas.objets + 1] = carte_posee(Cartes.Mesh(rang, (i % 4) + 1), p, tbl.face, p.yaw)
        end
        tas.cle = cle
    end

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

    function Rendu.Refresh()
        sans_echec("main", maj_ma_main)
        sans_echec("autres", maj_autres)
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
