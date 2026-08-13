-- Runnable demo for bemtvi-keys-helper.
--
--     BEMTVI_CONFIG=examples bemtvi examples/sample.txt
--
-- Each section below has a TYPE THIS / SEE THAT note. The short version: press
-- <leader> (Space) and pause.

-- ----- 1. the leader ---------------------------------------------------------
-- Set before anything registers a <leader> map or group. (The plugin expands
-- <leader> when the popup RENDERS, so setting it later still works — but keeping
-- it first is the habit that keeps your keymaps unambiguous.)
vim.g.mapleader = " "

-- ----- 2. load the plugin ----------------------------------------------------
-- Straight from this repo (a local-dev spec: `dir` is never cloned). A real config
-- would use `{ "bemtvi/bemtvi-keys-helper", config = ... }` plus `:PluginSync`.
--
-- TYPE THIS: <Space> and pause.  SEE THAT: a popup in the bottom-right corner
-- listing w / q / +file / +git.
btv.plugins({
  {
    name = "bemtvi-keys-helper",
    dir = vim.fn.expand("<sfile>:p:h:h"), -- the repo root (this file's grandparent dir)
    config = function()
      require("bemtvi-keys-helper").setup({
        delay = 200,
        spec = {
          { "<leader>f", group = "file" },
          { "<leader>g", group = "git" },
        },
      })
    end,
  },
})

-- ----- 3. a small leader menu ------------------------------------------------
-- `ff`/`fg` and `gs`/`gc` make `f` and `g` groups; the single-key maps complete
-- immediately, carrying their `desc`.
--
-- TYPE THIS: <Space> then f (while the popup is up).  SEE THAT: it refreshes to
-- the `f` group's keys AT ONCE — no second 200ms wait once the popup is open.
btv.keymap.set("n", "<leader>w", function()
  print("write")
end, { desc = "write" })
btv.keymap.set("n", "<leader>q", function()
  print("quit")
end, { desc = "quit" })
btv.keymap.set("n", "<leader>ff", function()
  print("find file")
end, { desc = "find file" })
btv.keymap.set("n", "<leader>fg", function()
  print("live grep")
end, { desc = "live grep" })
btv.keymap.set("n", "<leader>gs", function()
  print("git status")
end, { desc = "git status" })
btv.keymap.set("n", "<leader>gc", function()
  print("git commit")
end, { desc = "git commit" })

-- ----- 4. naming a group after the fact --------------------------------------
-- `add()` works any time — before or after setup(), before or after the leader is
-- set. Here it names a group whose maps are declared below it.
--
-- TYPE THIS: <Space> and pause.  SEE THAT: `b` reads "+buffer", not "+more".
require("bemtvi-keys-helper").add({
  { "<leader>b", group = "buffer" },
})
btv.keymap.set("n", "<leader>bn", "<cmd>bnext<cr>", { desc = "next buffer" })
btv.keymap.set("n", "<leader>bp", "<cmd>bprevious<cr>", { desc = "previous buffer" })

-- ----- 5. capping the popup's size -------------------------------------------
-- The popup spills into COLUMNS rather than off the bottom of the float, and
-- ellipsizes descriptions rather than letting a column be clipped off the right.
--
-- TYPE THIS: <C-w> and pause.  SEE THAT: all 24 window commands, in two columns.
-- Then uncomment the setup() below, restart, and try <C-w> again.
--
-- SEE THAT: the same keys re-flow into three narrow columns with ellipsized
-- descriptions. Cap it tighter still (`max_height = 5, max_width = 40`) and the
-- last cell becomes a "+5 more" badge — the popup says what it couldn't show
-- rather than dropping keys in silence.
--
-- require("bemtvi-keys-helper").setup({ max_height = 8, max_width = 46 })
