vim.cmd([[
  command ToggleRelative lua ToggleRelative()
  command ToggleTabWidth lua ToggleTabWidth()
  " command GGL lua GenerateGithubLink()
  command GGLC lua GenerateGithubLinkCommit()
  command GoHeapYourself lua GoHeapYourself()
]])


function ToggleRelative()
  if vim.wo.relativenumber then
    vim.wo.relativenumber = false
  else
    vim.wo.relativenumber = true
  end
end

function ToggleTabWidth()
  local current_tab_width = vim.api.nvim_buf_get_option(0, "tabstop")

  if current_tab_width == 2 then
    vim.api.nvim_buf_set_option(0, "tabstop", 4)
    vim.api.nvim_buf_set_option(0, "shiftwidth", 4)
    vim.api.nvim_command('echo "Tab width set to 4"')
  elseif current_tab_width == 4 then
    vim.api.nvim_buf_set_option(0, "tabstop", 2)
    vim.api.nvim_buf_set_option(0, "shiftwidth", 2)
    vim.api.nvim_command('echo "Tab width set to 2"')
  else
    vim.api.nvim_command('echoerr "Invalid tab width"')
  end
end

function GenerateGithubLink()
  -- Get the Git root directory
  local git_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]

  -- Ensure the Git root directory ends with a slash
  if not string.match(git_root, "/$") then
    git_root = git_root .. "/"
  end

  -- Get the GitHub repository URL
  local github_remote_url = vim.fn.systemlist("git config --get remote.origin.url")[1]

  -- Remove the ".git" extension from the URL
  github_remote_url = string.gsub(github_remote_url, "%.git$", "")

  -- Convert the Git URL to a GitHub URL
  github_remote_url = string.gsub(github_remote_url, "git@github.com:", "https://github.com/")
  github_remote_url = string.gsub(github_remote_url, "git://github.com/", "https://github.com/")

  -- Get the current branch name
  local current_branch = vim.fn.systemlist("git rev-parse --abbrev-ref HEAD")[1]

  -- Get the upstream branch name if it exists
  -- local upstream_branch = vim.fn.systemlist("git rev-parse --abbrev-ref @{u}")[1]

  -- If an upstream branch exists, use it; otherwise, use the current branch
  -- local branch_name = upstream_branch ~= "" and upstream_branch or current_branch


  -- Get the file name of the currently open buffer
  local file_name = vim.fn.expand("%")

  -- Get the line number of the current cursor position
  local line_number = vim.fn.line(".")




  -- Construct the GitHub link
  local github_link = github_remote_url .. "/blob/" .. current_branch .. "/" .. file_name .. "#L" .. line_number

  print("Yanking:\n", github_link)
  vim.fn.setreg("+", github_link)
  vim.fn.setreg("*", github_link)

  return github_link
end



local function GenerateGithubLink()
  -- Check if we're in a Git repository
  if vim.fn.system("git rev-parse --is-inside-work-tree"):match("true") == nil then
    vim.notify("Not in a Git repository", vim.log.levels.ERROR)
    return
  end

  -- Get the Git root directory
  local git_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
  git_root = git_root:gsub("/$", "") .. "/"

  -- Get the GitHub repository URL
  local github_remote_url = vim.fn.systemlist("git config --get remote.origin.url")[1]
  if not github_remote_url then
    vim.notify("No remote 'origin' found", vim.log.levels.ERROR)
    return
  end

  -- Parse and format the GitHub URL
  local repo_path = github_remote_url:match("github%.com[:/](.+)%.git$")
  if not repo_path then
    vim.notify("Invalid GitHub URL", vim.log.levels.ERROR)
    return
  end
  github_remote_url = "https://github.com/" .. repo_path

  -- Get the current branch name
  local current_branch = vim.fn.systemlist("git rev-parse --abbrev-ref HEAD")[1]

  -- Get the file name relative to the Git root
  local file_name = vim.fn.expand("%:p"):gsub("^" .. vim.pesc(git_root), "")

  -- Get the line numbers
  local start_line, end_line
  local mode = vim.fn.mode()
  if mode == 'n' then
    -- Normal mode: use current line
    start_line = vim.fn.line(".")
    end_line = start_line
  elseif mode == 'v' or mode == 'V' or mode == '\22' then
    -- Visual mode: use selected lines
    start_line = vim.fn.line("v")
    end_line = vim.fn.line(".")
    -- Ensure start_line is always the smaller number
    if start_line > end_line then
      start_line, end_line = end_line, start_line
    end
  else
    vim.notify("Unsupported mode for GitHub link generation", vim.log.levels.ERROR)
    return
  end

  -- Construct the GitHub link
  local github_link
  if start_line == end_line then
    github_link = string.format("%s/blob/%s/%s#L%d", 
      github_remote_url, current_branch, file_name, start_line)
  else
    github_link = string.format("%s/blob/%s/%s#L%d:L%d", 
      github_remote_url, current_branch, file_name, start_line, end_line)
  end

  -- Copy to clipboards and notify user
  vim.fn.setreg("+", github_link)
  vim.fn.setreg("*", github_link)
  vim.notify("GitHub link copied to clipboard:\n" .. github_link, vim.log.levels.INFO)

  return github_link
