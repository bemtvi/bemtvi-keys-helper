-- nxvim-keys-helper — a live popup of the keys that can follow what you've typed.
--
-- A which-key for nxvim, built natively on `nx.*`: no blocking key reads, no key
-- interception. It listens to the engine's pending-key ORACLE (`nx.on_key_pending`)
-- and draws the continuations as a non-focus floating window — so it never
-- interrupts the sequence you're in the middle of typing.
--
-- Install it through the `:Plugins` manager (in your init.lua):
--
--     nx.plugins({
--       { "davidrios/nxvim-keys-helper",
--         config = function() require("nxvim-keys-helper").setup({}) end },
--     })
--
-- TRY IT: press <leader> (or `g`, `z`, `<C-w>`) and pause. A bordered popup
-- appears in the bottom-right corner listing every key that can follow, with each
-- mapping's `desc`. Keep typing into a group and it refreshes to that group's keys;
-- complete a mapping, break the sequence, or wait the timeout and it closes.
--
-- ---------------------------------------------------------------------------
-- How it works (the three nx signals)
-- ---------------------------------------------------------------------------
--   * nx.on_key_pending(fn)   the engine's pending-prefix ORACLE. The server
--                 watches the mapped-prefix trie and pushes a context
--                 — { mode, keys, continuations = {{ key, desc, kind, available }}, label }
--                 — every time the withheld prefix changes (grows / descends /
--                 clears). It is fire-on-change, not per-keystroke (ADR 0002 rule
--                 4: no per-key Lua). The built-in command grammar arrives over the
--                 SAME event (source B): the OPEN states (`f` find-char, `r`
--                 replace, marks, operator-pending `d`/`c`/`y`) have no key list, so
--                 they carry a `label` ("Find character"); the FINITE built-in
--                 prefixes (`z` → zt/zz/zb…, `g` → gg/gt/…, `<C-w>` → window
--                 commands) carry enumerated `continuations`, and for `g` the engine
--                 MERGES the built-in motions with any maps sharing the `g` prefix
--                 (the LSP gd/gD/gr defaults) into one popup.
--   * nx.component{ surface = "float" }   the popup is a FLOAT-backed component:
--                 reactive state (the pending context) + a pure `render` + a
--                 lifecycle. An EMPTY render hides it, so the whole show/refresh/hide
--                 is declarative and the plugin never touches a float handle. The
--                 "float" surface takes NO focus and binds NO keys.
--   * nx.utils.debounce(fn, ms)   coalesce the oracle's bursts so a fast, deliberate
--                 sequence (`<Space>w` typed quickly) never flashes the popup — it
--                 only appears when you PAUSE. Only the FIRST show is debounced; once
--                 the popup is up, descending refreshes it at once (see setup).

local M = {}

-- The plugin's default highlight groups, mirroring the which-key.nvim names so a
-- colorscheme that already styles them just works. These are only applied as a
-- FALLBACK — if the active colorscheme (or the user, via opts.highlights) already
-- defines a group, that definition wins (see apply_highlights). The defaults read
-- well on a dark background with no theme loaded, so a bare setup() still looks
-- right.
local DEFAULT_HIGHLIGHTS = {
  WhichKey = { fg = "#7dcfff" }, -- the key itself (cyan)
  WhichKeyGroup = { fg = "#bb9af7", bold = true }, -- a +prefix group
  WhichKeyDesc = { fg = "#c0caf5" }, -- a mapping's description
  WhichKeySeparator = { fg = "#565f89" }, -- the gap between key and desc
}

