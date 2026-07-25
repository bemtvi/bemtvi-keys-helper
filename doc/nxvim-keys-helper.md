<!-- DO NOT EDIT doc/nxvim-keys-helper.txt BY HAND. It is generated from this file by
panvimdoc — run `scripts/gen-vimdoc.sh` after editing. -->

A live popup of the keys that can follow what you've just typed — a **which-key** for nxvim.

Press `<leader>` (or `g`, `z`, `<C-w>`, …) and pause: a bordered popup appears in the
bottom-right corner listing every key that can come next, each with its description. Keep typing
into a group and it refreshes to that group's keys; complete a mapping, break the sequence, or
wait out the timeout and it closes.

```
╭  <C-w> — Window  ────────────────────────────────────╮
│ +       Taller                 _   Max height        │
│ -       Shorter                c   Close window      │
│ <       Narrower               h   Focus left        │
│ <C-w>   +Dock layer            j   Focus down        │
│ =       Equalize sizes         k   Focus up          │
│ >       Wider                  l   Focus right       │
│ H       Move window left       o   Only window       │
│ J       Move window down       q   Quit window       │
│ K       Move window up         s   Split horizontal  │
│ L       Move window right      v   Split vertical    │
│ T       Move to new tab        w   Focus next window │
│ W       Focus previous window  |   Max width         │
╰──────────────────────────────────────────────────────╯
```

<!-- Passed through verbatim so `:help nxvim-keys-helper` lands on this page (panvimdoc
     derives per-section tags but no bare project tag). -->

```vimdoc
                              *nxvim-keys-helper* *nxvim-keys-helper-intro*
```

# How it works

The plugin is built entirely on the native `nx.*` API: **no blocking key reads, no key
interception**. It never sits between you and the editor — it only watches and draws.

Three nx signals do the whole job:

- `nx.on_key_pending(fn)` — the engine's pending-prefix *oracle*. The
  server watches the mapped-prefix trie and pushes a context
  (`{ mode, keys, continuations, label }`) every time the withheld prefix
  changes: grows, descends, or clears. It is fire-on-change, not
  per-keystroke (ADR 0002 rule 4: no per-key Lua), so an idle editor pays
  nothing.
- `nx.component{ surface = "float" }` — the popup is a float-backed
  component: reactive state (the pending context) plus a pure `render`. An
  *empty* render hides it, so the whole show/refresh/hide cycle is
  declarative and the plugin never touches a float handle. The `float`
  surface takes no focus and binds no keys.
- `nx.utils.debounce(fn, ms)` — coalesces the oracle's bursts so a fast,
  deliberate sequence (`<Space>w` typed quickly) never flashes the popup.
  Only the *first* show is debounced; once the popup is up, descending into
  a group refreshes it immediately rather than making you wait out another
  `delay`.

# Install

Declare it with the built-in `:Plugins` manager in your `init.lua`:

```lua
nx.plugins({
  {
    "davidrios/nxvim-keys-helper",
    config = function()
      require("nxvim-keys-helper").setup({})
    end,
  },
})
```

Then run `:PluginSync` to clone it. That's it — start typing a prefix and pause.

# Setup

`require("nxvim-keys-helper").setup(opts)` wires the popup. Every field is optional; the defaults
are shown below.

```lua
require("nxvim-keys-helper").setup({
  delay = 200,         -- pause (ms) after the last key before it shows
  timeout = false,     -- vim.o.timeout (see Timeout below)
  relative = "bottom", -- anchor: "bottom" | "cursor" | "editor"
  border = "rounded",  -- "rounded" | "single" | "double" | "solid" | "none"
  group_marker = "+",  -- shown before a group name, e.g. "+file"
  max_height = 20,     -- tallest before it spills into columns
  max_width = 80,      -- widest before descriptions ellipsize
  highlights = {},     -- highlight-group overrides (see Highlights)
  spec = {},           -- name your prefix groups (see Naming groups)
})
```

A mistyped option is a **hard error** naming the offender — never a popup that silently never
appears.

`setup()` is idempotent, and a second call re-applies its config to the *live* popup: `delay`,
`relative`, `border`, `group_marker`, and the size caps are all read when the popup shows or
renders, never captured at mount. `highlights` are **merged** into whatever is already
registered, so a later call adding one override does not drop the others. Only the component
itself is mounted once.

## Timeout

`timeout` is applied straight to `vim.o.timeout`, and it defaults to **`false`**.

A which-key wants a paused prefix to stay pending for as long as you're looking at the popup, but
vim's default (`timeout = true`) commits the prefix to the built-in grammar after `timeoutlen` —
which is what strands mapped continuations like the LSP `gd`/`gD`/`gr` defaults as no longer
firable. Disabling the mapping timeout keeps the sequence open. Pass `timeout = true` to `setup()`
to keep vim's normal behaviour instead.

## Size

