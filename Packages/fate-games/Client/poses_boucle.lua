-- Poses en boucle rejouees par chaque client : PNJ (Server/domain/pnj.lua,
-- valeur pose_boucle) et assis du loup-garou, joueurs comme bots (ww_pose).
-- Un PlayAnimation lance par le serveur n'atteint pas le joueur qui se
-- connecte, ou qui voit le corps apparaitre, plus tard : 27/09, les PNJ
-- perdaient leur pose a la reconnexion. Le serveur ecrit la pose dans une
-- valeur synchronisee ; ce script la rejoue localement, et l'arrete quand
-- elle disparait.

return function()
    local jouee = setmetatable({}, { __mode = "k" })   -- corps -> animation rejouee ici

    local function suivre(liste)
        for _, c in pairs(liste) do
            if c:IsValid() then
                local anim = c:GetValue("pose_boucle", nil) or c:GetValue("ww_pose", nil)
                if anim ~= jouee[c] then
                    local avant = jouee[c]
                    if avant then pcall(function() c:StopAnimation(avant) end) end
                    if anim then
                        pcall(function() c:PlayAnimation(anim, "DefaultSlot", true, 0.2, 0.2, 1.0, true) end)
                    end
                    jouee[c] = anim
                end
            end
        end
    end

    Timer.SetInterval(function()
        suivre(CharacterSimple.GetAll())
        pcall(function() suivre(Character.GetAll()) end)
    end, 500)
end
