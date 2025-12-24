local language = "rust"

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

local treesitter_spec
local lockfile
if vim.fn.has("nvim-0.11") == 1 then
    treesitter_spec = {
        "nvim-treesitter/nvim-treesitter",
        config = function(_, opts)
            require("nvim-treesitter").setup(opts)
            local installed = require("nvim-treesitter.config").get_installed()
            if not vim.tbl_contains(installed, language) then
                require("nvim-treesitter").install({ language }):wait()
            end
        end,
    }
    lockfile = "tests/lazy-lock.json"
else
    treesitter_spec = {
        "nvim-treesitter/nvim-treesitter",
        branch = "master",
        config = function(_, opts)
            require("nvim-treesitter.configs").setup(opts)
            local parsers = require("nvim-treesitter.parsers")
            if not parsers.has_parser(language) then
                vim.cmd("TSInstallSync " .. language)
            end
        end,
    }
    lockfile = "tests/lazy-lock-10.json"
end

local opts = {
    spec = {
        "nvim-lua/plenary.nvim",
        treesitter_spec,
        "nvim-neotest/nvim-nio",
        "nvim-neotest/neotest",
    },
    lockfile = lockfile,
}

if _G.arg[1] == "--update" then
    table.remove(_G.arg, 1)
    require("lazy.minit").setup(opts)
else
    table.insert(_G.arg, "--offline")
    require("lazy.minit").busted(opts)
end
