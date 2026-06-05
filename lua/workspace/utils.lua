local M = {}

local uv = vim.uv or vim.loop

--- Strips comments (line & block) and trailing commas from a JSONC string.
---@param str string The raw JSONC string
---@return string The sanitized JSON-compliant string
function M.strip_comments(str)
  -- 1. Remove block comments /* ... */
  str = str:gsub("/%*.-%*/", "")
  
  -- 2. Remove line comments // ... but avoid stripping URI schemas like file://
  local lines = {}
  for line in str:gmatch("[^\r\n]+") do
    local clean_line = line
    local start = 1
    local comment_idx = line:find("//", start)
    
    while comment_idx do
      -- If the comment marker is preceded by a colon, it's part of a protocol (e.g. file://)
      if comment_idx > 1 and line:sub(comment_idx - 1, comment_idx - 1) == ":" then
        start = comment_idx + 2
        comment_idx = line:find("//", start)
      else
        -- It is a genuine line comment, strip it and everything after it
        clean_line = line:sub(1, comment_idx - 1)
        break
      end
    end
    table.insert(lines, clean_line)
  end
  
  local clean_str = table.concat(lines, "\n")
  
  -- 3. Strip trailing commas in objects and arrays to make it standard JSON
  clean_str = clean_str:gsub(",(%s*})", "%1")
  clean_str = clean_str:gsub(",(%s*])", "%1")
  
  return clean_str
end

--- Checks if a path exists and is a directory.
---@param path string
---@return boolean
function M.is_dir(path)
  local stat = uv.fs_stat(path)
  return (stat and stat.type == "directory") or false
end

--- Checks if a path exists and is a file.
---@param path string
---@return boolean
function M.is_file(path)
  local stat = uv.fs_stat(path)
  return (stat and stat.type == "file") or false
end

--- Normalizes a path, resolving relative/URI formats and symlinks.
---@param workspace_file_path string Absolute path to the workspace file
---@param folder_path string Path or file:// URI to resolve
---@return string Absolute resolved path
function M.resolve_path(workspace_file_path, folder_path)
  -- Extract path if it is a file:// URI
  if folder_path:sub(1, 7) == "file://" then
    folder_path = folder_path:sub(8)
  end

  -- Check if it is an absolute path (starts with / or has Win drive letter)
  local is_absolute = folder_path:sub(1, 1) == "/" or folder_path:match("^[a-zA-Z]:")
  if is_absolute then
    return vim.fn.resolve(folder_path)
  end

  -- It is a relative path. Resolve relative to workspace file directory
  local ws_dir = vim.fn.fnamemodify(workspace_file_path, ":h")
  local full_path = ws_dir .. "/" .. folder_path
  return vim.fn.resolve(full_path)
end

return M
