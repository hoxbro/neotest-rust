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

local spec = {
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
}
local opts = {
    spec = spec,
    lockfile = "tests/lazy-lock.json",
}

if _G.arg[1] == "--update" then
    table.remove(_G.arg, 1)
    require("lazy.minit").setup(opts)
else
    table.insert(_G.arg, "--offline")
    require("lazy.minit").busted(opts)
end
