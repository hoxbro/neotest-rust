local lazypath = vim.env.LAZY_STDPATH
if not (vim.uv or vim.loop).fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable",
        "--depth=1",
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

local root = vim.fn.fnamemodify(vim.env.LAZY_STDPATH, ":p")
for _, name in ipairs({ "config", "data", "state", "cache" }) do
    vim.env[("XDG_%s_HOME"):format(name:upper())] = root .. "/" .. name
end

local opts = require("lazy.minit").busted.setup({
    spec = {
        "nvim-lua/plenary.nvim",
        {
            "nvim-treesitter/nvim-treesitter",
            main = "nvim-treesitter.configs",
            config = function(_, opts)
                require("nvim-treesitter").setup(opts)
                local installed = require("nvim-treesitter.config").get_installed()
                if not vim.tbl_contains(installed, "rust") then
                    require("nvim-treesitter").install({ "rust" }):wait()
                end
            end,
        },
        "nvim-neotest/nvim-nio",
        "nvim-neotest/neotest",
    },
    lockfile = "tests/lazy-lock.json",
})

vim.o.loadplugins = true
require("lazy").setup(opts)

if _G.arg[1] == "--update" then
    require("lazy").update():wait()
else
    require("lazy.minit").busted.run()
end
