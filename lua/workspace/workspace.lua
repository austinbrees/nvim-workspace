local M = {}

local Uri = require("workspace.uri")
local utils = require("workspace.utils")

-- State variables
M.workspaceFolders = nil
M.workspaceFile = nil
M.name = ""
M.virtualRoot = nil

-- Internal settings store
local active_settings = {}

-- Events
local function create_event()
  local listeners = {}
  local event = {}
  
  setmetatable(event, {
    __call = function(t, callback)
      table.insert(listeners, callback)
      local index = #listeners
      return {
        dispose = function()
          listeners[index] = nil
        end
      }
    end
  })
  
  function event.fire(...)
    for _, cb in pairs(listeners) do
      if cb then
        pcall(cb, ...)
      end
    end
  end
  
  return event
end

M.onDidChangeWorkspaceFolders = create_event()
M.onDidOpenTextDocument = create_event()
M.onDidCloseTextDocument = create_event()
M.onDidSaveTextDocument = create_event()
M.onWillSaveTextDocument = create_event()
M.onDidChangeTextDocument = create_event()

--- Create a VS Code style TextDocument object from a Neovim buffer.
---@param bufnr number
---@param path string
---@return table TextDocument
function M.create_text_document(bufnr, path)
  local doc = {}
  doc.uri = Uri.file(path)
  doc.fileName = path
  doc.isDirty = vim.bo[bufnr].modified
  doc.isUntitled = path == ""
  doc.languageId = vim.bo[bufnr].filetype
  doc.version = vim.api.nvim_buf_get_changedtick(bufnr)
  doc.lineCount = vim.api.nvim_buf_line_count(bufnr)
  
  function doc.getText()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    return table.concat(lines, "\n")
  end
  
  function doc.lineAt(line_idx)
    -- line_idx is 0-indexed in VS Code API
    local line_num = line_idx + 1
    if line_num < 1 or line_num > doc.lineCount then
      return nil
    end
    local line_text = vim.api.nvim_buf_get_lines(bufnr, line_num - 1, line_num, false)[1] or ""
    return {
      text = line_text,
      lineNumber = line_idx,
    }
  end
  
  return doc
end

-- Read-only property textDocuments
local get_text_documents_meta = {
  __index = function(_, key)
    if key == "textDocuments" then
      local docs = {}
      local bufs = vim.api.nvim_list_bufs()
      for _, buf in ipairs(bufs) do
        if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "" then
          local path = vim.api.nvim_buf_get_name(buf)
          if path ~= "" then
            table.insert(docs, M.create_text_document(buf, path))
          end
        end
      end
      return docs
    end
    return rawget(M, key)
  end
}
setmetatable(M, get_text_documents_meta)

