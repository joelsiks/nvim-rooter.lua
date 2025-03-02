local _config = {
  patterns = {},
  trigger_patterns = {},
  exclude_filetypes = {
    ['help'] = true,
    ['nofile'] = true,
    ['NvimTree'] = true,
    ['dashboard'] = true,
    ['TelescopePrompt'] = true,
  },
  fallback_to_parent = false,
}

local function parent_dir(dir)
  return vim.fn.fnamemodify(dir, ':h')
end

local function change_dir(dir)
  local cd_method = {
    global = vim.api.nvim_set_current_dir,
    window = vim.cmd.lcd,
    tabpage = vim.cmd.tcd,
    smart = vim.fn.chdir,
  }
  cd_method[_config.cd_scope](dir)
end

local function match(dir, pattern)
  if string.sub(pattern, 1, 1) == '=' then
    return vim.fn.fnamemodify(dir, ':t') == string.sub(pattern, 2, #pattern)
  else
    return vim.fn.globpath(dir, pattern) ~= ''
  end
end

local function matches(dir, patterns)
  for _, pattern in ipairs(patterns) do
    if match(dir, pattern) then
      return true
    end
  end
  return false
end

local function activate()
  if vim.g.SessionLoad == 1 then
    return false
  end

  if _config.exclude_filetypes[vim.bo.filetype] ~= nil then
    return false
  end

  local filename = vim.api.nvim_buf_get_name(0)
  for _, pattern in ipairs(_config.trigger_patterns) do
    -- https://riptutorial.com/lua/topic/5829/pattern-matching
    -- if filename:match(pattern) then -- should i use this or the one below?
    if vim.api.nvim_eval(string.format('"%s" =~ glob2regpat("%s")', filename, pattern)) == 1 then
      return true
    end
  end
  return false
end

local function get_root(patterns)
  patterns = patterns ~= nil and patterns or _config.patterns

  -- don't need to resove sybolic links explicitly, because
  -- `nvim_buf_get_name` returns the resolved path.
  local current = vim.api.nvim_buf_get_name(0)
  current = current == "" and vim.fn.getcwd() or current
  local parent = parent_dir(current)

  -- start by checking the current directory, if it matches we finish early.
  if matches(current, patterns) then
    return current
  end

  while 1 do
    if matches(parent, patterns) then
      return parent
    end

    -- go up a level
    current, parent = parent, parent_dir(parent)
    if parent == current then
      break
    end
  end
  return nil
end

local function apply_root(root)
  if root ~= nil then
    change_dir(root)
  elseif _config.fallback_to_parent then
    local buffer = vim.api.nvim_buf_get_name(0):gsub('^suda://', '', 1)
    local parent = parent_dir(buffer)
    if vim.fn.getcwd() ~= parent then
      change_dir(parent)
    end
  end
end

local function rooter_default()
  if not activate() then
    return
  end

  local root = vim.fn.exists('b:root_dir') == 1 and vim.api.nvim_buf_get_var(0, 'root_dir') or nil
  if root == nil then
    root = get_root()
    vim.api.nvim_buf_set_var(0, 'root_dir', root)
  end

  apply_root(root)
end

local function rooter_custom(pattern)
  if not activate() then
    return
  end

  local root = get_root(pattern)
  vim.api.nvim_buf_set_var(0, 'root_dir', root)
  apply_root(root)
end

local function rooter_toggle()
  local parent = parent_dir(vim.api.nvim_buf_get_name(0))
  if vim.fn.getcwd() ~= parent then
    change_dir(parent)
  else
    rooter_default()
  end
end

local function merge(tbl1, tbl2)
  -- Merges a "map" and a table
  -- tbl1 is considered to be the map and
  -- tbl2 is considered to be the table
  if tbl2 == nil then
    return tbl1
  end

  local res = {}
  for _, k in ipairs(tbl2) do
    res[k] = true
  end
  return vim.tbl_extend('force', tbl1, res)
end

local function setup_autocmd()
  local group_id = vim.api.nvim_create_augroup('nvim_rooter', { clear = true })
  local au = vim.api.nvim_create_autocmd

  au('BufRead', {
    group = group_id,
    callback = function()
      vim.api.nvim_buf_set_var(0, 'root_dir', nil)
    end,
  })

  au('BufEnter', {
    group = group_id,
    nested = true,
    callback = function()
      require('nvim-rooter').rooter_default()
    end,
  })
end

local function setup(opts)
  opts = opts ~= nil and opts or {}
  _config.patterns = opts.rooter_patterns ~= nil and opts.rooter_patterns
    or { '.git', '.hg', '.svn' }
  _config.trigger_patterns = opts.trigger_patterns ~= nil and opts.trigger_patterns or { '*' }
  _config.exclude_filetypes = merge(_config.exclude_filetypes, opts.exclude_filetypes)
  _config.fallback_to_parent = opts.fallback_to_parent ~= nil and opts.fallback_to_parent
  _config.cd_scope = opts.cd_scope ~= nil and opts.cd_scope or "global"

  if opts.manual == nil or opts.manual == false then
    setup_autocmd()
  end
end

return {
  setup = setup,
  rooter_default = rooter_default,
  rooter_custom = rooter_custom,
  rooter_toggle = rooter_toggle,
  get_root = get_root,
}
