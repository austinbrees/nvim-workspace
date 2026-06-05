local M = {}

local utils = require("vscode.utils")
local history_file = vim.fn.stdpath("data") .. "/vscode-workspace-recent.json"

--- Get the list of recently loaded workspace paths.
---@return table Array of string paths
function M.get()
  if not utils.is_file(history_file) then
    return {}
  end
  local f = io.open(history_file, "r")
  if not f then return {} end
  local content = f:read("*all")
  f:close()
  
  local ok, data = pcall(vim.json.decode, content)
  if ok and type(data) == "table" then
    return data
  end
  return {}
end

--- Add a workspace path to the recent history, maintaining a cap of 10 items.
---@param path string
function M.add(path)
  path = vim.fn.resolve(vim.fn.expand(path))
  local list = M.get()
  
  -- Remove existing duplicates
  for i = #list, 1, -1 do
    if list[i] == path then
      table.remove(list, i)
    end
  end
  
  -- Prepend the path to list
  table.insert(list, 1, path)
  
  -- Limit list size to 10 entries
  while #list > 10 do
    table.remove(list)
  end
  
  -- Serialize and write to cache file
  local ok, json_str = pcall(vim.json.encode, list)
  if ok then
    local f = io.open(history_file, "w")
    if f then
      f:write(json_str)
      f:close()
    end
  end
end

return M
