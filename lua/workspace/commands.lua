local M = {}

local registry = {}

--- Register a custom command in the VS Code commands registry.
---@param commandId string Unique identifier for the command
---@param callback function Lua callback triggered on command execution
---@return table Disposable handle to unregister the command
function M.registerCommand(commandId, callback)
  registry[commandId] = callback
  return {
    dispose = function()
      registry[commandId] = nil
    end
  }
end

--- Execute a registered command.
---@param commandId string Command identifier to invoke
---@vararg any Arguments to pass to the callback
---@return boolean success, any result or error message
function M.executeCommand(commandId, ...)
  local cb = registry[commandId]
  if not cb then
    return false, "Command not found: " .. tostring(commandId)
  end
  
  local ok, res = pcall(cb, ...)
  if not ok then
    return false, res
  end
  return true, res
end

return M