-- Defaults merged with the user's opts in setup(). `delay` is the pause (ms) after
-- the LAST key before the popup appears — real which-key uses ~200ms so quick,
-- deliberate sequences stay invisible. `relative`/`border` are passed straight to
-- the float mount; "bottom" is the classic bottom-right which-key spot.
-- `timeout` is applied straight to `vim.o.timeout`. It defaults to FALSE — a
-- which-key wants a paused prefix to stay pending for as long as you look at the
-- popup, but vim's default `timeout = true` commits the prefix to the built-in
-- grammar after `timeoutlen` (which is what strands the LSP `g`-maps as
-- `available == false`, see entries_for). Disabling it keeps the sequence open. Pass
-- `timeout = true` to setup() to keep vim's mapping timeout instead.
--
-- Every one of these is read at RENDER / SHOW time, never captured at mount, so a
-- second setup() re-applies them to the live popup.
M.config = {
  delay = 200,
  timeout = false,
  relative = "bottom",
  border = "rounded",
  group_marker = "+", -- prefix shown before a group's name (e.g. "+file")
  highlights = {}, -- user highlight overrides, keyed by group name
  -- The popup's largest size, in cells. Defaults to the float's own hard caps (see
  -- FLOAT_MAX_H / FLOAT_MAX_W); lower them to keep the popup small, raise them and
  -- the caps still win. A screen smaller than the cap bounds it further.
  max_height = 20,
  max_width = 80,
}

-- The group-name registry, as RAW (unexpanded) spec entries in registration order:
-- `{ { prefix = "<leader>f", group = "file" }, … }`. The server reports a prefix that
-- only leads deeper as `kind = "group"` with `desc = nil` (it has no own mapping to
-- carry a description), so a group's NAME can only come from here. Populated by M.add
-- (and opts.spec in setup). Stored raw — `<leader>` is expanded lazily, see groups().
M._spec = {}

local mounted = nil -- the component handle, so a second setup() doesn't double-mount

-- ----- group registry -------------------------------------------------------

-- The notation a leader expands to, matching how the oracle reports it: a space
-- leader prints as "<Space>" (see key_to_notation), every other single-char leader
-- is itself. `which` is "mapleader" or "maplocalleader"; both default to "\" as in
-- vim. We normalize to NOTATION (not the raw char) because the live context path we
-- match against — ctx.keys .. continuation.key — is always notation.
local function leader_notation(which)
  local l = vim.g[which]
  if l == nil then
    l = "\\"
  end
  if l == " " then
    return "<Space>"
  end
  return l
end

-- Normalize a registered prefix (e.g. "<leader>f") into the notation the oracle
-- emits ("<Space>f"), expanding <leader>/<localleader> case-insensitively.
local function normalize_prefix(s)
  s = s:gsub("<[lL][eE][aA][dD][eE][rR]>", function()
    return leader_notation("mapleader")
  end)
  s = s:gsub("<[lL][oO][cC][aA][lL][lL][eE][aA][dD][eE][rR]>", function()
    return leader_notation("maplocalleader")
  end)
  return s
end

