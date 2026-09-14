-- Journalisation structuree (docs/ARCHITECTURE.md section 4).
--
-- Aucune dependance : la log doit fonctionner avant que quoi que ce soit d'autre existe.

local Enums = Package.Require("Shared/enums.lua")

-- Console.Warn / Console.Error ne sont pas garantis sur toutes les versions du moteur :
-- on retombe sur Console.Log plutot que d'appeler une fonction nil.
local console_warn  = Console.Warn  or Console.Log
local console_error = Console.Error or Console.Log

return function(config)
    local Log = {}

    local min_level = Enums.LogLevel[config.log.min_level] or Enums.LogLevel.INFO
    local counter   = 0

    -- Identifiant propage dans toute une chaine d'intention, pour reconstituer une
    -- transaction complete a partir de n'importe laquelle de ses lignes.
    function Log.NewCorrelationId()
        counter = counter + 1
        return string.format("%d-%d", os.time(), counter)
    end

    local function write(level, module, message, correlation_id)
        if Enums.LogLevel[level] < min_level then return end

        local line = string.format("[%s][%s] %s", level, module, message)
        if correlation_id then
            line = line .. " (cid=" .. correlation_id .. ")"
        end

        if level == "ERROR" then
            console_error(line)
        elseif level == "WARN" then
            console_warn(line)
        else
            Console.Log(line)
        end
    end

    function Log.Debug(module, message, cid) write("DEBUG", module, message, cid) end
    function Log.Info(module, message, cid)  write("INFO",  module, message, cid) end
    function Log.Warn(module, message, cid)  write("WARN",  module, message, cid) end
    function Log.Error(module, message, cid) write("ERROR", module, message, cid) end

    -- Ligne d'audit : format fixe, destine a etre relu par un humain ou un outil.
    -- Tout ce qui cree, detruit ou transfere de la valeur doit passer par ici.
    function Log.Audit(entry)
        write("INFO", "audit", string.format(
            "actor=%s target=%s action=%s pos=%s payload=%s",
            tostring(entry.actor),
            tostring(entry.target),
            tostring(entry.action),
            tostring(entry.position),
            tostring(entry.payload)
        ), entry.correlation_id)
    end

    return Log
end
