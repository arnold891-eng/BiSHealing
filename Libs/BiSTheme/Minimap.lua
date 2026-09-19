--[[
  BiSTheme / Minimap.lua  --  the button on the minimap, and the little menu behind it.

  Arn, 19 Sep 2026, looking at 25 slash commands: "lets make a minimap button with the options too
  many / commands". That is the whole brief. A command you have to remember is a feature only its
  author uses, and one addon here had grown twenty-five of them.

      /bish config, /bish lock, /bish center, /bish rescan, /bish reset, /bishf, /bishf mouse ...

  becomes one button you can see, with the same words behind it:

      BiS> Healing _                  <- the prompt, when Console.lua is loaded
        options                       <- a row that runs what the command ran
        mouse binds
        ---
        lock frames            on     <- a row that also says what it is set to
        what can I see?

  Usage from any addon:

      local b = BiSTheme.Minimap("BiSHealing", {
        icon  = "Interface\\Icons\\Spell_Nature_MagicImmunity",
        label = "Healing",
        db    = db.minimap,                  -- where the angle and the hidden flag live
        menu  = function() return { ... } end,
        onRight = function() OpenOptions() end,
      })

  A menu row is a table: { text, note, func, checked, disabled }, or { sep = true } for a line, or
  { title = "..." } for a heading. Pass `menu` as a FUNCTION when any note or tick changes - it is
  called every time the menu opens, so the rows say what is true now rather than what was true when
  the addon loaded.

  SELF-GUARDED like Console.lua and Options.lua: an addon may ship a copy under Libs\BiSTheme\ so
  the button works without the BiSTheme addon installed. Newest MINIMAP_MINOR wins. The canonical
  file lives here and is copied out by _bisdev/sync.ps1, never edited in place.

  It needs nothing from Options.lua or Console.lua, and uses the prompt for the menu header when
  Console.lua happens to be there.
]]

BiSTheme = BiSTheme or {}
local T = BiSTheme
if (T.MINIMAP_MINOR or 0) >= 1 then return end
T.MINIMAP_MINOR = 1

-- palette fallback: only when this file is embedded and no other BiSTheme file ran. Duplicated on
-- purpose, exactly as Options.lua duplicates it - a shared local between two embedded files is a
-- load-order bet, and this file may be the only one of the three an addon ships.
if not T.rgb then
  local FALLBACK = {
    bg = "121020", surface = "1a1730", sunken = "221d3c", line = "2a2446",
    line2 = "3a3260", ink = "ece8f6", ink2 = "c6bedd", muted = "968ead",
    accent = "b980ff", accentSoft = "2c2148", good = "4fd0cf", warn = "f08cb0",
    gold = "e5c04a", slate = "8fb4d6", dim = "8e86a6",
  }
  T.hex = T.hex or FALLBACK
  local cache = {}
  function T.rgb(name)
    local hex = T.hex[name] or T.hex.ink
    local c = cache[hex]
    if c then return c[1], c[2], c[3] end
    c = { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
          tonumber(hex:sub(5, 6), 16) / 255 }
    cache[hex] = c
    return c[1], c[2], c[3]
  end
  function T.rgba(name, a) local r, g, b = T.rgb(name) return r, g, b, a or 1 end
  function T.text(name, s) return "|cff" .. (T.hex[name] or T.hex.ink) .. tostring(s) .. "|r" end
end

-- Console.lua owns Fit; define it here too, for an addon that ships the button without the prompt.
if not T.Fit then
  function T.Fit(fs, text, width)
    fs:SetText(text)
    if not width or not fs.GetStringWidth then return text end
    local t = text
    while fs:GetStringWidth() > width and #t > 1 do
      t = t:sub(1, -2)
      fs:SetText(t .. "...")
    end
    return fs:GetText()
  end
end

-- The shape, in one table so a suite can assert on the numbers rather than repeat them.
T.MINIMAP = {
  SIZE   = 28,     -- the button
  ICON   = 18,
  RADIUS = 80,     -- the fallback ring: right for a 140 px minimap, wrong for every other one
  OVER   = 10,     -- how far PAST the edge the button's middle sits, so it straddles the ring
  ANGLE  = 204,    -- where a fresh install puts it: lower left, clear of the clock and the tracker
  ROW    = 15,     -- one menu row
  HEADER = 15,
  PAD    = 5,
  MIN_W  = 116,
  MAX_W  = 240,
}

local SHADE = { frame = "0d0b18", header = "141127", field = "17132e",
                hair = "2a2446", edge = "3a3260" }
local function colour(name)
  local hex = SHADE[name]
  if hex then
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
           tonumber(hex:sub(5, 6), 16) / 255
  end
  return T.rgb(name)
end

