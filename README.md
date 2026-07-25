# nxvim-keys-helper

A live popup of the keys that can follow what you've just typed — a **which-key**
for [nxvim](https://github.com/davidrios/nxvim).

Press `<leader>` (or `g`, `z`, `<C-w>`, …) and pause: a bordered popup appears in
the bottom-right corner listing every key that can come next, each with its
description. Keep typing into a group and it refreshes to that group's keys;
complete a mapping, break the sequence, or wait out the timeout and it closes.

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

It is built natively on the `nx.*` API — **no blocking key reads, no key
interception**. It subscribes to nxvim's pending-key *oracle*
(`nx.on_key_pending`) and renders the continuations onto a non-focus floating
window, so it never interrupts the sequence you're in the middle of typing.

- **Your maps and the built-in grammar** — the same oracle feeds `showcmd`, so
  `z`, `g`, `<C-w>` and the operator-pending states show up alongside your own
  mappings (and `g` merges both into one popup).
- **Named groups** — a bare prefix reads as `+file` / `+git` instead of `+more`.
- **Columnized** — a long alphabet spills into columns rather than off the
  bottom of the float.
- **Themeable** — the which-key.nvim highlight-group names, installed only as a
  fallback so your colorscheme wins.

## Install

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

## Documentation

Full docs — every `setup()` option, naming prefix groups, the built-in command
grammar, the highlight groups, and the module API — live in the help file. The
same source renders both on GitHub and in the editor:

- In editor: `:help nxvim-keys-helper`
- On GitHub: [doc/nxvim-keys-helper.md](./doc/nxvim-keys-helper.md) (the help source)

## Trying it locally

```sh
NXVIM_CONFIG=examples nxvim examples/sample.txt
```

(run from the repo root — the demo config in `examples/init.lua` loads the plugin
straight from this checkout, so no `:PluginSync` is needed).

## Development

```sh
nxvim --test-plugin .
```

The Lua suite (`test/popup_spec.lua`) drives a real editor through nxvim's native
`nx.test` framework: feed a leader prefix, wait for the debounced popup, and
assert on the floating window's text via `t:float()`.

The vimdoc `doc/nxvim-keys-helper.txt` is **generated** from
`doc/nxvim-keys-helper.md` via
[panvimdoc](https://github.com/kdheepak/panvimdoc): edit the `.md`, then run
`bash scripts/gen-vimdoc.sh` (needs `pandoc` + `git`). Never edit the `.txt` by
hand.

## License

MIT © David Rios
