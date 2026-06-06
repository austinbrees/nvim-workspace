# nvim-workspace

`nvim-workspace` is a Neovim plugin that emulates the Visual Studio Code Multi-Root Workspace model in Lua. It exposes a global `workspace` object that allows user configurations, scripts, and other plugins to query workspace folders, read workspace configuration settings (supporting `.code-workspace` JSONC files), spawn terminals, prompt messages, and register command or document lifecycle listeners natively.

---

## Features

- **Global `workspace` Variable**: Provides 1-to-1 matching namespaces (`workspace.Uri`, `workspace.workspace`, `workspace.window`, `workspace.commands`) inside Neovim Lua.
- **VS Code Workspaces Compatibility**: Parses and loads `.code-workspace` files (JSONC) to set up multi-root workspaces.
- **LSP Dynamic Syncing**: Automatically registers workspace folders to running LSP clients (supporting `gopls`, `vtsls`, `pyright`, etc.) for workspace-wide indexing.
- **Integrated Terminal Creator**: Emulates `workspace.window.createTerminal`, opening split or floating windows running shells in workspace roots.
- **Clean Event Lifecycle**: Bridges Neovim's autocmds into event lists (like `onDidOpenTextDocument`, `onDidChangeTextDocument`, and `onDidSaveTextDocument`) with clean, disposable event handlers.
- **Settings Configuration**: Scopes setting values using `.get()` and `.has()` from `.code-workspace` files.
- **Transparent Search Hijacking**: Intercepts Telescope, Fzf-lua, and Snacks.picker calls to automatically search all workspace folders.

---

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "austinbrees/nvim-workspace",
  config = function()
    require("workspace").setup({
      terminal_position = "horizontal", -- "horizontal" | "vertical" | "tab" | "float"
      terminal_size = 15,                -- Size of terminal window split
      auto_lsp = true,                   -- Sync workspace folders to active LSP servers
      hijack_search = true,              -- Intercept and search across all workspace folders automatically
    })
  end
}
```

---

## User Commands

| Command | Description |
|---|---|
| `:WorkspaceOpen [path]` | Opens a workspace file. If no path is provided, walks up from CWD to find a `.code-workspace` file, otherwise falling back to recent history. |
| `:WorkspaceAddFolder [dir]` | Adds a folder path to the active workspace. If no path is provided, displays an interactive selector menu allowing you to: 1. Add the active file/explorer directory directly (works with Neo-tree, netrw, and oil.nvim), 2. Browse/navigate the filesystem (upstream/downstream) visually via Telescope, 3. Browse directories via a native macOS File Dialog (on macOS), 4. Fuzzy find directories recursively using Telescope, or 5. Input a folder path manually. If currently in single-root CWD mode, enters a transient (untitled) workspace. |
| `:WorkspaceSaveAs [path]` | Saves the active workspace configuration to a `.code-workspace` file. |
| `:WorkspaceClose` | Closes the active workspace, resetting folders back to Neovim CWD. |
| `:WorkspaceExplorer` | Opens/switches your file explorer (e.g. Neo-tree, falling back to Netrw) to the virtual workspace root folder. |
| `:WorkspaceFiles` | Performs a Telescope find_files search across all workspace folders simultaneously. |
| `:WorkspaceGrep` | Performs a Telescope live_grep search across all workspace folders simultaneously. |

---

## API Reference & Usage

The emulated `workspace` object behaves just like the JS/TS counterpart:

### `workspace.Uri`

Handles URI schemas, file paths, and cross-platform formatting.

```lua
-- Create file URI
local uri = workspace.Uri.file("/Users/user/project/main.lua")
print(uri.scheme) -- "file"
print(uri.path)   -- "/Users/user/project/main.lua"
print(uri.fsPath) -- "/Users/user/project/main.lua"

-- Parse arbitrary URI string
local raw_uri = workspace.Uri.parse("file:///Users/user/project/main.lua#L20?q=test")
print(raw_uri.fragment) -- "L20"
print(raw_uri.query)    -- "q=test"
```

### `workspace.workspace`

Manage multi-root directories, configurations, document queries, and event registrations.

```lua
-- Get workspace state
local name = workspace.workspace.name
local file = workspace.workspace.workspaceFile -- Uri object or nil
local folders = workspace.workspace.workspaceFolders -- Array of folders {uri, name, index}

-- Retrieve scoped configuration (defined in .code-workspace settings block)
local editor_config = workspace.workspace.getConfiguration("editor")
local tab_size = editor_config.get("tabSize") -- 2
local format_on_save = editor_config.has("formatOnSave") -- true

-- Resolve containing folder of a file
local folder = workspace.workspace.getWorkspaceFolder(workspace.Uri.file("/path/to/project/main.lua"))

-- Convert path to relative path
local rel_path = workspace.workspace.asRelativePath("/path/to/project/src/index.js", false) -- "src/index.js"

-- Find files using glob pattern
local files = workspace.workspace.findFiles("**/*.lua") -- returns list of Uri objects

-- Register document events (returns a disposable handle)
local disposable = workspace.workspace.onDidOpenTextDocument(function(document)
  print("Document opened: " .. document.fileName)
  print("Language: " .. document.languageId)
end)

-- Later, to unregister:
disposable.dispose()
```

### `workspace.window`

Manages terminal windows, active text buffers, and message modals.

```lua
-- Create and run a terminal inside a specific workspace directory
local term = workspace.window.createTerminal({
  name = "Build Server",
  cwd = workspace.Uri.file("/Users/user/project/backend"),
  shellPath = "/bin/zsh",
  env = { PORT = "8080" }
})

-- Show terminal split
term:show()

-- Send a command to the terminal
term:sendText("npm run dev")

-- Close/dispose the terminal buffer
term:dispose()

-- Query active editor buffer
local editor = workspace.window.activeTextEditor
if editor then
  print("Active buffer path: " .. editor.document.fileName)
  print("Cursor coordinates: line " .. editor.selection.active.line .. ", char " .. editor.selection.active.character)
end

-- Show an interactive notification with selection options (returns a Promise-like object)
workspace.window.showInformationMessage("Select your layout", "Grid", "List"):then(function(choice)
  if choice == "Grid" then
    print("User chose Grid!")
  end
end)
```

### `workspace.commands`

Register and execute custom commands programmatically.

```lua
-- Register a custom command
local disp = workspace.commands.registerCommand("extension.sayHello", function(name)
  vim.notify("Hello " .. (name or "World"))
end)

-- Execute command
workspace.commands.executeCommand("extension.sayHello", "Austin")

-- Unregister command
disp.dispose()
```

---

## Configuration Options

When calling `setup()`, you can customize:

| Option | Type | Default | Description |
|---|---|---|---|
| `terminal_position` | `string` | `"horizontal"` | Position layout for terminal splits (`"horizontal"`, `"vertical"`, `"tab"`, `"float"`). |
| `terminal_size` | `number` | `15` | Default height (horizontal split) or width (vertical split) of the terminal. |
| `auto_lsp` | `boolean` | `true` | Automatically calls `vim.lsp.buf.add_workspace_folder` for all loaded folders on LSP client attach. |
| `hijack_search` | `boolean` | `true` | Intercepts Telescope, Fzf-lua, and Snacks.picker calls to automatically search all workspace folders. |

---

## License

MIT
