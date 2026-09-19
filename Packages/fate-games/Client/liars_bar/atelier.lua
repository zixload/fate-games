-- Branchement sur l'atelier (panneau dev, F2), s'il est charge.
--
-- L'eventail et le tas deviennent reglables a la souris, en direct. Les
-- valeurs arrivent par "atelier:reglage_change" ; enregistrees dans le
-- panneau, elles reviennent a chaque connexion. Sans atelier, rien ne se
-- passe : les evenements partent dans le vide.

return function(config, rendu)
    -- Un champ par nombre reglable ; pas = increment de base du bouton.
    local function champ(chemin, label, pas)
        return { chemin = chemin, label = label, pas = pas }
    end

    local DECLARATIONS = {
        {
            id = "liars.eventail", label = "Éventail (ma main)", valeurs = config.fan,
            champs = {
                champ("pos.x", "Avant", 1), champ("pos.y", "Côté", 1), champ("pos.z", "Hauteur", 1),
                champ("rot.p", "Tangage", 1), champ("rot.y", "Lacet", 1), champ("rot.r", "Roulis", 1),
                champ("carte.p", "Carte : tangage", 1), champ("carte.y", "Carte : lacet", 1),
                champ("carte.r", "Carte : roulis", 1),
                champ("ecart", "Écart entre cartes", 1), champ("rayon", "Rayon de l'arc", 0.5),
                champ("taille", "Taille", 0.001), champ("levee", "Levée (choisie)", 0.5),
                champ("curseur", "Levée (curseur)", 0.5),
            },
        },
        {
            id = "liars.table", label = "Tas de la table", valeurs = config.table,
            champs = {
                champ("decalage.x", "Tas : x", 1), champ("decalage.y", "Tas : y", 1),
                champ("decalage.z", "Tas : hauteur", 0.1),
                champ("dos.p", "Face cachée : tangage", 1), champ("dos.y", "Face cachée : lacet", 1),
                champ("dos.r", "Face cachée : roulis", 1),
                champ("face.p", "Révélée : tangage", 1), champ("face.y", "Révélée : lacet", 1),
                champ("face.r", "Révélée : roulis", 1),
                champ("epaisseur", "Épaisseur du tas", 0.05), champ("dispersion", "Désordre", 0.5),
                champ("ecart_revelation", "Écart des révélées", 0.5),
            },
        },
    }

    local CIBLES = { ["liars.eventail"] = config.fan, ["liars.table"] = config.table }

    -- Recopie les seuls nombres deja presents : une valeur recue ne cree
    -- jamais de champ.
    local function appliquer(cible, source)
        for cle, valeur in pairs(source or {}) do
            local actuel = cible[cle]
            if type(actuel) == "number" and type(valeur) == "number" then
                cible[cle] = valeur
            elseif type(actuel) == "table" and type(valeur) == "table" then
                appliquer(actuel, valeur)
            end
        end
    end

    Events.Subscribe("atelier:reglage_change", function(id, valeurs)
        local cible = CIBLES[id]
        if not cible then return end
        appliquer(cible, valeurs)
        rendu.Reconstruire()
    end)

    local function declarer()
        Events.Call("atelier:declarer_reglages", DECLARATIONS)
    end
    Events.Subscribe("atelier:pret", declarer)
    declarer()
end
