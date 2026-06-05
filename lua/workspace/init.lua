local M = {}

M.default_config = {
  terminal_position = "horizontal", -- "horizontal" | "vertical" | "tab" | "float"
  terminal_size = 15,                -- Default window size for terminal splits
  auto_lsp = true,                   -- Auto-sync workspace folders to LSP
  hijack_search = true,              -- Hijack Telescope, Fzf-lua, and Snacks.picker automatically
}

--- Setup the plugin configuration and inject global `workspace` variable.
---@param user_config table? User-provided custom configurations
function M.setup(user_config)
  _G.workspace_config = vim.tbl_deep_extend("force", M.default_config, user_config or {})
  
  -- Expose the global workspace emulation namespace
  _G.workspace = {
    Uri = require("workspace.uri"),
    workspace = require("workspace.workspace"),
    window = require("workspace.window"),
    commands = require("workspace.commands"),
  }

  -- Initialize search hijacking
  require("workspace.search").setup()
end

return M
