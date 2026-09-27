-- Ce qui se passe dans les jeux, pour l'ecran d'accueil (domain/accueil.lua) :
-- le resume des salons et parties de chaque jeu inscrit, et le fil des
-- derniers gains. Pur : aucun appel au moteur, teste dans tests/suites/activite.lua.

return function()
    local Activite = {}

    -- Cle de jeu (prefixe des identifiants de partie) -> nom affiche.
    local JEUX = {
        werewolf = { nom = "Loup-garou", dans = "au loup-garou" },
        liars    = { nom = "Liar's Bar", dans = "au Liar's Bar" },
        duel     = { nom = "Duel", dans = "en duel" },
    }
    local MAX_GAINS = 10

    local inscrits = {}          -- { { cle, resume } }, dans l'ordre d'inscription
    local derniere = nil         -- signature du dernier resume rendu par Changement
    local gains = {}             -- plus recent d'abord

    -- resume() rend une liste de { statut, joueurs, bots, max, mise, detail }.
    function Activite.Inscrire(cle, resume)
        inscrits[#inscrits + 1] = { cle = cle, resume = resume }
    end

    function Activite.Resume(en_ligne)
        local lignes = {}
        for _, j in ipairs(inscrits) do
            -- Un jeu qui plante, ou rend une ligne mal formee, ne doit pas
            -- vider le tableau des autres : tout son resume est protege.
            pcall(function()
                local liste = j.resume()
                if type(liste) ~= "table" then return end
                local siennes = {}
                for _, l in ipairs(liste) do
                    if type(l) == "table" then
                        siennes[#siennes + 1] = {
                            jeu = JEUX[j.cle] and JEUX[j.cle].nom or tostring(j.cle),
                            statut = l.statut, joueurs = tonumber(l.joueurs) or 0, bots = tonumber(l.bots) or 0,
                            max = l.max, mise = tonumber(l.mise) or 0, detail = l.detail,
                        }
                    end
                end
                for _, l in ipairs(siennes) do lignes[#lignes + 1] = l end
            end)
        end
        return { lignes = lignes, en_ligne = en_ligne or 0 }
    end

    local function signature(r)
        local t = { tostring(r.en_ligne) }
        for _, l in ipairs(r.lignes) do
            t[#t + 1] = table.concat({ l.jeu, tostring(l.statut), l.joueurs, l.bots, tostring(l.max), l.mise,
                tostring(l.detail) }, "|")
        end
        return table.concat(t, ";")
    end

    -- Le resume s'il a change depuis le dernier rendu, sinon nil.
    function Activite.Changement(en_ligne)
        local r = Activite.Resume(en_ligne)
        local s = signature(r)
        if s == derniere then return nil end
        derniere = s
        return r
    end

    function Activite.JeuDePartie(partie)
        local cle = tostring(partie or ""):match("^(%w+):")
        return cle and JEUX[cle] or nil
    end

    function Activite.AjouterGain(nom, partie, montant)
        local jeu = Activite.JeuDePartie(partie)
        if not jeu or type(montant) ~= "number" or montant <= 0 then return nil end
        local g = { nom = nom or "Quelqu'un", jeu = jeu.nom, dans = jeu.dans, montant = montant }
        table.insert(gains, 1, g)
        while #gains > MAX_GAINS do table.remove(gains) end
        return g
    end

    function Activite.Gains()
        local copie = {}
        for i, g in ipairs(gains) do copie[i] = g end
        return copie
    end

    return Activite
end
