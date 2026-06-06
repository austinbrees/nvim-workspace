-- Ensure workspace is initialized with default config if not done yet
if not _G.workspace then
  pcall(require, "workspace")
  if _G.workspace == nil then
    -- Fallback in case of load order issues
    require("workspace").setup({})
  end
end

-- LSP Sync folders helper
local function sync_lsp_folders(bufnr)
  if not _G.workspace or not _G.workspace.workspace or not _G.workspace.workspace.workspaceFolders then
    return
  end
  if not _G.workspace_config or not _G.workspace_config.auto_lsp then
    return
  end
  
  local folders = _G.workspace.workspace.workspaceFolders
  if not folders or #folders <= 1 then
    -- Skip syncing if only a single default CWD folder is present,
    -- unless we explicitly loaded a .code-workspace file
    if not _G.workspace.workspace.workspaceFile then
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
  local ws = _G.workspace.workspace
  local recent = require("workspace.recent")
  
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

-- Open Workspace Command
local function open_workspace(path)
  local ws = _G.workspace.workspace
  local recent = require("workspace.recent")
  
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

-- Add Folder Command (Transition to workspace mode if not already)
local function prompt_add_folder()
  local choices = {}
  local choice_actions = {}
  
  -- 1. Check if we can detect a directory from the active buffer/explorer
  local current_file = vim.api.nvim_buf_get_name(0)
  local detected_dir = nil
  
  if vim.bo.filetype == "netrw" then
    local curdir = vim.b.netrw_curdir
    local cfile = vim.fn.expand("<cfile>")
    if curdir then
      if cfile and cfile ~= "" then
        local full_path = curdir .. "/" .. cfile
        if vim.fn.isdirectory(full_path) == 1 then
          detected_dir = full_path
        else
          detected_dir = curdir
        end
      else
        detected_dir = curdir
      end
    end
  elseif vim.bo.filetype == "neo-tree" then
    local ok_neotree, neotree_manager = pcall(require, "neo-tree.sources.manager")
    if ok_neotree then
      local state = neotree_manager.get_state("filesystem")
      if state and state.tree then
        local node = state.tree:get_node()
        if node then
          if node.type == "directory" then
            detected_dir = node.path
          else
            detected_dir = vim.fn.fnamemodify(node.path, ":h")
          end
        end
      end
    end
  elseif vim.bo.filetype == "oil" then
    local ok_oil, oil = pcall(require, "oil")
    if ok_oil then
      local entry = oil.get_cursor_entry()
      local current_oil_dir = oil.get_current_dir()
      if current_oil_dir then
        if entry and entry.type == "directory" then
          detected_dir = current_oil_dir .. entry.name
        else
          detected_dir = current_oil_dir
        end
      end
    end
  elseif current_file ~= "" and vim.bo.buftype == "" then
    detected_dir = vim.fn.fnamemodify(current_file, ":h")
  end
  
  if detected_dir then
    detected_dir = vim.fn.resolve(vim.fn.expand(detected_dir))
    local label = string.format("Add active folder: %s", detected_dir)
    table.insert(choices, label)
    choice_actions[label] = function()
      local success = _G.workspace.workspace.addFolder(detected_dir)
      if success then
        local state_str = _G.workspace.workspace.workspaceFile and "workspace config" or "untitled workspace"
        vim.notify(string.format("Added folder to %s: %s", state_str, detected_dir), vim.log.levels.INFO)
      else
        vim.notify("Failed to add folder: " .. detected_dir, vim.log.levels.ERROR)
      end
    end
  end
  
  -- macOS native file dialog choice
  local is_mac = vim.fn.has("mac") == 1 or vim.fn.has("macunix") == 1
  if is_mac then
    local label = "Browse folders via macOS File Dialog..."
    table.insert(choices, label)
    choice_actions[label] = function()
      local stdout = {}
      vim.fn.jobstart({ "osascript", "-e", "POSIX path of (choose folder with prompt \"Select Folder to Add\")" }, {
        stdout_buffered = true,
        on_stdout = function(_, data)
          if data then
            for _, line in ipairs(data) do
              if line ~= "" then
                table.insert(stdout, line)
              end
            end
          end
        end,
        on_exit = function(_, exit_code)
          if exit_code == 0 and #stdout > 0 then
            local path = table.concat(stdout, "\n")
            path = path:gsub("%s+$", "")
            if path:sub(-1) == "/" or path:sub(-1) == "\\" then
              path = path:sub(1, -2)
            end
            path = vim.fn.resolve(vim.fn.expand(path))
            local success = _G.workspace.workspace.addFolder(path)
            if success then
              local state_str = _G.workspace.workspace.workspaceFile and "workspace config" or "untitled workspace"
              vim.notify(string.format("Added folder to %s: %s", state_str, path), vim.log.levels.INFO)
            else
              vim.notify("Failed to add folder: " .. path, vim.log.levels.ERROR)
            end
          else
            vim.notify("Add folder canceled.", vim.log.levels.INFO)
          end
        end
      })
    end
  end
  
  -- 2. Telescope fuzzy finder choice (if Telescope is installed)
  local has_telescope = pcall(require, "telescope")
  if has_telescope then
    local label_nav = "Browse folders (Telescope, navigate filesystem)..."
    table.insert(choices, label_nav)
    choice_actions[label_nav] = function()
      local ok, pickers = pcall(require, "telescope.pickers")
      if not ok then return end
      local finders = require("telescope.finders")
      local conf = require("telescope.config").values
      local actions = require("telescope.actions")
      local action_state = require("telescope.actions.state")
      
      local function run_picker(path)
        path = vim.fn.resolve(vim.fn.expand(path))
        
        local dirs = {
          "[Select current: " .. path .. "]",
          "../ (Go up)"
        }
        
        local uv = vim.uv or vim.loop
        local handle = uv.fs_scandir(path)
        if handle then
          local subdirs = {}
          while true do
            local name, type = uv.fs_scandir_next(handle)
            if not name then break end
            if type == "directory" and name:sub(1, 1) ~= "." then
              table.insert(subdirs, name .. "/")
            end
          end
          table.sort(subdirs)
          for _, sd in ipairs(subdirs) do
            table.insert(dirs, sd)
          end
        end
        
        pickers.new({}, {
          prompt_title = "Browse: " .. path,
          finder = finders.new_table({
            results = dirs
          }),
          sorter = conf.generic_sorter({}),
          attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
              local selection = action_state.get_selected_entry()
              actions.close(prompt_bufnr)
              if selection then
                local chosen = selection[1]
                if chosen:sub(1, 15) == "[Select current" then
                  local success = _G.workspace.workspace.addFolder(path)
                  if success then
                    local state_str = _G.workspace.workspace.workspaceFile and "workspace config" or "untitled workspace"
                    vim.notify(string.format("Added folder to %s: %s", state_str, path), vim.log.levels.INFO)
                  else
                    vim.notify("Failed to add folder: " .. path, vim.log.levels.ERROR)
                  end
                elseif chosen == "../ (Go up)" then
                  local parent_path = vim.fn.fnamemodify(path, ":h")
                  run_picker(parent_path)
                else
                  local target_path = path .. "/" .. chosen:sub(1, -2)
                  run_picker(target_path)
                end
              end
            end)
            return true
          end,
        }):find()
      end
      
      run_picker(vim.fn.getcwd())
    end

    local label_find = "Fuzzy find folder to add (Telescope, recursive search)..."
    table.insert(choices, label_find)
    choice_actions[label_find] = function()
      local ok, builtin = pcall(require, "telescope.builtin")
      if not ok then return end
      
      local search_root = vim.fn.fnamemodify(vim.fn.getcwd(), ":h")
      local opts = {
        prompt_title = "Select Folder to Add",
        cwd = search_root,
        find_command = { "fd", "--type", "d", "--hidden", "--exclude", ".git", "--max-depth", "4" },
        attach_mappings = function(prompt_bufnr, map)
          local actions = require("telescope.actions")
          local action_state = require("telescope.actions.state")
          
          actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            local selection = action_state.get_selected_entry()
            if selection and selection[1] then
              local abs_path = vim.fn.resolve(search_root .. "/" .. selection[1])
              local success = _G.workspace.workspace.addFolder(abs_path)
              if success then
                local state_str = _G.workspace.workspace.workspaceFile and "workspace config" or "untitled workspace"
                vim.notify(string.format("Added folder to %s: %s", state_str, abs_path), vim.log.levels.INFO)
              else
                vim.notify("Failed to add folder: " .. abs_path, vim.log.levels.ERROR)
              end
            end
          end)
          return true
        end
      }
      
      if vim.fn.executable("fd") == 0 then
        opts.find_command = { "find", ".", "-type", "d", "-not", "-path", "*/.*", "-maxdepth", "4" }
      end
      
      builtin.find_files(opts)
    end
  end
  
  -- 3. Manual entry choice
  local manual_label = "Type folder path manually..."
  table.insert(choices, manual_label)
  choice_actions[manual_label] = function()
    local path = vim.fn.input("Folder to add: ", "", "dir")
    if not path or path == "" then
      vim.notify("Add folder canceled.", vim.log.levels.INFO)
      return
    end
    path = vim.fn.resolve(vim.fn.expand(path))
    local success = _G.workspace.workspace.addFolder(path)
    if success then
      local state_str = _G.workspace.workspace.workspaceFile and "workspace config" or "untitled workspace"
      vim.notify(string.format("Added folder to %s: %s", state_str, path), vim.log.levels.INFO)
    else
      vim.notify("Failed to add folder: " .. path, vim.log.levels.ERROR)
    end
  end
  
  -- Show selector
  vim.ui.select(choices, {
    prompt = "Select how to add a folder to the workspace",
  }, function(choice)
    if choice and choice_actions[choice] then
      choice_actions[choice]()
    end
  end)
