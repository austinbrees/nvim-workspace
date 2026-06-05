local Uri = {}
Uri.__index = Uri

local is_windows = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1

--- Constructor for Uri
---@param fields table {scheme: string, authority: string, path: string, query: string, fragment: string}
---@return table Uri object
function Uri.new(fields)
  local self = setmetatable({}, Uri)
  self.scheme = fields.scheme or ""
  self.authority = fields.authority or ""
  self.path = fields.path or ""
  self.query = fields.query or ""
  self.fragment = fields.fragment or ""
  
  -- Calculate fsPath
  local fsPath = self.path
  if self.scheme == "file" then
    if is_windows then
      -- If Windows, replace forward slashes with backslashes
      -- If path starts with a slash before drive letter like /C:/..., strip the leading slash
      if fsPath:match("^/[a-zA-Z]:") then
        fsPath = fsPath:sub(2)
      end
      fsPath = fsPath:gsub("/", "\\")
    end
  end
  self.fsPath = fsPath
  return self
end

--- Create a Uri representing a local file path.
---@param path string
---@return table Uri object
function Uri.file(path)
  path = vim.fn.resolve(vim.fn.expand(path))
  if is_windows then
    path = path:gsub("\\", "/")
  end
  return Uri.new({
    scheme = "file",
    path = path,
  })
end

--- Parse a string URI into a Uri object.
---@param val string|table
---@return table Uri object
function Uri.parse(val)
  if type(val) == "table" and val.scheme then
    return val -- Already a Uri object
  end
  
  local scheme, rest = val:match("^([^:]+):(.*)$")
  if not scheme then
    -- If no scheme is present, treat it as a file system path
    return Uri.file(val)
  end
  
  local authority = ""
  local path = rest
  local query = ""
  local fragment = ""
  
  -- Split authority and path
  if path:sub(1, 2) == "//" then
    local content = path:sub(3)
    local first_slash = content:find("/")
    if first_slash then
      authority = content:sub(1, first_slash - 1)
      path = content:sub(first_slash)
    else
      authority = content
      path = ""
    end
  end
  
  -- Split fragment (#)
  local hash_idx = path:find("#")
  if hash_idx then
    fragment = path:sub(hash_idx + 1)
    path = path:sub(1, hash_idx - 1)
  end
  
  -- Split query (?)
  local q_idx = path:find("%?")
  if q_idx then
    query = path:sub(q_idx + 1)
    path = path:sub(1, q_idx - 1)
  end
  
  return Uri.new({
    scheme = scheme,
    authority = authority,
    path = path,
    query = query,
    fragment = fragment,
  })
end

--- Serialize Uri to string.
---@return string
function Uri:toString()
  local str = self.scheme .. "://"
  if self.authority ~= "" then
    str = str .. self.authority
  end
  str = str .. self.path
  if self.query ~= "" then
    str = str .. "?" .. self.query
  end
  if self.fragment ~= "" then
    str = str .. "#" .. self.fragment
  end
  return str
end

function Uri:__tostring()
  return self:toString()
end

return Uri
