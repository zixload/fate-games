-- Le jugement d'une contestation.
--
-- On revele UNIQUEMENT la derniere pose. Si toutes ses cartes sont la carte de
-- table ou des jokers, la pretention etait vraie et c'est l'accusateur qui
-- tire ; si une seule est intruse, c'est le menteur. Un seul jugement, aucune
-- ambiguite.
--
-- Ce module ne sait pas ce qu'est un barillet, ni une manche. Il designe un
-- perdant, rien de plus.

return function(Deck)
    local Challenge = {}

    function Challenge.Resolve(cards, rank)
        if #cards == 0 then
            error("pose vide : rien a juger")
        end

        for _, card in ipairs(cards) do
            if not Deck.Matches(card, rank) then
                return "liar"
            end
        end

        return "accuser"
    end

    return Challenge
end
