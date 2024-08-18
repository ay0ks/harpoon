local group = vim.api.nvim_create_augroup("Harpoon", {})

local config = {
    title_align = "left",
    menu_fallback_width = 69,
    menu_max_width = 120,
    menu_width_ratio = 0.62569,
    menu_fallback_height = 8,
    menu_max_height = 16,
    menu_height_ratio = 1.5,
    menu_style = "minimal",
    menu_border = "single",
}
local state = {
    menu_open = false,
    menu_buf_id = nil,
    menu_win_id = nil,
    buffers = {},
}

local toggle_menu

local function close_menu()
    state.menu_open = false
    if state.menu_buf_id ~= nil and vim.api.nvim_buf_is_valid(state.menu_buf_id) then
        vim.api.nvim_buf_delete(state.menu_buf_id, { force = true })
    end
    if state.menu_win_id ~= nil and vim.api.nvim_win_is_valid(state.menu_win_id) then
        vim.api.nvim_win_close(state.menu_win_id, true)
    end
end

local function open_menu()
    local win = vim.api.nvim_list_uis()
    local width, height = config.menu_fallback_width, config.menu_fallback_height
    if #win > 0 then
        width = math.floor(win[1].width * config.menu_width_ratio)
        hidth = math.floor(win[1].height * config.menu_height_ratio)
    end
    if config.menu_max_width and width > config.menu_max_width then
        width = config.menu_max_width
    end
    if config.menu_max_height and height > config.menu_max_height then
        height = config.menu_max_height
    end

    local bufnr = vim.api.nvim_create_buf(false, true)
    local winnr = vim.api.nvim_open_win(bufnr, true, {
        relative = "editor",
        title = "Harpoon",
        title_pos = config.title_align or "left",
        row = math.floor(((vim.o.lines - height) / 2) - 1),
        col = math.floor((vim.o.columns - width) / 2),
        width = width,
        height = height,
        style = config.menu_style or "minimal",
        border = config.menu_border or "single",
    })
    state.menu_buf_id = bufnr
    state.menu_win_id = winnr
    if winnr == 0 then
        close_menu()
        error("Failed to create window")
    end
    state.menu_open = true

    local cf = vim.api.nvim_buf_get_name(0)
    local cmd = string.format(
        "autocmd Filetype harpoon "
        .. "let path = '%s' | call clearmatches() | "
        -- move the cursor to the line containing the current filename
        .. "call search('\\V'.path.'\\$') | "
        -- add a hl group to that line
        .. "call matchadd('HarpoonCurrentFile', '\\V'.path.'\\$')",
        cf:gsub("\\", "\\\\")
    )
    vim.cmd(cmd)

    if vim.api.nvim_buf_get_name(state.menu_buf_id) == "" then
        vim.api.nvim_buf_set_name(state.menu_buf_id,
            "harpoon://menu#" .. state.menu_win_id .. "#" .. state.menu_buf_id)
    end

    vim.api.nvim_set_option_value("filetype", "harpoon", {
        buf = state.menu_buf_id,
    })
    vim.api.nvim_set_option_value("buftype", "acwrite", {
        buf = state.menu_buf_id
    })

    vim.keymap.set({ "n", "v", "i" }, "<M-j>", function()
        local idx = vim.fn.line(".")
        local buf = state.buffers[idx]
        if state.buffers[idx + 1] then
            local nbuf = state.buffers[idx + 1]
            state.buffers[idx + 1] = buf
            state.buffers[idx] = nbuf
            vim.cmd([[:m .+1]])
        else
            vim.notify("No buffer below", vim.log.levels.WARN)
        end
    end, { buffer = state.menu_buf_id, silent = true })

    vim.keymap.set({ "n", "v", "i" }, "<M-k>", function()
        local idx = vim.fn.line(".")
        local buf = state.buffers[idx]
        if state.buffers[idx - 1] then
            local pbuf = state.buffers[idx - 1]
            state.buffers[idx - 1] = buf
            state.buffers[idx] = pbuf
            vim.cmd([[:m .-2]])
        else
            vim.notify("No buffer above", vim.log.levels.WARN)
        end
    end, { buffer = state.menu_buf_id, silent = true })

    vim.keymap.set("n", "q", function()
        toggle_menu()
    end, { buffer = state.menu_buf_id, silent = true })

    vim.keymap.set("n", "<Esc>", function()
        toggle_menu()
    end, { buffer = state.menu_buf_id, silent = true })

    vim.keymap.set("n", "<CR>", function()
        local idx = vim.fn.line(".")
        local buf = state.buffers[idx]
        if buf == nil then
            return
        end
        local bufnr, bufn = buf[1], buf[2]
        local lineno, colno = state.buffers[idx][3], state.buffers[idx][4]
        if bufnr == -1 then
            bufnr = vim.fn.bufadd(bufn)
        end
        if not vim.api.nvim_buf_is_loaded(bufnr) then
            vim.fn.bufload(bufn)
            vim.api.nvim_set_option_value("buflisted", true, {
                buf = bufnr,
            })
        end
        vim.api.nvim_set_current_buf(bufnr)
        local lineno_ = vim.api.nvim_buf_line_count(bufnr)
        if lineno_ >= lineno and #vim.api.nvim_buf_get_lines(bufnr, lineno_ - 1, lineno_, false)[1] >= colno then
            vim.api.nvim_win_set_cursor(0, { lineno, colno })
        end
    end, { buffer = state.menu_buf_id, silent = true })

    vim.api.nvim_create_autocmd({ "BufWriteCmd" }, {
        group = group,
        buffer = state.menu_buf_id,
        callback = function()
            vim.schedule(function()
                toggle_menu()
            end)
        end,
    })

    vim.api.nvim_create_autocmd({ "BufLeave" }, {
        group = group,
        buffer = bufnr,
        callback = function()
            toggle_menu()
        end,
    })

    vim.api.nvim_set_option_value("number", true, {
        win = state.menu_win_id,
    })

    local items = {}
    for _, buffer in ipairs(state.buffers) do
        table.insert(items, buffer[2])
    end

    vim.api.nvim_buf_set_lines(state.menu_buf_id, 0, -1, false, items)
    -- vim.api.nvim_buf_set_option(state.menu_buf_id, "modifiable", false)
