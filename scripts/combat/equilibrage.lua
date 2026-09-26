-- Equilibrage du combat : fait se battre des bots (combat/ia.lua) sur 100
-- combats par affiche et donne les victoires, la duree, les parades, blocages,
-- esquives, gardes brisees, feintes et coups portes.
--
--     lua scripts/combat/equilibrage.lua          depuis la racine du depot
--
-- Les bots ne jouent pas comme des humains : c'est un garde-fou (une arme qui
-- gagne 95 % du temps a un probleme), pas le dernier mot de l'equilibre.

local root = "."
local PACKAGE = root .. "/Packages/fate-games"
_G.Package = { Require = (function()
  local cache = {}
  return function(p) if cache[p] then return cache[p] end local r = dofile(PACKAGE .. "/Server/" .. p) cache[p] = r return r end
end)() }
local Combat = Package.Require("combat/init.lua")
local G = Combat.geometrie
local function lcg(g) local x = g return function(k) x = (x * 1103515245 + 12345) % 2147483648 return (x // 65536) % k + 1 end end
local function combat(aa, na, ab, nb, graine)
  local r = lcg(graine)
  local w = Combat.nouveau()
  Combat.ajouter(w, "a", { arme = aa, pos = G.v(0, 0, 90), yaw = 0 })
  Combat.ajouter(w, "b", { arme = ab, pos = G.v(600, 0, 90), yaw = 180 })
  local mem, niv = { a = {}, b = {} }, { a = na, b = nb }
  local stats = { pare = 0, bloque = 0, esquive_reussie = 0, degats = 0, garde_brisee = 0, feinte = 0 }
  for i = 1, 20 * 180 do
    local decs = {}
    for _, id in ipairs({ "a", "b" }) do decs[id] = Combat.ia.decider(Combat, w, id, r, mem[id], niv[id]) end
    local nouvelles = {}
    for _, id in ipairs({ "a", "b" }) do
      local f, dec = w.combattants[id], decs[id]
      if dec.regard and f.etat == "vivant" then
        local v = G.moins(dec.aller_vers or dec.regard, f.pos)
        local d = math.sqrt(v.x * v.x + v.y * v.y)
        local pas = 0
        if dec.distance and d > dec.distance then pas = math.min(d - dec.distance, 300 * 0.05 * Combat.vitesse(w, id)) end
        local dir = d > 0 and G.fois(G.v(v.x, v.y, 0), 1 / d) or G.v()
        nouvelles[id] = { G.plus(f.pos, G.fois(dir, pas)), G.lacet_vers(f.pos, dec.regard) }
      end
    end
    for id, n in pairs(nouvelles) do Combat.placer(w, id, n[1], n[2], 0) end
    for _, id in ipairs({ "a", "b" }) do
      for _, e in ipairs(Combat.ia.executer(Combat, w, id, decs[id], r, niv[id])) do if stats[e.kind] then stats[e.kind] = stats[e.kind] + 1 end end
    end
    for _, e in ipairs(Combat.avancer(w, 0.05)) do if stats[e.kind] then stats[e.kind] = stats[e.kind] + 1 end end
    if w.combattants.a.etat ~= "vivant" or w.combattants.b.etat ~= "vivant" then
      return (w.combattants.a.etat ~= "vivant") and "b" or "a", i * 0.05, stats, true
    end
  end
  return "timeout", 180, stats, false
end
for _, cas in ipairs({ { "epee_longue", "difficile", "epee_longue", "facile" }, { "epee_courte", "normal", "epee_courte", "normal" },
    { "poings", "normal", "poings", "normal" }, { "masse", "normal", "dague", "normal" }, { "epee_longue", "normal", "epee_bouclier", "normal" },
    { "hache", "normal", "lance", "normal" }, { "dague", "normal", "masse", "normal" }, { "epee_bouclier", "normal", "epee_longue", "normal" },
    { "poings", "normal", "poings", "normal" }, { "pistolet", "normal", "epee_courte", "normal" }, { "arc", "normal", "epee_courte", "normal" } }) do
  local v, duree, morts = { a = 0, b = 0, timeout = 0 }, 0, 0
  local tot = {}
  for g = 1, 100 do
    local r, d, st, mort = combat(cas[1], cas[2], cas[3], cas[4], g)
    v[r] = v[r] + 1; duree = duree + d; if mort then morts = morts + 1 end
    for k, n in pairs(st) do tot[k] = (tot[k] or 0) + n end
  end
  print(("%-14s %-9s vs %-14s %-9s : a %2d  b %2d  temps %2d | duree moy %5.1f s | pare %4.1f bloque %4.1f esquive %4.1f brisee %3.1f feinte %3.1f coups %4.1f"):format(
    cas[1], cas[2], cas[3], cas[4], v.a, v.b, v.timeout, duree / 100, tot.pare / 100, tot.bloque / 100, tot.esquive_reussie / 100, tot.garde_brisee / 100, tot.feinte / 100, tot.degats / 100))
end
