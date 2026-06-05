local M = {}

local function hijack_telescope(builtin)
  if builtin._workspace_hijacked then return end
  builtin._workspace_hijacked = true

  local function wrap_search(orig_func, search_dirs_key)
    return function(opts)
      opts = opts or {}
      if _G.workspace and _G.workspace.workspace and _G.workspace.workspace.workspaceFolders then
        local ws = _G.workspace.workspace
        if ws.workspaceFile or #ws.workspaceFolders > 1 then
          local paths = {}
          for _, folder in ipairs(ws.workspaceFolders) do
            table.insert(paths, folder.uri.fsPath)
          end
          opts[search_dirs_key or "search_dirs"] = opts[search_dirs_key or "search_dirs"] or paths
        end
      end
      return orig_func(opts)
    end
  end

  if type(builtin.find_files) == "function" then
    builtin.find_files = wrap_search(builtin.find_files, "search_dirs")
  end
  if type(builtin.live_grep) == "function" then
    builtin.live_grep = wrap_search(builtin.live_grep, "search_dirs")
  end
  if type(builtin.grep_string) == "function" then
    builtin.grep_string = wrap_search(builtin.grep_string, "search_dirs")
  end
  if type(builtin.git_files) == "function" then
    local orig_git_files = builtin.git_files
    builtin.git_files = function(opts)
      opts = opts or {}
      if _G.workspace and _G.workspace.workspace and (_G.workspace.workspace.workspaceFile or #_G.workspace.workspace.workspaceFolders > 1) then
        return builtin.find_files(opts)
      end
      return orig_git_files(opts)
    end
  end
end

local function hijack_fzf_lua(fzf)
  if fzf._workspace_hijacked then return end
  fzf._workspace_hijacked = true

  local function wrap_fzf(orig_func)
    return function(opts)
      opts = opts or {}
      if _G.workspace and _G.workspace.workspace and _G.workspace.workspace.workspaceFolders then
        local ws = _G.workspace.workspace
        if ws.workspaceFile or #ws.workspaceFolders > 1 then
          if ws.virtualRoot then
            opts.cwd = opts.cwd or ws.virtualRoot
            -- Ensure search tools follow symlinks (e.g. fd -L, rg -L)
            opts.fd_opts = opts.fd_opts or "--color=never --type f --hidden --follow --exclude .git"
            opts.rg_opts = opts.rg_opts or "--column --line-number --no-heading --color=always --smart-case --hidden --follow"
          end
        end
      end
      return orig_func(opts)
    end
  end

  if type(fzf.files) == "function" then
    fzf.files = wrap_fzf(fzf.files)
  end
  if type(fzf.live_grep) == "function" then
    fzf.live_grep = wrap_fzf(fzf.live_grep)
  end
  if type(fzf.grep) == "function" then
    fzf.grep = wrap_fzf(fzf.grep)
  end
end

local function hijack_snacks_picker(picker)
  if picker._workspace_hijacked then return end
  picker._workspace_hijacked = true

  local function wrap_snacks(orig_func)
    return function(opts)
      opts = opts or {}
      if _G.workspace and _G.workspace.workspace and _G.workspace.workspace.workspaceFolders then
        local ws = _G.workspace.workspace
        if ws.workspaceFile or #ws.workspaceFolders > 1 then
          local paths = {}
          for _, folder in ipairs(ws.workspaceFolders) do
            table.insert(paths, folder.uri.fsPath)
          end
          opts.dirs = opts.dirs or paths
        end
      end
      return orig_func(opts)
    end
  end

  if type(picker.files) == "function" then
    picker.files = wrap_snacks(picker.files)
  end
  if type(picker.grep) == "function" then
    picker.grep = wrap_snacks(picker.grep)
  end
end

function M.setup()
  if not _G.workspace_config or _G.workspace_config.hijack_search == false then
    return
  end

  local function hijack_module(modname, module)
    if modname == "telescope.builtin" then
      hijack_telescope(module)
    elseif modname == "fzf-lua" then
      hijack_fzf_lua(module)
    elseif modname == "snacks.picker" then
      hijack_snacks_picker(module)
    elseif modname == "snacks" then
      if module.picker then
        hijack_snacks_picker(module.picker)
      end
    end
  end

  -- Wrap already loaded modules
  for modname, module in pairs(package.loaded) do
    hijack_module(modname, module)
  end

  -- Wrap require for future loads
  local original_require = _G.require
  _G.require = function(modname)
    local module = original_require(modname)
    pcall(hijack_module, modname, module)
    return module
  end
end

return M
