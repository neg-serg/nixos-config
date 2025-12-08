-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ mfussenegger/nvim-dap                                                        │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'mfussenegger/nvim-dap', -- neovim debugger protocol support
    dependencies={
        {'rcarriga/nvim-dap-ui'}, -- better ui for nvim-dap
        {'theHamsta/nvim-dap-virtual-text'}},  -- virtual debugging text support
    config=function()
        local status, dapui = pcall(require, 'dapui')
        if (not status) then return end
        dapui.setup()
        local dap = require('dap')
        local widgets = require('dap.ui.widgets')

        local function opt(msg)
            return { desc = "DAP: " .. msg }
        end

        vim.keymap.set("n", "<leader>db", function() dap.toggle_breakpoint() end, opt("breakpoint"))
        vim.keymap.set("n", "<F2>", function() dap.continue() end, opt("continue"))
        vim.keymap.set("n", "<F3>", function() dap.step_into() end, opt("step into"))
        vim.keymap.set("n", "<F4>", function() dap.step_over() end, opt("step over"))
        vim.keymap.set("n", "<F5>", function() dap.step_out() end, opt("step out"))
        vim.keymap.set("n", "<leader>dui", function() dapui.toggle() end, opt("toggle ui"))
        vim.keymap.set("n", "<leader>duh", function() widgets.hover() end, opt("hover"))
        vim.keymap.set("n", "<leader>duf", function() widgets.centered_float(widgets.scopes) end, opt("float view"))
        vim.keymap.set("n", "<leader>dB", function()
            dap.set_breakpoint(vim.fn.input("Breakpoint condition: "))
        end, opt("contitional breakpoint"))
        vim.keymap.set("n", "<leader>dl", function()
            dap.set_breakpoint(nil, nil, vim.fn.input("Log point message: "))
        end, opt("log point message"))
        dap.listeners.after.event_initialized["dapui_config"] = function()
            dapui.open()
        end
        dap.listeners.after.event_terminated["dapui_config"] = function()
            dapui.close()
        end
        dap.listeners.after.event_exited["dapui_config"] = function()
            dapui.close()
        end
        dap.configurations.lua={
            {
                type="nlua",
                request="attach",
                name="Attach to running Neovim instance",
                host=function()
                    local value=vim.fn.input("Host [127.0.0.1]: ")
                    if value ~= "" then return value end
                    return "127.0.0.1"
                end,
                port=function()
                    local val=tonumber(vim.fn.input("Port: "))
                    assert(val, "Please provide a port number")
                    return val
                end,
            },
        }
        require("nvim-dap-virtual-text").setup()
        -- Rust adapters: prefer codelldb, fallback to lldb-dap
        if vim.fn.executable('codelldb') == 1 then
            dap.adapters.codelldb = function(on_adapter)
                local tcp = vim.loop.new_tcp()
                tcp:bind('127.0.0.1', 0)
                local host, port = tcp:getsockname()
                tcp:shutdown()
                tcp:close()
                local handle
                local pid_or_err
                handle, pid_or_err = vim.loop.spawn('codelldb', {
                    args = { '--port', tostring(port) },
                    detached = true,
                }, function(code)
                    handle:close()
                    if code ~= 0 then
                        vim.schedule(function()
                            vim.notify('codelldb exited with code ' .. code, vim.log.levels.WARN)
                        end)
                    end
                end)
                if not handle then
                    vim.notify('Error running codelldb: ' .. tostring(pid_or_err), vim.log.levels.ERROR)
                    return
                end
                vim.defer_fn(function()
                    on_adapter({
                        type = 'server',
                        host = host,
                        port = port,
                    })
                end, 100)
            end
        elseif vim.fn.executable('lldb-dap') == 1 then
            dap.adapters.lldb = {
                type = 'executable',
                command = 'lldb-dap',
                name = 'lldb',
            }
        end
        -- Provide a basic Rust config if none is loaded yet.
        if not dap.configurations.rust or #dap.configurations.rust == 0 then
            local adapter = dap.adapters.codelldb and 'codelldb' or 'lldb'
            dap.configurations.rust = {
                {
                    name = 'Debug executable (rustaceanvim fallback)',
                    type = adapter,
                    request = 'launch',
                    program = function()
                        return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
                    end,
                    cwd = '${workspaceFolder}',
                    stopOnEntry = false,
                },
            }
        end
        -- vim: fdm=marker
    end,
    event={'BufNewFile','BufRead'}}
