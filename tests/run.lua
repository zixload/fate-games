-- Lanceur du banc de test.
--
--     lua tests/run.lua              depuis la racine du depot
--     .\scripts\test.ps1             equivalent sous PowerShell
--
-- Ne demarre pas le serveur : les globales du moteur sont bouchonnees (voir stubs.lua),
-- et Package.Require est reimplemente ici pour charger les vrais fichiers du package.
--
-- Code de sortie 0 si tout passe, 1 sinon, pour etre utilisable en CI.

local script = arg and arg[0] or "tests/run.lua"
local root   = script:match("^(.*)[/\\][Tt]ests[/\\]run%.lua$") or "."

local PACKAGE = root .. "/Packages/fate-games"

local Harness = dofile(root .. "/tests/harness.lua")
local Stubs   = dofile(root .. "/tests/stubs.lua")

-- Reimplementation de Package.Require. Le moteur cherche dans cinq emplacements ;
-- on reproduit ceux qui nous concernent cote serveur, dans le meme ordre de priorite,
-- avec le meme cache par chemin.
local require_cache = {}
local searchers = {
    PACKAGE .. "/Server/",
    PACKAGE .. "/",
    PACKAGE .. "/Shared/",
    PACKAGE .. "/Client/",
}

local function file_exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

_G.Package = {
    Require = function(path)
        if require_cache[path] ~= nil then
            return require_cache[path]
        end

        for _, base in ipairs(searchers) do
            local full = base .. path
            if file_exists(full) then
                local chunk, err = loadfile(full)
                if not chunk then
                    error(("Package.Require : %s ne compile pas : %s"):format(full, tostring(err)))
                end
                local result = chunk()
                require_cache[path] = result
                return result
            end
        end

        error("Package.Require : fichier introuvable -> " .. tostring(path))
    end,

    Subscribe = function() end,
    Export    = function() end,
}

Stubs.install()

local suites = {
    "log",
    "scheduler",
    "ids",
    "migrations",
    "intents",
    "accounts",
    "characters",
    "interactables",
    "liars_deck",
    "liars_revolver",
    "liars_challenge",
    "liars_round",
    "liars_match",
}

print(("banc de test fate-games (%s)"):format(_VERSION))

for _, name in ipairs(suites) do
    local suite = dofile(root .. "/tests/suites/" .. name .. ".lua")
    suite(Harness, Stubs)
end

os.exit(Harness.report())
