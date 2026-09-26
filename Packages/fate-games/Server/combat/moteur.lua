-- Moteur de combat (docs/COMBAT.md), en Lua pur : aucune dependance a nanos
-- ni a fate-games, pour etre repris tel quel (Qin RP).
--
-- Contrat : un monde `w`, des intentions qui rendent (effets) ou (nil, raison),
-- et Combat.avancer(w, dt) qui fait passer le temps et rend des effets. Un
-- effet est une table { kind = ..., ... } que l'adaptateur traduit en jeu.
-- Aucune valeur de degats ne vient du client : il ne dit que ce qu'il veut
-- faire et ou il vise, le moteur verifie et tranche.

return function(R, A, S, G)
    local Combat = {}

    local MIROIR = { gauche = "droite", droite = "gauche", haut = "haut" }
    local DIRECTIONS = { gauche = true, droite = true, haut = true }

    ---------------------------------------------------------------- monde

    -- Copie des regles, surchargees table par table par la config d'un mode.
    local function regles(config)
        local r = {}
        for k, v in pairs(R) do
            if type(v) == "table" then
                local t = {}
                for k2, v2 in pairs(v) do t[k2] = v2 end
                r[k] = t
            else
                r[k] = v
            end
        end
        for k, v in pairs(config or {}) do
            if type(v) == "table" and type(r[k]) == "table" then
                for k2, v2 in pairs(v) do r[k][k2] = v2 end
            else
                r[k] = v
            end
        end
        return r
    end

    function Combat.nouveau(config)
        return { t = 0, R = regles(config), combattants = {}, projectiles = {}, prochain_projectile = 1 }
    end

    local function combattant(w, id) return w.combattants[id] end

    local function en_vie(f) return f and f.etat == "vivant" end

    local function a_statut(w, f, nom)
        local s = f.statuts[nom]
        return s ~= nil and s.fin > w.t
    end

    local function ennemis(w, a, b)
        if a == b then return false end
        if a.camp ~= b.camp then return true end
        return w.R.tir.tir_ami == true
    end

    local function oeil(w, f)
        return G.v(f.pos.x, f.pos.y, f.pos.z + w.R.tir.oeil.z)
    end

    function Combat.ajouter(w, id, o)
        o = o or {}
        local c = w.R.combattant
        local f = {
            id = id, camp = o.camp or id, pos = G.copie(o.pos or G.v()), yaw = o.yaw or 0, pitch = 0,
            sante_max = o.sante or c.sante, endurance_max = c.endurance, posture_max = c.posture, mana_max = c.mana,
            armure = o.armure or "aucune", arme = o.arme or "poings", etat = "vivant",
            statuts = {}, historique = {}, recharges = {}, dernieres = {},
            dernier_effort = -99, dernier_choc = -99, dernier_choc_posture = -99, dernier_tir = -99,
            vitesse_annoncee = 1,
        }
        f.sante, f.endurance, f.posture, f.mana = f.sante_max, f.endurance_max, 0, f.mana_max
        local arme = A[f.arme]
        f.munitions = arme and arme.chargeur or 0
        f.historique[1] = { t = w.t, pos = G.copie(f.pos) }
        w.combattants[id] = f
        return f
    end

    function Combat.retirer(w, id) w.combattants[id] = nil end

    -- Remet un combattant a neuf (reapparition, nouvelle manche).
    function Combat.reinitialiser(w, id, pos, yaw)
        local f = combattant(w, id)
        if not f then return end
        f.sante, f.endurance, f.posture, f.mana = f.sante_max, f.endurance_max, 0, f.mana_max
        f.etat, f.statuts, f.action, f.garde, f.esquive, f.bande = "vivant", {}, nil, nil, nil, nil
        f.recharge_fin, f.releve_par, f.a_terre_fin, f.sprint = nil, nil, nil, false
        local arme = A[f.arme]
        f.munitions = arme and arme.chargeur or 0
        if pos then
            f.pos, f.yaw = G.copie(pos), yaw or f.yaw
            f.historique = { { t = w.t, pos = G.copie(pos) } }
        end
    end

    -- L'adaptateur donne a chaque pas la position (centre du corps), le regard
    -- et la vitesse. Les positions sont gardees un moment : un tir est verifie
    -- la ou etait la cible quand le tireur l'a vue (compensation de latence).
    function Combat.placer(w, id, pos, yaw, pitch)
        local f = combattant(w, id)
        if not f then return end
        f.pos, f.yaw, f.pitch = G.copie(pos), yaw or f.yaw, pitch or f.pitch
        local h = f.historique
        h[#h + 1] = { t = w.t, pos = G.copie(pos) }
        local limite = w.t - w.R.tir.historique
        while #h > 2 and h[2].t < limite do table.remove(h, 1) end
    end

    local function position_a(f, t)
        local h = f.historique
        if #h == 0 or t >= h[#h].t then return G.copie(f.pos) end
        if t <= h[1].t then return G.copie(h[1].pos) end
        for i = #h, 2, -1 do
            local a, b = h[i - 1], h[i]
            if t >= a.t and t <= b.t then
                local k = b.t > a.t and (t - a.t) / (b.t - a.t) or 1
                return G.lerp(a.pos, b.pos, k)
            end
        end
        return G.copie(f.pos)
    end

    function Combat.equiper(w, id, arme)
        local f = combattant(w, id)
        if not (f and A[arme]) then return nil, "arme_inconnue" end
        if f.action or f.bande then return nil, "occupe" end
        f.arme, f.garde, f.recharge_fin = arme, nil, nil
        f.munitions = A[arme].chargeur or 0
        return { { kind = "equipe", id = id, arme = arme } }
    end

    function Combat.armure(w, id, armure)
        local f = combattant(w, id)
        if not (f and w.R.armures[armure]) then return nil, "armure_inconnue" end
        f.armure = armure
        return {}
    end

    ---------------------------------------------------------------- statuts

    local function poser_statut(w, f, nom, duree, fx, donnees)
        local s = donnees or {}
        s.fin = w.t + duree
        f.statuts[nom] = s
        fx[#fx + 1] = { kind = "statut", id = f.id, statut = nom, duree = duree }
    end

    local function peut_agir(w, f)
        if not en_vie(f) then return false, "hors_combat" end
        if a_statut(w, f, "etourdi") then return false, "etourdi" end
        if a_statut(w, f, "expose") then return false, "expose" end
        return true
    end

    -- Une meme intention trop tot apres la precedente est ignoree.
    local function trop_tot(w, f, quoi)
        local d = f.dernieres[quoi]
        if d and w.t - d < w.R.intentions_min then return true end
        f.dernieres[quoi] = w.t
        return false
    end

    local function depenser(w, f, cout)
        f.endurance = math.max(0, f.endurance - cout)
        f.dernier_effort = w.t
    end

    local function cout_endurance(w, f, base)
        return base * (w.R.poids_armures[f.armure] or { endurance = 1 }).endurance
    end

    ---------------------------------------------------------------- degats

    -- Degats apres zone, armure (moins la penetration) et vulnerabilite.
    local function calculer(w, f, base, type_, zone_mult, penetration)
        local red = (w.R.armures[f.armure] or {})[type_] or 0
        local m = base * zone_mult * (1 - red * (1 - (penetration or 0)))
        if a_statut(w, f, "vulnerable") then m = m * w.R.etats.vulnerable_mult end
        return math.floor(m * 10 + 0.5) / 10
    end

    local mourir, tomber

    function mourir(w, f, source, fx, cause)
        f.etat, f.sante = "mort", 0
        f.action, f.garde, f.esquive, f.bande, f.releve_par, f.sprint = nil, nil, nil, nil, nil, false
        fx[#fx + 1] = { kind = "mort", id = f.id, source = source, cause = cause }
    end

    function tomber(w, f, source, fx)
        f.etat, f.sante = "a_terre", 0
        f.action, f.garde, f.esquive, f.bande, f.releve_par, f.sprint = nil, nil, nil, nil, nil, false
        f.a_terre_fin = w.t + w.R.a_terre.saignement
        fx[#fx + 1] = { kind = "a_terre", id = f.id, source = source }
    end

    local function interrompre(w, f, fx, raison)
        if f.action and f.action.kind == "sort" then
            fx[#fx + 1] = { kind = "sort_interrompu", id = f.id, sort = f.action.sort }
            f.action = nil
        elseif f.action and f.action.kind == "attaque" and f.action.phase == "armement" then
            fx[#fx + 1] = { kind = "interrompu", id = f.id, raison = raison }
            f.action = nil
        end
    end

    -- Applique des degats deja calcules : barriere, sante, mort ou a terre.
    local function blesser(w, f, montant, type_, zone, source, fx)
        if f.etat == "mort" then return end
        if f.etat == "a_terre" then
            return mourir(w, f, source, fx, "acheve")
        end
        local b = f.statuts.barriere
        if b and b.fin > w.t and b.reste > 0 then
            local pris = math.min(b.reste, montant)
            b.reste, montant = b.reste - pris, montant - pris
            fx[#fx + 1] = { kind = "absorbe", id = f.id, montant = pris, reste = b.reste }
            if montant <= 0 then return end
        end
        f.sante = math.max(0, f.sante - montant)
        f.dernier_choc = w.t
        fx[#fx + 1] = { kind = "degats", cible = f.id, source = source, montant = montant, zone = zone,
            type = type_, sante = f.sante }
        if f.action and f.action.kind == "sort" and montant >= w.R.etats.interruption_sort then
            interrompre(w, f, fx, "touche")
        end
        if f.sante <= 0 then
            if w.R.a_terre.actif then tomber(w, f, source, fx) else mourir(w, f, source, fx, type_) end
        end
    end

    local function garde_brisee(w, f, fx)
        f.garde, f.posture = nil, 0
        if f.action and f.action.kind ~= "sort" then f.action = nil end
        interrompre(w, f, fx, "garde_brisee")
        fx[#fx + 1] = { kind = "garde_brisee", id = f.id }
        poser_statut(w, f, "etourdi", w.R.etats.garde_brisee_etourdi, fx)
        poser_statut(w, f, "vulnerable", w.R.etats.vulnerable, fx)
    end

    local function charger_posture(w, f, montant, fx)
        if montant <= 0 or not en_vie(f) then return end
        f.posture = math.min(f.posture_max, f.posture + montant)
        f.dernier_choc_posture = w.t
        if f.posture >= f.posture_max then garde_brisee(w, f, fx) end
    end

    -- Degats venus d'ailleurs (chute, arme native, piege), passes par les
    -- memes regles d'armure.
    function Combat.degats(w, id, base, type_, zone, source)
        local f = combattant(w, id)
        if not f or f.etat == "mort" then return nil, "hors_combat" end
        local fx = {}
        zone = zone or "torse"
        local mult = type_ == "chute" and 1 or (w.R.zones[zone] or 1)
        local montant = type_ == "chute" and base or calculer(w, f, base, type_, mult, 0)
        blesser(w, f, montant, type_, zone, source, fx)
        return fx
    end

    ---------------------------------------------------------------- corps a corps

    function Combat.attaquer(w, id, force, dir)
        local f = combattant(w, id)
        local ok, raison = peut_agir(w, f)
        if not ok then return nil, raison end
        if trop_tot(w, f, "attaque") then return nil, "trop_tot" end
        local arme = A[f.arme]
        if not (arme and arme.famille == "melee") then return nil, "pas_corps_a_corps" end
        if f.action or f.esquive and w.t < f.esquive.fin then return nil, "occupe" end
        force = force == "lourde" and "lourde" or "legere"
        dir = DIRECTIONS[dir] and dir or "droite"
        local att = arme[force]
        local cout = cout_endurance(w, f, att.endurance)
        if f.endurance < cout then return nil, "epuise" end
        depenser(w, f, cout)
        f.garde = nil
        local t = w.t
        f.action = { kind = "attaque", force = force, dir = dir, arme = f.arme, debut = t, phase = "armement",
            fin_armement = t + att.armement, fin_frappe = t + att.armement + att.frappe,
            fin = t + att.armement + att.frappe + att.recuperation, touches = {} }
        return { { kind = "attaque", id = id, force = force, dir = dir, arme = f.arme, armement = att.armement } }
    end

    function Combat.feinter(w, id)
        local f = combattant(w, id)
        if not en_vie(f) then return nil, "hors_combat" end
        local a = f.action
        if not (a and a.kind == "attaque" and a.phase == "armement") then return nil, "rien_a_feinter" end
        local duree = a.fin_armement - a.debut
        if w.t - a.debut > duree * w.R.defense.feinte_jusqua then return nil, "trop_tard" end
        local cout = cout_endurance(w, f, w.R.defense.feinte_cout)
        if f.endurance < cout then return nil, "epuise" end
        depenser(w, f, cout)
        f.action = nil
        return { { kind = "feinte", id = id } }
    end

    function Combat.garder(w, id, dir)
        local f = combattant(w, id)
        local ok, raison = peut_agir(w, f)
        if not ok then return nil, raison end
        if f.action then return nil, "occupe" end
        dir = DIRECTIONS[dir] and dir or "droite"
        if f.garde and f.garde.dir == dir then return {} end
        f.garde = { dir = dir, depuis = w.t }
        return { { kind = "garde", id = id, dir = dir } }
    end

    function Combat.lacher_garde(w, id)
        local f = combattant(w, id)
        if not (f and f.garde) then return {} end
        f.garde = nil
        return { { kind = "garde", id = id, dir = nil } }
    end

    function Combat.esquiver(w, id, dir)
        local f = combattant(w, id)
        local ok, raison = peut_agir(w, f)
        if not ok then return nil, raison end
        if trop_tot(w, f, "esquive") then return nil, "trop_tot" end
        if f.action then return nil, "occupe" end
        if f.esquive and w.t < f.esquive.fin then return nil, "occupe" end
        local d = w.R.defense
        local cout = cout_endurance(w, f, d.esquive_cout)
        if f.endurance < cout then return nil, "epuise" end
        depenser(w, f, cout)
        f.garde = nil
        f.esquive = { debut = w.t, invulnerable = w.t + d.esquive_invulnerable, fin = w.t + d.esquive_duree }
        return { { kind = "esquive", id = id, dir = dir or "arriere", distance = d.esquive_distance } }
    end

    -- Zone d'un coup de corps a corps : un coup d'en haut vise la tete, un
    -- attaquant qui regarde bas vise les jambes.
    local function zone_melee(a, dir)
        if dir == "haut" then return "tete" end
        if (a.pitch or 0) < -30 then return "jambes" end
        return "torse"
    end

    local ZONES_MELEE = { tete = 1.4, torse = 1.0, bras = 0.8, jambes = 0.85 }

    local function resoudre_coup(w, a, d, fx)
        local action = a.action
        local arme = A[action.arme]
        local att = arme[action.force]
        local arme_d = A[d.arme] or A.poings
        action.touches[d.id] = true

        -- Esquive : invulnerable au debut du pas.
        if d.esquive and w.t <= d.esquive.invulnerable then
            fx[#fx + 1] = { kind = "esquive_reussie", id = d.id, source = a.id }
            return
        end

        -- Garde : de face, et du bon cote (le bouclier couvre tout le devant).
        local g = d.garde
        local bouclier = arme_d.famille == "melee" and arme_d.garde.bouclier
        local demi = bouclier and w.R.defense.bouclier_demi_angle or w.R.defense.garde_demi_angle
        if g and arme_d.famille == "melee" and G.ecart(d.yaw, d.pos, a.pos) <= demi
            and (bouclier or g.dir == MIROIR[action.dir]) then
            local parable = action.force == "legere" or arme_d.poids ~= "leger"
            if parable and w.t - g.depuis <= w.R.defense.parade then
                -- Parade : le coup est annule, l'attaquant est expose.
                a.action = nil
                d.endurance = math.min(d.endurance_max, d.endurance + w.R.defense.parade_rendue)
                fx[#fx + 1] = { kind = "pare", id = d.id, source = a.id }
                poser_statut(w, a, "expose", w.R.defense.parade_expose, fx)
                charger_posture(w, a, w.R.defense.parade_posture, fx)
                return
            end
            -- Blocage : une part traverse, la garde coute endurance et posture.
            local traverse = arme_d.garde.traverse
            local montant = calculer(w, d, att.degats * traverse, att.type, 1, arme.penetration)
            depenser(w, d, cout_endurance(w, d, att.endurance * arme_d.garde.endurance))
            fx[#fx + 1] = { kind = "bloque", id = d.id, source = a.id, traverse = montant }
            if montant > 0 then blesser(w, d, montant, att.type, "torse", a.id, fx) end
            if not en_vie(d) then return end
            if action.force == "lourde" and d.endurance <= 0 then return garde_brisee(w, d, fx) end
            charger_posture(w, d, att.posture * arme_d.garde.posture, fx)
            return
        end

        -- Touche.
        local zone = zone_melee(a, action.dir)
        local montant = calculer(w, d, att.degats, att.type, ZONES_MELEE[zone], arme.penetration)
        blesser(w, d, montant, att.type, zone, a.id, fx)
        if not en_vie(d) then return end
        charger_posture(w, d, att.posture * 0.5, fx)
        if not en_vie(d) then return end
        local e = w.R.etats
        if att.saignement then poser_statut(w, d, "saignement", e.saignement.duree, fx, { dps = e.saignement.dps }) end
        if zone == "jambes" then
            poser_statut(w, d, "ralenti", e.jambes_ralenti.duree, fx, { vitesse = e.jambes_ralenti.vitesse })
        end
        if zone == "tete" and att.type == "contondant" and action.force == "lourde" then
            poser_statut(w, d, "etourdi", e.tete_etourdi, fx)
        end
        -- Un coup encaisse coupe une attaque legere en armement (pas une lourde).
        if d.action and d.action.kind == "attaque" and d.action.phase == "armement" and d.action.force == "legere" then
            interrompre(w, d, fx, "touche")
        end
    end

    local function frapper(w, a, fx)
        local arme = A[a.action.arme]
        local s = w.R.silhouette
        for _, d in pairs(w.combattants) do
            if not a.action then return end
            if d ~= a and en_vie(d) and not a.action.touches[d.id] and ennemis(w, a, d)
                and math.abs(d.pos.z - a.pos.z) < s.demi_hauteur * 1.6
                and G.dans_arc(a.pos, a.yaw, d.pos, arme.portee, arme.demi_angle, s.rayon) then
                resoudre_coup(w, a, d, fx)
            end
        end
    end

    ---------------------------------------------------------------- tir

    function Combat.recharger(w, id)
        local f = combattant(w, id)
        local ok, raison = peut_agir(w, f)
        if not ok then return nil, raison end
        local arme = A[f.arme]
        if not (arme and arme.chargeur) then return nil, "rien_a_recharger" end
        if f.recharge_fin then return nil, "occupe" end
        if f.munitions >= arme.chargeur then return nil, "plein" end
        f.recharge_fin = w.t + arme.recharge
        return { { kind = "recharge", id = id, duree = arme.recharge } }
    end

    local function baisse(arme, distance)
        local c = arme.chute
        if not c or distance <= c.debut then return 1 end
        if distance >= c.fin then return c.min end
        return 1 - (1 - c.min) * (distance - c.debut) / (c.fin - c.debut)
    end

    -- Base orthonormee autour d'une direction, pour ouvrir un cone.
    local function base_autour(dir)
        local haut = math.abs(dir.z) > 0.95 and G.v(1, 0, 0) or G.v(0, 0, 1)
        local d = G.normal(dir)
        local cote = G.normal({ x = d.y * haut.z - d.z * haut.y, y = d.z * haut.x - d.x * haut.z, z = d.x * haut.y - d.y * haut.x })
        local dessus = { x = cote.y * d.z - cote.z * d.y, y = cote.z * d.x - cote.x * d.z, z = cote.x * d.y - cote.y * d.x }
        return d, cote, dessus
    end

    -- Un rayon contre la capsule d'une cible a un instant donne : distance
    -- parcourue et zone, ou nil.
    local function rayon_touche(w, origine, dir, portee, cible, instant)
        local s = w.R.silhouette
        local centre = position_a(cible, instant)
        local fin = G.plus(origine, G.fois(dir, portee))
        local k, point, ecart = G.segment_capsule(origine, fin, centre, s.demi_hauteur, s.rayon)
        if not k then return nil end
        return k * portee, G.zone(point, centre, s.demi_hauteur, s.rayon, s, ecart), point
    end

    -- tir = { origine, direction, cible (id, facultatif : ce que le client a
    -- touche d'apres sa trace), ping (s) }.
    function Combat.tirer(w, id, tir)
        local f = combattant(w, id)
        local ok, raison = peut_agir(w, f)
        if not ok then return nil, raison end
        local arme = A[f.arme]
        if not (arme and arme.famille == "tir") then return nil, "pas_arme_a_feu" end
        if f.recharge_fin then return nil, "recharge" end
        if w.t - f.dernier_tir < arme.cadence - 0.01 then return nil, "cadence" end
        if f.munitions <= 0 then return nil, "vide" end
        local o = tir and tir.origine
        if not (o and tir.direction) then return nil, "tir_invalide" end
        if G.distance(o, oeil(w, f)) > w.R.tir.oeil.tolerance then return nil, "origine" end

        f.munitions, f.dernier_tir = f.munitions - 1, w.t
        f.garde, f.dernier_effort = nil, f.dernier_effort
        local dir = G.normal(tir.direction)
        local fx = { { kind = "tir", id = id, origine = G.copie(o), direction = dir, arme = f.arme, munitions = f.munitions } }

        local cible = tir.cible and combattant(w, tir.cible)
        if not (cible and en_vie(cible) and ennemis(w, f, cible)) then return fx end
        local instant = w.t - math.min(math.max(tir.ping or 0, 0), w.R.tir.latence_max)

        -- Les plombs suivent un motif fixe dans le cone : aucun hasard.
        local rayons = { dir }
        if arme.plombs then
            rayons = {}
            local d, cote, dessus = base_autour(dir)
            local ouverture = math.tan(math.rad(arme.cone))
            for i = 1, arme.plombs do
                local m = A.motif_plombs[(i - 1) % #A.motif_plombs + 1]
                rayons[i] = G.normal(G.plus(d, G.plus(G.fois(cote, m[1] * ouverture), G.fois(dessus, m[2] * ouverture))))
            end
        end
        local total, zone_max, touches = 0, nil, 0
        for _, r in ipairs(rayons) do
            local dist, zone = rayon_touche(w, o, r, arme.portee, cible, instant)
            if dist then
                touches = touches + 1
                total = total + calculer(w, cible, arme.degats * baisse(arme, dist), arme.type, w.R.zones[zone], arme.penetration)
                if not zone_max or w.R.zones[zone] > w.R.zones[zone_max] then zone_max = zone end
            end
        end
        if touches == 0 then
            fx[#fx + 1] = { kind = "tir_refuse", id = id, cible = cible.id }
            return fx
        end
        blesser(w, cible, math.floor(total * 10 + 0.5) / 10, arme.type, zone_max, id, fx)
        if en_vie(cible) and zone_max == "jambes" then
            local e = w.R.etats.jambes_ralenti
            poser_statut(w, cible, "ralenti", e.duree, fx, { vitesse = e.vitesse })
        end
        return fx
    end

    -- Une balle deja confirmee par le jeu (arme native de nanos : c'est elle
    -- qui a trouve l'os touche). Le moteur n'y ajoute que ses regles : zone,
    -- armure, baisse avec la distance, ralenti aux jambes. `distance` en cm.
    function Combat.balle(w, id, cible, zone, distance)
        local f, c = combattant(w, id), combattant(w, cible)
        if not (en_vie(f) and c and en_vie(c)) then return nil, "hors_combat" end
        if not ennemis(w, f, c) then return nil, "allie" end
        local arme = A[f.arme]
        if not (arme and arme.famille == "tir") then return nil, "pas_arme_a_feu" end
        zone = w.R.zones[zone] and zone or "torse"
        local fx = {}
        local total = calculer(w, c, arme.degats * baisse(arme, distance or 0), arme.type, w.R.zones[zone], arme.penetration)
        blesser(w, c, total, arme.type, zone, id, fx)
        if en_vie(c) and zone == "jambes" then
            local e = w.R.etats.jambes_ralenti
            poser_statut(w, c, "ralenti", e.duree, fx, { vitesse = e.vitesse })
        end
        return fx
    end

    ---------------------------------------------------------------- arc

    function Combat.bander(w, id)
        local f = combattant(w, id)
        local ok, raison = peut_agir(w, f)
        if not ok then return nil, raison end
        local arme = A[f.arme]
        if not (arme and arme.famille == "arc") then return nil, "pas_arc" end
        if f.action or f.bande then return nil, "occupe" end
        if f.recharge_fin then return nil, "recharge" end
        f.bande, f.garde = { debut = w.t }, nil
        return { { kind = "bande", id = id } }
    end

    local function lancer_projectile(w, p, fx)
        p.id = w.prochain_projectile
        w.prochain_projectile = w.prochain_projectile + 1
        w.projectiles[p.id] = p
        fx[#fx + 1] = { kind = "projectile", pid = p.id, id = p.lanceur, pos = G.copie(p.pos), vitesse = G.copie(p.vitesse),
            quoi = p.quoi }
    end

    function Combat.decocher(w, id, origine, direction)
        local f = combattant(w, id)
        if not (en_vie(f) and f.bande) then return nil, "pas_bande" end
        local arme = A[f.arme]
        if G.distance(origine, oeil(w, f)) > w.R.tir.oeil.tolerance then return nil, "origine" end
        local k = arme.charge > 0 and math.min(1, (w.t - f.bande.debut) / arme.charge) or 1
        f.bande = nil
        depenser(w, f, cout_endurance(w, f, arme.endurance))
        if arme.recharge then f.recharge_fin = w.t + arme.recharge end
        local fx = {}
        lancer_projectile(w, {
            lanceur = id, quoi = f.arme, pos = G.copie(origine),
            vitesse = G.fois(G.normal(direction), arme.vitesse_min + (arme.vitesse_max - arme.vitesse_min) * k),
            gravite = arme.gravite, rayon = arme.rayon, fin = w.t + arme.duree,
            degats = arme.degats_min + (arme.degats_max - arme.degats_min) * k, type = arme.type,
            penetration = arme.penetration, charge = k,
        }, fx)
        return fx
    end

    -- Le client du lanceur voit sa fleche toucher le decor : elle s'arrete.
    function Combat.impact_decor(w, id, pid, pos)
        local p = w.projectiles[pid]
        if not (p and p.lanceur == id) then return nil, "inconnu" end
        w.projectiles[pid] = nil
        return { { kind = "projectile_impact", pid = pid, pos = pos and G.copie(pos) or G.copie(p.pos) } }
    end

    local function toucher_projectile(w, p, cible, point, zone, fx)
        local lanceur = combattant(w, p.lanceur)
        local arme_d = A[cible.arme]
        -- Un bouclier leve de face arrete les projectiles.
        if cible.garde and arme_d and arme_d.famille == "melee" and arme_d.garde.bouclier
            and G.ecart(cible.yaw, cible.pos, p.pos) <= w.R.defense.bouclier_demi_angle then
            fx[#fx + 1] = { kind = "bloque", id = cible.id, source = p.lanceur, traverse = 0, projectile = p.id }
            charger_posture(w, cible, (p.posture or 10) * arme_d.garde.posture, fx)
            return
        end
        if cible.esquive and w.t <= cible.esquive.invulnerable then return "rate" end
        local montant = calculer(w, cible, p.degats, p.type, w.R.zones[zone], p.penetration)
        blesser(w, cible, montant, p.type, zone, p.lanceur, fx)
        if not en_vie(cible) then return end
        if p.posture then charger_posture(w, cible, p.posture, fx) end
        if not en_vie(cible) then return end
        local e = w.R.etats
        if p.statut == "brulure" then
            poser_statut(w, cible, "brulure", e.brulure.duree, fx, { dps = e.brulure.dps })
        elseif p.statut == "gel" then
            poser_statut(w, cible, "ralenti", S.statuts.gel.duree, fx, { vitesse = S.statuts.gel.vitesse })
        end
        if zone == "jambes" then
            poser_statut(w, cible, "ralenti", e.jambes_ralenti.duree, fx, { vitesse = e.jambes_ralenti.vitesse })
        end
        return lanceur
    end

    local function avancer_projectiles(w, dt, fx)
        local s = w.R.silhouette
        for pid, p in pairs(w.projectiles) do
            local depart = p.pos
            local arrivee = G.plus(depart, G.fois(p.vitesse, dt))
            p.vitesse.z = p.vitesse.z - 980 * (p.gravite or 0) * dt
            local meilleur, mk, mpoint, mzone
            for _, c in pairs(w.combattants) do
                local lanceur = combattant(w, p.lanceur)
                if c.id ~= p.lanceur and en_vie(c) and (not lanceur or ennemis(w, lanceur, c)) then
                    local k, point, ecart = G.segment_capsule(depart, arrivee, c.pos, s.demi_hauteur, s.rayon + (p.rayon or 0))
                    if k and (not mk or k < mk) then
                        meilleur, mk, mpoint = c, k, point
                        mzone = G.zone(point, c.pos, s.demi_hauteur, s.rayon, s, math.max(0, ecart - (p.rayon or 0)))
                    end
                end
            end
            if meilleur then
                p.pos = mpoint
                local r = toucher_projectile(w, p, meilleur, mpoint, mzone, fx)
                if r ~= "rate" then
                    w.projectiles[pid] = nil
                    fx[#fx + 1] = { kind = "projectile_impact", pid = pid, pos = G.copie(mpoint), cible = meilleur.id }
                else
                    p.pos = arrivee
                end
            elseif w.t >= p.fin then
                w.projectiles[pid] = nil
                fx[#fx + 1] = { kind = "projectile_fin", pid = pid, pos = G.copie(arrivee) }
            else
                p.pos = arrivee
            end
        end
    end

    ---------------------------------------------------------------- magie

    function Combat.incanter(w, id, sort, cible)
        local f = combattant(w, id)
        local ok, raison = peut_agir(w, f)
        if not ok then return nil, raison end
        local s = S[sort]
        if not (s and s.forme) then return nil, "sort_inconnu" end
        if f.action or f.bande then return nil, "occupe" end
        if (f.recharges[sort] or -1) > w.t then return nil, "recharge" end
        local arme = A[f.arme]
        local cout = s.mana * (arme and arme.focus or 1)
        if f.mana < cout then return nil, "mana" end
        f.mana = f.mana - cout
        f.garde = nil
        f.recharges[sort] = w.t + s.incantation + s.recharge
        f.action = { kind = "sort", sort = sort, cible = cible, debut = w.t, fin = w.t + s.incantation }
        return { { kind = "incantation", id = id, sort = sort, duree = s.incantation } }
    end

    local function lancer_sort(w, f, action, fx)
        local s = S[action.sort]
        local dir = G.direction(f.yaw, f.pitch)
        fx[#fx + 1] = { kind = "sort", id = f.id, sort = action.sort }
        if s.forme == "projectile" then
            lancer_projectile(w, {
                lanceur = f.id, quoi = action.sort, pos = G.plus(oeil(w, f), G.fois(dir, 40)),
                vitesse = G.fois(dir, s.vitesse), gravite = s.gravite, rayon = s.rayon, fin = w.t + s.duree,
                degats = s.degats, type = s.type, statut = s.statut, posture = s.posture,
            }, fx)
        elseif s.forme == "cone" then
            local sil = w.R.silhouette
            for _, d in pairs(w.combattants) do
                if en_vie(d) and ennemis(w, f, d) and G.dans_arc(f.pos, f.yaw, d.pos, s.portee, s.demi_angle, sil.rayon) then
                    blesser(w, d, calculer(w, d, s.degats, s.type, 1, 0), s.type, "torse", f.id, fx)
                    if en_vie(d) then
                        charger_posture(w, d, s.posture, fx)
                        fx[#fx + 1] = { kind = "repousse", id = d.id, source = f.id,
                            direction = G.normal(G.moins(G.v(d.pos.x, d.pos.y, 0), G.v(f.pos.x, f.pos.y, 0))), force = s.repousse }
                    end
                end
            end
        elseif s.forme == "ligne" then
            local o = oeil(w, f)
            local meilleur, md, mzone
            for _, d in pairs(w.combattants) do
                if en_vie(d) and ennemis(w, f, d) then
                    local dist, zone = rayon_touche(w, o, dir, s.portee, d, w.t)
                    if dist and (not md or dist < md) then meilleur, md, mzone = d, dist, zone end
                end
            end
            fx[#fx + 1] = { kind = "eclair", id = f.id, origine = o, direction = dir, portee = md or s.portee }
            if meilleur then
                blesser(w, meilleur, calculer(w, meilleur, s.degats, s.type, w.R.zones[mzone], 0), s.type, mzone, f.id, fx)
                if en_vie(meilleur) then
                    charger_posture(w, meilleur, s.posture, fx)
                    if en_vie(meilleur) and s.etourdi then poser_statut(w, meilleur, "etourdi", s.etourdi, fx) end
                end
            end
        elseif s.forme == "soi" then
            if s.absorbe then
                poser_statut(w, f, "barriere", s.duree, fx, { reste = s.absorbe })
            elseif s.bond then
                local avant = G.direction(f.yaw, 0)
                fx[#fx + 1] = { kind = "bond", id = f.id, destination = G.plus(f.pos, G.fois(avant, s.bond)) }
            end
        elseif s.forme == "allie" then
            local cible = action.cible and combattant(w, action.cible)
            if not (cible and en_vie(cible) and not ennemis(w, f, cible)
                and G.distance(cible.pos, f.pos) <= s.portee) then cible = f end
            for _, nom in ipairs(s.arrete or {}) do
                if cible.statuts[nom] then
                    cible.statuts[nom] = nil
                    fx[#fx + 1] = { kind = "statut_fin", id = cible.id, statut = nom }
                end
            end
            poser_statut(w, cible, "soin", s.duree_soin, fx, { hps = s.soin / s.duree_soin })
        end
    end

    ---------------------------------------------------------------- sprint, a terre

    function Combat.sprinter(w, id, oui)
        local f = combattant(w, id)
        if not en_vie(f) then return nil, "hors_combat" end
        oui = oui == true
        if oui and f.endurance < 5 then return nil, "epuise" end
        if f.sprint == oui then return {} end
        f.sprint = oui
        return { { kind = "sprint", id = id, actif = oui } }
    end

    function Combat.relever(w, aidant, cible)
        local a, c = combattant(w, aidant), combattant(w, cible)
        if not (en_vie(a) and c and c.etat == "a_terre") then return nil, "impossible" end
        if ennemis(w, a, c) then return nil, "ennemi" end
        if G.distance(a.pos, c.pos) > w.R.a_terre.distance then return nil, "trop_loin" end
        c.releve_par = { id = aidant, debut = w.t }
        return { { kind = "relever_debut", id = cible, aidant = aidant, duree = w.R.a_terre.relever } }
    end

    function Combat.achever(w, id, cible)
        local a, c = combattant(w, id), combattant(w, cible)
        if not (en_vie(a) and c and c.etat == "a_terre") then return nil, "impossible" end
        if not ennemis(w, a, c) then return nil, "allie" end
        if G.distance(a.pos, c.pos) > w.R.a_terre.distance then return nil, "trop_loin" end
        local fx = {}
        mourir(w, c, id, fx, "acheve")
        return fx
    end

    ---------------------------------------------------------------- temps

    -- Multiplicateur de vitesse du moment : armure, statuts, garde, arc bande.
    local function vitesse(w, f)
        if f.etat == "a_terre" then return 0.25 end
        if f.etat ~= "vivant" then return 0 end
        local v = (w.R.poids_armures[f.armure] or { vitesse = 1 }).vitesse
        if a_statut(w, f, "etourdi") then return 0 end
        local r = f.statuts.ralenti
        if r and r.fin > w.t then v = v * r.vitesse end
        if f.garde then v = v * 0.75 end
        if f.bande then v = v * 0.6 end
        if f.action and f.action.kind == "sort" then v = v * 0.5 end
        return math.floor(v * 100 + 0.5) / 100
    end

    local function avancer_combattant(w, f, dt, fx)
        local t = w.t
        -- Statuts : degats et soins dans le temps, fins.
        for nom, s in pairs(f.statuts) do
            if s.fin <= t then
                f.statuts[nom] = nil
                fx[#fx + 1] = { kind = "statut_fin", id = f.id, statut = nom }
            elseif en_vie(f) then
                if s.dps then
                    s.cumul = (s.cumul or 0) + s.dps * dt
                    if s.cumul >= 1 then
                        local n = math.floor(s.cumul)
                        s.cumul = s.cumul - n
                        blesser(w, f, n, nom == "brulure" and "magique" or "tranchant", "torse", nil, fx)
                    end
                elseif s.hps then
                    f.sante = math.min(f.sante_max, f.sante + s.hps * dt)
                end
            end
        end

        if f.etat == "a_terre" then
            local r = f.releve_par
            if r then
                local a = combattant(w, r.id)
                if not (en_vie(a) and G.distance(a.pos, f.pos) <= w.R.a_terre.distance)
                    or a.dernier_choc >= r.debut then
                    f.releve_par = nil
                    fx[#fx + 1] = { kind = "relever_annule", id = f.id }
                elseif t - r.debut >= w.R.a_terre.relever then
                    f.releve_par, f.etat, f.a_terre_fin = nil, "vivant", nil
                    f.sante = w.R.a_terre.sante_relevee
                    fx[#fx + 1] = { kind = "releve", id = f.id, aidant = r.id }
                end
            end
            if f.etat == "a_terre" and t >= (f.a_terre_fin or t) then mourir(w, f, nil, fx, "saignement") end
            return
        end
        if not en_vie(f) then return end

        -- Action en cours.
        local a = f.action
        if a and a.kind == "attaque" then
            if a.phase == "armement" and t >= a.fin_armement then
                a.phase = "frappe"
                fx[#fx + 1] = { kind = "frappe", id = f.id }
            end
            if a.phase == "frappe" then
                frapper(w, f, fx)
                if f.action == a and t >= a.fin_frappe then a.phase = "recuperation" end
            end
            if f.action == a and t >= a.fin then f.action = nil end
        elseif a and a.kind == "sort" and t >= a.fin then
            f.action = nil
            lancer_sort(w, f, a, fx)
        end
        if f.esquive and t >= f.esquive.fin then f.esquive = nil end
        if f.recharge_fin and t >= f.recharge_fin then
            f.recharge_fin = nil
            local arme = A[f.arme]
            if arme and arme.chargeur then f.munitions = arme.chargeur end
            fx[#fx + 1] = { kind = "recharge_fin", id = f.id, munitions = f.munitions }
        end

        -- Arc bande trop longtemps : le bras fatigue.
        local arme = A[f.arme]
        if f.bande and arme and arme.fatigue_apres and t - f.bande.debut > arme.fatigue_apres then
            depenser(w, f, arme.fatigue_cout * dt)
            if f.endurance <= 0 then
                f.bande = nil
                fx[#fx + 1] = { kind = "bande_fin", id = f.id }
            end
        end

        -- Sprint.
        local c = w.R.combattant
        if f.sprint then
            depenser(w, f, c.sprint_cout * dt)
            if f.endurance <= 0 then
                f.sprint = false
                fx[#fx + 1] = { kind = "sprint", id = f.id, actif = false }
            end
        end

        -- Recuperation.
        if t - f.dernier_effort >= c.endurance_delai then
            local k = f.garde and c.endurance_regen_garde or 1
            f.endurance = math.min(f.endurance_max, f.endurance + c.endurance_regen * k * dt)
        end
        if t - f.dernier_choc_posture >= c.posture_delai then
            f.posture = math.max(0, f.posture - c.posture_regen * dt)
        end
        f.mana = math.min(f.mana_max, f.mana + c.mana_regen * dt)
    end

    function Combat.avancer(w, dt)
        w.t = w.t + dt
        local fx = {}
        -- Ordre stable : les combattants par identifiant.
        local ids = {}
        for id in pairs(w.combattants) do ids[#ids + 1] = id end
        table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
        for _, id in ipairs(ids) do
            local f = w.combattants[id]
            if f then avancer_combattant(w, f, dt, fx) end
        end
        avancer_projectiles(w, dt, fx)
        for _, id in ipairs(ids) do
            local f = w.combattants[id]
            if f then
                local v = vitesse(w, f)
                if v ~= f.vitesse_annoncee then
                    f.vitesse_annoncee = v
                    fx[#fx + 1] = { kind = "vitesse", id = id, mult = v }
                end
            end
        end
        return fx
    end

    ---------------------------------------------------------------- lecture

    -- Ce que le HUD d'un combattant montre.
    function Combat.etat(w, id)
        local f = combattant(w, id)
        if not f then return nil end
        local statuts = {}
        for nom, s in pairs(f.statuts) do
            if s.fin > w.t then statuts[#statuts + 1] = { nom = nom, reste = s.fin - w.t } end
        end
        table.sort(statuts, function(a, b) return a.nom < b.nom end)
        local arme = A[f.arme]
        return {
            sante = f.sante, sante_max = f.sante_max, endurance = f.endurance, endurance_max = f.endurance_max,
            posture = f.posture, posture_max = f.posture_max, mana = f.mana, mana_max = f.mana_max,
            etat = f.etat, arme = f.arme, armure = f.armure, munitions = f.munitions,
            chargeur = arme and arme.chargeur, recharge = f.recharge_fin and (f.recharge_fin - w.t) or nil,
            garde = f.garde and f.garde.dir or nil, action = f.action and (f.action.phase or f.action.kind) or nil,
            statuts = statuts, vitesse = vitesse(w, f),
        }
    end

    Combat.vitesse = function(w, id)
        local f = combattant(w, id)
        return f and vitesse(w, f) or 0
    end

    return Combat
end
