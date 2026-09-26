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

    -- Du pivot du modele au centre visible de la carte, tourne par r ; e :
    -- echelle de la carte (1 en main, table.echelle sur la table).
    local plates = config.plates and config.plates.actif and config.plates or nil

    local function vers_centre(modele, r, e)
        -- Les cartes plates ont leur centre a l'origine.
        if plates then return Vector(0, 0, 0) end
        local o = Cartes.Centre(modele)
        e = e or 1
        return r:RotateVector(Vector(o.x * e, o.y * e, o.z * e))
    end

    -- Les cartes posees sur la table sont plus grandes qu'en main : lisibles
    -- de l'autre bout de la table.
    local function echelle_table()
        return config.table.echelle or 1
    end

    -- Cartes plates : les plaques de chaque carte (face et dos), pour les
    -- montrer, les cacher et les detruire avec elle.
    local plaques = setmetatable({}, { __mode = "k" })

    local function detruire_carte(o)
        for _, pl in ipairs(plaques[o] or {}) do
            if pl:IsValid() then pl:Destroy() end
        end
        plaques[o] = nil
        if o and o:IsValid() then o:Destroy() end
    end

    local function detruire(objets)
        for _, o in ipairs(objets or {}) do detruire_carte(o) end
    end

    -- La visibilite d'un acteur ne passe pas a ce qui lui est accroche (les
    -- supports invisibles portent des cartes visibles) : une carte plate
    -- montre ou cache ses deux plaques.
    local function montrer(c, oui)
        if not (c and c:IsValid()) then return end
        if plaques[c] then
            for _, pl in ipairs(plaques[c]) do
                if pl:IsValid() then pl:SetVisibility(oui) end
            end
        else
            c:SetVisibility(oui)
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

    -- Le dessin (Client/liars_bar/cartes/<nom>.png) d'un modele du jeu de 52 :
    -- les anciens noms de modeles restent la cle, pour que la main, le tas et
    -- la revelation ne changent pas. DOS : une carte vue de dos des deux cotes.
    local DOS = plates and "dos" or config.back_mesh
    local DESSINS = { Ace = "as", King = "roi", Queen = "dame" }
    local function dessin(modele)
        if modele == "dos" then return "dos" end
        if modele == config.joker_mesh then return "joker" end
        local valeur = tostring(modele):match("::(%a+)_of_")
        return DESSINS[valeur] or "dos"
    end

    local function plaque(parent, image, r, l)
        local pl = StaticMesh(Vector(), Rotator(), "nanos-world::SM_Plane", CollisionType.NoCollision)
        sans_collision(pl)
        pl:AttachTo(parent, AttachmentRule.SnapToTarget, "", 0)
        pl:SetRelativeRotation(r)
        if l then pl:SetRelativeLocation(l) end
        local ok, err = pcall(function()
            pl:SetMaterial(plates.materiau)
            pl:SetMaterialTextureParameter("Texture", plates.images .. image .. ".png")
        end)
        if not ok then Console.Error("[cartes plates] " .. tostring(err)) end
        return pl
    end

    -- Une carte. Plate : un support invisible qui garde la convention des
    -- anciens modeles (face traversee par Y, largeur X, hauteur Z, centre a
    -- l'origine), et deux SM_Plane dos a dos (plan de 100 x 100, normale Z) :
    -- l'eventail, le tas et les vols gardent leurs reglages.
    local function nouvelle_carte(modele, position, rotation)
        if not plates then
            local c = StaticMesh(position, rotation, modele, CollisionType.NoCollision)
            sans_collision(c)
            return c
        end
        local c = StaticMesh(position, rotation, config.pivot_mesh, CollisionType.NoCollision)
        sans_collision(c)
        c:SetVisibility(false)
        local recto, verso = dessin(modele), "dos"
        if plates.retourner then recto, verso = verso, recto end
        local face = plaque(c, recto, rot(plates.rot))
        face:SetScale(Vector(plates.largeur / 100, plates.hauteur / 100, 1))
        local dos = plaque(face, verso, rot(plates.rot_dos), Vector(0, 0, -0.03))
        plaques[c] = { face, dos }
        return c
    end

    -- Taille d'une carte : e = 1 en main, table.echelle sur la table.
    local function mettre_a_l_echelle(c, e)
        local t = (plates and 1 or config.fan.taille) * (e or 1)
        c:SetScale(Vector(t, t, t))
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
        local c = nouvelle_carte(modele, Vector(), Rotator())
        c:AttachTo(parent, AttachmentRule.SnapToTarget, "", 0)
        local r = rot(config.fan.carte)
        c:SetRelativeRotation(r)
        mettre_a_l_echelle(c, 1)
        -- Le pivot du modele est loin de la carte : on la recule d'autant,
        -- pour que ce soit son centre qui soit sur la fente.
        c:SetRelativeLocation(vers_centre(modele, r) * -1)
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
            fente:SetRelativeRotation(Rotator(f.p, f.yaw, f.r))
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

    -- Lieu (centre visible) et rotation monde d'une carte posee a plat sur la
    -- table.
    local function lieu_table(lieu, orientation, lacet, centre)
        return Vector(centre.x + lieu.x, centre.y + lieu.y, centre.z + lieu.z),
            Rotator(orientation.p, orientation.y + (lacet or 0), orientation.r)
    end

    local function carte_libre(modele, position, rotation, e)
        local c = nouvelle_carte(modele, position, rotation)
        mettre_a_l_echelle(c, e)
        return c
    end

    -- Le modele est place par son pivot, loin de la carte : on le pose de
    -- sorte que ce soit son centre visible qui soit au lieu voulu.
    local function carte_posee(modele, lieu, orientation, lacet, centre)
        local p, r = lieu_table(lieu, orientation, lacet, centre)
        local e = echelle_table()
        return carte_libre(modele, p - vers_centre(modele, r, e), r, e)
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

    -- de et vers sont des centres visibles : le vol deplace le centre de la
    -- carte, sinon elle tournerait autour d'un point a 32 cm d'elle.
    -- e_de, e_vers : echelle au depart et a l'arrivee (main ou table) ;
    -- duree, arc : ceux du vol, sinon ceux de config.anim.
    local function voler(modele, de, de_rot, vers, vers_rot, retard, a_l_arrivee, e_de, e_vers, duree, arc)
        e_de, e_vers = e_de or 1, e_vers or 1
        local ok, c = pcall(carte_libre, modele, de - vers_centre(modele, de_rot, e_de), de_rot, e_de)
        if not ok then return end
        vols[#vols + 1] = {
            c = c, modele = modele, de_rot = de_rot, vers_rot = vers_rot,
            de = de, vers = vers, e_de = e_de, e_vers = e_vers,
            t = -(retard or 0), duree = duree or anim.duree or 0.45, arc = arc or anim.arc or 18,
            fin = a_l_arrivee,
        }
    end

    Client.Subscribe("Tick", function(delta)
        for i = #vols, 1, -1 do
            local v = vols[i]
            v.t = v.t + delta
            if v.t >= v.duree or not v.c:IsValid() then
                detruire_carte(v.c)
                table.remove(vols, i)
                if v.fin then pcall(v.fin) end
            elseif v.t > 0 then
                local k = lisse(v.t / v.duree)
                local haut = math.sin(math.pi * k) * v.arc
                local r = Rotator(
                    v.de_rot.Pitch + angle(v.vers_rot.Pitch - v.de_rot.Pitch) * k,
                    v.de_rot.Yaw + angle(v.vers_rot.Yaw - v.de_rot.Yaw) * k,
                    v.de_rot.Roll + angle(v.vers_rot.Roll - v.de_rot.Roll) * k)
                local centre = Vector(
                    v.de.X + (v.vers.X - v.de.X) * k,
                    v.de.Y + (v.vers.Y - v.de.Y) * k,
                    v.de.Z + (v.vers.Z - v.de.Z) * k + haut)
                local e = v.e_de + (v.e_vers - v.e_de) * k
                mettre_a_l_echelle(v.c, e)
                v.c:SetRotation(r)
                v.c:SetLocation(centre - vers_centre(v.modele, r, e))
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

    -- Centre visible d'une carte deja posee (dans une main, sur la table).
    local function visuel(c, modele)
        local r = c:GetRotation()
        return c:GetLocation() + vers_centre(modele, r), r
    end

    -- Les cartes d'une main qui vient d'etre donnee partent du centre de la
    -- table, face cachee, et prennent leur place dans l'eventail.
    local function faire_venir(cartes, modeles)
        if Client.GetTime() > donne_jusqu_a then return end
        local centre = centre_table()
        local de, de_rot = lieu_table(config.table.decalage, config.table.dos, 0, centre)
        for i, c in ipairs(cartes) do
            if c:IsValid() then
                local vers, vers_rot = visuel(c, modeles[i] or DOS)
                montrer(c, false)
                voler(DOS, de, de_rot, vers, vers_rot, (i - 1) * (anim.ecart_donne or 0.09), function()
                    montrer(c, true)
                end, echelle_table(), 1)
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
        if nouvelle then faire_venir(ma_main.cartes, modeles) end
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
                                and Cartes.Mesh(DEMO_MAIN[i] or "king", (i % 4) + 1) or DOS
                        end
                        groupe.objets, groupe.cartes = eventail(perso, os_de(perso), modeles, {})
                        groupe.cle, groupe.nombre = cle, nombre
                        if nouvelle then faire_venir(groupe.cartes, modeles) end
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
        -- La superposition (nametags.lua) pose son carton au-dessus du tas.
        local dec = config.table.decalage
        journal.lieu_tas = Vector(centre.x + dec.x, centre.y + dec.y, centre.z + dec.z)
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
            tas.objets[#tas.objets + 1] = carte_posee(DOS, p, tbl.dos, p.yaw, centre)
        end
        for i, rang in ipairs(revelees) do
            local p = Cartes.Revelee(#revelees, i, tbl)
            tas.objets[#tas.objets + 1] = carte_posee(Cartes.Mesh(rang, (i % 4) + 1), p, tbl.face, p.yaw, centre)
        end
        tas.cle = cle
    end

    ---------------------------------------------------------------- mouvements du jeu

    -- La carte i (sur n) de l'eventail, refaite seule avec sa propre chaine :
    -- os de la main, pivot, fente, exactement comme eventail(). Elle suit le
    -- geste de pose (ANIM_Seated_Card_Play, joue par le serveur au meme
    -- moment) meme quand l'eventail est redessine sans elle. Une copie
    -- accrochee en KeepWorld, lue sur la carte d'origine, partait en l'air et
    -- tournee : ici rien n'est lu dans le monde, tout est relatif. Rend la
    -- carte et le pivot a detruire.
    local function carte_tenue(perso, modele, n, i, levee)
        if not (perso and perso:IsValid()) then return nil end
        local pivot = support(perso, os_de(perso))
        pivot:SetRelativeLocation(vec(config.fan.pos))
        pivot:SetRelativeRotation(rot(config.fan.rot))
        local f = Cartes.Fente(n, i, config.fan, levee or 0)
        local fente = support(pivot)
        fente:SetRelativeLocation(Vector(f.x, f.y, f.z))
        fente:SetRelativeRotation(Rotator(f.p, f.yaw, f.r))
        return carte_accrochee(modele, fente), pivot, fente
    end

    -- Quelqu'un pose : comme dans l'animation, ses cartes restent dans sa main
    -- pendant qu'elle avance vers le centre, puis, quand elle touche la table
    -- (anim.lacher secondes), elles la quittent et tombent a plat sur le tas,
    -- face cachee. Chez moi ce sont celles que j'avais levees ; chez les
    -- autres, des dos pris au bout de leur eventail. Appele avant que la main
    -- soit redessinee sans elles.
    local function poser(chaise, nombre)
        if config.en_main == false or not nombre or nombre <= 0 then return end
        local depart = {}
        if chaise == journal.my_chair then
            for i, c in ipairs(ma_main.cartes) do
                if (ma_main.levees[i] or 0) >= config.fan.levee and c:IsValid() then
                    depart[#depart + 1] = { c = c, modele = ma_main.modeles[i],
                        i = i, n = #ma_main.cartes, levee = ma_main.levees[i] }
                end
            end
            if #depart ~= nombre then
                depart = {}
                for i = #ma_main.cartes, math.max(1, #ma_main.cartes - nombre + 1), -1 do
                    depart[#depart + 1] = { c = ma_main.cartes[i], modele = ma_main.modeles[i],
                        i = i, n = #ma_main.cartes, levee = ma_main.levees[i] }
                end
            end
        else
            local groupe = autres[chaise]
            local cartes = groupe and groupe.cartes or {}
            for i = #cartes, math.max(1, #cartes - nombre + 1), -1 do
                depart[#depart + 1] = { c = cartes[i], modele = DOS, i = i, n = #cartes, levee = 0 }
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
            or (chaise == journal.my_chair and mon_personnage() or nil)
        local lacher = math.floor((anim.lacher or 0.5) * 1000)
        for n = 1, nombre do
            local p = Cartes.Tas(premiere + n - 1, tbl)
            local vers, vers_rot = lieu_table(p, tbl.dos, p.yaw, centre)
            local src = depart[n]
            local modele = src and src.modele or DOS
            local tenue, chaine = nil, {}
            if src and src.c and src.c:IsValid() then
                local ok, t, pivot, fente = pcall(carte_tenue, perso, modele, src.n, src.i, src.levee)
                if ok then tenue, chaine = t, { fente, pivot } end
                montrer(src.c, false)
            end
            vers_le_tas = vers_le_tas + 1
            local function arrivee()
                vers_le_tas = math.max(0, vers_le_tas - 1)
                Rendu.Refresh()
            end
            -- Lacher : de la ou la main a porte la carte jusqu'au tas, court et
            -- presque sans arc, comme une carte qu'on laisse tomber.
            Timer.SetTimeout(function()
                local de, de_rot
                if tenue and tenue:IsValid() then
                    de, de_rot = visuel(tenue, modele)
                    detruire_carte(tenue)
                    detruire(chaine)
                elseif perso and perso:IsValid() then
                    de, de_rot = perso:GetLocation() + Vector(0, 0, 40), perso:GetRotation()
                end
                if not de then return arrivee() end
                voler(modele, de, de_rot, vers, vers_rot, (n - 1) * (anim.ecart_lacher or 0.04), arrivee,
                    1, echelle_table(), anim.duree_lacher or 0.22, anim.arc_lacher or 3)
            end, lacher)
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
                end, echelle_table(), echelle_table())
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
