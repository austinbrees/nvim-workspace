# vscode.nvim

`vscode.nvim` is a Neovim plugin that emulates the Visual Studio Code Extension API namespaces in Lua. It exposes a global `vscode` object that allows user configurations, scripts, and other plugins to query workspace folders, read workspace configuration settings (supporting `.code-workspace` JSONC files), spawn terminals, prompt messages, and register command or document lifecycle listeners exactly like VS Code extensions.

---

## Features

- **Global `vscode` Variable**: Provides 1-to-1 matching namespaces (`vscode.Uri`, `vscode.workspace`, `vscode.window`, `vscode.commands`) inside Neovim Lua.
- **VS Code Workspaces**: Parses and loads `.code-workspace` files (JSONC) to set up multi-root workspaces.
- **LSP Dynamic Syncing**: Automatically registers workspace folders to running LSP clients (supporting `gopls`, `vtsls`, `pyright`, etc.) for workspace-wide indexing.
- **Integrated Terminal Creator**: Emulates `vscode.window.createTerminal`, opening split or floating windows running shells in workspace roots.
- **Clean Event Lifecycle**: Bridges Neovim's autocmds into event lists (like `onDidOpenTextDocument`, `onDidChangeTextDocument`, and `onDidSaveTextDocument`) with clean, disposable event handlers.
- **Settings Configuration**: Scopes setting values using `.get()` and `.has()` from `.code-workspace` files.

---

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "austinbrees/vscode.nvim",
  config = function()
    require("vscode").setup({
      terminal_position = "horizontal", -- "horizontal" | "vertical" | "tab" | "float"
      terminal_size = 15,                -- Size of terminal window split
      auto_lsp = true,                   -- Sync workspace folders to active LSP servers
    })
  end
}
```

---

## User Commands

| Command | Description |
|---|---|
| `:WorkspaceOpen [path]` | Opens a workspace file. If no path is provided, walks up from CWD to find a `.code-workspace` file, otherwise falling back to recent history. |
| `:WorkspaceAddFolder [dir]` | Adds a folder path to the active workspace. If currently in single-root CWD mode, enters a transient (untitled) workspace. |
| `:WorkspaceSaveAs [path]` | Saves the active workspace configuration to a `.code-workspace` file. |
| `:WorkspaceClose` | Closes the active workspace, resetting folders back to Neovim CWD. |
| `:WorkspaceExplorer` | Opens/switches your file explorer (e.g. Neo-tree, falling back to Netrw) to the virtual workspace root folder. |
| `:WorkspaceFiles` | Performs a Telescope find_files search across all workspace folders simultaneously. |
| `:WorkspaceGrep` | Performs a Telescope live_grep search across all workspace folders simultaneously. |

---

## API Reference & Usage

The emulated `vscode` object behaves just like the JS/TS counterpart:

### `vscode.Uri`

Handles URI schemas, file paths, and cross-platform formatting.

```lua
-- Create file URI
local uri = vscode.Uri.file("/Users/user/project/main.lua")
print(uri.scheme) -- "file"
print(uri.path)   -- "/Users/user/project/main.lua"
print(uri.fsPath) -- "/Users/user/project/main.lua"

-- Parse arbitrary URI string
local raw_uri = vscode.Uri.parse("file:///Users/user/project/main.lua#L20?q=test")
print(raw_uri.fragment) -- "L20"
print(raw_uri.query)    -- "q=test"
```

### `vscode.workspace`

Manage multi-root directories, configurations, document queries, and event registrations.

```lua
-- Get workspace state
local name = vscode.workspace.name
local file = vscode.workspace.workspaceFile -- Uri object or nil
local folders = vscode.workspace.workspaceFolders -- Array of folders {uri, name, index}

-- Retrieve scoped configuration (defined in .code-workspace settings block)
local editor_config = vscode.workspace.getConfiguration("editor")
local tab_size = editor_config.get("tabSize") -- 2
local format_on_save = editor_config.has("formatOnSave") -- true

-- Resolve containing folder of a file
local folder = vscode.workspace.getWorkspaceFolder(vscode.Uri.file("/path/to/project/main.lua"))

-- Convert path to relative path
local rel_path = vscode.workspace.asRelativePath("/path/to/project/src/index.js", false) -- "src/index.js"

-- Find files using glob pattern
local files = vscode.workspace.findFiles("**/*.lua") -- returns list of Uri objects

-- Register document events (returns a disposable handle)
local disposable = vscode.workspace.onDidOpenTextDocument(function(document)
  print("Document opened: " .. document.fileName)
  print("Language: " .. document.languageId)
end)

-- Later, to unregister:
disposable.dispose()
```

### `vscode.window`

Manages terminal windows, active text buffers, and message modals.

```lua
-- Create and run a terminal inside a specific workspace directory
local term = vscode.window.createTerminal({
  name = "Build Server",
  cwd = vscode.Uri.file("/Users/user/project/backend"),
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
local editor = vscode.window.activeTextEditor
if editor then
  print("Active buffer path: " .. editor.document.fileName)
  print("Cursor coordinates: line " .. editor.selection.active.line .. ", char " .. editor.selection.active.character)
end

-- Show an interactive notification with selection options (returns a Promise-like object)
vscode.window.showInformationMessage("Select your layout", "Grid", "List"):then(function(choice)
  if choice == "Grid" then
    print("User chose Grid!")
  end
end)
```

### `vscode.commands`

Register and execute custom commands programmatically.

```lua
-- Register a custom command
local disp = vscode.commands.registerCommand("extension.sayHello", function(name)
  vim.notify("Hello " .. (name or "World"))
end)

-- Execute command
vscode.commands.executeCommand("extension.sayHello", "Austin")

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
