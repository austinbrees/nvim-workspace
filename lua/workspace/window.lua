local M = {}

local Uri = require("workspace.uri")

local Terminal = {}

--- Constructor for Terminal
---@param options table
---@return table Terminal object
function Terminal.new(options)
  options = options or {}
  local self = {}
  self.name = options.name or "Terminal"
  self.bufnr = vim.api.nvim_create_buf(false, true)
  
  -- Set unlisted buffer name
  vim.api.nvim_buf_set_name(self.bufnr, self.name)
  
  local job_id = 0
  vim.api.nvim_buf_call(self.bufnr, function()
    local spawn_opts = {}
    
    -- Handle directory
    if options.cwd then
      local cwd_path = type(options.cwd) == "table" and options.cwd.fsPath or options.cwd
      spawn_opts.cwd = vim.fn.resolve(vim.fn.expand(cwd_path))
    end
    
    -- Handle environment variables
    if options.env then
      spawn_opts.env = options.env
    end
    
    -- Resolve shell
    local cmd = options.shellPath or vim.o.shell
    if options.shellArgs then
      local shell_cmd = { cmd }
      for _, arg in ipairs(options.shellArgs) do
        table.insert(shell_cmd, arg)
      end
      cmd = shell_cmd
    end
    
    -- Spawn terminal inside the buffer
    job_id = vim.fn.termopen(cmd, spawn_opts)
  end)
  
  self.processId = job_id
  
  -- Method: show
  function self.show(preserve_focus_or_self, preserve_focus)
    local actual_preserve = preserve_focus_or_self
    if type(preserve_focus_or_self) == "table" then
      actual_preserve = preserve_focus
    end
    
    local win = vim.fn.bufwinid(self.bufnr)
    if win == -1 then
      local position = _G.workspace_config and _G.workspace_config.terminal_position or "horizontal"
      local size = _G.workspace_config and _G.workspace_config.terminal_size or 15
      
      if position == "vertical" then
        vim.cmd("vertical " .. size .. "new")
      elseif position == "tab" then
        vim.cmd("tabnew")
      elseif position == "float" then
        local width = math.floor(vim.o.columns * 0.8)
        local height = math.floor(vim.o.lines * 0.8)
        local row = math.floor((vim.o.lines - height) / 2)
        local col = math.floor((vim.o.columns - width) / 2)
        local win_opts = {
          relative = "editor",
          width = width,
          height = height,
          row = row,
          col = col,
          style = "minimal",
          border = "rounded",
        }
        win = vim.api.nvim_open_win(self.bufnr, true, win_opts)
      else
        vim.cmd(size .. "new")
      end
      
      if position ~= "float" then
        win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(win, self.bufnr)
      end
    end
    
    if not actual_preserve then
      vim.api.nvim_set_current_win(win)
      vim.cmd("startinsert")
    end
  end
  
  -- Method: sendText
  function self.sendText(text_or_self, text_or_newline, addNewLine)
    local actual_text = text_or_self
    local actual_newline = text_or_newline
    
    if type(text_or_self) == "table" then
      actual_text = text_or_newline
      actual_newline = addNewLine
    end
    
    if actual_newline == nil or actual_newline == true then
      actual_text = actual_text .. "\n"
    end
    vim.api.nvim_chan_send(self.processId, actual_text)
  end
  
  -- Method: dispose
  function self.dispose()
    if vim.api.nvim_buf_is_valid(self.bufnr) then
      vim.api.nvim_buf_delete(self.bufnr, { force = true })
    end
  end
  
  return self
end


--- Create a terminal.
---@param options table
---@return table Terminal object
function M.createTerminal(options)
  return Terminal.new(options)
end

--- Show an information message with selection list.
---@param message string
---@vararg string List of buttons/options
---@return table Promise-like object supporting .then(callback)
function M.showInformationMessage(message, ...)
  local items = { ... }
  local promise = {}
  
  function promise.then_cb(callback)
    if #items == 0 then
      vim.notify(message, vim.log.levels.INFO)
      if callback then callback(nil) end
    else
      vim.ui.select(items, {
        prompt = message,
      }, function(choice)
        if callback then
          callback(choice)
        end
      end)
    end
  end
  
  promise["then"] = function(t, callback)
    t.then_cb(callback)
  end
  
  setmetatable(promise, {
    __call = function(t, callback)
      t.then_cb(callback)
    end
  })
  
  return promise
end

-- Hook activeTextEditor property
local get_active_editor_meta = {
  __index = function(t, key)
    if key == "activeTextEditor" then
      local bufnr = vim.api.nvim_get_current_buf()
      -- Filter out non-editor buffers
      if vim.bo[bufnr].buftype ~= "" then
        return nil
      end
      local path = vim.api.nvim_buf_get_name(bufnr)
      local workspace = require("workspace.workspace")
      local doc = workspace.create_text_document(bufnr, path)
      
      local cursor = vim.api.nvim_win_get_cursor(0)
      local line = cursor[1] - 1
      local character = cursor[2]
      local pos = { line = line, character = character }
      
      return {
        document = doc,
        selection = {
          anchor = pos,
          active = pos,
          isEmpty = true
        }
      }
    end
    return rawget(t, key)
  end
}
setmetatable(M, get_active_editor_meta)

return M
