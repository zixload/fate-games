-- Cerveau d'un combattant bot (docs/COMBAT.md), en Lua pur : il ne voit que
-- ce que le moteur sait et joue avec les memes intentions qu'un joueur.
-- Il reagit a ce qu'il voit venir apres un temps de reaction, avec une
-- chance de bien lire le coup : c'est le niveau.
--
--     local decision = IA.decider(Combat, w, id, rng, memoire, niveau)
--     -- decision.aller_vers : position a rejoindre (ou nil)
--     -- decision.distance   : distance a garder de la cible
--     -- decision.regard     : position a regarder
--     -- decision.intentions : { { "attaquer", "legere", "droite" }, ... }

local IA = {}

IA.niveaux = {
    facile    = { reaction = 0.45, lecture = 0.35, parade = 0.1, agressivite = 0.35, feinte = 0.02 },
    normal    = { reaction = 0.3,  lecture = 0.6,  parade = 0.25, agressivite = 0.55, feinte = 0.06 },
    difficile = { reaction = 0.18, lecture = 0.85, parade = 0.5, agressivite = 0.75, feinte = 0.12 },
}

local MIROIR = { gauche = "droite", droite = "gauche", haut = "haut" }
local DIRS = { "gauche", "droite", "haut" }

local function distance_plane(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function plus_proche(w, f)
    local meilleur, md
    for _, c in pairs(w.combattants) do
        if c ~= f and c.etat == "vivant" and (c.camp ~= f.camp) then
            local d = distance_plane(f.pos, c.pos)
            if not md or d < md then meilleur, md = c, d end
        end
    end
    return meilleur, md
end

function IA.decider(Combat, w, id, rng, memoire, niveau)
    local f = w.combattants[id]
    local n = IA.niveaux[niveau or "normal"] or IA.niveaux.normal
    local d = { intentions = {} }
    if not (f and f.etat == "vivant") then return d end
    local cible, dist = plus_proche(w, f)
    if not cible then return d end
    d.regard, d.cible = cible.pos, cible.id
    local A = Combat.armes
    local arme = A[f.arme] or A.poings
    local function veut(...) d.intentions[#d.intentions + 1] = { ... } end
    local function hasard(p) return rng(1000) <= p * 1000 end

    if arme.famille == "melee" then
        d.aller_vers, d.distance = cible.pos, arme.portee * 0.75

        -- Une attaque arrive : la voir (apres le temps de reaction), la lire.
        local a = cible.action
        if a and a.kind == "attaque" and a.phase == "armement" and dist <= (A[a.arme] or arme).portee + 60 then
            memoire.vue = memoire.vue or {}
            local cle = tostring(a.debut)
            -- La reaction se compte depuis le debut de l'armement, pas depuis le
            -- moment ou ce bot y pense : sinon l'ordre de passage des bots decide.
            if not memoire.vue[cle] then memoire.vue[cle] = { t = a.debut, lu = hasard(n.lecture) } end
            local vue = memoire.vue[cle]
            if vue.lu and w.t - vue.t >= n.reaction then
                if a.force == "bousculade" then
                    -- Une bousculade ne se bloque pas : on l'esquive.
                    if f.endurance > 25 and not memoire.esquive_bousculade then
                        veut("esquiver", "arriere")
                        memoire.esquive_bousculade = true
                    end
                elseif a.force == "lourde" and f.endurance > 40 and hasard(0.35) then
                    veut("esquiver", "arriere")
                else
                    -- Parer, c'est poser la garde au dernier moment ; sinon bloquer.
                    local reste = a.fin_armement - w.t
                    if not f.garde or f.garde.dir ~= MIROIR[a.dir] then
                        if reste > 0.2 and hasard(n.parade) then
                            memoire.parer = { dir = MIROIR[a.dir], a = a.fin_armement - 0.1 }
                        else
                            veut("garder", MIROIR[a.dir])
                        end
                    end
                end
            end
        end
        if not (a and a.force == "bousculade") then memoire.esquive_bousculade = nil end
        if memoire.parer and w.t >= memoire.parer.a then
            veut("garder", memoire.parer.dir)
            memoire.parer = nil
        end

        -- Attaquer quand on est a portee et libre.
        if not f.action and dist <= arme.portee and not (a and a.kind == "attaque") then
            if f.garde and hasard(0.5) then veut("lacher_garde") end
            -- Une garde tenue de pres : la bousculer.
            if cible.garde and dist <= 120 and f.endurance > 30 and hasard(n.agressivite * 0.06) then
                veut("bousculer")
            elseif hasard(n.agressivite * 0.12) then
                -- Contre un bouclier leve, les lourdes cassent la garde.
                local arme_c = A[cible.arme]
                local bouclier = cible.garde and arme_c and arme_c.famille == "melee" and arme_c.garde.bouclier
                local force = (f.endurance > 45 and hasard(bouclier and 0.75 or 0.3)) and "lourde" or "legere"
                veut("attaquer", force, DIRS[rng(3)])
                memoire.feinte = hasard(n.feinte) and w.t + 0.12 or nil
            end
        end
        if memoire.feinte and w.t >= memoire.feinte then
            veut("feinter")
            memoire.feinte = nil
        end
        -- Le bouclier couvre tout le devant : on le garde leve, on riposte.
        if arme.garde.bouclier and not f.action and not f.garde and f.endurance > 25 and not memoire.feinte
            and (#d.intentions == 0) and hasard(0.2) then
            veut("garder", "droite")
        end
        -- Epuise : reculer et souffler.
        if f.endurance < 15 then d.distance = arme.portee * 2 end
    elseif arme.famille == "tir" then
        d.aller_vers, d.distance = cible.pos, math.min(arme.portee * 0.4, 1500)
        if f.munitions <= 0 and not f.recharge_fin then
            veut("recharger")
        elseif w.t - f.dernier_tir >= arme.cadence and hasard(n.agressivite * 0.3) then
            veut("tirer")
        end
    elseif arme.famille == "arc" then
        d.aller_vers, d.distance = cible.pos, 1200
        if not f.bande and not f.recharge_fin then
            veut("bander")
        elseif f.bande and w.t - f.bande.debut >= (arme.charge > 0 and arme.charge or 0) + 0.1 then
            veut("decocher")
        end
    end

    -- Un peu de magie a distance, si le mana le permet.
    if dist > 500 and f.mana >= 40 and not f.action and hasard(0.01 * n.agressivite) then
        veut("incanter", "trait_de_feu")
    end
    return d
end

-- Execute les intentions d'une decision avec le moteur ; rend les effets.
-- Les tirs partent des yeux vers la cible, avec l'imprecision du niveau.
function IA.executer(Combat, w, id, decision, rng, niveau)
    local f = w.combattants[id]
    local fx = {}
    if not f then return fx end
    local G = Combat.geometrie
    local n = IA.niveaux[niveau or "normal"] or IA.niveaux.normal
    local function ajouter(r) for _, e in ipairs(r or {}) do fx[#fx + 1] = e end end
    local oeil = G.v(f.pos.x, f.pos.y, f.pos.z + w.R.tir.oeil.z)
    local cible = decision.regard
    for _, it in ipairs(decision.intentions or {}) do
        local quoi = it[1]
        if quoi == "tirer" or quoi == "decocher" then
            if cible then
                local erreur = (1 - n.lecture) * 60
                local vise = G.v(cible.x + (rng(100) - 50) / 50 * erreur, cible.y + (rng(100) - 50) / 50 * erreur,
                    cible.z + 20 + (rng(100) - 50) / 50 * erreur)
                local dir = G.moins(vise, oeil)
                if quoi == "tirer" then
                    ajouter(Combat.tirer(w, id, { origine = oeil, direction = dir, cible = decision.cible, ping = 0 }))
                else
                    ajouter(Combat.decocher(w, id, oeil, dir))
                end
            end
        elseif Combat[quoi] then
            ajouter(Combat[quoi](w, id, it[2], it[3]))
            -- Un bot decide de sa garde a chaque instant : pas de garde tenue
            -- qui reviendrait seule (c'est pour le joueur qui tient le clic).
            if quoi == "garder" then f.garde_tenue = nil end
        end
    end
    return fx
end

return IA
