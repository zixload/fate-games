-- Etat affiche par le HUD provisoire de Liar's Bar.
--
-- Pur : aucune globale nanos, donc testable hors jeu. Il recoit les
-- evenements du serveur sous leur nom court et tient ce qu'il faut dessiner.
-- Il ne juge rien du jeu : le serveur tranche, le journal raconte.

return function(config)
    local Journal = {}

    local RANGS = { king = "Roi", queen = "Dame", ace = "As", joker = "Joker" }

    local RAISONS = {
        partie_en_cours      = "une partie est en cours",
        place_occupee        = "cette place est prise",
        pas_assis            = "il faut être assis pour lancer",
        pas_assez_de_joueurs = "pas assez de joueurs",
        pas_a_table          = "tu n'es pas à la table",
        aucune_partie        = "aucune partie en cours",
        charge_invalide      = "demande invalide",
        demarrage_impossible = "la partie n'a pas pu démarrer",
    }

    function Journal.RankName(r)
        return RANGS[r] or tostring(r)
    end

    function Journal.New()
        local j = {
            my_chair   = nil,
            names      = {},
            table_rank = nil,
            turn       = nil,
            hand       = {},
            lines      = {},
        }
        local selected = {}    -- indice -> true
        local pending  = nil   -- indices envoyes, en attente de confirmation

        local function qui(chair)
            if chair == nil then return "?" end
            local nom = j.names[chair]
            if nom then return ("%s (chaise %d)"):format(nom, chair) end
            return ("chaise %d"):format(chair)
        end

        local function ligne(text, kind)
            j.lines[#j.lines + 1] = { text = text, kind = kind or "info" }
            while #j.lines > config.journal_lines do
                table.remove(j.lines, 1)
            end
        end

        local function refus(code, contexte)
            local texte = RAISONS[code] or tostring(code)
            if code == "pas_assez_de_joueurs" and type(contexte) == "table" then
                texte = ("%s (%s/%s)"):format(texte, tostring(contexte.assis), tostring(contexte.minimum))
            end
            ligne("Refusé : " .. texte, "refus")
        end

        local function hors_partie()
            j.hand, j.table_rank, j.turn = {}, nil, nil
            selected, pending = {}, nil
        end

        local H = {}

        H.seated = function(chair, name, is_me)
            j.names[chair] = name
            if is_me then j.my_chair = chair end
            ligne(("%s s'assoit, chaise %d"):format(tostring(name or "?"), chair))
        end

        H.unseated = function(chair)
            ligne(("Chaise %d libérée"):format(chair))
            j.names[chair] = nil
            if j.my_chair == chair then
                j.my_chair = nil
                hors_partie()
            end
        end

        H.started = function(list)
            hors_partie()
            ligne(("Partie lancée : %d joueurs"):format(#(list or {})))
        end

        H.deal = function(cards)
            j.hand = {}
            for i, c in ipairs(cards or {}) do j.hand[i] = c end
            selected, pending = {}, nil
            ligne(("Tu reçois %d cartes"):format(#j.hand))
        end

        H.table_card = function(r)
            j.table_rank = r
            ligne("Carte de table : " .. Journal.RankName(r))
        end

        H.turn = function(chair)
            j.turn = chair
            selected = {}
            if chair ~= nil and chair == j.my_chair then
                ligne("Tour : à toi !")
            else
                ligne("Tour : " .. qui(chair))
            end
        end

        H.cards_played = function(chair, count)
            ligne(("%s pose %d carte(s)"):format(qui(chair), count))
            if chair == j.my_chair and pending then
                table.sort(pending, function(a, b) return a > b end)
                for _, i in ipairs(pending) do table.remove(j.hand, i) end
                pending = nil
            end
        end

        H.accuse = function(accuser, target)
            ligne(("%s accuse %s"):format(qui(accuser), qui(target)))
        end

        H.reveal = function(chair, cards)
            local noms = {}
            for i, c in ipairs(cards or {}) do noms[i] = Journal.RankName(c) end
            ligne(("Révélé chez %s : %s"):format(qui(chair), table.concat(noms, ", ")))
        end

        H.designated = function(chair)
            if chair ~= nil and chair == j.my_chair then
                ligne("Tu dois tirer : E sur le revolver")
            else
                ligne(qui(chair) .. " doit tirer")
            end
        end

        H.shoot = function(chair, chamber, fatal)
            ligne(("%s tire… %s"):format(qui(chair), fatal and "BANG" or "à blanc"))
        end

        H.eliminated = function(chair)
            ligne(qui(chair) .. " est éliminé")
        end

        H.round_ended = function()
            j.turn = nil
            selected = {}
            ligne("Fin de manche")
        end

        H.match_ended = function(winner)
            hors_partie()
            if winner then
                ligne("Victoire : " .. qui(winner))
            else
                ligne("Partie terminée sans vainqueur")
            end
        end

        H.refused = function(code, contexte)
            refus(code, contexte)
        end

        H.intent_result = function(name, ok, detail)
            if name ~= "liars_play" and name ~= "liars_challenge" then return end
            if ok then return end
            if name == "liars_play" then pending = nil end
            refus(type(detail) == "table" and detail.audit or detail)
        end

        function j:On(event, ...)
            local handler = H[event]
            if handler then handler(...) end
        end

        function j:IsMyTurn()
            return j.my_chair ~= nil and j.turn == j.my_chair
        end

        function j:Who(chair)
            return qui(chair)
        end

        function j:Selection()
            local out = {}
            for i in pairs(selected) do out[#out + 1] = i end
            table.sort(out)
            return out
        end

        function j:IsSelected(i)
            return selected[i] == true
        end

        -- Choisir ou retirer une carte. Refuse hors de son tour, hors de la
        -- main et au-dela du plafond : rend vrai si la selection a change.
        function j:Toggle(i)
            if not j:IsMyTurn() then return false end
            if i < 1 or i > #j.hand then return false end
            if selected[i] then
                selected[i] = nil
                return true
            end
            if #j:Selection() >= config.max_play then return false end
            selected[i] = true
            return true
        end

        -- La pose part vers le serveur : la main n'est retouchee qu'a sa
        -- confirmation, par cards_played pour ma chaise.
        function j:MarkPending(indices)
            pending = indices
            selected = {}
        end

        return j
    end

    return Journal
end
