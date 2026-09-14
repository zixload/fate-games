-- Micro-framework de test. Volontairement minimal : pas de dependance, pas d'installation,
-- juste de quoi grouper des cas, comparer des valeurs et sortir avec un code d'erreur
-- exploitable par une CI.

local Harness = {}

local suite_name = nil
local passed     = 0
local failures   = {}

function Harness.describe(name, fn)
    suite_name = name
    print("")
    print(name)
    fn()
    suite_name = nil
end

function Harness.it(name, fn)
    local label = (suite_name or "?") .. " > " .. name
    local ok, err = pcall(fn)

    if ok then
        passed = passed + 1
        print("  ok   " .. name)
    else
        failures[#failures + 1] = { label = label, err = err }
        print("  ECHEC " .. name)
        print("        " .. tostring(err))
    end
end

-- Les assertions remontent l'erreur au niveau de l'appelant pour que le message
-- pointe la ligne du test et non celle du harnais.
local function fail(message)
    error(message, 3)
end

function Harness.assert_eq(actual, expected, label)
    if actual ~= expected then
        fail(("%s : attendu <%s>, obtenu <%s>")
            :format(label or "valeur", tostring(expected), tostring(actual)))
    end
end

function Harness.assert_true(value, label)
    if not value then
        fail(("%s : attendu vrai, obtenu <%s>"):format(label or "valeur", tostring(value)))
    end
end

function Harness.assert_false(value, label)
    if value then
        fail(("%s : attendu faux, obtenu <%s>"):format(label or "valeur", tostring(value)))
    end
end

function Harness.assert_nil(value, label)
    if value ~= nil then
        fail(("%s : attendu nil, obtenu <%s>"):format(label or "valeur", tostring(value)))
    end
end

function Harness.assert_count(tbl, expected, label)
    local n = 0
    for _ in pairs(tbl) do n = n + 1 end
    if n ~= expected then
        fail(("%s : attendu %d element(s), obtenu %d"):format(label or "table", expected, n))
    end
end

-- Verifie qu'un appel leve bien une erreur, et accessoirement qu'elle contient un motif.
function Harness.assert_error(fn, pattern)
    local ok, err = pcall(fn)
    if ok then
        fail("attendu une erreur, aucune levee")
    end
    if pattern and not tostring(err):find(pattern, 1, true) then
        fail(("erreur attendue contenant <%s>, obtenu <%s>"):format(pattern, tostring(err)))
    end
end

function Harness.report()
    print("")
    print(("%d test(s) ok, %d echec(s)"):format(passed, #failures))

    if #failures > 0 then
        print("")
        for _, f in ipairs(failures) do
            print("  - " .. f.label)
        end
        return 1
    end
    return 0
end

return Harness