end

vim.api.nvim_create_user_command("WorkspaceAddFolder", function(opts)
  local path = opts.args
  if not path or path == "" then
    prompt_add_folder()
  else
    path = vim.fn.resolve(vim.fn.expand(path))
    local success = _G.workspace.workspace.addFolder(path)
    if success then
      local state_str = _G.workspace.workspace.workspaceFile and "workspace config" or "untitled workspace"
      vim.notify(string.format("Added folder to %s: %s", state_str, path), vim.log.levels.INFO)
    else
      vim.notify("Failed to add folder: " .. path, vim.log.levels.ERROR)
    end
  end
end, {
  nargs = "?",
  complete = "dir"
})

-- Save Workspace As Command
vim.api.nvim_create_user_command("WorkspaceSaveAs", function(opts)
  local path = opts.args
  if not path or path == "" then
    vim.notify("Please specify a path to save the workspace file (e.g. :WorkspaceSaveAs project.code-workspace)", vim.log.levels.ERROR)
    return
  end
  local success, err = _G.workspace.workspace.save(path)
  if success then
    require("workspace.recent").add(path)
    vim.notify("Saved workspace config to: " .. path, vim.log.levels.INFO)
  else
    vim.notify("Failed to save workspace: " .. tostring(err), vim.log.levels.ERROR)
  end
end, {
  nargs = 1,
  complete = "file"
})