The popup grows to fit its content, bounded by `max_height` / `max_width` and by the screen. When
the keys don't fit in one column it lays them out in **columns** rather than running off the
bottom — the `<C-w>` alphabet alone is 24 keys, more than the float's 20-row cap. If a column set
is too wide, descriptions ellipsize (`…`) so no column is clipped off the right edge; and if the
screen is genuinely too small to hold everything, the last cell says `+N more` rather than
dropping keys in silence.

The editor's content float caps at 20 rows by 80 cells, so raising `max_height` / `max_width`
past those has no effect. Lowering them keeps the popup deliberately small.

# Naming groups

A prefix that only leads deeper (e.g. `<leader>f` when you have `<leader>ff` and `<leader>fg`)
shows as a **group**. nxvim's engine has no description to attach to a bare prefix, so by default
a group renders as `+more`. Give it a real name with `spec`:

```lua
require("nxvim-keys-helper").setup({
  spec = {
    { "<leader>f", group = "file" },          -- positional prefix
    { prefix = "<leader>g", group = "git" },  -- or the named field
  },
})
```

`<leader>` / `<localleader>` are expanded the way nxvim reports keys, and they are expanded when
the popup **renders** — not when the entry is registered. So a config that sets `vim.g.mapleader`
*after* the plugin's `config` function runs (the usual plugin-manager ordering) still gets its
group names.

Leaf mappings need no registration — their description comes straight from the `desc` you pass to
`nx.keymap.set`:

```lua
nx.keymap.set("n", "<leader>w", "<cmd>write<cr>", { desc = "write" })
```

# Built-in command grammar

The popup is fed by the same oracle nxvim uses for `showcmd`, so it covers the built-in motions
too, not just your maps:

- pause after `z` for the viewport commands (`zt` / `zz` / `zb`, …),
- after `<C-w>` for the window commands,
- after `g` for the go-to motions, **merged** with any `g`-prefixed maps
  (the LSP `gd`/`gD`/`gr` defaults),
- mid-`f` or after a lone operator (`d`/`c`/`y`) for an "awaiting input"
  hint card (`Find character`, `Operator pending`, …).

The open states — find-char, replace, marks, registers — have no finite key list to enumerate, so
they arrive with a human label instead and render as a one-line hint card.

# Highlights

The popup uses four highlight groups, named after which-key.nvim's so a colorscheme that already
styles them just works:

```
WhichKey           the key itself
WhichKeyGroup      a +group label
WhichKeyDesc       a mapping's description / hint card
WhichKeySeparator  the gap between the key and its description
```

The plugin installs its built-in colors only as a **fallback** — if your colorscheme (or your
`highlights` override) already defines a group, that wins. Override any of them explicitly:

```lua
require("nxvim-keys-helper").setup({
  highlights = {
    WhichKey = { fg = "#89b4fa" },
    WhichKeyGroup = { fg = "#f9e2af", bold = true },
  },
})
```

Because most colorschemes open with `:hi clear`, the fallbacks are re-installed on every
`ColorScheme` event — after the new theme has had its say, so a theme that styles `WhichKey*`
still wins and one that doesn't keeps working colors.

# API

## setup

`require("nxvim-keys-helper").setup(opts)` — wire the popup. See |nxvim-keys-helper-setup|.
Returns the module, so `local kh = require("nxvim-keys-helper").setup({})` works.

## add

`require("nxvim-keys-helper").add(spec)` — register group names outside of `setup()`. `spec` takes
the same entries as `opts.spec`:

```lua
require("nxvim-keys-helper").add({
  { "<leader>b", group = "buffer" },
  { prefix = "<leader>x", group = "trouble" },
})
```

Call it any time — before or after `setup()`, before or after `vim.g.mapleader` is set. Re-adding
a prefix replaces its name, so calling it repeatedly is safe. The next popup reflects it.

## config

`require("nxvim-keys-helper").config` — the live, merged config table. Read-only by convention;
change it through `setup()` so validation runs.

# Trying it locally

This repo ships a runnable demo. From a checkout of this repo:

```sh
NXVIM_CONFIG=examples nxvim examples/sample.txt
```

The demo's `init.lua` loads the plugin straight from this checkout (`dir=`), so no `:PluginSync`
is needed.

# Development

```sh
nxvim --test-plugin .
```

The Lua suite (`test/popup_spec.lua`) drives a real editor through nxvim's native `nx.test`
framework: feed a leader prefix, wait for the debounced popup, and assert on the floating
window's text via `t:float()`.

```lua
nx.test.it("shows the leader menu on pause", function(t)
  t:feed("<Space>")
  local float = t:wait_for(function()
    return t:float()
  end)
  nx.test.expect(float.text).to_contain("write")
end)
```

The vimdoc `doc/nxvim-keys-helper.txt` is **generated** from `doc/nxvim-keys-helper.md` via
panvimdoc <https://github.com/kdheepak/panvimdoc>: edit the `.md`, then run
`bash scripts/gen-vimdoc.sh` (needs `pandoc` + `git`). Never edit the `.txt` by hand.
