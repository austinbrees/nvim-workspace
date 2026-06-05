-- Ensure vscode is initialized with default config if not done yet
if not _G.vscode then
  pcall(require, "vscode")
  if _G.vscode == nil then
    -- Fallback in case of load order issues
    require("vscode").setup({})
  end
end

-- LSP Sync folders helper
local function sync_lsp_folders(bufnr)
  if not _G.vscode or not _G.vscode.workspace or not _G.vscode.workspace.workspaceFolders then
    return
  end
  if not _G.vscode_config or not _G.vscode_config.auto_lsp then
    return
  end
  
  local folders = _G.vscode.workspace.workspaceFolders
  if not folders or #folders <= 1 then
    -- Skip syncing if only a single default CWD folder is present,
    -- unless we explicitly loaded a .code-workspace file
    if not _G.vscode.workspace.workspaceFile then
      return
    end
  end

  vim.api.nvim_buf_call(bufnr, function()
    -- Check if LSP clients support workspace folders and sync
    for _, folder in ipairs(folders) do
      local path = folder.uri.fsPath
      local current_folders = vim.lsp.buf.list_workspace_folders()
      local exists = false
      for _, cf in ipairs(current_folders) do
        if cf == path then
          exists = true
          break
        end
      end
      if not exists then
        -- This adds it to clients supporting didChangeWorkspaceFolders
        pcall(vim.lsp.buf.add_workspace_folder, path)
      end
    end
  end)
end

-- Load Workspace function
local function load_workspace(path)
  local ws = _G.vscode.workspace
  local recent = require("vscode.recent")
  
  if path and path ~= "" then
    local success, err = ws.load(path)
    if success then
      recent.add(path)
      vim.notify("Loaded workspace: " .. ws.name, vim.log.levels.INFO)
      
      -- Sync LSP folders for all currently active buffers
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
          sync_lsp_folders(bufnr)
        end
      end
    else
      vim.notify("Failed to load workspace: " .. tostring(err), vim.log.levels.ERROR)
    end
    return
  end
  
  -- Auto-find code-workspace file by walking up directory tree
  local cwd = vim.fn.getcwd()
  local workspace_files = {}
  local dir = cwd
  while dir and dir ~= "" do
    local glob = vim.fn.globpath(dir, "*.code-workspace", false, true)
    for _, file in ipairs(glob) do
      table.insert(workspace_files, file)
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      break
    end
    dir = parent
  end
  
  if #workspace_files == 1 then
    load_workspace(workspace_files[1])
  elseif #workspace_files > 1 then
    vim.ui.select(workspace_files, {
      prompt = "Select workspace file to load",
    }, function(choice)
      if choice then
        load_workspace(choice)
      end
    end)
  else
    -- Prompt from recent files
    local recents = recent.get()
    if #recents > 0 then
      vim.ui.select(recents, {
        prompt = "No workspace file found. Select a recent workspace to load",
      }, function(choice)
        if choice then
          load_workspace(choice)
        end
      end)
    else
      vim.notify("No .code-workspace files found in directory tree or recent history.", vim.log.levels.WARN)
    end
  end
end

-- VSCode Open Workspace Command
local function open_workspace(path)
  local ws = _G.vscode.workspace
  local recent = require("vscode.recent")
  
  if path and path ~= "" then
    local success, err = ws.load(path)
    if success then
      recent.add(path)
      vim.notify("Opened workspace: " .. ws.name, vim.log.levels.INFO)
      
      -- Sync LSP folders for all active buffers
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
          sync_lsp_folders(bufnr)
        end
      end
    else
      vim.notify("Failed to open workspace: " .. tostring(err), vim.log.levels.ERROR)
    end
    return
  end
  
  -- Auto-find workspace files
  local cwd = vim.fn.getcwd()
  local workspace_files = {}
  local dir = cwd
  while dir and dir ~= "" do
    local glob = vim.fn.globpath(dir, "*.code-workspace", false, true)
    for _, file in ipairs(glob) do
      table.insert(workspace_files, file)
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      break
    end
    dir = parent
  end
  
  if #workspace_files == 1 then
    open_workspace(workspace_files[1])
  elseif #workspace_files > 1 then
    vim.ui.select(workspace_files, {
      prompt = "Select workspace file to open",
    }, function(choice)
      if choice then
        open_workspace(choice)
      end
    end)
  else
    -- Fallback to recent history selection
    local recents = recent.get()
    if #recents > 0 then
      vim.ui.select(recents, {
        prompt = "No workspace file found. Select a recent workspace to open",
      }, function(choice)
        if choice then
          open_workspace(choice)
        end
      end)
    else
      vim.notify("No .code-workspace files found in directory tree or recent history.", vim.log.levels.WARN)
    end
  end
end

vim.api.nvim_create_user_command("WorkspaceOpen", function(opts)
  open_workspace(opts.args)
end, {
  nargs = "?",
  complete = "file"
})

-- VSCode Add Folder Command (Transition to workspace mode if not already)
vim.api.nvim_create_user_command("WorkspaceAddFolder", function(opts)
  local path = opts.args
  if not path or path == "" then
    path = vim.fn.getcwd()
  end
  local success = _G.vscode.workspace.addFolder(path)
  if success then
    local state_str = _G.vscode.workspace.workspaceFile and "workspace config" or "untitled workspace"
    vim.notify(string.format("Added folder to %s: %s", state_str, path), vim.log.levels.INFO)
  else
    vim.notify("Failed to add folder: " .. path, vim.log.levels.ERROR)
  end
end, {
  nargs = "?",
  complete = "dir"
})

