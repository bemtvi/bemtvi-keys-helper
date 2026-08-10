-- Tests for nxvim-keys-helper, run with `nxvim --test-plugin`.
--
--     nxvim --test-plugin ~/work/nxvim-plugins/nxvim-keys-helper
--
-- They drive a real editor through the `nx.test` framework: feed a leader prefix,
-- wait for the debounced popup, and assert on the floating window's text via
-- `t:float()`. `delay = 0` makes the popup appear on the next tick so a test never
-- waits on a wall-clock timer.

nx.test.describe("nxvim-keys-helper", function()
  nx.test.before_each(function()
    -- Space leader, set BEFORE the maps so <leader> expands to <Space>.
    vim.g.mapleader = " "
    require("nxvim-keys-helper").setup({
      delay = 0,
      spec = {
        { "<leader>f", group = "file" },
        { "<leader>g", group = "git" },
      },
    })
    nx.keymap.set("n", "<leader>w", function() end, { desc = "write" })
    nx.keymap.set("n", "<leader>q", function() end, { desc = "quit" })
    nx.keymap.set("n", "<leader>ff", function() end, { desc = "find file" })
    nx.keymap.set("n", "<leader>fg", function() end, { desc = "live grep" })
    nx.keymap.set("n", "<leader>gs", function() end, { desc = "git status" })
    nx.keymap.set("n", "<leader>gc", function() end, { desc = "git commit" })
  end)

  -- Pressing <leader> and pausing pops the menu of continuations.
  nx.test.it("shows the leader menu on pause", function(t)
    t:feed("<Space>")
    local float = t:wait_for(function()
      return t:float()
    end)
    nx.test.expect(float.text).to_contain("write")
    nx.test.expect(float.text).to_contain("quit")
  end)

  -- A prefix that only leads deeper renders with its registered group name.
  nx.test.it("names groups from the spec", function(t)
    t:feed("<Space>")
    local float = t:wait_for(function()
      return t:float()
    end)
    nx.test.expect(float.text).to_contain("+file")
    nx.test.expect(float.text).to_contain("+git")
  end)

  -- Descending into a group refreshes the popup to that group's keys.
  nx.test.it("refreshes when descending into a group", function(t)
    t:feed("<Space>f")
    local float = t:wait_for(function()
      local f = t:float()
      return f and f.text:find("find file") and f
    end)
    nx.test.expect(float.text).to_contain("find file")
    nx.test.expect(float.text).to_contain("live grep")
    -- The top-level leaves are gone now that we're inside `f`.
    nx.test.expect(float.text).never.to_contain("quit")
  end)

  -- Breaking the sequence (<Esc>) closes the popup.
  nx.test.it("closes when the sequence is aborted", function(t)
    t:feed("<Space>")
    t:wait_for(function()
      return t:float()
    end)
    t:feed("<Esc>")
    local closed = t:wait_for(function()
      return t:float() == nil
    end)
    nx.test.expect(closed).to_be_truthy()
  end)

  -- The built-in command grammar feeds the same popup: pausing after `z` lists the
  -- viewport commands (their continuation keys), no user maps involved.
  nx.test.it("shows the built-in z viewport grammar", function(t)
    t:feed("z")
    local float = t:wait_for(function()
      return t:float()
    end)
    -- `zt` (scroll cursor to top) — its continuation key `t` is listed.
    nx.test.expect(float.text).to_contain("t")
  end)

  -- An OPEN built-in state (source B) has no key list — it arrives with empty
  -- continuations and a label, which renders as a one-line hint card in the title
  -- and the body.
  nx.test.it("shows a hint card for an open built-in state", function(t)
    t:feed("f")
    local float = t:wait_for(function()
      return t:float()
    end)
    nx.test.expect(float.text).to_contain("Find character")
    nx.test.expect(float.title).to_contain("Find character")
  end)

  -- REGRESSION: the `<C-w>` alphabet is 24 keys, more than the content float's
  -- 20-row cap — as a single column the server clipped the tail and the popup
  -- silently lost `s`/`v`/`w`/`|`. They must be columnized, never dropped.
  nx.test.it("columnizes a long grammar instead of dropping rows", function(t)
    t:feed("<C-w>")
    local float = t:wait_for(function()
      return t:float()
    end)
    -- Within the float's row cap...
    nx.test.expect(#float.lines <= 20).to_be_truthy()
    -- ...and still carrying the keys that used to fall off the end.
    nx.test.expect(float.text).to_contain("Split horizontal")
    nx.test.expect(float.text).to_contain("Split vertical")
    nx.test.expect(float.text).to_contain("Max width")
    -- ...as well as the head of the list.
    nx.test.expect(float.text).to_contain("Taller")
    nx.test.expect(float.text).to_contain("Dock layer")
  end)

  -- Every row stays inside the float's 80-column cap, so a columnized layout never
  -- gets its right-hand column clipped off.
  nx.test.it("keeps columnized rows within the float width cap", function(t)
    t:feed("<C-w>")
    local float = t:wait_for(function()
      return t:float()
    end)
    for _, line in ipairs(vim.split(float.text, "\n", { plain = true })) do
      nx.test.expect(nx.str.displaywidth(line) <= 80).to_be_truthy()
    end
  end)

  -- Too narrow for the natural column widths: descriptions ellipsize so every column
  -- still fits, rather than the float clipping one off the right edge.
  nx.test.it("ellipsizes descriptions when the popup is capped narrow", function(t)
    local kh = require("nxvim-keys-helper")
    kh.setup({ max_width = 34 })
    t:feed("<C-w>")
    local float = t:wait_for(function()
      return t:float()
    end)
    kh.setup({ max_width = 80 })
    for _, line in ipairs(vim.split(float.text, "\n", { plain = true })) do
      nx.test.expect(nx.str.displaywidth(line) <= 34).to_be_truthy()
    end
    nx.test.expect(float.text).to_contain("…")
  end)

  -- Capped so short that not even columns fit everything: the popup SAYS how many
  -- keys it couldn't show instead of dropping them silently.
  nx.test.it("reports the keys a too-small popup cannot show", function(t)
    local kh = require("nxvim-keys-helper")
    kh.setup({ max_height = 2 })
    t:feed("<C-w>")
    local float = t:wait_for(function()
      return t:float()
    end)
    kh.setup({ max_height = 20 })
    nx.test.expect(#float.lines).to_equal(2)
    nx.test.expect(float.text).to_contain("more")
    -- The marker has to FIT — it is what announces the overflow, so it must not be
    -- the thing the float clips off the right edge.
    for _, line in ipairs(vim.split(float.text, "\n", { plain = true })) do
      nx.test.expect(nx.str.displaywidth(line) <= 78).to_be_truthy()
    end
  end)

  -- A re-run of setup() re-applies config to the LIVE popup: the show delay is read
  -- when a prefix goes pending, not frozen into the debounce at mount time.
  nx.test.it("re-applies the delay on a second setup", function(t)
    local kh = require("nxvim-keys-helper")
    kh.setup({ delay = 60000 })
    t:feed("<Space>", { settle = 4 })
    -- Nothing showed in those ticks — the new 60s delay is in force.
    nx.test.expect(t:float()).to_be_nil()
    kh.setup({ delay = 0 }) -- restore for the tests after this one
    t:feed("<Esc>")
  end)

  -- Once the popup is UP, descending refreshes it immediately: re-debouncing would
  -- leave the previous prefix's keys on screen for another `delay` ms.
  nx.test.it("refreshes an open popup without re-waiting the delay", function(t)
    local kh = require("nxvim-keys-helper")
    kh.setup({ delay = 300 })
    t:feed("<Space>")
    t:wait_for(function()
      return t:float()
    end, { interval = 5, tries = 200 })
    -- A few settle ticks — single-digit ms, far under the 300ms show delay.
    t:feed("f", { settle = 3 })
    nx.test.expect(t:float().text).to_contain("find file")
    kh.setup({ delay = 0 })
  end)

  -- `<leader>` in a spec is resolved when the popup RENDERS, not when the entry is
  -- registered — a config that sets `vim.g.mapleader` after the plugin's setup()
  -- (the usual lazy-plugin ordering) still gets its group names.
  nx.test.it("resolves <leader> in the spec at render time", function(t)
    local kh = require("nxvim-keys-helper")
    vim.g.mapleader = "," -- register the group under a DIFFERENT leader...
    kh.add({ { "<leader>z", group = "zed" } })
    vim.g.mapleader = " " -- ...then settle on the real one
    nx.keymap.set("n", "<leader>za", function() end, { desc = "alpha" })
    t:feed("<Space>")
    local float = t:wait_for(function()
      return t:float()
    end)
    nx.test.expect(float.text).to_contain("+zed")
  end)

  -- A colorscheme almost always opens with `:hi clear`, wiping the fallback groups.
  -- The plugin must re-install them on ColorScheme, or the popup loses its colors
  -- the moment a theme loads.
  nx.test.it("re-installs its highlight fallbacks after a colorscheme", function(t)
    t:cmd("hi clear")
    nx.test.expect(nx.hl.exists("WhichKey")).to_be_falsy()
    t:cmd("colorscheme nxvim")
    nx.test.expect(nx.hl.exists("WhichKey")).to_be_truthy()
    nx.test.expect(nx.hl.exists("WhichKeyGroup")).to_be_truthy()
  end)

  -- The defaults are DERIVED from the active theme (nx.hl.palette), not hardcoded, so
  -- the popup reads as part of whatever colorscheme is loaded. Under the editor's own
  -- `nxvim` scheme that means its One Dark hues, and switching themes re-derives them.
  nx.test.it("derives its default colors from the active colorscheme", function(t)
    local function fg(group)
      local d = nx.hl.get(0, { name = group, link = false })
      return d.fg and string.format("#%06x", d.fg) or nil
    end
    t:cmd("colorscheme nxvim")
    nx.test.expect(fg("WhichKey")).to_equal("#56b6c2") -- One Dark cyan
    nx.test.expect(fg("WhichKeyGroup")).to_equal("#c678dd") -- One Dark purple
    nx.test.expect(fg("WhichKeyDesc")).to_equal("#abb2bf") -- One Dark fg
    nx.test.expect(fg("WhichKeySeparator")).to_equal("#5c6370") -- One Dark comment

    -- A different theme moves them: define the groups the palette reads, then reload.
    t:cmd("hi clear")
    nx.hl.define(0, "Operator", { fg = "#111111" })
    nx.hl.define(0, "Keyword", { fg = "#222222" })
    nx.hl.define(0, "Normal", { fg = "#333333", bg = "#000000" })
    nx.hl.define(0, "Comment", { fg = "#444444" })
    require("nxvim-keys-helper").setup()
    nx.test.expect(fg("WhichKey")).to_equal("#111111")
    nx.test.expect(fg("WhichKeyGroup")).to_equal("#222222")
    nx.test.expect(fg("WhichKeyDesc")).to_equal("#333333")
    nx.test.expect(fg("WhichKeySeparator")).to_equal("#444444")
  end)

  -- Loud on nonsense rather than a popup that silently never shows.
  nx.test.it("rejects a bad option type", function(t)
    local kh = require("nxvim-keys-helper")
    local ok, err = pcall(kh.setup, { delay = "soon" })
    nx.test.expect(ok).to_be_falsy()
    nx.test.expect(tostring(err)).to_contain("delay")
  end)
end)