end

toggle_menu = function()
    if state.menu_open then
        close_menu()
    else
        open_menu()
    end
end

local function setup(partial_config)
    vim.tbl_deep_extend("force", config, partial_config)
    
    vim.api.nvim_create_user_command("HarpoonAddBuffer", function()
        local bufnr = vim.api.nvim_get_current_buf()
        local bufn = vim.api.nvim_buf_get_name(bufnr)
        if
            not (vim.api.nvim_buf_is_valid(bufnr)
                or vim.api.nvim_buf_get_option(bufnr, "buflisted"))
            or (bufn == "" or bufn:match("^.+://*")) then
            vim.notify("Pseudo buffers are not supported", vim.log.levels.WARN)
            return
        end
        local cur = vim.api.nvim_win_get_cursor(0)
        local lineno, colno = cur[1], cur[2]
        for _, buf in ipairs(state.buffers) do
            if buf[2] == bufn then
                vim.notify("This buffer is already present in the Harpoon list", vim.log.levels.WARN)
                return
            end
        end
        table.insert(state.buffers, { bufnr, bufn, lineno, colno })
        vim.cmd([[:echo ""]])
    end, {})

    vim.api.nvim_create_user_command("HarpoonToggle", function()
        toggle_menu()
    end, {})

    vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
        group = group,
        pattern = "*",
        callback = function(ev)
            local bufnr = vim.api.nvim_get_current_buf()
            local bufn = vim.api.nvim_buf_get_name(bufnr)
            if bufn == "" or bufn:match("^.+://*") then
                return
            end
            for _, buf in ipairs(state.buffers) do
                if buf[2] == bufn then
                    local cur = vim.api.nvim_win_get_cursor(0)
                    buf[3], buf[4] = cur[1], cur[2]
                    return
                end
            end
        end,
    })
end

return { setup = setup }