end

vim.api.nvim_create_user_command('GGL', function(opts)
  if opts.range ~= 0 then
    vim.cmd('normal! gv')  -- Reselect the last visual selection
  end
  GenerateGithubLink()
end, {range = true})

function GoHeapYourself()
  print("Running \"go build -gcflags '-m -l' .\"")
  vim.cmd[[
    cgetexpr system("go build -gcflags '-m -l' .")
    copen
  ]]
end


-- Define a function to delete the line the cursor is on from the quickfix list
local function delete_from_qf_list(line_numbers)
  local quickfixList = vim.fn.getqflist()
  local currentWindow = vim.api.nvim_get_current_win()
  local current_line = vim.fn.line(".")

  if #quickfixList > 0 then
    -- Iterate over line numbers in reverse order to avoid skipping elements
    for i = #quickfixList, 1, -1 do
      for _, num in ipairs(line_numbers) do
        if i == num then
          -- Remove the line from the quickfix list
          table.remove(quickfixList, i)
          -- Adjust the current line if necessary
          if current_line > i then
            current_line = current_line - 1
          end
        end
      end
    end
  end

  -- Update the quickfix list
  vim.fn.setqflist(quickfixList)

  -- Set the cursor position to the updated current line
  vim.api.nvim_win_set_cursor(currentWindow, {current_line, 0})
end

function dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end

-- Function to remove the current line or selected lines
function remove_lines()
  -- Check if visual selection is active
  -- local is_visual = vim.fn.getpos("'<") ~= vim.fn.getpos("'>")
  -- print(dump(vim.fn.getpos("'<")), dump( vim.fn.getpos("'>")))

  local mode = vim.api.nvim_get_mode()
  -- print(dump(mode))

  local line_numbers = {}

  if mode.mode == "n" then
    -- Normal mode, remove current line
    local current_line = vim.fn.line(".")
    table.insert(line_numbers, current_line)
  else
    local cursor = vim.api.nvim_win_get_cursor(0)
    local cline, ccol = cursor[1], cursor[2]
    local vline, vcol = vim.fn.line('v'), vim.fn.col('v')

    local sline
    local eline
    if cline == vline then
      if ccol <= vcol then
        sline = cline
        eline = vline
      else
        sline = vline
        eline = cline
      end
    elseif cline < vline then
      sline = cline
      eline = vline
    else
      sline = vline
      eline = cline
    end

    local min_line = math.min(sline, eline)
    local max_line = math.max(sline, eline)
    for line = min_line, max_line do
      table.insert(line_numbers, line)
    end
  end

  delete_from_qf_list(line_numbers)

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
end



-- -- Create an autogroup for the quickfix keymaps
-- local qf_keymaps_group = vim.api.nvim_create_augroup("QfKeymaps", { clear = true })
--
-- -- Add autocommands to the group
-- vim.api.nvim_create_autocmd("BufEnter", {
--   group = qf_keymaps_group,
--   pattern = "*",
--   callback = function()
--     local bufnr = vim.fn.bufnr("%")
--     if vim.fn.getbufvar(bufnr, "&buftype") == "quickfix" then
--       vim.api.nvim_set_keymap('n', 'dd', '<cmd>lua remove_lines()<CR>', { noremap = true, silent = true })
--       vim.api.nvim_set_keymap('v', 'd', '<cmd>lua remove_lines()<CR>', { noremap = true, silent = true })
--     end
--   end
-- })

vim.cmd[[ 
augroup QflKeys
  autocmd!
  autocmd FileType qf noremap <buffer> dd <cmd>lua remove_lines()<CR>
  autocmd FileType qf xnoremap <buffer> d <cmd>lua remove_lines()<CR>
augroup END
]]

-- Resize mode commands
vim.api.nvim_create_user_command('ResizeMode', function(opts)
  local resize = require('custom.resize_mode')
  local action = (opts.fargs[1] or 'toggle'):lower()
  local amount = tonumber(opts.fargs[2])
  if action == 'start' then
    resize.start({ amount = amount })
  elseif action == 'stop' then
    resize.stop()
  else
    resize.toggle({ amount = amount })
  end
end, {
  nargs = '*',
  complete = function()
    return { 'start', 'stop', 'toggle' }
  end,
  desc = 'i3-style window resize mode (start|stop|toggle [amount])',
})

vim.api.nvim_create_user_command('ResizeModeToggle', function(opts)
  local amount = tonumber(opts.fargs[1])
  require('custom.resize_mode').toggle({ amount = amount })
end, { nargs = '?', desc = 'Toggle i3-style window resize mode' })