local function tex(parent, layer, name, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetAllPoints()
  local r, g, b = colour(name)
  t:SetColorTexture(r, g, b, a or 1)
  return t
end

local function fs(parent, text, size, name)
  local s = parent:CreateFontString(nil, "OVERLAY")
  s:SetFont(STANDARD_TEXT_FONT, size or 9, "")
  local r, g, b = colour(name or "ink")
  s:SetTextColor(r, g, b, 1)
  s:SetText(text or "")
  return s
end

local function border(frame, name, a)
  local b = {}
  for _, side in ipairs({ "top", "bottom", "left", "right" }) do
    local t = frame:CreateTexture(nil, "OVERLAY")
    local r, g, bl = colour(name)
    t:SetColorTexture(r, g, bl, a or 1)
    b[side] = t
  end
  b.top:SetPoint("TOPLEFT") b.top:SetPoint("TOPRIGHT") b.top:SetHeight(1)
  b.bottom:SetPoint("BOTTOMLEFT") b.bottom:SetPoint("BOTTOMRIGHT") b.bottom:SetHeight(1)
  b.left:SetPoint("TOPLEFT") b.left:SetPoint("BOTTOMLEFT") b.left:SetWidth(1)
  b.right:SetPoint("TOPRIGHT") b.right:SetPoint("BOTTOMRIGHT") b.right:SetWidth(1)
  b.name = name
  function b:set(n, alpha)
    local r, g, bl = colour(n)
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
      self[side]:SetColorTexture(r, g, bl, alpha or 1)
    end
    self.name = n
  end
  return b
end

-- atan2 left Lua in 5.3 and the game still has it. Either way, one name.
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

--------------------------------------------------------------------
-- the menu
--------------------------------------------------------------------

--- Resolve whatever the addon handed us into a plain list of rows. Exported because it is the one
--- part a headless suite can read back and name: the rows a click would show, with every note and
--- tick already asked.
function T.MinimapItems(menu)
  local spec = menu
  if type(spec) == "function" then
    local ok, got = pcall(spec)
    spec = ok and got or nil
  end
  if type(spec) ~= "table" then return {} end
  local rows = {}
  for _, row in ipairs(spec) do
    if type(row) == "table" then
      local r = {}
      for k, v in pairs(row) do r[k] = v end
      -- a checked or a note that is a FUNCTION is asked now, so the row says what is true now
      if type(r.checked) == "function" then
        local ok, on = pcall(r.checked)
        r.checked = (ok and on) and true or false
      end
      if type(r.note) == "function" then
        local ok, said = pcall(r.note)
        r.note = ok and said or nil
      end
      rows[#rows + 1] = r
    end
  end
  return rows
end

local function rowFrame(menu, i)
  local r = menu.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, menu)
  r:SetHeight(T.MINIMAP.ROW)
  r.hi = tex(r, "BACKGROUND", "accentSoft", 0)
  r.tick = tex(r, "ARTWORK", "accent", 1)
  r.tick:ClearAllPoints()
  r.tick:SetSize(5, 5)
  r.tick:SetPoint("LEFT", 5, 0)
  r.text = fs(r, "", 9, "ink2")
  r.text:SetPoint("LEFT", 13, 0)
  r.note = fs(r, "", 8, "muted")
  r.note:SetPoint("RIGHT", -6, 0)
  r.line = tex(r, "ARTWORK", "hair", 1)
  r.line:ClearAllPoints()
  r.line:SetHeight(1)
  r.line:SetPoint("LEFT", 5, 0)
  r.line:SetPoint("RIGHT", -5, 0)
  r:SetScript("OnEnter", function(s)
    local item = s.item
    if item and not item.sep and not item.title and not item.disabled then
      s.hi:SetColorTexture(T.rgba("accentSoft", 0.9))
      s.text:SetTextColor(T.rgb("ink"))
    end
  end)
  r:SetScript("OnLeave", function(s)
    s.hi:SetColorTexture(T.rgba("accentSoft", 0))
    s.text:SetTextColor(colour(s.item and s.item.title and "accent" or "ink2"))
  end)
  r:SetScript("OnClick", function(s)
    local item = s.item
    if not item or item.sep or item.title or item.disabled then return end
    -- CLOSE FIRST. A row that opens a window wants the menu out of the way, and a row that throws
    -- must not leave the menu sitting open on top of the error.
    menu:Hide()
    if type(item.func) == "function" then
      local ok, err = pcall(item.func)
      if not ok then print("|cffb980ffBiS|r: that menu row failed: " .. tostring(err)) end
    end
  end)
  menu.rows[i] = r
  return r
end

local function buildMenu(button)
  local menu = button.menuFrame
  if not menu then
    menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:EnableMouse(true)
    menu:Hide()
    tex(menu, "BACKGROUND", "frame", 0.97)
    menu.edge = border(menu, "edge", 1)
    menu.rows = {}

    -- the header: the family prompt when Console.lua is loaded, a plain word when it is not
    menu.head = CreateFrame("Frame", nil, menu)
    menu.head:SetHeight(T.MINIMAP.HEADER)
    menu.head:SetPoint("TOPLEFT", 1, -1)
    menu.head:SetPoint("TOPRIGHT", -1, -1)
    tex(menu.head, "BACKGROUND", "header", 1)
    menu.title = fs(menu.head, "", 9, "accent")
    menu.title:SetPoint("LEFT", 5, 0)

    -- CLICKING ANYWHERE ELSE SHUTS IT. A menu you can only leave by picking one of its rows is a
    -- trap, so a full-screen catcher sits one layer under it and eats the next click.
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    if catcher.SetFrameLevel and menu.GetFrameLevel then
      local lvl = menu:GetFrameLevel()
      if type(lvl) == "number" then catcher:SetFrameLevel(math.max(0, lvl - 1)) end
    end
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnClick", function() menu:Hide() end)
    catcher:Hide()
    menu.catcher = catcher
    menu:SetScript("OnHide", function() catcher:Hide() end)

    button.menuFrame = menu
  end

  local items = T.MinimapItems(button.opts.menu)
  local label = button.opts.label or button.key or "BiS"
  if T.Console and not menu.con then
    menu.con = T.Console(menu.title, { width = T.MINIMAP.MAX_W - 20, size = 9 })
    menu.con:Set("name", label)
    menu:SetScript("OnUpdate", function(s)
      if s.con and s.con.Paint then s.con:Paint() end
    end)
  elseif not menu.con then
    menu.title:SetText("BiS> " .. label)
  end

  -- Width: the longest row, clamped. MEASURED rather than guessed, because a note like
  -- "shift+wheel" is wider than the row that carries it, and a menu that clips its own words is
  -- worse than the commands it replaced.
  local width = T.MINIMAP.MIN_W
  local probe = menu.probe
  if not probe then
    probe = fs(menu, "", 9, "ink2")
    probe:Hide()
    menu.probe = probe
  end
  for _, item in ipairs(items) do
    local text = item.title or item.text
    if text and probe.GetStringWidth then
      probe:SetText(text .. "    " .. tostring(item.note or ""))
      local w = (probe:GetStringWidth() or 0) + 26
      if w > width then width = w end
    end
  end
  if width > T.MINIMAP.MAX_W then width = T.MINIMAP.MAX_W end

  local y = T.MINIMAP.HEADER + 2
  for i, item in ipairs(items) do
    local r = rowFrame(menu, i)
    r.item = item
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 1, -y)
    r:SetPoint("TOPRIGHT", -1, -y)
    if item.sep then
      r:SetHeight(5)
      r.text:SetText("")
      r.note:SetText("")
      r.tick:Hide()
      r.line:Show()
      r:Disable()
      y = y + 5
    else
      r:SetHeight(T.MINIMAP.ROW)
      r.line:Hide()
      T.Fit(r.text, item.title or item.text or "", width - 42)
      r.text:SetTextColor(colour(item.title and "accent"
                                 or (item.disabled and "dim" or "ink2")))
      r.note:SetText(item.note or "")
      if item.checked then r.tick:Show() else r.tick:Hide() end
      if item.title or item.disabled then r:Disable() else r:Enable() end
      y = y + T.MINIMAP.ROW
    end
    r:Show()
  end
  -- rows left over from a longer menu last time: parked, not destroyed
  for i = #items + 1, #menu.rows do
    menu.rows[i]:Hide()
    menu.rows[i].item = nil
  end

  menu:SetSize(width, y + T.MINIMAP.PAD)
  menu.width, menu.height, menu.count = width, y + T.MINIMAP.PAD, #items
  return menu
