local M = {}

local uv = vim.uv or vim.loop
local is_windows = vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1
local path_sep = is_windows and ';' or ':'
local dir_sep = package.config:sub(1, 1)

local function join(...)
  return table.concat({ ... }, dir_sep)
end

local function exists(path)
  return path ~= nil and uv.fs_stat(path) ~= nil
end

local function prepend_path(path_value, entry)
  if not entry or entry == '' then
    return path_value
  end
  if not exists(entry) then
    return path_value
  end

  local current = path_value or ''
  local padded = path_sep .. current .. path_sep
  if padded:find(path_sep .. entry .. path_sep, 1, true) then
    return current
  end

  if current == '' then
    return entry
  end
  return entry .. path_sep .. current
end

local function split_args(raw)
  if raw == nil or raw == '' then
    return {}
  end
  return vim.split(raw, '%s+', { trimempty = true })
end

function M.find_project_root(path)
  local start_path = path

  if start_path == nil or start_path == '' then
    local current_file = vim.api.nvim_buf_get_name(0)
    if current_file ~= '' then
      start_path = vim.fs.dirname(current_file)
    else
      start_path = vim.fn.getcwd()
    end
  else
    local stat = uv.fs_stat(start_path)
    if stat and stat.type == 'file' then
      start_path = vim.fs.dirname(start_path)
    end
  end

  local marker = vim.fs.find({ 'pubspec.yaml', '.git' }, { upward = true, path = start_path })[1]
  if marker then
    return vim.fs.dirname(marker)
  end

  return start_path
end

local function flutter_sdk_root(project_root)
  if not project_root or project_root == '' then
    return nil
  end
  return join(project_root, '.fvm', 'flutter_sdk')
end

local function flutter_bin(project_root)
  local sdk_root = flutter_sdk_root(project_root)
  if not sdk_root then
    return nil
  end
  return join(sdk_root, 'bin')
end

local function dart_bin(project_root)
  local fbin = flutter_bin(project_root)
  if not fbin then
    return nil
  end
  return join(fbin, 'cache', 'dart-sdk', 'bin')
end

function M.resolve_flutter_cmd(project_root)
  local fbin = flutter_bin(project_root)
  if fbin then
    local local_flutter = join(fbin, is_windows and 'flutter.bat' or 'flutter')
    if exists(local_flutter) and vim.fn.executable(local_flutter) == 1 then
      return { local_flutter }
    end
  end

  if vim.fn.executable('fvm') == 1 then
    return { 'fvm', 'flutter' }
  end

  if vim.fn.executable('flutter') == 1 then
    return { 'flutter' }
  end

  return nil
end

function M.resolve_dartls_cmd(project_root)
  local dbin = dart_bin(project_root)
  if dbin then
    local local_dart = join(dbin, is_windows and 'dart.exe' or 'dart')
    if exists(local_dart) and vim.fn.executable(local_dart) == 1 then
      return { local_dart, 'language-server', '--protocol=lsp' }
    end
  end

  local global_dart = vim.fn.exepath('dart')
  if global_dart ~= '' then
    return { global_dart, 'language-server', '--protocol=lsp' }
  end

  return nil
end

function M.dartls_env(project_root, base_env)
  local env = vim.tbl_extend('force', {}, base_env or {})
  local path_value = env.PATH or vim.env.PATH or ''
  local sdk_root = flutter_sdk_root(project_root)
  local fbin = flutter_bin(project_root)
  local dbin = dart_bin(project_root)

  path_value = prepend_path(path_value, dbin)
  path_value = prepend_path(path_value, fbin)
  env.PATH = path_value

  if sdk_root and exists(sdk_root) then
    env.FLUTTER_ROOT = sdk_root
  end

  return env
end

local function open_task_terminal(cmd, cwd, title)
  vim.cmd('botright 12split')
  vim.cmd('enew')
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buflisted = false
  if title and title ~= '' then
    pcall(vim.api.nvim_buf_set_name, buf, title)
  end
  vim.fn.termopen(cmd, { cwd = cwd })
  vim.cmd('startinsert')
end

local function run_flutter_task(subcommand, extra_args, title)
  local root = M.find_project_root()
  local flutter_cmd = M.resolve_flutter_cmd(root)

  if not flutter_cmd then
    vim.notify('Flutter executable not found. Install Flutter or FVM.', vim.log.levels.ERROR)
    return
  end

  local full_cmd = vim.deepcopy(flutter_cmd)
  vim.list_extend(full_cmd, subcommand)
  vim.list_extend(full_cmd, extra_args)

  open_task_terminal(full_cmd, root, title)
end

local function recreate_user_command(name, callback, opts)
  pcall(vim.api.nvim_del_user_command, name)
  vim.api.nvim_create_user_command(name, callback, opts or {})