local function make_relative(base_dir, target_dir)
  base_dir = base_dir:gsub("\\", "/")
  target_dir = target_dir:gsub("\\", "/")
  if base_dir:sub(-1) == "/" then base_dir = base_dir:sub(1, -2) end
  if target_dir:sub(-1) == "/" then target_dir = target_dir:sub(1, -2) end
  
  local base_parts = {}
  for segment in base_dir:gmatch("[^/]+") do
    table.insert(base_parts, segment)
  end
  local target_parts = {}
  for segment in target_dir:gmatch("[^/]+") do
    table.insert(target_parts, segment)
  end
  
  local common_idx = 0
  for i = 1, math.min(#base_parts, #target_parts) do
    if base_parts[i] == target_parts[i] then
      common_idx = i
    else
      break
    end
  end
  
  if common_idx == 0 then
    return target_dir
  end
  
  local rel = {}
  for i = common_idx + 1, #base_parts do
    table.insert(rel, "..")
  end
  for i = common_idx + 1, #target_parts do
    table.insert(rel, target_parts[i])
  end
  
  if #rel == 0 then
    return "."
  end
  return table.concat(rel, "/")
end

local function update_virtual_root()
  if M.virtualRoot then
    pcall(vim.fn.delete, M.virtualRoot, "rf")
    M.virtualRoot = nil
  end
  
  -- Only build virtual root if we have multiple roots OR if we explicitly loaded a workspace file!
  if not M.workspaceFile and (#M.workspaceFolders <= 1) then
    if vim.env.TMUX then
      pcall(vim.fn.jobstart, { "tmux", "set-environment", "-r", "ACTIVE_NVIM_WORKSPACE" })
      pcall(vim.fn.jobstart, { "tmux", "set-environment", "-r", "ACTIVE_NVIM_WORKSPACE_NAME" })
    end
    return
  end
  
  local cache_dir = vim.fn.stdpath("cache") .. "/nvim-workspace/" .. M.name
  pcall(vim.fn.delete, cache_dir, "rf")
  pcall(vim.fn.mkdir, cache_dir, "p")
  
  local uv = vim.uv or vim.loop
  for _, folder in ipairs(M.workspaceFolders) do
    local link_path = cache_dir .. "/" .. folder.name
    local target_path = folder.uri.fsPath
    pcall(uv.fs_symlink, target_path, link_path, { dir = true })
  end
  M.virtualRoot = cache_dir
  
  if vim.env.TMUX then
    pcall(vim.fn.jobstart, { "tmux", "set-environment", "ACTIVE_NVIM_WORKSPACE", cache_dir })
    pcall(vim.fn.jobstart, { "tmux", "set-environment", "ACTIVE_NVIM_WORKSPACE_NAME", M.name })
  end
end

--- Initialize with fallback (defaulting to current working directory).
function M.init_default()
  local cwd = vim.fn.getcwd()
  M.workspaceFolders = {
    {
      uri = Uri.file(cwd),
      name = vim.fn.fnamemodify(cwd, ":t"),
      index = 0
    }
  }
  M.workspaceFile = nil
  M.name = vim.fn.fnamemodify(cwd, ":t")
  active_settings = {}
  
  if M.virtualRoot then
    pcall(vim.fn.delete, M.virtualRoot, "rf")
    M.virtualRoot = nil
  end
  
  if vim.env.TMUX then
    pcall(vim.fn.jobstart, { "tmux", "set-environment", "-r", "ACTIVE_NVIM_WORKSPACE" })
    pcall(vim.fn.jobstart, { "tmux", "set-environment", "-r", "ACTIVE_NVIM_WORKSPACE_NAME" })
  end
end

--- Load a .code-workspace file.
---@param file_path string
---@return boolean success, string? error_message
function M.load(file_path)
  file_path = vim.fn.resolve(vim.fn.expand(file_path))
  if not utils.is_file(file_path) then
    return false, "File does not exist: " .. file_path
  end
  
  local f = io.open(file_path, "r")
  if not f then
    return false, "Could not open file: " .. file_path
  end
  local content = f:read("*all")
  f:close()
  
  local clean_content = utils.strip_comments(content)
  local ok, data = pcall(vim.json.decode, clean_content)
  if not ok then
    return false, "Failed to parse JSON: " .. tostring(data)
  end
  
  if not data.folders or type(data.folders) ~= "table" then
    return false, "Workspace file must contain a 'folders' array"
  end
  
  local old_folders = M.workspaceFolders
  local folders = {}
  for idx, folder in ipairs(data.folders) do
    local path = folder.path or folder.uri
    if path then
      local abs_path = utils.resolve_path(file_path, path)
      table.insert(folders, {
        uri = Uri.file(abs_path),
        name = folder.name or vim.fn.fnamemodify(abs_path, ":t"),
        index = idx - 1,
        raw_path = path -- Store raw path for serialization
      })
    end
  end
  
  M.workspaceFolders = folders
  M.workspaceFile = Uri.file(file_path)
  M.name = vim.fn.fnamemodify(file_path, ":t:r") -- Filename without extension
  active_settings = data.settings or {}
  
  -- Generate virtual root with symbolic links to all workspace folders
  update_virtual_root()
  
  -- Fire event
  M.onDidChangeWorkspaceFolders.fire({
    added = folders,
    removed = old_folders or {}
  })
  
  return true
end

--- Save the current workspace folders and settings back to the workspaceFile.
---@param file_path string?
---@return boolean success, string? error_message
function M.save(file_path)
  local target_file = file_path
  if not target_file then
    if M.workspaceFile then
      target_file = M.workspaceFile.fsPath
    else
      return false, "No workspace file path specified"
    end
  else
    target_file = vim.fn.resolve(vim.fn.expand(target_file))
  end
  
  local target_dir = vim.fn.fnamemodify(target_file, ":h")
  local raw_folders = {}
  for _, folder in ipairs(M.workspaceFolders or {}) do
    local rel_path = make_relative(target_dir, folder.uri.fsPath)
    table.insert(raw_folders, {
      path = rel_path,
      name = folder.name ~= vim.fn.fnamemodify(folder.uri.fsPath, ":t") and folder.name or nil
    })
  end
  
  local data = {
    folders = raw_folders,
    settings = active_settings
  }
  
  local ok, json_str = pcall(vim.json.encode, data)
  if not ok then
    return false, "Failed to encode workspace: " .. tostring(json_str)
  end
  
  local f = io.open(target_file, "w")
  if not f then
    return false, "Could not open file for writing: " .. target_file
  end
  f:write(json_str)
  f:close()
  
  -- Update state if we saved to a new file
  M.workspaceFile = Uri.file(target_file)
  M.name = vim.fn.fnamemodify(target_file, ":t:r")
  
  -- Regenerate virtual directories
  update_virtual_root()
  
  return true
end

--- Add a folder path to the workspace folders list.
---@param folder_path string
---@param name string?
---@return boolean success
function M.addFolder(folder_path, name)
  folder_path = vim.fn.resolve(vim.fn.expand(folder_path))
  if not utils.is_dir(folder_path) then
    return false
  end
  
  -- Check if already exists
  M.workspaceFolders = M.workspaceFolders or {}
  for _, f in ipairs(M.workspaceFolders) do
    if f.uri.fsPath == folder_path then
      return true -- Already present
    end
  end
  
  -- Transition from CWD single-root to untitled multi-root transient workspace
  if not M.workspaceFile and #M.workspaceFolders == 1 then
    M.name = "Untitled"
  end
  
  local next_index = #M.workspaceFolders
  local new_folder = {
    uri = Uri.file(folder_path),
    name = name or vim.fn.fnamemodify(folder_path, ":t"),
    index = next_index
  }
  
  table.insert(M.workspaceFolders, new_folder)
  
  -- Update virtual root directory links
  update_virtual_root()
  
  -- Auto-save if it is a loaded workspace file
  if M.workspaceFile then
    M.save()
  end
  
  M.onDidChangeWorkspaceFolders.fire({
    added = { new_folder },
    removed = {}
  })
  
  return true
end

--- Remove a folder path or folder index from the workspace folders list.
---@param index_or_path string|number
---@return boolean success
function M.removeFolder(index_or_path)
  M.workspaceFolders = M.workspaceFolders or {}
  local remove_idx = nil
  
  if type(index_or_path) == "number" then
    if index_or_path >= 0 and index_or_path < #M.workspaceFolders then
      remove_idx = index_or_path + 1
    end
  else
    local target_path = vim.fn.resolve(vim.fn.expand(index_or_path))
    for idx, folder in ipairs(M.workspaceFolders) do
      if folder.uri.fsPath == target_path then
        remove_idx = idx
        break
      end
    end
  end
  
  if not remove_idx then
    return false
  end
  
  local removed_folder = table.remove(M.workspaceFolders, remove_idx)
  
  -- Re-index folders
  for idx, folder in ipairs(M.workspaceFolders) do
    folder.index = idx - 1
  end
  
  -- Update virtual root directory links
  update_virtual_root()
  
  -- Auto-save if it is a loaded workspace file
  if M.workspaceFile then
    M.save()
  end
  
  M.onDidChangeWorkspaceFolders.fire({
    added = {},
    removed = { removed_folder }
  })
  
  return true
end

-- Configuration Helper Functions
local function get_nested_key(t, key)
  if type(t) ~= "table" then return nil end
  if t[key] ~= nil then
    return t[key]
  end
  local parts = {}
  for part in key:gmatch("[^%.]+") do
    table.insert(parts, part)
  end
  local current = t
  for _, part in ipairs(parts) do
    if type(current) == "table" then
      current = current[part]
    else
      return nil
    end
  end
  return current
end

local Config = {}

function Config.new(settings, section)
  local self = {}
  
  function self.get(key_or_self, key)
    local actual_key = key_or_self
    if type(key_or_self) == "table" and key ~= nil then
      actual_key = key
    end
    local full_key = actual_key
    if section and section ~= "" then
      full_key = section .. "." .. actual_key
    end
    return get_nested_key(settings, full_key)
  end
  
  function self.has(key_or_self, key)
    return self.get(key_or_self, key) ~= nil
  end
  
  function self.update(key_or_self, key_or_val, value)
    local actual_key = key_or_self
    local actual_val = key_or_val
    if type(key_or_self) == "table" and value ~= nil then
      actual_key = key_or_val
      actual_val = value
    end
    
    local full_key = actual_key
    if section and section ~= "" then
      full_key = section .. "." .. actual_key
    end
    settings[full_key] = actual_val
    if M.workspaceFile then
      M.save()
    end
  end
  
  self.settings = settings
  self.section = section
  
  return self
end

--- Get a WorkspaceConfiguration object.
---@param section string? Optional settings prefix section (e.g. "editor")
---@return table WorkspaceConfiguration
function M.getConfiguration(section)
  return Config.new(active_settings, section)
end

--- Find the workspace folder containing the given resource.
---@param uri string|table URI object or string path
---@return table? WorkspaceFolder
function M.getWorkspaceFolder(uri)
  local check_path = type(uri) == "table" and uri.fsPath or uri
  check_path = vim.fn.resolve(vim.fn.expand(check_path))
  
  local best_match = nil
  local max_len = -1
  
  for _, folder in ipairs(M.workspaceFolders or {}) do
    local f_path = folder.uri.fsPath
    if check_path:sub(1, #f_path) == f_path then
      -- Verify it's a boundary matches (either same folder, or subfolder)
      local next_char = check_path:sub(#f_path + 1, #f_path + 1)
      if next_char == "" or next_char == "/" or next_char == "\\" then
        if #f_path > max_len then
          best_match = folder
          max_len = #f_path
        end
      end
    end
  end
  
  return best_match
end

--- Convert a path to a relative path relative to its containing workspace folder.
---@param path_or_uri string|table
---@param include_folder_name boolean?
---@return string
function M.asRelativePath(path_or_uri, include_folder_name)
  local full_path = type(path_or_uri) == "table" and path_or_uri.fsPath or path_or_uri
  full_path = vim.fn.resolve(vim.fn.expand(full_path))
  
  local folder = M.getWorkspaceFolder(full_path)
  if not folder then
    return full_path
  end
  
  local folder_path = folder.uri.fsPath
  local rel = full_path:sub(#folder_path + 2) -- Skip trailing separator
  if include_folder_name then
    return folder.name .. "/" .. rel
  end
  return rel
end

--- Search for files in workspace matching a glob pattern.
---@param include string Glob pattern to search (e.g. "**/*.lua")
---@param exclude string? Currently ignored, for 1-to-1 parity
---@param max_results number?
---@return table Array of Uri objects
function M.findFiles(include, exclude, max_results)
  local results = {}
  max_results = max_results or 100
  local pattern = include or "**/*"
  
  for _, folder in ipairs(M.workspaceFolders or {}) do
    local files = vim.fn.globpath(folder.uri.fsPath, pattern, false, true)
    for _, file in ipairs(files) do
      if #results >= max_results then
        break
      end
      table.insert(results, Uri.file(file))
    end
    if #results >= max_results then
      break
    end
  end
  return results
end

-- Initialize default state
M.init_default()

return M