end

--------------------------------------------------------------------
-- the button
--------------------------------------------------------------------

--- Put a button on the minimap. Returns the button, or nil when this client has no minimap frame
--- to hang it on - which is the headless case, and any future client that renames it.
function T.Minimap(key, opts)
  opts = opts or {}
  local M = T.MINIMAP
  local parent = _G.Minimap
  if not parent or not CreateFrame then return nil end

  local b = CreateFrame("Button", "BiSMinimap" .. tostring(key or ""), parent)
  b.key, b.opts = key, opts
  b:SetSize(M.SIZE, M.SIZE)
  b:SetFrameStrata("MEDIUM")
  if b.SetFrameLevel and parent.GetFrameLevel then
    local lvl = parent:GetFrameLevel()
    if type(lvl) == "number" then b:SetFrameLevel(lvl + 8) end
  end
  b:RegisterForClicks("AnyUp")
  b:RegisterForDrag("LeftButton")

  -- The face: our own dark disc and border rather than Blizzard's brass ring, because the ring is
  -- 53 px of art around a 20 px icon and the family already owns a look.
  tex(b, "BACKGROUND", "frame", 0.92)
  b.edge = border(b, "edge", 1)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(M.ICON, M.ICON)
  b.icon:SetPoint("CENTER")
  if opts.icon then
    b.icon:SetTexture(opts.icon)
    -- trim the icon's own border off, so it fills our square rather than framing itself
    if b.icon.SetTexCoord then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  else
    b.icon:Hide()
    b.letter = fs(b, "B", 12, "accent")
    b.letter:SetPoint("CENTER")
  end

  --- How far out the ring is. MEASURED, not assumed: 80 is the number every minimap button in the
  --- game uses and it is only correct for a 140 px minimap. Arn, 19 Sep, with a screenshot of this
  --- button sitting inside the map while everyone else's sat on the edge: "everyone else buttons
  --- are on the outside". This client's minimap is wider, so 80 was well inside it.
  function b:Radius()
    local w = parent.GetWidth and parent:GetWidth()
    if type(w) == "number" and w > 0 then return w / 2 + M.OVER end
    return M.RADIUS
  end

  --- Where it sits. The angle is a compass reading in degrees, kept in the addon's own db so it
  --- survives a reload, and the maths is the same for every minimap the game has ever had.
  function b:Place()
    local d = self.opts.db
    local a = math.rad((type(d) == "table" and tonumber(d.angle)) or M.ANGLE)
    local r = self:Radius()
    self:ClearAllPoints()
    self:SetPoint("CENTER", parent, "CENTER", r * math.cos(a), r * math.sin(a))
    return a
  end

  --- Drag it round the edge. OnUpdate rather than OnDragStop, so it follows the cursor while you
  --- hold it - which is what every other minimap button in the game does.
  local function follow(self)
    if not GetCursorPosition or not parent.GetCenter then return end
    local mx, my = parent:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    if not mx or not cx or scale == 0 then return end
    local angle = math.deg(atan2(cy / scale - my, cx / scale - mx))
    local d = self.opts.db
    if type(d) == "table" then d.angle = angle end
    self.angle = angle
    self:Place()
  end
  b.Follow = follow
  b:SetScript("OnDragStart", function(s)
    s.dragging = true
    s:CloseMenu()
    s:SetScript("OnUpdate", follow)
  end)
  b:SetScript("OnDragStop", function(s)
    s.dragging = false
    s:SetScript("OnUpdate", nil)
  end)

  --- The menu, opened against the button and kept on the screen.
  function b:OpenMenu()
    local menu = buildMenu(self)
    menu:ClearAllPoints()
    -- below the button, opening away from the nearest screen edge
    local cx = self.GetCenter and select(1, self:GetCenter()) or 0
    local mid = ((UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 1024) / 2
    if (cx or 0) < mid then
      menu:SetPoint("TOPLEFT", self, "BOTTOMRIGHT", 2, -2)
    else
      menu:SetPoint("TOPRIGHT", self, "BOTTOMLEFT", -2, -2)
    end
    menu.catcher:Show()
    menu:Show()
    return menu
  end

  function b:CloseMenu()
    if self.menuFrame then self.menuFrame:Hide() end
  end

  function b:ToggleMenu()
    if self.menuFrame and self.menuFrame:IsShown() then
      self:CloseMenu()
      return false
    end
    self:OpenMenu()
    return true
  end

  b:SetScript("OnClick", function(s, click)
    if click == "RightButton" and type(s.opts.onRight) == "function" then
      s:CloseMenu()
      s.opts.onRight()
      return
    end
    s:ToggleMenu()
  end)

  b:SetScript("OnEnter", function(s)
    s.edge:set("accent", 1)
    if not GameTooltip then return end
    GameTooltip:SetOwner(s, "ANCHOR_LEFT")
    GameTooltip:AddLine("BiS> " .. tostring(s.opts.label or s.key), T.rgb("accent"))
    for _, line in ipairs(s.opts.tooltip or {}) do
      GameTooltip:AddLine(line, T.rgb("muted"))
    end
    GameTooltip:AddLine("left-click  the menu", T.rgb("muted"))
    if s.opts.onRight then GameTooltip:AddLine("right-click  options", T.rgb("muted")) end
    GameTooltip:AddLine("drag  move me round the edge", T.rgb("muted"))
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(s)
    s.edge:set("edge", 1)
    if GameTooltip then GameTooltip:Hide() end
  end)

  --- Show it, hide it, or put it back where the db says. ONE place, so an options toggle and a
  --- slash command cannot disagree about which is true.
  function b:Refresh()
    local d = self.opts.db
    self:Place()
    if type(d) == "table" and d.hide then self:Hide() else self:Show() end
    return self:IsShown()
  end

  function b:SetHidden(hide)
    local d = self.opts.db
    if type(d) == "table" then d.hide = hide and true or false end
    return self:Refresh()
  end

  b:Refresh()
  return b
end