end

local function dartls_attached(bufnr)
  if vim.lsp.get_clients then
    return #vim.lsp.get_clients({ bufnr = bufnr, name = 'dartls' }) > 0
  end

  for _, client in ipairs(vim.lsp.get_active_clients()) do
    if client.name == 'dartls' then
      return true
    end
  end

  return false
end

local function maybe_start_dartls(bufnr)
  if vim.g.nvim_l_disable_local_dartls_auto == 1 then
    return
  end
  if not vim.api.nvim_buf_is_valid(bufnr) or dartls_attached(bufnr) then
    return
  end

  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local root = M.find_project_root(file_path)
  local cmd = M.resolve_dartls_cmd(root)
  if not cmd then
    return
  end

  vim.api.nvim_buf_call(bufnr, function()
    vim.lsp.start({
      name = 'dartls',
      cmd = cmd,
      cmd_env = M.dartls_env(root),
      root_dir = root,
      init_options = {
        closingLabels = true,
        flutterOutline = true,
        onlyAnalyzeProjectsWithOpenFiles = false,
        outline = true,
        suggestFromUnimportedLibraries = true,
      },
      settings = {
        dart = {
          completeFunctionCalls = true,
          showTodos = true,
        },
      },
    })
  end)
end

function M.setup()
  if vim.g.nvim_l_flutter_setup == 1 then
    return
  end
  vim.g.nvim_l_flutter_setup = 1

  recreate_user_command('ProjectFlutterRun', function(opts)
    run_flutter_task({ 'run' }, split_args(opts.args), 'term://flutter-run')
  end, { nargs = '*' })

  recreate_user_command('ProjectFlutterTest', function(opts)
    run_flutter_task({ 'test' }, split_args(opts.args), 'term://flutter-test')
  end, { nargs = '*' })

  recreate_user_command('ProjectFlutterAnalyze', function(opts)
    run_flutter_task({ 'analyze' }, split_args(opts.args), 'term://flutter-analyze')
  end, { nargs = '*' })

  recreate_user_command('ProjectFlutterPubGet', function()
    run_flutter_task({ 'pub', 'get' }, {}, 'term://flutter-pub-get')
  end, { nargs = 0 })

  recreate_user_command('ProjectFlutterGen', function()
    run_flutter_task({ 'pub', 'run', 'build_runner', 'build', '--delete-conflicting-outputs' }, {}, 'term://flutter-gen')
  end, { nargs = 0 })

  recreate_user_command('ProjectFlutterWatch', function()
    run_flutter_task({ 'pub', 'run', 'build_runner', 'watch', '--delete-conflicting-outputs' }, {}, 'term://flutter-watch')
  end, { nargs = 0 })

  recreate_user_command('ProjectDartLspStart', function()
    maybe_start_dartls(vim.api.nvim_get_current_buf())
  end, { nargs = 0 })

  local flutter_group = vim.api.nvim_create_augroup('NvimLFlutter', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = flutter_group,
    pattern = 'dart',
    callback = function(args)
      vim.bo[args.buf].expandtab = true
      vim.bo[args.buf].shiftwidth = 2
      vim.bo[args.buf].tabstop = 2

      local opts = { buffer = args.buf, silent = true }
      vim.keymap.set('n', '<leader>Fr', '<cmd>ProjectFlutterRun<cr>', vim.tbl_extend('force', opts, { desc = 'Flutter run' }))
      vim.keymap.set('n', '<leader>Ft', '<cmd>ProjectFlutterTest<cr>', vim.tbl_extend('force', opts, { desc = 'Flutter test' }))
      vim.keymap.set('n', '<leader>Fa', '<cmd>ProjectFlutterAnalyze<cr>', vim.tbl_extend('force', opts, { desc = 'Flutter analyze' }))
      vim.keymap.set('n', '<leader>Fp', '<cmd>ProjectFlutterPubGet<cr>', vim.tbl_extend('force', opts, { desc = 'Flutter pub get' }))
      vim.keymap.set('n', '<leader>Fg', '<cmd>ProjectFlutterGen<cr>', vim.tbl_extend('force', opts, { desc = 'Flutter codegen build' }))
      vim.keymap.set('n', '<leader>Fw', '<cmd>ProjectFlutterWatch<cr>', vim.tbl_extend('force', opts, { desc = 'Flutter codegen watch' }))
      vim.keymap.set('n', 'gd', vim.lsp.buf.definition, vim.tbl_extend('force', opts, { desc = 'LSP: goto definition' }))
      vim.keymap.set('n', 'K', vim.lsp.buf.hover, vim.tbl_extend('force', opts, { desc = 'LSP: hover' }))

      vim.defer_fn(function()
        maybe_start_dartls(args.buf)
      end, 500)
    end,
  })
end

return M
