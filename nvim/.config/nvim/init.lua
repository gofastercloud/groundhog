-- ============================
-- Modern Neovim Config
-- ============================

-- Core options
vim.o.number = true
vim.o.relativenumber = true
vim.o.termguicolors = true
vim.o.cursorline = true
-- Indentation defaults (spaces). VS Code is configured for tabs (insertSpaces
-- false, prettier.useTabs), so per-project style belongs in .editorconfig:
-- Neovim reads it natively (0.9+) and overrides these buffer-locally
-- (indent_style, indent_size, tab_width), keeping both editors consistent.
vim.o.expandtab = true
vim.o.shiftwidth = 2
vim.o.tabstop = 2
vim.o.smartindent = true
vim.o.clipboard = "unnamedplus"
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.incsearch = true
vim.o.wrap = false
vim.o.scrolloff = 8
vim.o.sidescrolloff = 8
vim.o.signcolumn = "yes"
vim.o.updatetime = 250
vim.o.splitbelow = true
vim.o.splitright = true
vim.o.undofile = true

vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Disable unused providers (suppresses checkhealth warnings)
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_node_provider = 0

local map = vim.keymap.set

-- Basic keymaps
map("n", "<leader>w", "<cmd>w<CR>", { desc = "Save" })
map("n", "<leader>q", "<cmd>q<CR>", { desc = "Quit" })
map("n", "<leader>h", "<cmd>nohlsearch<CR>", { desc = "Clear highlights" })

-- Better window navigation
map("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Move to lower window" })
map("n", "<C-k>", "<C-w>k", { desc = "Move to upper window" })
map("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })

-- Move lines in visual mode
map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move line down" })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move line up" })

-- Keep cursor centered when scrolling
map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")
map("n", "n", "nzzzv")
map("n", "N", "Nzzzv")

-- Better paste (don't yank replaced text)
map("x", "<leader>p", '"_dP', { desc = "Paste without yanking" })

-- ============================
-- lazy.nvim bootstrap
-- ============================
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- ============================
-- Plugins
-- ============================
require("lazy").setup({
  -- Theme: Catppuccin Mocha
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    opts = {
      flavour = "mocha",
      integrations = {
        gitsigns = true,
        nvimtree = true,
        telescope = { enabled = true },
        treesitter = true,
        which_key = true,
        cmp = true,
        native_lsp = { enabled = true },
      },
    },
  },

  -- Statusline with Catppuccin
  {
    "nvim-lualine/lualine.nvim",
    opts = {
      options = {
        theme = "catppuccin-mocha",
        component_separators = { left = "", right = "" },
        section_separators = { left = "", right = "" },
      },
    },
  },

  -- File explorer
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    keys = {
      { "<leader>e", "<cmd>NvimTreeToggle<CR>", desc = "Toggle file explorer" },
    },
    opts = {},
  },

  -- Telescope (fuzzy finder)
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<CR>", desc = "Find files" },
      { "<leader>fg", "<cmd>Telescope live_grep<CR>", desc = "Live grep" },
      { "<leader>fb", "<cmd>Telescope buffers<CR>", desc = "Find buffers" },
      { "<leader>fr", "<cmd>Telescope oldfiles<CR>", desc = "Recent files" },
    },
    opts = {},
  },

  -- Treesitter (main branch rewrite; needs tree-sitter-cli to build parsers).
  -- Highlighting is Neovim's own; this plugin installs parsers and indents.
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      local parsers = {
        "lua", "vim", "vimdoc", "query", "bash", "zsh", "nu",
        "python", "javascript", "typescript", "tsx", "go", "rust",
        "json", "yaml", "toml", "markdown", "markdown_inline",
        "html", "css", "sql", "dockerfile", "hcl", "terraform",
        "gitcommit", "diff",
      }
      require("nvim-treesitter").install(parsers)
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(ev)
          local lang = vim.treesitter.language.get_lang(ev.match)
          if not (lang and pcall(vim.treesitter.start, ev.buf, lang)) then
            return
          end
          vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end,
      })
    end,
  },

  -- LSP server configs (lsp/*.lua) used by vim.lsp.enable below. Must not be
  -- lazy: the configs only exist once the plugin is on the runtimepath.
  { "neovim/nvim-lspconfig" },

  -- Completion
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")
      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-b>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"] = cmp.mapping.abort(),
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "path" },
        }, {
          { name = "buffer" },
        }),
      })
    end,
  },

  -- Git signs in the gutter
  {
    "lewis6991/gitsigns.nvim",
    opts = {
      signs = {
        add = { text = "+" },
        change = { text = "~" },
        delete = { text = "_" },
        topdelete = { text = "‾" },
        changedelete = { text = "~" },
      },
    },
  },

  -- Which-key: keybind hints
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {},
  },

  -- Auto-pairs: close brackets/quotes
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = true,
  },

  -- ============================
  -- Vim Training / Gamification
  -- ============================

  -- vim-be-good: game-style motion drills (ThePrimeagen)
  -- Launch with :VimBeGood
  {
    "ThePrimeagen/vim-be-good",
    cmd = "VimBeGood",
  },

  -- hardtime.nvim: punishes bad habits, forces proper motions
  -- Toggle with :Hardtime toggle
  {
    "m4xshen/hardtime.nvim",
    dependencies = { "MunifTanjim/nui.nvim" },
    event = "VeryLazy",
    opts = {
      -- Start gentle: warn instead of block
      restriction_mode = "hint",
      -- Disable in file explorer so it doesn't annoy you there
      disabled_filetypes = { "NvimTree", "lazy", "TelescopePrompt" },
      -- Max repeated key presses before hint/block
      max_count = 3,
    },
  },
}, {
  rocks = { enabled = false },
})

-- ============================
-- Colorscheme (after plugins)
-- ============================
vim.cmd.colorscheme("catppuccin")

-- ============================
-- LSP (vim.lsp.config, nvim 0.11+)
-- ============================
local capabilities = require("cmp_nvim_lsp").default_capabilities()

vim.lsp.config("lua_ls", {
  capabilities = capabilities,
  settings = {
    Lua = {
      diagnostics = { globals = { "vim" } },
      workspace = { checkThirdParty = false },
    },
  },
})

local servers = { "pyright", "ruff", "ts_ls", "gopls", "terraformls", "nushell" }
for _, server in ipairs(servers) do
  vim.lsp.config(server, { capabilities = capabilities })
end

-- Only enable servers whose binary is installed, so a missing tool never
-- produces startup errors.
local enabled = {}
for _, server in ipairs(vim.list_extend({ "lua_ls" }, servers)) do
  local cmd = vim.lsp.config[server] and vim.lsp.config[server].cmd
  if type(cmd) == "table" and vim.fn.executable(cmd[1]) == 1 then
    table.insert(enabled, server)
  end
end
vim.lsp.enable(enabled)

-- LSP keymaps. Neovim 0.11+ already maps K (hover), grr (references),
-- grn (rename), gra (code action) and gri (implementation).
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local opts = { buffer = ev.buf }
    map("n", "gd", vim.lsp.buf.definition, opts)
    map("n", "<leader>rn", vim.lsp.buf.rename, opts)
    map("n", "<leader>ca", vim.lsp.buf.code_action, opts)
  end,
})
