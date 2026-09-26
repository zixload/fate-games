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
        pas_ton_revolver     = "ce revolver appartient à une autre place",
        tir_en_cours         = "le coup est en cours",
        pas_designe          = "ce n'est pas ton tir",
        arme_deja_prise      = "revolver déjà en main",
        arme_non_preparee    = "prends d'abord ton revolver",
        arme_pas_prete       = "attends que le revolver soit en place",
        aucun_tir_en_attente = "aucun tir en attente",
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
            designated = nil,
            gun_ready  = false,
            hand       = {},
            lines      = {},
            cursor     = nil,  -- carte de ma main sous le curseur (molette)
            counts     = {},   -- chaise -> cartes en main, information publique
            pile       = {},   -- poses de la manche : { chair, count }
            revealed   = nil,  -- derniere revelation : { chair, cards }
            version    = 0,    -- change a chaque modification ; le rendu la surveille
        }
        local selected = {}    -- indice -> true
        local pending  = nil   -- indices envoyes, en attente de confirmation
        local en_jeu   = {}    -- chaises de la partie en cours
        local morts    = {}    -- chaises eliminees

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
            j.designated, j.gun_ready = nil, false
            j.cursor, j.counts, j.pile, j.revealed = nil, {}, {}, nil
            selected, pending = {}, nil
        end

        -- Le curseur reste dans la main : il suit une main qui retrecit.
        local function borner_curseur()
            if #j.hand == 0 then
                j.cursor = nil
            elseif not j.cursor or j.cursor > #j.hand then
                j.cursor = math.min(j.cursor or 1, #j.hand)
            end
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
            en_jeu, morts = {}, {}
            for _, entree in ipairs(list or {}) do en_jeu[entree.chair] = true end
            ligne(("Partie lancée : %d joueurs"):format(#(list or {})))
        end

        H.deal = function(cards)
            j.hand = {}
            for i, c in ipairs(cards or {}) do j.hand[i] = c end
            selected, pending = {}, nil
            j.cursor = #j.hand > 0 and 1 or nil
            ligne(("Tu reçois %d cartes"):format(#j.hand))
        end

        -- Chaque carte de table ouvre une manche : chaque joueur encore en vie
        -- recoit une main pleine, et le tas du centre repart de zero.
        H.table_card = function(r)
            j.table_rank = r
            j.pile, j.revealed = {}, nil
            for chair in pairs(en_jeu) do
                j.counts[chair] = morts[chair] and 0 or config.hand_size
            end
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
            j.counts[chair] = math.max(0, (j.counts[chair] or 0) - count)
            j.pile[#j.pile + 1] = { chair = chair, count = count }
            if chair == j.my_chair and pending then
                table.sort(pending, function(a, b) return a > b end)
                for _, i in ipairs(pending) do table.remove(j.hand, i) end
                pending = nil
                borner_curseur()
            end
        end

        H.accuse = function(accuser, target)
            ligne(("%s accuse %s"):format(qui(accuser), qui(target)))
        end

        H.reveal = function(chair, cards)
            local noms = {}
            for i, c in ipairs(cards or {}) do noms[i] = Journal.RankName(c) end
            local copie = {}
            for i, c in ipairs(cards or {}) do copie[i] = c end
            j.revealed = { chair = chair, cards = copie }
            ligne(("Révélé chez %s : %s"):format(qui(chair), table.concat(noms, ", ")))
        end

        H.designated = function(chair)
            j.designated, j.gun_ready = chair, false
            if chair ~= nil and chair == j.my_chair then
                ligne("Tu dois prendre ton revolver")
            else
                ligne(qui(chair) .. " doit tirer")
            end
        end

        H.shoot_prepare = function(chair)
            ligne(qui(chair) .. " prend son revolver…")
        end

        H.gun_ready = function(chair)
            if chair == j.my_chair then j.gun_ready = true end
        end

        H.gun_cancelled = function(chair)
            if chair == j.designated then
                j.designated, j.gun_ready = nil, false
            end
        end

        -- Le decompte de chaque barillet est public : on dit ou en est le tireur,
        -- et ce que vaudra son prochain tir.
        H.shoot = function(chair, chamber, fatal)
            j.designated, j.gun_ready = nil, false
            local total = config.chambers
            local suite
            if fatal then
                suite = ("tir %d sur %d"):format(chamber, total)
            elseif total - chamber <= 1 then
                suite = ("tir %d sur %d, le prochain est mortel"):format(chamber, total)
            else
                suite = ("tir %d sur %d, prochain : 1 chance sur %d")
                    :format(chamber, total, total - chamber)
            end
            ligne(("%s tire… %s (%s)"):format(qui(chair), fatal and "BANG" or "à blanc", suite))
        end

        H.eliminated = function(chair)
            morts[chair] = true
            j.counts[chair] = 0
            ligne(qui(chair) .. " est éliminé")
        end

        local FINS = {
            challenged = "Fin de manche : l'accusation est réglée",
            exhausted  = "Manche nulle : plus personne pour répondre à la dernière pose",
        }

        H.round_ended = function(reason)
            j.turn = nil
            j.designated, j.gun_ready = nil, false
            selected = {}
            ligne(FINS[reason] or "Fin de manche")
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
            if name ~= "liars_play" and name ~= "liars_challenge"
                and name ~= "liars_shoot" then return end
            if ok then return end
            if name == "liars_play" then pending = nil end
            if name == "liars_shoot" and j.designated == j.my_chair then
                j.gun_ready = true
            end
            refus(type(detail) == "table" and detail.audit or detail)
        end

        function j:On(event, ...)
            local handler = H[event]
            if handler then handler(...) end
            j.version = j.version + 1
        end

        -- Molette : le curseur tourne dans la main, a tout moment.
        function j:MoveCursor(delta)
            j.version = j.version + 1
            if #j.hand == 0 then return end
            local i = ((j.cursor or 1) - 1 + delta) % #j.hand
            j.cursor = i + 1
        end

        -- Clic : choisir ou retirer la carte sous le curseur.
        function j:ToggleCursor()
            if not j.cursor then return false end
            return j:Toggle(j.cursor)
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
                j.version = j.version + 1
                return true
            end
            if #j:Selection() >= config.max_play then return false end
            selected[i] = true
            j.version = j.version + 1
            return true
        end

        -- Une carte envoyee, en attente de la confirmation du serveur.
        function j:IsPending(i)
            for _, k in ipairs(pending or {}) do
                if k == i then return true end
            end
            return false
        end

        -- La pose part vers le serveur : la main n'est retouchee qu'a sa
        -- confirmation, par cards_played pour ma chaise.
        function j:MarkPending(indices)
            pending = indices
            selected = {}
            j.version = j.version + 1
        end

        return j
    end

    return Journal
end
