local language = "rust"

local v = vim.version()
local lazypath = string.format(".lazy/nvim-%d%02d", v.major, v.minor)
vim.env.LAZY_STDPATH = lazypath

if not vim.uv.fs_stat(lazypath) then
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
local config = function(_, opts)
    if vim.fn.has("nvim-0.11") == 1 then
        require("nvim-treesitter").setup(opts)
        local installed = require("nvim-treesitter.config").get_installed()
        if not vim.tbl_contains(installed, language) then
            require("nvim-treesitter").install({ language }):wait()
        end
    else
        require("nvim-treesitter.configs").setup(opts)
        local parsers = require("nvim-treesitter.parsers")
        if not parsers.has_parser(language) then
            vim.cmd("TSInstallSync " .. language)
        end
    end
end

if vim.fn.has("nvim-0.12") == 1 then
    treesitter_spec = {
        "nvim-treesitter/nvim-treesitter",
        branch = "main",
        config = config,
    }
elseif vim.fn.has("nvim-0.11") == 1 then
    treesitter_spec = {
        "nvim-treesitter/nvim-treesitter",
        -- Last commit before https://github.com/nvim-treesitter/nvim-treesitter/commit/c82bf96f0a773d85304feeb695e1e23b2207ac35
        commit = "90cd6580e720caedacb91fdd587b747a6e77d61f",
        config = config,
    }
else
    treesitter_spec = {
        "nvim-treesitter/nvim-treesitter",
        branch = "master",
        config = config,
    }
end

local opts = {
    spec = {
        "nvim-lua/plenary.nvim",
        treesitter_spec,
        "nvim-neotest/nvim-nio",
        "nvim-neotest/neotest",
        { dir = vim.uv.cwd() },
    },
    lockfile = string.format("tests/lazy-lock-%02d.json", v.minor),
}

if _G.arg[1] == "--update" then
    table.remove(_G.arg, 1)
    require("lazy.minit").setup(opts)
elseif _G.arg[1] == "--install" then
    table.remove(_G.arg, 1)
    vim.env.LAZY_OFFLINE = "1"
    require("lazy.minit").setup(opts)
else
    vim.env.LAZY_OFFLINE = "1"
    require("lazy.minit").setup(opts)
    dofile("tests/runner.lua").run()
end