-- The normalized `oracle prefix -> group name` lookup the renderer reads, derived
-- from M._spec and MEMOIZED.
--
-- It is derived lazily — not baked in at M.add — because `vim.g.mapleader` is very
-- often set AFTER the plugin's setup() runs (a plugin manager configures its plugins
-- before the rest of init.lua), and normalizing "<leader>f" against the wrong leader
-- silently yields a registry that never matches: the popup shows a bare "+more" and
-- nothing hints why. Resolving at render time means the spec always agrees with the
-- leader actually in force.
--
-- The cache is keyed on both leaders, so a leader change invalidates it on its own;
-- M.add drops it explicitly. Rebuilding is O(#spec) and only happens on that change,
-- so the render path is a plain table lookup.
local groups_cache, groups_cache_sig

local function groups()
  local sig = tostring(vim.g.mapleader) .. "\0" .. tostring(vim.g.maplocalleader)
  if groups_cache and groups_cache_sig == sig then
    return groups_cache
  end
  local map = {}
  for _, e in ipairs(M._spec) do
    map[normalize_prefix(e.prefix)] = e.group
  end
  groups_cache, groups_cache_sig = map, sig
  return map
end

-- add(spec) — name prefix groups so the popup shows "+file" instead of a bare
-- "+more". `spec` is a list of entries; each is either
--   { "<leader>f", group = "file" }            (positional prefix)
--   { prefix = "<leader>g", group = "git" }    (named field)
-- Only the group NAME is taken from here — leaf mappings carry their own `desc`
-- through nx.keymap.set. Call it any time (before or after setup, before or after
-- `vim.g.mapleader` is set); the next popup reflects it. Re-adding a prefix replaces
-- its name, so calling it repeatedly is safe.
function M.add(spec)
  if type(spec) ~= "table" then
    error("nxvim-keys-helper.add: expects a list of { prefix, group } entries", 2)
  end
  for _, entry in ipairs(spec) do
    if type(entry) ~= "table" then
      error("nxvim-keys-helper.add: each entry must be a { prefix, group } table", 2)
    end
    local prefix = entry.prefix or entry[1]
    if type(prefix) ~= "string" then
      error("nxvim-keys-helper.add: each entry needs a prefix string", 2)
    end
    if entry.group ~= nil and type(entry.group) ~= "string" then
      error("nxvim-keys-helper.add: `group` must be a string", 2)
    end
    local found
    for _, e in ipairs(M._spec) do
      if e.prefix == prefix then
        found = e
        break
      end
    end
    if found then
      found.group = entry.group
    else
      M._spec[#M._spec + 1] = { prefix = prefix, group = entry.group }
    end
  end
  groups_cache = nil -- the spec moved; rebuild on the next render
end

-- ----- highlights -----------------------------------------------------------

-- Apply the highlight groups as a FALLBACK: an explicit user override (opts.highlights)
-- always wins; otherwise a default is installed only when the group isn't already
-- defined, so a colorscheme that styles WhichKey* keeps its colors.
local function apply_highlights(user)
  for name, spec in pairs(DEFAULT_HIGHLIGHTS) do
    if user[name] then
      nx.hl.define(0, name, user[name])
    elseif not nx.hl.exists(name) then
      nx.hl.define(0, name, spec)
    end
  end
  -- Any extra groups the user named that aren't in our defaults — honor them too.
  for name, spec in pairs(user) do
    if not DEFAULT_HIGHLIGHTS[name] then
      nx.hl.define(0, name, spec)
    end
  end
end

-- ----- layout ---------------------------------------------------------------

-- The content float's own caps, mirrored from the server's projection
-- (nxvim-server/src/redraw.rs::project_content_float): rows past MAX_H and cells past
-- MAX_W are CLIPPED, silently. The `<C-w>` alphabet alone is 24 keys — laid out as one
-- column it lost its last four rows off the bottom of the float with nothing on screen
-- to say so. So the layout budgets itself against these caps and spills into COLUMNS
-- rather than off the end.
local FLOAT_MAX_H, FLOAT_MAX_W = 20, 80
local FLOAT_CHROME = 2 -- the bordered box spends one cell on each side

local PAD = 1 -- breathing space on each side of a cell
local GAP = 3 -- cells between a key and its description
local MIN_LABEL = 3 -- narrowest a description column shrinks to ("a…")
local MIN_CELL = PAD + 1 + GAP + MIN_LABEL + PAD -- narrowest possible column

-- The rows / cells the popup may occupy: the configured maximum, bounded by the
-- float's hard caps and by the screen when the terminal is smaller than either.
local function budget()
  local rows = tonumber(vim.o.lines) or (FLOAT_MAX_H + FLOAT_CHROME)
  local cells = tonumber(vim.o.columns) or (FLOAT_MAX_W + FLOAT_CHROME)
  return math.max(1, math.min(FLOAT_MAX_H, M.config.max_height, rows - FLOAT_CHROME)),
    math.max(MIN_CELL, math.min(FLOAT_MAX_W, M.config.max_width, cells - FLOAT_CHROME))
end

-- `s` clipped to `w` display cells, ellipsized when it doesn't fit. Returns the text
-- and its display width. `sw` is `s`'s own width (already known to the caller).
-- Display-width aware, so a wide/CJK description clips at the right CELL rather than
-- the right byte; the binary search keeps it to O(log n) substring builds, and it only
-- runs at all on the narrow-terminal path.
local function clip(s, w, sw)
  if sw <= w then
    return s, sw
  end
  if w <= 1 then
    return "…", 1
  end
  local lo, hi = 0, nx.str.chars(s) -- widest char-prefix that fits w-1 cells
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if nx.str.displaywidth(nx.str.charpart(s, 0, mid)) <= w - 1 then
      lo = mid
    else
      hi = mid - 1
    end
  end
  local head = nx.str.charpart(s, 0, lo)
  return head .. "…", nx.str.displaywidth(head) + 1
end

-- The badge shown when the popup is too small to hold every key — see columnize.
local function overflow_marker(n)
  return string.format(" +%d more ", n)
end

-- Slice `entries` into column-major columns that fit `h` rows and `w` cells, each
-- carrying its own key / label column widths.
--
-- Columns are added only as the row budget demands (`ceil(n / h)`), so a short menu
-- keeps the classic single-column which-key look. When the columns don't fit the width
-- budget the widest description column gives up a cell at a time until they do — even
-- descriptions beat a column clipped off the right edge. Returns the columns plus the
-- count of entries that STILL didn't fit (only reachable on a screen too small to hold
-- them), which the caller surfaces rather than dropping silently.
local function columnize(entries, h, w)
  local n = #entries
  local ncols = math.max(1, math.min(math.floor(w / MIN_CELL), math.ceil(n / h)))
  local rows = math.ceil(n / ncols)
  local hidden = 0
  if rows > h then
    -- Too small for everything even columnized: fill what fits and reserve the last
    -- cell for the "+N more" marker.
    rows = h
    local capacity = rows * ncols - 1
    hidden = n - capacity
    n = capacity
    -- The marker occupies the reserved cell, so the columns must leave room for it —
    -- otherwise the very badge announcing the overflow is what the float clips off.
    w = math.max(MIN_CELL, w - nx.str.displaywidth(overflow_marker(hidden)))
  end

  local cols = {}
  for ci = 1, ncols do
    local col = { items = {}, kw = 1, lw = 1 }
    for r = 1, rows do
      local i = (ci - 1) * rows + r
      if i <= n and entries[i] then
        col.items[r] = entries[i]
        col.kw = math.max(col.kw, entries[i].kw)
        col.lw = math.max(col.lw, entries[i].lw)
      end
    end
    cols[ci] = col
  end

  -- Shrink description columns (widest first) until the row fits the width budget.
  local function total()
    local t = 0
    for _, col in ipairs(cols) do
      t = t + PAD + col.kw + GAP + col.lw + PAD
    end
    return t
  end
  while total() > w do
    local widest, wi = MIN_LABEL, nil
    for i, col in ipairs(cols) do
      if col.lw > widest then
        widest, wi = col.lw, i
      end
    end
    if not wi then
      break -- every column is already at its floor; the float clips the overflow
    end
    cols[wi].lw = cols[wi].lw - 1
  end
  return cols, rows, hidden
end

-- ----- rendering ------------------------------------------------------------

-- The continuations worth drawing, each pre-measured (display width, not byte length,
-- so wide/multibyte keys line up) with its resolved label and highlight.
--
-- `available == false` is a mapped continuation (e.g. the LSP gd/gD/gr) the oracle
-- still reports after the leader timeout committed its prefix to the built-in
-- grammar — pressing it now does nothing, so we drop the dead row rather than show it.
--
-- A group continuation (`kind == "group"`) is shown as the configured marker plus its
-- registered name (see groups()), falling back to the server's desc and then "more" —
-- a pure prefix has no mapping of its own to carry a description. A leaf shows its
-- mapping's `desc`.
local function entries_for(ctx)
  local named = groups()
  local out = {}
  for _, c in ipairs(ctx.continuations) do
    if c.available ~= false then
      local label, hl
      if c.kind == "group" then
        local desc = c.desc ~= nil and c.desc ~= "" and c.desc or nil
        label = M.config.group_marker .. (named[ctx.keys .. c.key] or desc or "more")
        hl = "WhichKeyGroup"
      else
        label = (c.desc ~= nil and c.desc ~= "") and c.desc or ""
        hl = "WhichKeyDesc"
      end
      out[#out + 1] = {
        key = c.key,
        kw = nx.str.displaywidth(c.key),
        label = label,
        lw = nx.str.displaywidth(label),
        hl = hl,
      }
    end
  end
  return out
end

-- Lay the continuations out as an aligned `key   label` grid, spilling into columns
-- when one column wouldn't fit the float. Each row is a list of `{ text, hl_group }`
-- CHUNKS (the styled-float form), so the key, the separator, and the description each
-- get their own color.
--
-- Source B (the open built-in states: `f` find-char, `r` replace, marks, …) has NO
-- discrete keys — its continuation set is open — so it arrives with empty
-- continuations and a `ctx.label`. We render that as a single hint card.
local function lines_for(ctx)
  local entries = entries_for(ctx)

  -- No keys to list (an open source-B state, or a context whose continuations were
  -- all unavailable): render the label as a single hint card.
  if #entries == 0 then
    return { { { string.format(" %s ", ctx.label or "…"), "WhichKeyDesc" } } }
  end

  local h, w = budget()
  local cols, rows, hidden = columnize(entries, h, w)
  local ncols = #cols

  local out = {}
  for r = 1, rows do
    local chunks = {}
    for ci = 1, ncols do
      local col, e = cols[ci], cols[ci].items[r]
      if e then
        local label, lw = clip(e.label, col.lw, e.lw)
        chunks[#chunks + 1] = { string.rep(" ", PAD), nil }
        chunks[#chunks + 1] = { e.key, "WhichKey" }
        chunks[#chunks + 1] = { string.rep(" ", col.kw - e.kw + GAP), "WhichKeySeparator" }
        chunks[#chunks + 1] = { label, e.hl }
        -- Pad out to the column's width so the next column lines up; the last column
        -- needs only its own margin (no trailing run to widen the float).
        local trail = PAD + (ci < ncols and (col.lw - lw) or 0)
        chunks[#chunks + 1] = { string.rep(" ", trail), nil }
      elseif ci < ncols then
        -- A hole in a short column: hold the width so later columns stay aligned.
        chunks[#chunks + 1] = { string.rep(" ", PAD + col.kw + GAP + col.lw + PAD), nil }
      end
    end
    out[#out + 1] = chunks
  end

  -- The screen was too small to hold every key even columnized. Say so in the last
  -- cell instead of letting the float clip the tail away in silence.
  if hidden > 0 then
    local last = out[#out]
    last[#last + 1] = { overflow_marker(hidden), "WhichKeyGroup" }
  end
  return out
end

-- ----- setup ----------------------------------------------------------------

-- The options setup() accepts, with the type each must be. Ordered (not a map) so the
-- error a bad config raises is always the same one.
local OPTIONS = {
  { "delay", "number" },
  { "timeout", "boolean" },
  { "relative", "string" },
  { "border", "string" },
  { "group_marker", "string" },
  { "max_height", "number" },
  { "max_width", "number" },
}

-- setup(opts) — wire the popup. Idempotent: a second call re-applies config and
-- highlights to the LIVE popup without mounting a second component.
--   opts.delay         pause (ms) after the last key before the popup shows (200)
--   opts.timeout       value for vim.o.timeout — false (the default) keeps a paused
--                      prefix pending; true restores vim's mapping timeout
--   opts.relative      float anchor: "bottom" | "cursor" | "editor" ("bottom")
--   opts.border        "rounded" | "single" | "double" | "solid" | "none"
--   opts.group_marker  string shown before a group name ("+")
--   opts.max_height    tallest the popup grows before spilling into columns (20)
--   opts.max_width     widest the popup grows before descriptions ellipsize (80)
--   opts.highlights    { GroupName = { fg=, bg=, bold= }, … } overrides, MERGED into
--                      any already registered
--   opts.spec          a group-name registry passed straight to M.add (see add)
function M.setup(opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    error("nxvim-keys-helper.setup: opts must be a table", 2)
  end

  -- Validate loudly: a mistyped option would otherwise land in M.config and surface
  -- much later as a popup that never appears (a string `delay`) or a float that fails
  -- to mount (a bad `border`).
  for _, o in ipairs(OPTIONS) do
    local name, want = o[1], o[2]
    local v = opts[name]
    if v ~= nil then
      if type(v) ~= want then
        error(
          string.format("nxvim-keys-helper.setup: `%s` must be a %s, got %s", name, want, type(v)),
          2
        )
      end
      M.config[name] = v
    end
  end
  if M.config.delay < 0 then
    error("nxvim-keys-helper.setup: `delay` must be >= 0", 2)
  end
  if M.config.max_height < 1 or M.config.max_width < MIN_CELL then
    error(
      string.format(
        "nxvim-keys-helper.setup: `max_height` must be >= 1 and `max_width` >= %d",
        MIN_CELL
      ),
      2
    )
  end

  if opts.highlights ~= nil then
    if type(opts.highlights) ~= "table" then
      error("nxvim-keys-helper.setup: `highlights` must be a table of group definitions", 2)
    end
    -- Merged, not replaced, so a later setup() adding one override doesn't drop the
    -- ones already in force (and the ColorScheme hook below re-applies the full set).
    for name, spec in pairs(opts.highlights) do
      if type(spec) ~= "table" then
        error("nxvim-keys-helper.setup: highlight `" .. tostring(name) .. "` must be a table", 2)
      end
      M.config.highlights[name] = spec
    end
  end
  apply_highlights(M.config.highlights)

  -- A colorscheme almost always opens with `:hi clear`, which wipes the fallbacks
  -- installed above and leaves the popup uncolored. Re-install them on ColorScheme —
  -- which fires AFTER the theme's own highlight calls, so a theme that styles
  -- WhichKey* still wins and one that doesn't gets working colors back. The augroup is
  -- cleared on each setup(), so a re-run never stacks a second hook.
  nx.autocmd.create("ColorScheme", {
    group = nx.augroup.create("NxvimKeysHelper", { clear = true }),
    desc = "nxvim-keys-helper: re-install the popup's fallback highlights",
    callback = function()
      apply_highlights(M.config.highlights)
    end,
  })

  -- Keep the prefix pending while the popup is up: by default `timeout = false`
  -- disables vim's mapping timeout, so a paused leader sequence never commits to
  -- the built-in grammar out from under the popup. A user who passed
  -- `timeout = true` gets vim's normal behavior back.
  vim.o.timeout = M.config.timeout

  if opts.spec then
    M.add(opts.spec)
  end

  -- Already mounted (a re-run of setup): config/highlights are live above, nothing
  -- more to do — don't stack a second oracle listener / float component.
  if mounted then
    return M
  end

  mounted = nx.component({
    surface = "float",
    setup = function(ctx)
      -- The one piece of state: the current pending context (or nil when there is none).
      local state = ctx.reactive({ pending = nil })

      -- The FIRST show is debounced so a quick sequence never flashes the popup.
      -- `nx.utils.debounce` bakes its interval in at construction, so rebuild it when
      -- `config.delay` changes — otherwise a second setup()'s delay would be silently
      -- ignored for the rest of the session.
      local show, show_ms
      local function schedule(c)
        if show_ms ~= M.config.delay then
          if show then
            show:cancel()
          end
          show = nx.utils.debounce(function(pending)
            state.pending = pending
          end, M.config.delay)
          show_ms = M.config.delay
        end
        show(c)
      end
      local function cancel()
        if show then
          show:cancel()
        end
      end

      nx.on_key_pending(function(c)
        if c.keys == "" then
          -- Cleared context (prefix completed, broke, or timed out): cancel the
          -- pending show and hide at once. A live source-B state has empty
          -- continuations but a non-empty `keys`, so gate on `keys` alone.
          cancel()
          state.pending = nil
        elseif state.pending ~= nil then
          -- Already on screen: refresh NOW. Debouncing an open popup would leave the
          -- PREVIOUS prefix's keys up for another `delay` ms after you descended into
          -- a group — you'd be reading a menu you already left.
          cancel()
          state.pending = c
        else
          schedule(c)
        end
      end)

      return state
    end,

    -- Pure: the pending context in, the popup's rows out. `nil` → empty render → hidden.
    render = function(state)
      local c = state.pending
      if not c then
        return { lines = {} }
      end
      -- Title the popup `keys — label` so the prefix isn't cryptic: a bare `d` reads
      -- as "d — Delete". Source-A leader prefixes have no label, so they title with
      -- the keys alone.
      local title = " " .. c.keys
      if c.label and c.label ~= "" then
        title = title .. " — " .. c.label
      end
      -- `relative`/`border` ride every render (the float backend honors them per
      -- frame), so a second setup() re-anchors the LIVE popup instead of being stuck
      -- with whatever the first mount passed.
      return {
        lines = lines_for(c),
        title = title .. " ",
        relative = M.config.relative,
        border = M.config.border,
      }
    end,
  }).mount({ relative = M.config.relative, border = M.config.border })

  return M
end

return M