-- VSCode Save Workspace As Command
vim.api.nvim_create_user_command("WorkspaceSaveAs", function(opts)
  local path = opts.args
  if not path or path == "" then
    vim.notify("Please specify a path to save the workspace file (e.g. :WorkspaceSaveAs project.code-workspace)", vim.log.levels.ERROR)
    return
  end
  local success, err = _G.vscode.workspace.save(path)
  if success then
    require("vscode.recent").add(path)
    vim.notify("Saved workspace config to: " .. path, vim.log.levels.INFO)
  else
    vim.notify("Failed to save workspace: " .. tostring(err), vim.log.levels.ERROR)
  end
end, {
  nargs = 1,
  complete = "file"
})

-- VSCode Close Workspace Command
vim.api.nvim_create_user_command("WorkspaceClose", function()
  _G.vscode.workspace.init_default()
  vim.notify("Closed workspace. Reset to single-folder CWD root.", vim.log.levels.INFO)
end, {})

-- VSCode Workspace Explorer integration (Neo-tree fallback)
vim.api.nvim_create_user_command("WorkspaceExplorer", function()
  local ws = _G.vscode.workspace
  local folders = ws.workspaceFolders
  if not folders or #folders == 0 then
    vim.notify("No folders open in workspace.", vim.log.levels.WARN)
    return
  end

  local function open_explorer(path)
    local ok_neotree = pcall(require, "neo-tree")
    if ok_neotree then
      vim.cmd("Neotree dir=" .. vim.fn.fnameescape(path))
    else
      vim.cmd("edit " .. vim.fn.fnameescape(path))
    end
  end

  -- Prioritize the virtualRoot directory (containing symlinks to all folders)
  -- so that any file explorer will display them side-by-side!
  if ws.workspaceFile and ws.virtualRoot then
    open_explorer(ws.virtualRoot)
  elseif #folders == 1 then
    open_explorer(folders[1].uri.fsPath)
  else
    local folder_map = {}
    local names = {}
    for _, folder in ipairs(folders) do
      local label = string.format("%s (%s)", folder.name, folder.uri.fsPath)
      table.insert(names, label)
      folder_map[label] = folder.uri.fsPath
    end
    vim.ui.select(names, {
      prompt = "Select workspace folder to explore",
    }, function(choice)
      if choice and folder_map[choice] then
        open_explorer(folder_map[choice])
      end
    end)
  end
end, {})

-- VSCode Workspace Find Files (Telescope integration)
vim.api.nvim_create_user_command("WorkspaceFiles", function()
  local ws = _G.vscode.workspace
  local folders = ws.workspaceFolders
  if not folders or #folders == 0 then
    vim.notify("No folders open in workspace.", vim.log.levels.WARN)
    return
  end
  
  local ok, telescope = pcall(require, "telescope.builtin")
  if not ok then
    vim.notify("Telescope is not installed.", vim.log.levels.ERROR)
    return
  end
  
  local paths = {}
  for _, folder in ipairs(folders) do
    table.insert(paths, folder.uri.fsPath)
  end
  
  telescope.find_files({
    search_dirs = paths,
    prompt_title = "Find Files (" .. ws.name .. ")",
  })
end, {})

-- VSCode Workspace Live Grep (Telescope integration)
vim.api.nvim_create_user_command("WorkspaceGrep", function()
  local ws = _G.vscode.workspace
  local folders = ws.workspaceFolders
  if not folders or #folders == 0 then
    vim.notify("No folders open in workspace.", vim.log.levels.WARN)
    return
  end
  
  local ok, telescope = pcall(require, "telescope.builtin")
  if not ok then
    vim.notify("Telescope is not installed.", vim.log.levels.ERROR)
    return
  end
  
  local paths = {}
  for _, folder in ipairs(folders) do
    table.insert(paths, folder.uri.fsPath)
  end
  
  telescope.live_grep({
    search_dirs = paths,
    prompt_title = "Live Grep (" .. ws.name .. ")",
  })
end, {})


-- Event Bridge Group
local event_group = vim.api.nvim_create_augroup("VSCodeEventBridging", { clear = true })

local function fire_doc_event(bufnr, event_name)
  if not _G.vscode or not _G.vscode.workspace then return end
  if vim.bo[bufnr].buftype ~= "" then return end
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" then return end
  
  local doc = _G.vscode.workspace.create_text_document(bufnr, path)
  local ev = _G.vscode.workspace[event_name]
  if ev then
    if event_name == "onDidChangeTextDocument" then
      ev.fire({ document = doc })
    else
      ev.fire(doc)
    end
  end
end

-- Open Event
vim.api.nvim_create_autocmd("BufReadPost", {
  group = event_group,
  callback = function(args)
    fire_doc_event(args.buf, "onDidOpenTextDocument")
  end,
})

-- Save Events
vim.api.nvim_create_autocmd("BufWritePost", {
  group = event_group,
  callback = function(args)
    fire_doc_event(args.buf, "onDidSaveTextDocument")
  end,
})

vim.api.nvim_create_autocmd("BufWritePre", {
  group = event_group,
  callback = function(args)
    fire_doc_event(args.buf, "onWillSaveTextDocument")
  end,
})

-- Edit Events
vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
  group = event_group,
  callback = function(args)
    fire_doc_event(args.buf, "onDidChangeTextDocument")
  end,
})

-- Close Event
vim.api.nvim_create_autocmd("BufDelete", {
  group = event_group,
  callback = function(args)
    fire_doc_event(args.buf, "onDidCloseTextDocument")
  end,
})

-- LSP Attach Sync
local lsp_group = vim.api.nvim_create_augroup("VSCodeWorkspaceLspAttach", { clear = true })
vim.api.nvim_create_autocmd("LspAttach", {
  group = lsp_group,
  callback = function(args)
    vim.schedule(function()
      sync_lsp_folders(args.buf)
    end)
  end,
})
