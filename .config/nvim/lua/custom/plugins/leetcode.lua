return {
  'kawre/leetcode.nvim',
  build = function()
    vim.cmd 'TSUpdate html'
  end,
  dependencies = {
    'nvim-lua/plenary.nvim',
    'MunifTanjim/nui.nvim',
  },
  lazy = false,
  opts = {
    lang = 'golang',
    storage = {
      home = vim.fn.expand '~/Projects/leetcode',
    },
    theme = {
      ['normal'] = { fg = '#d4d4d4' },
      ['code'] = { fg = '#ce9178', bg = 'NONE' },
    },
    hooks = {
      ['question_enter'] = {
        function(question)
          local home = vim.fn.expand '~/Projects/leetcode'
          local slug = question.q.title_slug
          local id = question.q.frontend_id
          local md_path = home .. '/' .. id .. '.' .. slug .. '.md'

          if vim.fn.filereadable(md_path) == 1 then
            return
          end

          local content = question.q.content or question.q.translated_content or ''
          content = content:gsub('<p>', ''):gsub('</p>', '\n')
          content = content:gsub('<strong>', '**'):gsub('</strong>', '**')
          content = content:gsub('<em>', '*'):gsub('</em>', '*')
          content = content:gsub('<code>', '`'):gsub('</code>', '`')
          content = content:gsub('<pre>', '```\n'):gsub('</pre>', '\n```\n')
          content = content:gsub('<li>', '- '):gsub('</li>', '\n')
          content = content:gsub('<[^>]+>', '')
          content = content:gsub('&nbsp;', ' ')
          content = content:gsub('&lt;', '<'):gsub('&gt;', '>')
          content = content:gsub('&amp;', '&'):gsub('&quot;', '"')
          content = content:gsub('\n\n\n+', '\n\n')

          local lines = {
            '# ' .. id .. '. ' .. question.q.title,
            '',
            '**Difficulty:** ' .. question.q.difficulty,
            '',
            content,
          }

          local cases = question.q.testcase_list
          if cases and #cases > 0 then
            table.insert(lines, '## Test Cases')
            table.insert(lines, '')
            for i, tc in ipairs(cases) do
              table.insert(lines, '**Case ' .. i .. ':**')
              table.insert(lines, '```')
              table.insert(lines, tc)
              table.insert(lines, '```')
              table.insert(lines, '')
            end
          end

          local f = io.open(md_path, 'w')
          if f then
            f:write(table.concat(lines, '\n'))
            f:close()
          end
        end,
      },
    },
  },
}
