return function(H)
    local Combat = Package.Require("combat/init.lua")
    local G, A = Combat.geometrie, Combat.armes

    local PAS = 0.05
    local function avance(w, secondes)
        local fx = {}
        for _ = 1, math.floor(secondes / PAS + 0.5) do
            for _, e in ipairs(Combat.avancer(w, PAS)) do fx[#fx + 1] = e end
        end
        return fx
    end
    local function trouve(fx, kind, champ, valeur)
        for _, e in ipairs(fx or {}) do
            if e.kind == kind and (champ == nil or e[champ] == valeur) then return e end
        end
    end
    -- Deux combattants face a face, a `d` cm l'un de l'autre sur l'axe X.
    local function duel(arme_a, arme_d, d, config)
        local w = Combat.nouveau(config)
        Combat.ajouter(w, "a", { arme = arme_a or "epee_courte", pos = G.v(0, 0, 90), yaw = 0 })
        Combat.ajouter(w, "d", { arme = arme_d or "epee_courte", pos = G.v(d or 140, 0, 90), yaw = 180 })
        return w, w.combattants.a, w.combattants.d
    end
    local function frappe_complete(w, id, force, dir)
        Combat.attaquer(w, id, force, dir)
        local att = A[w.combattants[id].arme][force or "legere"]
        return avance(w, att.armement + att.frappe + 0.05)
    end

    H.describe("combat/geometrie", function()
        H.it("un arc devant, pas derriere ni trop loin", function()
            H.assert_true(G.dans_arc(G.v(0, 0, 0), 0, G.v(100, 20, 0), 150, 45, 0), "devant")
            H.assert_false(G.dans_arc(G.v(0, 0, 0), 0, G.v(-100, 0, 0), 150, 45, 0), "derriere")
            H.assert_false(G.dans_arc(G.v(0, 0, 0), 0, G.v(300, 0, 0), 150, 45, 0), "trop loin")
            H.assert_true(G.dans_arc(G.v(0, 0, 0), 0, G.v(170, 0, 0), 150, 45, 30), "le bord de la capsule compte")
        end)

        H.it("un rayon trouve la bonne zone d'une capsule", function()
            local R = Combat.regles.silhouette
            local c = G.v(500, 0, 90)
            local function zone(z, y)
                local p, q = G.v(0, y or 0, z), G.v(1000, y or 0, z)
                local k, point, ecart = G.segment_capsule(p, q, c, R.demi_hauteur, R.rayon)
                if not k then return nil end
                return G.zone(point, c, R.demi_hauteur, R.rayon, R, ecart)
            end
            H.assert_eq(zone(170), "tete", "tete")
            H.assert_eq(zone(110), "torse", "torse")
            H.assert_eq(zone(40), "jambes", "jambes")
            H.assert_eq(zone(110, 28), "bras", "un tir qui frole touche un bras")
            H.assert_nil(zone(110, 60), "a cote")
            H.assert_nil(zone(200), "au-dessus")
        end)

        H.it("lacet et ecart", function()
            H.assert_eq(math.floor(G.lacet_vers(G.v(0, 0, 0), G.v(0, 10, 0)) + 0.5), 90, "lacet")
            H.assert_eq(math.floor(G.ecart(180, G.v(0, 0, 0), G.v(-10, 1, 0)) + 0.5), 6, "ecart")
        end)
    end)

    H.describe("combat/corps a corps", function()
        H.it("une attaque legere touche apres son armement", function()
            local w, _, d = duel()
            Combat.attaquer(w, "a", "legere", "droite")
            avance(w, 0.2)
            H.assert_eq(d.sante, 100, "rien pendant l'armement")
            local fx = avance(w, 0.25)
            local deg = trouve(fx, "degats", "cible", "d")
            H.assert_true(deg ~= nil, "touche")
            H.assert_eq(deg.montant, 16, "degats de l'epee courte au torse")
            H.assert_eq(deg.zone, "torse", "zone")
        end)

        H.it("hors de portee ou dans le dos : rien", function()
            local w, _, d = duel(nil, nil, 400)
            frappe_complete(w, "a")
            H.assert_eq(d.sante, 100, "trop loin")
            local w2, a2, d2 = duel()
            a2.yaw = 180
            frappe_complete(w2, "a")
            H.assert_eq(d2.sante, 100, "il tourne le dos")
        end)

        H.it("un coup ne touche qu'une fois", function()
            local w, _, d = duel()
            Combat.attaquer(w, "a", "legere", "droite")
            avance(w, 1.2)
            H.assert_eq(d.sante, 84, "une seule fois malgre plusieurs pas dans la frappe")
        end)

        H.it("la garde du bon cote bloque, une part traverse", function()
            local w, _, d = duel()
            Combat.garder(w, "d", "gauche")      -- l'attaque vient de la droite de l'attaquant
            avance(w, 0.5)
            local fx = frappe_complete(w, "a", "legere", "droite")
            local b = trouve(fx, "bloque", "id", "d")
            H.assert_true(b ~= nil, "bloque")
            H.assert_eq(d.sante, 97.6, "15 % traversent")
            H.assert_true(d.posture > 0 and d.endurance < 100, "la garde coute")
        end)

        H.it("la garde du mauvais cote ne sert a rien", function()
            local w, _, d = duel()
            Combat.garder(w, "d", "droite")
            avance(w, 0.5)
            frappe_complete(w, "a", "legere", "droite")
            H.assert_eq(d.sante, 84, "touche")
        end)

        H.it("la parade : garde posee juste avant l'impact", function()
            local w, a, d = duel()
            Combat.attaquer(w, "a", "legere", "droite")
            avance(w, 0.3)
            Combat.garder(w, "d", "gauche")
            local fx = avance(w, 0.3)
            H.assert_true(trouve(fx, "pare", "id", "d") ~= nil, "pare")
            H.assert_eq(d.sante, 100, "aucun degat")
            H.assert_nil(a.action, "l'attaque est annulee")
            H.assert_true(a.posture >= 38, "l'attaquant perd de la posture")
            local _, raison = Combat.attaquer(w, "a", "legere", "droite")
            H.assert_eq(raison, "expose", "et reste expose")
        end)

        H.it("une lourde ne se pare pas avec une arme legere", function()
            local w, _, d = duel("epee_longue", "dague")
            Combat.attaquer(w, "a", "lourde", "droite")
            avance(w, 0.85)
            Combat.garder(w, "d", "gauche")
            local fx = avance(w, 0.3)
            H.assert_nil(trouve(fx, "pare"), "pas de parade")
            H.assert_true(trouve(fx, "bloque", "id", "d") ~= nil, "mais bloquee")
        end)

        H.it("l'esquive rend invulnerable un instant", function()
            local w, _, d = duel()
            Combat.attaquer(w, "a", "legere", "droite")
            avance(w, 0.3)
            Combat.esquiver(w, "d", "arriere")
            local fx = avance(w, 0.3)
            H.assert_true(trouve(fx, "esquive_reussie", "id", "d") ~= nil, "esquive")
            H.assert_eq(d.sante, 100, "intact")
        end)

        H.it("la feinte annule l'armement, jusqu'a un certain point", function()
            local w, a = duel("epee_longue")
            Combat.attaquer(w, "a", "lourde", "haut")
            avance(w, 0.2)
            local fx = Combat.feinter(w, "a")
            H.assert_true(fx ~= nil and trouve(fx, "feinte") ~= nil, "feinte")
            H.assert_nil(a.action, "plus d'attaque")
            avance(w, 0.2)
            Combat.attaquer(w, "a", "lourde", "haut")
            avance(w, 0.8)
            local _, raison = Combat.feinter(w, "a")
            H.assert_eq(raison, "trop_tard", "trop tard pour feinter")
        end)

        H.it("encaisser en garde remplit la posture jusqu'a la briser", function()
            local w, a, d = duel("masse", "epee_courte")
            Combat.garder(w, "d", "gauche")
            avance(w, 0.3)
            local brisee = false
            for _ = 1, 6 do
                a.endurance = 100
                d.endurance = 100
                Combat.garder(w, "d", "gauche")
                avance(w, 0.25)
                local fx = frappe_complete(w, "a", "lourde", "droite")
                avance(w, 0.9)
                if trouve(fx, "garde_brisee", "id", "d") then brisee = true break end
            end
            H.assert_true(brisee, "garde brisee")
            local _, raison = Combat.garder(w, "d", "gauche")
            H.assert_eq(raison, "etourdi", "etourdi")
        end)

        H.it("vulnerable apres une garde brisee : degats x1,5", function()
            local w, _, d = duel()
            d.statuts.vulnerable = { fin = 10 }
            frappe_complete(w, "a", "legere", "droite")
            H.assert_eq(d.sante, 76, "16 x 1,5")
        end)

        H.it("epuise : plus d'attaque lourde", function()
            local w, a = duel("hache")
            a.endurance = 10
            local _, raison = Combat.attaquer(w, "a", "lourde", "droite")
            H.assert_eq(raison, "epuise", "refuse")
        end)

        H.it("l'armure depend du type de coup", function()
            local w, _, d = duel("epee_courte")
            Combat.armure(w, "d", "plaques")
            frappe_complete(w, "a", "legere", "droite")
            H.assert_eq(d.sante, 94.4, "tranchant contre plaques : 35 %")
            local w2, _, d2 = duel("masse")
            Combat.armure(w2, "d", "plaques")
            frappe_complete(w2, "a", "legere", "droite")
            H.assert_eq(d2.sante, 82, "contondant contre plaques : 90 %")
        end)

        H.it("la lance perce les mailles", function()
            local w, _, d = duel("lance", nil, 250)
            Combat.armure(w, "d", "mailles")
            frappe_complete(w, "a", "legere", "droite")
            H.assert_eq(d.sante, 86.1, "16 x (1 - 0,20 x 0,65) = 13,9")
            local w2, _, d2 = duel("lance", nil, 70)
            frappe_complete(w2, "a", "legere", "droite")
            H.assert_eq(d2.sante, 100, "a bout portant, la lance ne touche pas")
        end)

        H.it("un coup d'en haut vise la tete", function()
            local w, _, d = duel()
            local fx = frappe_complete(w, "a", "legere", "haut")
            local deg = trouve(fx, "degats", "cible", "d")
            H.assert_eq(deg.zone, "tete", "tete")
            H.assert_eq(deg.montant, 22.4, "16 x 1,4")
        end)

        H.it("une lourde tranchante fait saigner", function()
            local w, _, d = duel("epee_longue", nil, 180)
            frappe_complete(w, "a", "lourde", "droite")
            local apres_coup = d.sante
            avance(w, 3)
            H.assert_true(d.sante < apres_coup - 5, "le saignement continue")
        end)

        H.it("viser bas touche les jambes et ralentit", function()
            local w, a, d = duel()
            a.pitch = -40
            local fx = frappe_complete(w, "a", "legere", "droite")
            H.assert_eq(trouve(fx, "degats", "cible", "d").zone, "jambes", "jambes")
            H.assert_true(trouve(fx, "vitesse", "id", "d") ~= nil or Combat.vitesse(w, "d") < 1, "ralenti")
        end)

        H.it("etre touche coupe une attaque legere en armement", function()
            local w, _, d = duel("dague", "epee_longue", 120)
            Combat.attaquer(w, "d", "legere", "gauche")
            Combat.attaquer(w, "a", "legere", "droite")
            local fx = avance(w, 0.45)
            H.assert_true(trouve(fx, "interrompu", "id", "d") ~= nil, "interrompu")
            H.assert_nil(d.action, "plus d'attaque")
        end)

        H.it("pas de degats entre coequipiers", function()
            local w = Combat.nouveau()
            Combat.ajouter(w, "a", { arme = "epee_courte", pos = G.v(0, 0, 90), yaw = 0, camp = "bleu" })
            Combat.ajouter(w, "b", { arme = "epee_courte", pos = G.v(140, 0, 90), yaw = 180, camp = "bleu" })
            frappe_complete(w, "a")
            H.assert_eq(w.combattants.b.sante, 100, "epargne")
        end)

        H.it("une hache large touche deux ennemis", function()
            local w = Combat.nouveau()
            Combat.ajouter(w, "a", { arme = "hache", pos = G.v(0, 0, 90), yaw = 0 })
            Combat.ajouter(w, "b", { pos = G.v(130, 60, 90), yaw = 180 })
            Combat.ajouter(w, "c", { pos = G.v(130, -60, 90), yaw = 180 })
            frappe_complete(w, "a")
            H.assert_true(w.combattants.b.sante < 100 and w.combattants.c.sante < 100, "les deux")
        end)
    end)

    H.describe("combat/tir", function()
        local function tireur(arme, distance, config)
            local w = Combat.nouveau(config)
            Combat.ajouter(w, "a", { arme = arme or "pistolet", pos = G.v(0, 0, 90), yaw = 0 })
            Combat.ajouter(w, "d", { pos = G.v(distance or 1000, 0, 90), yaw = 180 })
            return w, w.combattants.a, w.combattants.d
        end
        local function vise(w, z, y)
            local o = G.v(0, 0, 152)
            local cible = w.combattants.d.pos
            return { origine = o, direction = G.moins(G.v(cible.x, y or 0, z or 110), o), cible = "d" }
        end

        H.it("une balle au torse", function()
            local w, _, d = tireur()
            local fx = Combat.tirer(w, "a", vise(w))
            H.assert_eq(trouve(fx, "degats", "cible", "d").montant, 24, "pistolet au torse")
            H.assert_eq(d.sante, 76, "sante")
        end)

        H.it("la cadence est verifiee par le serveur", function()
            local w = tireur()
            Combat.tirer(w, "a", vise(w))
            local _, raison = Combat.tirer(w, "a", vise(w))
            H.assert_eq(raison, "cadence", "trop tot")
            avance(w, 0.3)
            H.assert_true(Combat.tirer(w, "a", vise(w)) ~= nil, "ensuite oui")
        end)

        H.it("chargeur vide, puis rechargement", function()
            local w, a = tireur("revolver")
            for _ = 1, 6 do
                Combat.tirer(w, "a", vise(w))
                avance(w, 0.6)
            end
            local _, raison = Combat.tirer(w, "a", vise(w))
            H.assert_eq(raison, "vide", "vide")
            Combat.recharger(w, "a")
            local _, r2 = Combat.tirer(w, "a", vise(w))
            H.assert_eq(r2, "recharge", "pas pendant le rechargement")
            local fx = avance(w, 2.3)
            H.assert_true(trouve(fx, "recharge_fin", "id", "a") ~= nil, "recharge")
            H.assert_eq(a.munitions, 6, "plein")
        end)

        H.it("les degats baissent avec la distance", function()
            local w, _, d = tireur("pistolet", 3000)
            Combat.tirer(w, "a", vise(w))
            H.assert_eq(d.sante, 81.6, "76,5 % au bord du corps, a 29,7 m")
        end)

        H.it("dans la tete : double", function()
            local w, _, d = tireur()
            local fx = Combat.tirer(w, "a", vise(w, 172))
            H.assert_eq(trouve(fx, "degats", "cible", "d").zone, "tete", "tete")
            H.assert_eq(d.sante, 52, "48 degats")
        end)

        H.it("un tir qui ne passe pas par la cible est refuse", function()
            local w, _, d = tireur()
            local fx = Combat.tirer(w, "a", vise(w, 110, 200))
            H.assert_true(trouve(fx, "tir_refuse") ~= nil, "refuse")
            H.assert_eq(d.sante, 100, "intact")
        end)

        H.it("compensation de latence, plafonnee", function()
            local w, _, d = tireur()
            avance(w, 0.1)
            Combat.placer(w, "d", G.v(1000, 0, 90), 180, 0)
            avance(w, 0.2)
            Combat.placer(w, "d", G.v(1000, 300, 90), 180, 0)
            local tir = vise(w)
            tir.direction = G.moins(G.v(1000, 0, 110), tir.origine)
            local fx = Combat.tirer(w, "a", tir)
            H.assert_true(trouve(fx, "tir_refuse") ~= nil, "sans latence, il est deja parti")
            avance(w, 0.35)
            local w2 = tireur()
            avance(w2, 0.1)
            Combat.placer(w2, "d", G.v(1000, 0, 90), 180, 0)
            avance(w2, 0.1)
            Combat.placer(w2, "d", G.v(1000, 300, 90), 180, 0)
            local tir2 = vise(w2)
            tir2.direction = G.moins(G.v(1000, 0, 110), tir2.origine)
            tir2.ping = 0.12
            local fx2 = Combat.tirer(w2, "a", tir2)
            H.assert_true(trouve(fx2, "degats", "cible", "d") ~= nil, "avec son ping, touche la ou il le voyait")
        end)

        H.it("un tir qui ne part pas des yeux est refuse", function()
            local w = tireur()
            local tir = vise(w)
            tir.origine = G.v(800, 0, 150)
            local _, raison = Combat.tirer(w, "a", tir)
            H.assert_eq(raison, "origine", "refuse")
        end)

        H.it("fusil a pompe : tout pres tout touche, de loin non", function()
            local w, _, d = tireur("fusil_pompe", 300)
            Combat.tirer(w, "a", vise(w))
            H.assert_eq(d.sante, 12, "8 plombs de 11")
            local w2, _, d2 = tireur("fusil_pompe", 2400)
            Combat.tirer(w2, "a", vise(w2))
            H.assert_true(d2.sante > 90, "de loin, presque rien")
        end)

        H.it("une balle confirmee par l'arme native : zone, armure, distance", function()
            local w, _, d = tireur("revolver", 3500)
            Combat.armure(w, "d", "cuir")
            local fx = Combat.balle(w, "a", "d", "tete", 3500)
            local deg = trouve(fx, "degats", "cible", "d")
            H.assert_eq(deg.zone, "tete", "tete")
            H.assert_eq(deg.montant, 56.4, "38 x 0,825 x 2 x 0,9")
            local _, raison = Combat.balle(w, "d", "a", "torse", 100)
            H.assert_eq(raison, "pas_arme_a_feu", "la cible n'a pas d'arme a feu")
        end)

        H.it("une balle dans la jambe ralentit", function()
            local w = tireur()
            Combat.tirer(w, "a", vise(w, 40))
            avance(w, 0.05)
            H.assert_true(Combat.vitesse(w, "d") < 1, "ralenti")
        end)
    end)

    H.describe("combat/arc", function()
        local function archer(arme, distance)
            local w = Combat.nouveau()
            Combat.ajouter(w, "a", { arme = arme or "arc", pos = G.v(0, 0, 90), yaw = 0 })
            Combat.ajouter(w, "d", { pos = G.v(distance or 1500, 0, 90), yaw = 180 })
            return w, w.combattants.a, w.combattants.d
        end
        local O = G.v(0, 0, 152)

        H.it("une fleche bandee a fond vole et touche", function()
            local w, _, d = archer()
            Combat.bander(w, "a")
            avance(w, 1.2)
            local fx = Combat.decocher(w, "a", O, G.v(1, 0, -0.02))
            H.assert_true(trouve(fx, "projectile") ~= nil, "partie")
            local fx2 = avance(w, 0.5)
            H.assert_true(trouve(fx2, "projectile_impact", "cible", "d") ~= nil, "arrivee")
            H.assert_true(d.sante <= 100 - 46 * 0.8, "degats pleins")
        end)

        H.it("peu bandee, elle fait peu de mal", function()
            local w, _, d = archer(nil, 800)
            Combat.bander(w, "a")
            avance(w, 0.2)
            Combat.decocher(w, "a", O, G.v(1, 0, 0.01))
            avance(w, 1)
            H.assert_true(d.sante > 70, "faible")
        end)

        H.it("un bouclier leve arrete la fleche", function()
            local w, _, d = archer()
            Combat.equiper(w, "d", "epee_bouclier")
            Combat.garder(w, "d", "droite")
            Combat.bander(w, "a")
            avance(w, 1.2)
            Combat.decocher(w, "a", O, G.v(1, 0, -0.02))
            local fx = avance(w, 0.5)
            H.assert_true(trouve(fx, "bloque", "id", "d") ~= nil, "bloquee")
            H.assert_eq(d.sante, 100, "intact")
        end)

        H.it("une fleche dans le decor s'arrete", function()
            local w = archer()
            Combat.bander(w, "a")
            avance(w, 0.5)
            local fx = Combat.decocher(w, "a", O, G.v(0, 1, 0))
            local pid = trouve(fx, "projectile").pid
            H.assert_true(Combat.impact_decor(w, "a", pid) ~= nil, "arretee")
            H.assert_nil(w.projectiles[pid], "retiree")
        end)
    end)

    H.describe("combat/magie", function()
        local function mage(distance)
            local w = Combat.nouveau()
            Combat.ajouter(w, "a", { arme = "poings", pos = G.v(0, 0, 90), yaw = 0 })
            Combat.ajouter(w, "d", { pos = G.v(distance or 800, 0, 90), yaw = 180 })
            return w, w.combattants.a, w.combattants.d
        end

        H.it("trait de feu : incantation, projectile, brulure", function()
            local w, a, d = mage()
            local fx = Combat.incanter(w, "a", "trait_de_feu")
            H.assert_true(trouve(fx, "incantation") ~= nil, "incante")
            H.assert_eq(a.mana, 78, "mana depense")
            avance(w, 0.5)
            H.assert_eq(d.sante, 100, "rien avant la fin de l'incantation")
            avance(w, 0.5)
            H.assert_true(d.sante <= 76, "touche")
            local apres = d.sante
            avance(w, 2)
            H.assert_true(d.sante < apres, "brule")
        end)

        H.it("recharge et mana", function()
            local w, a = mage()
            Combat.incanter(w, "a", "trait_de_feu")
            avance(w, 0.7)
            local _, raison = Combat.incanter(w, "a", "trait_de_feu")
            H.assert_eq(raison, "recharge", "en recharge")
            a.mana = 5
            local _, r2 = Combat.incanter(w, "a", "eclair")
            H.assert_eq(r2, "mana", "pas assez de mana")
        end)

        H.it("une incantation est coupee si l'on encaisse fort", function()
            local w = Combat.nouveau()
            Combat.ajouter(w, "a", { arme = "poings", pos = G.v(0, 0, 90), yaw = 0 })
            Combat.ajouter(w, "d", { arme = "epee_longue", pos = G.v(150, 0, 90), yaw = 180 })
            Combat.incanter(w, "a", "eclair")
            Combat.attaquer(w, "d", "legere", "droite")
            local fx = avance(w, 0.6)
            H.assert_true(trouve(fx, "sort_interrompu", "id", "a") ~= nil, "coupee")
            H.assert_nil(trouve(fx, "eclair"), "pas d'eclair")
        end)

        H.it("onde de choc : repousse et casse la posture", function()
            local w, _, d = mage(300)
            Combat.incanter(w, "a", "onde_de_choc")
            local fx = avance(w, 0.5)
            H.assert_true(trouve(fx, "repousse", "id", "d") ~= nil, "repousse")
            H.assert_true(d.posture >= 55, "posture")
        end)

        H.it("eclair : instantane, premier touche, etourdit", function()
            local w, a, d = mage(1000)
            a.pitch = -2                         -- a l'horizontale, l'eclair arrive dans la tete
            Combat.incanter(w, "a", "eclair")
            avance(w, 0.95)
            H.assert_eq(d.sante, 58, "42 au torse")
            local _, raison = Combat.attaquer(w, "d", "legere")
            H.assert_eq(raison, "etourdi", "etourdi")
        end)

        H.it("soin : rend de la sante et arrete le saignement", function()
            local w, a = mage()
            a.sante = 40
            a.statuts.saignement = { fin = 10, dps = 2 }
            Combat.incanter(w, "a", "soin")
            avance(w, 1.25)
            H.assert_nil(a.statuts.saignement, "plus de saignement")
            avance(w, 5)
            H.assert_true(a.sante >= 78, "soigne")
        end)

        H.it("barriere : absorbe", function()
            local w, a = mage()
            Combat.incanter(w, "a", "barriere")
            avance(w, 0.4)
            Combat.degats(w, "a", 30, "tranchant", "torse", "d")
            H.assert_eq(a.sante, 100, "absorbe")
            Combat.degats(w, "a", 30, "tranchant", "torse", "d")
            H.assert_eq(a.sante, 85, "le reste passe")
        end)

        H.it("bond : destination devant soi", function()
            local w = mage()
            Combat.incanter(w, "a", "bond")
            local fx = avance(w, 0.15)
            local b = trouve(fx, "bond", "id", "a")
            H.assert_true(b ~= nil and math.abs(b.destination.x - 600) < 1, "600 cm devant")
        end)

        H.it("le baton aide a la magie", function()
            local w, a = mage()
            Combat.equiper(w, "a", "baton")
            Combat.incanter(w, "a", "trait_de_feu")
            H.assert_eq(a.mana, 100 - 22 * 0.8, "20 % de moins")
        end)
    end)

    H.describe("combat/a terre", function()
        local function rp()
            local w = Combat.nouveau({ a_terre = { actif = true } })
            Combat.ajouter(w, "a", { pos = G.v(0, 0, 90), camp = "rouge" })
            Combat.ajouter(w, "b", { pos = G.v(100, 0, 90), camp = "bleu" })
            Combat.ajouter(w, "c", { pos = G.v(120, 60, 90), camp = "bleu" })
            return w, w.combattants.a, w.combattants.b, w.combattants.c
        end

        H.it("a 0 de sante on tombe a terre, un allie releve", function()
            local w, _, b = rp()
            local fx = Combat.degats(w, "b", 200, "tranchant", "torse", "a")
            H.assert_true(trouve(fx, "a_terre", "id", "b") ~= nil, "a terre")
            Combat.relever(w, "c", "b")
            local fx2 = avance(w, 4.1)
            H.assert_true(trouve(fx2, "releve", "id", "b") ~= nil, "releve")
            H.assert_eq(b.sante, 25, "un peu de sante")
        end)

        H.it("relever est coupe si l'aidant est touche", function()
            local w = rp()
            Combat.degats(w, "b", 200, "tranchant", "torse", "a")
            Combat.relever(w, "c", "b")
            avance(w, 1)
            Combat.degats(w, "c", 5, "tranchant", "torse", "a")
            local fx = avance(w, 0.1)
            H.assert_true(trouve(fx, "relever_annule", "id", "b") ~= nil, "annule")
        end)

        H.it("un ennemi acheve, le temps tue", function()
            local w, _, b = rp()
            Combat.degats(w, "b", 200, "tranchant", "torse", "a")
            local fx = Combat.achever(w, "a", "b")
            H.assert_true(trouve(fx, "mort", "id", "b") ~= nil, "acheve")
            local w2, _, b2 = rp()
            Combat.degats(w2, "b", 200, "tranchant", "torse", "a")
            avance(w2, 36)
            H.assert_eq(b2.etat, "mort", "saigne a mort")
        end)

        H.it("sans le mode, on meurt tout de suite", function()
            local w = Combat.nouveau()
            Combat.ajouter(w, "b", {})
            local fx = Combat.degats(w, "b", 200, "tranchant", "torse", "a")
            H.assert_true(trouve(fx, "mort", "id", "b") ~= nil, "mort")
        end)
    end)

    H.describe("combat/jauges", function()
        H.it("le sprint vide l'endurance et s'arrete a zero", function()
            local w = Combat.nouveau()
            local f = Combat.ajouter(w, "a", {})
            Combat.sprinter(w, "a", true)
            local fx = avance(w, 13)
            H.assert_true(trouve(fx, "sprint", "actif", false) ~= nil, "arrete")
            H.assert_false(f.sprint, "plus de sprint")
        end)

        H.it("l'endurance revient apres un temps sans effort", function()
            local w, a = duel()
            a.endurance = 20
            a.dernier_effort = w.t
            avance(w, 0.5)
            H.assert_eq(a.endurance, 20, "pas encore")
            avance(w, 1.5)
            H.assert_true(a.endurance > 30, "revient")
        end)

        H.it("deux esquives collees : la seconde est ignoree", function()
            local w = duel()
            Combat.esquiver(w, "a")
            local _, raison = Combat.esquiver(w, "a")
            H.assert_true(raison == "trop_tot" or raison == "occupe", "ignoree")
        end)

        H.it("la chute ignore l'armure", function()
            local w, a = duel()
            Combat.armure(w, "a", "plaques")
            Combat.degats(w, "a", 20, "chute", "jambes")
            H.assert_eq(a.sante, 80, "20 pleins")
        end)

        H.it("etat pour le HUD, et remise a neuf", function()
            local w, a = duel("pistolet")
            a.sante = 30
            local e = Combat.etat(w, "a")
            H.assert_eq(e.sante, 30, "sante")
            H.assert_eq(e.chargeur, 12, "chargeur")
            Combat.reinitialiser(w, "a", G.v(5, 5, 90))
            H.assert_eq(a.sante, 100, "remis a neuf")
            H.assert_eq(a.pos.x, 5, "deplace")
        end)
    end)

    H.describe("combat/bots", function()
        local function lcg(graine)
            local x = graine
            return function(k)
                x = (x * 1103515245 + 12345) % 2147483648
                return (x // 65536) % k + 1
            end
        end
        -- Deux bots se battent ; ils avancent l'un vers l'autre (cinematique simple).
        local function combat(arme_a, niveau_a, arme_b, niveau_b, graine)
            local r = lcg(graine)
            local w = Combat.nouveau()
            Combat.ajouter(w, "a", { arme = arme_a, pos = G.v(0, 0, 90), yaw = 0 })
            Combat.ajouter(w, "b", { arme = arme_b, pos = G.v(600, 0, 90), yaw = 180 })
            local memoires = { a = {}, b = {} }
            local niveaux = { a = niveau_a, b = niveau_b }
            for _ = 1, 20 * 120 do
                for _, id in ipairs({ "a", "b" }) do
                    local f = w.combattants[id]
                    local dec = Combat.ia.decider(Combat, w, id, r, memoires[id], niveaux[id])
                    if dec.regard and f.etat == "vivant" then
                        local vers = G.moins(dec.aller_vers or dec.regard, f.pos)
                        local d = math.sqrt(vers.x * vers.x + vers.y * vers.y)
                        local pas = 0
                        if dec.distance and d > dec.distance then pas = math.min(d - dec.distance, 300 * 0.05 * Combat.vitesse(w, id)) end
                        local dir = d > 0 and G.fois(G.v(vers.x, vers.y, 0), 1 / d) or G.v()
                        Combat.placer(w, id, G.plus(f.pos, G.fois(dir, pas)), G.lacet_vers(f.pos, dec.regard), 0)
                    end
                    Combat.ia.executer(Combat, w, id, dec, r, niveaux[id])
                end
                Combat.avancer(w, 0.05)
                if w.combattants.a.etat ~= "vivant" or w.combattants.b.etat ~= "vivant" then break end
            end
            local a, b = w.combattants.a, w.combattants.b
            if a.etat ~= "vivant" then return "b" elseif b.etat ~= "vivant" then return "a" end
            return a.sante > b.sante and "a" or "b"
        end

        H.it("deux bots a l'epee finissent leur combat", function()
            local fins = 0
            for graine = 1, 10 do
                local r = combat("epee_courte", "normal", "epee_courte", "normal", graine)
                if r then fins = fins + 1 end
            end
            H.assert_eq(fins, 10, "tous finis")
        end)

        H.it("a armes egales, le meilleur bot gagne le plus souvent", function()
            local victoires = 0
            for graine = 1, 30 do
                if combat("epee_longue", "difficile", "epee_longue", "facile", graine) == "a" then victoires = victoires + 1 end
            end
            H.assert_true(victoires >= 20, "le difficile gagne " .. victoires .. " fois sur 30")
        end)

        H.it("le meme niveau des deux cotes : equilibre", function()
            local victoires = 0
            for graine = 1, 40 do
                if combat("hache", "normal", "hache", "normal", graine) == "a" then victoires = victoires + 1 end
            end
            H.assert_true(victoires >= 10 and victoires <= 30, "a gagne " .. victoires .. " fois sur 40")
        end)
    end)

    H.describe("combat/robustesse", function()
        H.it("150 melees au hasard : jauges bornees, les morts ne font rien", function()
            local function lcg(graine)
                local x = graine
                return function(k)
                    x = (x * 1103515245 + 12345) % 2147483648
                    return (x // 65536) % k + 1
                end
            end
            local ARMES = { "poings", "dague", "epee_courte", "epee_longue", "hache", "masse", "lance",
                "epee_bouclier", "baton", "pistolet", "revolver", "fusil", "fusil_pompe", "arc", "arbalete" }
            local SORTS = { "trait_de_feu", "onde_de_choc", "eclair", "gel", "soin", "barriere", "bond" }
            local DIRS = { "gauche", "droite", "haut" }
            local ARMURES = { "aucune", "tissu", "cuir", "mailles", "plaques" }
            for graine = 1, 150 do
                local r = lcg(graine)
                local w = Combat.nouveau({ a_terre = { actif = graine % 3 == 0 } })
                local ids = {}
                for i = 1, 2 + r(4) do
                    local id = "c" .. i
                    ids[i] = id
                    Combat.ajouter(w, id, { arme = ARMES[r(#ARMES)], armure = ARMURES[r(#ARMURES)],
                        camp = r(3), pos = G.v(r(600) - 300, r(600) - 300, 90), yaw = r(360) })
                end
                for _ = 1, 600 do
                    for _, id in ipairs(ids) do
                        local f = w.combattants[id]
                        local cible = w.combattants[ids[r(#ids)]]
                        Combat.placer(w, id, G.plus(f.pos, G.v(r(21) - 11, r(21) - 11, 0)),
                            G.lacet_vers(f.pos, cible.pos) + r(40) - 20, r(40) - 25)
                        local choix = r(14)
                        local mort = f.etat == "mort"
                        local fx
                        if choix == 1 then fx = Combat.attaquer(w, id, r(2) == 1 and "legere" or "lourde", DIRS[r(3)])
                        elseif choix == 2 then fx = Combat.garder(w, id, DIRS[r(3)])
                        elseif choix == 3 then fx = Combat.lacher_garde(w, id)
                        elseif choix == 4 then fx = Combat.esquiver(w, id, "gauche")
                        elseif choix == 5 then fx = Combat.feinter(w, id)
                        elseif choix == 6 then
                            local o = G.v(f.pos.x, f.pos.y, f.pos.z + 62)
                            fx = Combat.tirer(w, id, { origine = o, cible = cible.id, ping = r(30) / 100,
                                direction = G.moins(G.v(cible.pos.x, cible.pos.y, cible.pos.z + r(100) - 50), o) })
                        elseif choix == 7 then fx = Combat.recharger(w, id)
                        elseif choix == 8 then fx = Combat.bander(w, id)
                        elseif choix == 9 then
                            fx = Combat.decocher(w, id, G.v(f.pos.x, f.pos.y, f.pos.z + 62), G.moins(cible.pos, f.pos))
                        elseif choix == 10 then fx = Combat.incanter(w, id, SORTS[r(#SORTS)], cible.id)
                        elseif choix == 11 then fx = Combat.sprinter(w, id, r(2) == 1)
                        elseif choix == 12 then fx = Combat.relever(w, id, cible.id)
                        elseif choix == 13 then fx = Combat.achever(w, id, cible.id)
                        elseif choix == 14 and r(40) == 1 then fx = Combat.equiper(w, id, ARMES[r(#ARMES)])
                        end
                        if mort and choix ~= 3 and choix ~= 11 then
                            for _, e in ipairs(fx or {}) do
                                H.assert_true(e.kind ~= "attaque" and e.kind ~= "tir" and e.kind ~= "incantation",
                                    "un mort ne fait rien (graine " .. graine .. ")")
                            end
                        end
                    end
                    Combat.avancer(w, 0.05)
                    for _, id in ipairs(ids) do
                        local f = w.combattants[id]
                        H.assert_true(f.sante >= 0 and f.sante <= f.sante_max, "sante bornee (graine " .. graine .. ")")
                        H.assert_true(f.endurance >= 0 and f.endurance <= f.endurance_max, "endurance bornee")
                        H.assert_true(f.posture >= 0 and f.posture <= f.posture_max, "posture bornee")
                        H.assert_true(f.mana >= 0 and f.mana <= f.mana_max, "mana borne")
                        H.assert_true(f.munitions >= 0, "munitions positives")
                        if f.etat == "mort" then H.assert_eq(f.sante, 0, "un mort a 0") end
                    end
                end
                -- Tout projectile finit par disparaitre.
                for _ = 1, 120 do Combat.avancer(w, 0.05) end
                H.assert_nil(next(w.projectiles), "projectiles nettoyes (graine " .. graine .. ")")
            end
        end)
    end)
end