-- Close Workspace Command
vim.api.nvim_create_user_command("WorkspaceClose", function()
  _G.workspace.workspace.init_default()
  vim.notify("Closed workspace. Reset to single-folder CWD root.", vim.log.levels.INFO)
end, {})

-- Workspace Explorer integration (Neo-tree fallback)
vim.api.nvim_create_user_command("WorkspaceExplorer", function()
  local ws = _G.workspace.workspace
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

-- Workspace Find Files (Telescope integration)
vim.api.nvim_create_user_command("WorkspaceFiles", function()
  local ws = _G.workspace.workspace
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

-- Workspace Live Grep (Telescope integration)
vim.api.nvim_create_user_command("WorkspaceGrep", function()
  local ws = _G.workspace.workspace
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
local event_group = vim.api.nvim_create_augroup("WorkspaceEventBridging", { clear = true })

local function fire_doc_event(bufnr, event_name)
  if not _G.workspace or not _G.workspace.workspace then return end
  if vim.bo[bufnr].buftype ~= "" then return end
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" then return end
  
  local doc = _G.workspace.workspace.create_text_document(bufnr, path)
  local ev = _G.workspace.workspace[event_name]
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
local lsp_group = vim.api.nvim_create_augroup("WorkspaceLspAttach", { clear = true })
vim.api.nvim_create_autocmd("LspAttach", {
  group = lsp_group,
  callback = function(args)
    vim.schedule(function()
      sync_lsp_folders(args.buf)
    end)
  end,
})
