local M = {}

M.default_config = {
  terminal_position = "horizontal", -- "horizontal" | "vertical" | "tab" | "float"
  terminal_size = 15,                -- Default window size for terminal splits
  auto_lsp = true,                   -- Auto-sync workspace folders to LSP
  hijack_search = true,              -- Hijack Telescope, Fzf-lua, and Snacks.picker automatically
}

--- Setup the plugin configuration and inject global `vscode` variable.
---@param user_config table? User-provided custom configurations
function M.setup(user_config)
  _G.vscode_config = vim.tbl_deep_extend("force", M.default_config, user_config or {})
  
  -- Expose the global vscode emulation namespace
  _G.vscode = {
    Uri = require("vscode.uri"),
    workspace = require("vscode.workspace"),
    window = require("vscode.window"),
    commands = require("vscode.commands"),
  }

  -- Initialize search hijacking
  require("vscode.search").setup()
end

return M
