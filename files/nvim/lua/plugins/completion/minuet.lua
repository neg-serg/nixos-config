-- Minuet: fill-in-the-middle completion against the local llama-fim service
-- (modules/llm/fim.nix, Qwen2.5-Coder-1.5B Q8 on 127.0.0.1:8012). Qwen2.5
-- uses the FIM special tokens below; llama.cpp serves a plain /v1/completions
-- endpoint, so the prompt is assembled here (minuet's own llama.cpp recipe).
--
-- The server is a user unit without a wantedBy: nvim starts it on startup and
-- stops it when the last nvim exits, so the 1.5B model does not sit in VRAM
-- while the chat stack needs the whole card.
local function llamaFim(action)
  vim.fn.jobstart({ 'systemctl', '--user', action, 'llama-fim.service' }, { detach = true })
end

return {
  'milanglacier/minuet-ai.nvim',
  event = { 'VimEnter' },
  config = function()
    require('minuet').setup {
      provider = 'openai_fim_compatible',
      n_completions = 1,
      -- Characters of buffer context (minuet's unit), split 3:1 around the
      -- cursor. 2048 chars ≈ 500 tokens: the 1.5B prefill is fast enough at
      -- this size, and more context measurably helps inside function bodies.
      context_window = 2048,
      context_ratio = 0.75,
      request_timeout = 2,
      debounce = 200,
      throttle = 250,
      notify = 'error',
      provider_options = {
        openai_fim_compatible = {
          -- The server authenticates nothing; minuet wants a var name and
          -- TERM is always set.
          api_key = 'TERM',
          name = 'Llama.cpp',
          end_point = 'http://127.0.0.1:8012/v1/completions',
          model = 'qwen2.5-coder-1.5b',
          optional = {
            max_tokens = 128,
            temperature = 0.0,
            top_p = 0.9,
            stop = { '<|fim_pad|>', '<|endoftext|>', '<|file_sep|>' },
          },
          template = {
            prompt = function(before, after, _)
              return '<|fim_prefix|>' .. before .. '<|fim_suffix|>' .. after .. '<|fim_middle|>'
            end,
            suffix = false,
          },
        },
      },
      virtualtext = {
        auto_trigger_ft = {
          'lua',
          'python',
          'rust',
          'nix',
          'sh',
          'bash',
          'c',
          'cpp',
          'go',
          'javascript',
          'javascriptreact',
          'typescript',
          'typescriptreact',
          'haskell',
        },
        show_on_completion_menu = false,
        keymap = {
          accept = '<M-CR>',
          accept_line = '<M-l>',
          next = '<M-]>',
          prev = '<M-[>',
          dismiss = '<M-e>',
        },
      },
    }

    -- Start once per editor session; the model load (~1.5 s) happens while the
    -- user is still reading the file, not on the first keystroke.
    vim.schedule(function()
      llamaFim 'start'
    end)

    vim.api.nvim_create_autocmd('VimLeavePre', {
      callback = function()
        -- gsub returns two values; parenthesise it or tonumber gets the
        -- replacement count as its `base` argument.
        local count = tonumber(((vim.fn.system 'pgrep -xc nvim'):gsub('%s+', ''))) or 0
        if count <= 1 then
          llamaFim 'stop'
        end
      end,
    })
  end,
}
