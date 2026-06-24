-- Symbol index: cross-layer go-to-definition for proto / graphql / resolver code.
-- Activates only in repos that have both a `protos/` dir and a buf config.

local M = {}

local uv = vim.uv or vim.loop
local scripts_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h') .. '/scripts/symbol-index'

local function sha1(s)
  return vim.fn.sha256(s):sub(1, 12)
end

local function find_repo_root(start)
  start = vim.fn.fnamemodify(start, ':p')
  local dir = vim.fs.dirname(start)
  while dir and dir ~= '/' do
    if uv.fs_stat(dir .. '/protos') and (
       uv.fs_stat(dir .. '/buf.yaml') or
       uv.fs_stat(dir .. '/buf/buf.yaml')
    ) then
      return dir
    end
    local parent = vim.fs.dirname(dir)
    if parent == dir then break end
    dir = parent
  end
  return nil
end

local function cache_dir_for(root)
  local d = vim.fn.stdpath('cache') .. '/symbol-index/' .. sha1(root)
  vim.fn.mkdir(d, 'p')
  return d
end

local repos = {}

local function load_tsv(path)
  local t = {}
  local f = io.open(path, 'r')
  if not f then return t end
  for line in f:lines() do
    local k, v = line:match('^([^\t]+)\t(.+)$')
    if k then t[k] = v end
  end
  f:close()
  return t
end

local function load_all(state)
  state.tables = {
    proto = load_tsv(state.cache_dir .. '/proto-symbols.tsv'),
    r2g   = load_tsv(state.cache_dir .. '/resolver-to-gql.tsv'),
    g2r   = load_tsv(state.cache_dir .. '/gql-to-resolver.tsv'),
  }
end

local function build(state, on_done)
  vim.system(
    { scripts_dir .. '/build-all.sh', state.root, state.cache_dir },
    { text = true },
    vim.schedule_wrap(function(res)
      if res.code ~= 0 then
        vim.notify('symbol-index build failed: ' .. (res.stderr or ''), vim.log.levels.WARN)
      end
      load_all(state)
      if on_done then on_done() end
    end)
  )
end

local function get_state(root)
  local s = repos[root]
  if s then return s end
  s = { root = root, cache_dir = cache_dir_for(root), tables = nil }
  repos[root] = s
  if uv.fs_stat(s.cache_dir .. '/proto-symbols.tsv') then
    load_all(s)
  else
    build(s)
  end
  return s
end

local function pick_table(state, bufname)
  local lower = bufname:lower()
  if lower:match('%.pb%.go$') or lower:match('%.proto$') then
    return state.tables.proto
  end
  if lower:match('resolvers.*%.go$') or lower:match('%.resolvers%.go$') then
    return state.tables.r2g
  end
  if lower:match('%.graphql$') or lower:match('%.graphqls$') then
    return state.tables.g2r
  end
  return nil
end

function M.jump()
  local bufname = vim.api.nvim_buf_get_name(0)
  if bufname == '' then return false end
  local root = find_repo_root(bufname)
  if not root then return false end
  local state = get_state(root)
  if not state.tables then return false end

  local sym = vim.fn.expand('<cword>')
  if sym == '' then return false end
  local tbl = pick_table(state, bufname)
  if not tbl then return false end
  local loc = tbl[sym]
  if not loc then return false end

  local file, line = loc:match('^(.-):(%d+)$')
  if not file then return false end
  if not file:match('^/') then file = root .. '/' .. file end
  vim.cmd('edit +' .. line .. ' ' .. vim.fn.fnameescape(file))
  return true
end

function M.rebuild()
  local bufname = vim.api.nvim_buf_get_name(0)
  local root = bufname ~= '' and find_repo_root(bufname) or find_repo_root(vim.fn.getcwd())
  if not root then
    vim.notify('symbol-index: no protos/+buf config found upward from buffer/cwd', vim.log.levels.WARN)
    return
  end
  local state = get_state(root)
  vim.notify('symbol-index: rebuilding ' .. root)
  build(state, function()
    vim.notify('symbol-index: rebuilt (' .. (vim.tbl_count(state.tables.proto) +
      vim.tbl_count(state.tables.r2g) + vim.tbl_count(state.tables.g2r)) .. ' symbols)')
  end)
end

function M.setup()
  vim.api.nvim_create_user_command('SymbolIndexBuild', M.rebuild, {})

  local grp = vim.api.nvim_create_augroup('SymbolIndex', { clear = true })

  vim.api.nvim_create_autocmd('BufEnter', {
    group = grp,
    callback = function(args)
      local name = vim.api.nvim_buf_get_name(args.buf)
      if name == '' then return end
      if not find_repo_root(name) then return end
      vim.keymap.set('n', 'gd', function()
        if not M.jump() then vim.lsp.buf.definition() end
      end, { buffer = args.buf, desc = 'Goto def (symbol-index + LSP)' })
    end,
  })

  vim.api.nvim_create_autocmd('BufWritePost', {
    group = grp,
    pattern = { '*.proto', '*.graphql', '*.graphqls', '*resolvers*.go' },
    callback = function(args)
      local root = find_repo_root(vim.api.nvim_buf_get_name(args.buf))
      if not root then return end
      build(get_state(root))
    end,
  })
end

return M
