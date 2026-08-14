-- Tests for bemtvi-keys-helper, run with `bemtvi --test-plugin`.
--
--     bemtvi --test-plugin ~/work/bemtvi-plugins/bemtvi-keys-helper
--
-- They drive a real editor through the `btv.test` framework: feed a leader prefix,
-- wait for the debounced popup, and assert on the floating window's text via
-- `t:float()`. `delay = 0` makes the popup appear on the next tick so a test never
-- waits on a wall-clock timer.

btv.test.describe("bemtvi-keys-helper", function()
  btv.test.before_each(function()
    -- Space leader, set BEFORE the maps so <leader> expands to <Space>.
    vim.g.mapleader = " "
    require("bemtvi-keys-helper").setup({
      delay = 0,
      spec = {
        { "<leader>f", group = "file" },
        { "<leader>g", group = "git" },
      },
    })
    btv.keymap.set("n", "<leader>w", function() end, { desc = "write" })
    btv.keymap.set("n", "<leader>q", function() end, { desc = "quit" })
    btv.keymap.set("n", "<leader>ff", function() end, { desc = "find file" })
    btv.keymap.set("n", "<leader>fg", function() end, { desc = "live grep" })
    btv.keymap.set("n", "<leader>gs", function() end, { desc = "git status" })
    btv.keymap.set("n", "<leader>gc", function() end, { desc = "git commit" })
  end)

  -- Pressing <leader> and pausing pops the menu of continuations.
  btv.test.it("shows the leader menu on pause", function(t)
    t:feed("<Space>")
    local float = t:wait_for(function()
      return t:float()
    end)
    btv.test.expect(float.text).to_contain("write")
    btv.test.expect(float.text).to_contain("quit")
  end)

  -- A prefix that only leads deeper renders with its registered group name.
  btv.test.it("names groups from the spec", function(t)
    t:feed("<Space>")
    local float = t:wait_for(function()
      return t:float()
    end)
    btv.test.expect(float.text).to_contain("+file")
    btv.test.expect(float.text).to_contain("+git")
  end)

  -- Descending into a group refreshes the popup to that group's keys.
  btv.test.it("refreshes when descending into a group", function(t)
    t:feed("<Space>f")
    local float = t:wait_for(function()
      local f = t:float()
      return f and f.text:find("find file") and f
    end)
    btv.test.expect(float.text).to_contain("find file")
    btv.test.expect(float.text).to_contain("live grep")
    -- The top-level leaves are gone now that we're inside `f`.
    btv.test.expect(float.text).never.to_contain("quit")
  end)

  -- Breaking the sequence (<Esc>) closes the popup.
  btv.test.it("closes when the sequence is aborted", function(t)
    t:feed("<Space>")
    t:wait_for(function()
      return t:float()
    end)
    t:feed("<Esc>")
    local closed = t:wait_for(function()
      return t:float() == nil
    end)
    btv.test.expect(closed).to_be_truthy()
  end)

  -- The built-in command grammar feeds the same popup: pausing after `z` lists the
  -- viewport commands (their continuation keys), no user maps involved.
  btv.test.it("shows the built-in z viewport grammar", function(t)
    t:feed("z")
    local float = t:wait_for(function()
      return t:float()
    end)
    -- `zt` (scroll cursor to top) — its continuation key `t` is listed.
    btv.test.expect(float.text).to_contain("t")
  end)

  -- An OPEN built-in state (source B) has no key list — it arrives with empty
  -- continuations and a label, which renders as a one-line hint card in the title
  -- and the body.
  btv.test.it("shows a hint card for an open built-in state", function(t)
    t:feed("f")
    local float = t:wait_for(function()
      return t:float()
    end)
    btv.test.expect(float.text).to_contain("Find character")
    btv.test.expect(float.title).to_contain("Find character")
  end)

  -- REGRESSION: the `<C-w>` alphabet is 24 keys, more than the content float's
  -- 20-row cap — as a single column the server clipped the tail and the popup
  -- silently lost `s`/`v`/`w`/`|`. They must be columnized, never dropped.
  btv.test.it("columnizes a long grammar instead of dropping rows", function(t)
    t:feed("<C-w>")
    local float = t:wait_for(function()
      return t:float()
    end)
    -- Within the float's row cap...
    btv.test.expect(#float.lines <= 20).to_be_truthy()
    -- ...and still carrying the keys that used to fall off the end.
    btv.test.expect(float.text).to_contain("Split horizontal")
    btv.test.expect(float.text).to_contain("Split vertical")
    btv.test.expect(float.text).to_contain("Max width")
    -- ...as well as the head of the list.
    btv.test.expect(float.text).to_contain("Taller")
    btv.test.expect(float.text).to_contain("Dock layer")
  end)

  -- Every row stays inside the float's 80-column cap, so a columnized layout never
  -- gets its right-hand column clipped off.
  btv.test.it("keeps columnized rows within the float width cap", function(t)
    t:feed("<C-w>")
    local float = t:wait_for(function()
      return t:float()
    end)
    for _, line in ipairs(vim.split(float.text, "\n", { plain = true })) do
      btv.test.expect(btv.str.displaywidth(line) <= 80).to_be_truthy()
    end
  end)

  -- Too narrow for the natural column widths: descriptions ellipsize so every column
  -- still fits, rather than the float clipping one off the right edge.
  btv.test.it("ellipsizes descriptions when the popup is capped narrow", function(t)
    local kh = require("bemtvi-keys-helper")
    kh.setup({ max_width = 34 })
    t:feed("<C-w>")
    local float = t:wait_for(function()
      return t:float()
    end)
    kh.setup({ max_width = 80 })
    for _, line in ipairs(vim.split(float.text, "\n", { plain = true })) do
      btv.test.expect(btv.str.displaywidth(line) <= 34).to_be_truthy()
    end
    btv.test.expect(float.text).to_contain("…")
  end)

  -- Capped so short that not even columns fit everything: the popup SAYS how many
  -- keys it couldn't show instead of dropping them silently.
  btv.test.it("reports the keys a too-small popup cannot show", function(t)
    local kh = require("bemtvi-keys-helper")
    kh.setup({ max_height = 2 })
    t:feed("<C-w>")
    local float = t:wait_for(function()
      return t:float()
    end)
    kh.setup({ max_height = 20 })
    btv.test.expect(#float.lines).to_equal(2)
    btv.test.expect(float.text).to_contain("more")
    -- The marker has to FIT — it is what announces the overflow, so it must not be
    -- the thing the float clips off the right edge.
    for _, line in ipairs(vim.split(float.text, "\n", { plain = true })) do
      btv.test.expect(btv.str.displaywidth(line) <= 78).to_be_truthy()
    end
  end)

  -- A re-run of setup() re-applies config to the LIVE popup: the show delay is read
  -- when a prefix goes pending, not frozen into the debounce at mount time.
  btv.test.it("re-applies the delay on a second setup", function(t)
    local kh = require("bemtvi-keys-helper")
    kh.setup({ delay = 60000 })
    t:feed("<Space>", { settle = 4 })
    -- Nothing showed in those ticks — the new 60s delay is in force.
    btv.test.expect(t:float()).to_be_nil()
    kh.setup({ delay = 0 }) -- restore for the tests after this one
    t:feed("<Esc>")
  end)

  -- Once the popup is UP, descending refreshes it immediately: re-debouncing would
  -- leave the previous prefix's keys on screen for another `delay` ms.
  btv.test.it("refreshes an open popup without re-waiting the delay", function(t)
    local kh = require("bemtvi-keys-helper")
    kh.setup({ delay = 300 })
    t:feed("<Space>")
    t:wait_for(function()
      return t:float()
    end, { interval = 5, tries = 200 })
    -- A few settle ticks — single-digit ms, far under the 300ms show delay.
    t:feed("f", { settle = 3 })
    btv.test.expect(t:float().text).to_contain("find file")
    kh.setup({ delay = 0 })
  end)

  -- `<leader>` in a spec is resolved when the popup RENDERS, not when the entry is
  -- registered — a config that sets `vim.g.mapleader` after the plugin's setup()
  -- (the usual lazy-plugin ordering) still gets its group names.
  btv.test.it("resolves <leader> in the spec at render time", function(t)
    local kh = require("bemtvi-keys-helper")
    vim.g.mapleader = "," -- register the group under a DIFFERENT leader...
    kh.add({ { "<leader>z", group = "zed" } })
    vim.g.mapleader = " " -- ...then settle on the real one
    btv.keymap.set("n", "<leader>za", function() end, { desc = "alpha" })
    t:feed("<Space>")
    local float = t:wait_for(function()
      return t:float()
    end)
    btv.test.expect(float.text).to_contain("+zed")
  end)

  -- A colorscheme almost always opens with `:hi clear`, wiping the fallback groups.
  -- The plugin must re-install them on ColorScheme, or the popup loses its colors
  -- the moment a theme loads.
  btv.test.it("re-installs its highlight fallbacks after a colorscheme", function(t)
    t:cmd("hi clear")
    btv.test.expect(btv.hl.exists("WhichKey")).to_be_falsy()
    t:cmd("colorscheme bemtvi")
    btv.test.expect(btv.hl.exists("WhichKey")).to_be_truthy()
    btv.test.expect(btv.hl.exists("WhichKeyGroup")).to_be_truthy()
  end)

  -- The defaults are DERIVED from the active theme (btv.hl.palette), not hardcoded, so
  -- the popup reads as part of whatever colorscheme is loaded. Under the editor's own
  -- `bemtvi` scheme that means its One Dark hues, and switching themes re-derives them.
  btv.test.it("derives its default colors from the active colorscheme", function(t)
    local function fg(group)
      local d = btv.hl.get(0, { name = group, link = false })
      return d.fg and string.format("#%06x", d.fg) or nil
    end
    t:cmd("colorscheme bemtvi")
    btv.test.expect(fg("WhichKey")).to_equal("#56b6c2") -- One Dark cyan
    btv.test.expect(fg("WhichKeyGroup")).to_equal("#c678dd") -- One Dark purple
    btv.test.expect(fg("WhichKeyDesc")).to_equal("#abb2bf") -- One Dark fg
    btv.test.expect(fg("WhichKeySeparator")).to_equal("#5c6370") -- One Dark comment

    -- A different theme moves them: define the groups the palette reads, then reload.
    t:cmd("hi clear")
    btv.hl.define(0, "Operator", { fg = "#111111" })
    btv.hl.define(0, "Keyword", { fg = "#222222" })
    btv.hl.define(0, "Normal", { fg = "#333333", bg = "#000000" })
    btv.hl.define(0, "Comment", { fg = "#444444" })
    require("bemtvi-keys-helper").setup()
    btv.test.expect(fg("WhichKey")).to_equal("#111111")
    btv.test.expect(fg("WhichKeyGroup")).to_equal("#222222")
    btv.test.expect(fg("WhichKeyDesc")).to_equal("#333333")
    btv.test.expect(fg("WhichKeySeparator")).to_equal("#444444")
  end)

  -- A client that can only deliver a chord via a stand-in (the browser: Chrome keeps
  -- `<C-w>` for itself, so the web client sends it on Alt) declares the substitution in
  -- `btv.ui.caps().key_labels`. The popup must NAME the chord the user can press —
  -- offering `<C-w>` to someone whose browser eats it is the one thing a key helper
  -- must not do. `btv._set_ui_caps` is the setter the server calls at attach; it takes
  -- the labels as the flat pair list the wire carries.
  btv.test.it("names keys the way the attached client can send them", function(t)
    btv._set_ui_caps(true, true, false, { "<C-w>", "<A-w>" })
    t:feed("<C-w>")
    local float = t:wait_for(function()
      local f = t:float()
      return f and f.text:find("Dock layer") and f
    end)
    -- The doubled window prefix is the row a browser visitor cannot press as reported.
    btv.test.expect(float.text).to_contain("<A-w>")
    btv.test.expect(float.text).never.to_contain("<C-w>")
    -- Unsubstituted continuations are untouched.
    btv.test.expect(float.text).to_contain("s")
    -- Including the title, which names the prefix you are already holding.
    btv.test.expect(float.title).to_contain("<A-w>")
    btv.test.expect(float.title).never.to_contain("<C-w>")
  end)

  -- …and with nothing to substitute (every terminal client) the canonical notation is
  -- what shows, so the relabeling can't leak into a session that never asked for it.
  btv.test.it("leaves keys alone when the client substitutes nothing", function(t)
    btv._set_ui_caps(true, true, false, {})
    t:feed("<C-w>")
    local float = t:wait_for(function()
      local f = t:float()
      return f and f.text:find("Dock layer") and f
    end)
    btv.test.expect(float.text).to_contain("<C-w>")
  end)

  -- Loud on nonsense rather than a popup that silently never shows.
  btv.test.it("rejects a bad option type", function(t)
    local kh = require("bemtvi-keys-helper")
    local ok, err = pcall(kh.setup, { delay = "soon" })
    btv.test.expect(ok).to_be_falsy()
    btv.test.expect(tostring(err)).to_contain("delay")
  end)
end)
