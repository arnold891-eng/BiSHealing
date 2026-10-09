--[[
  BiSHealing / Forever :: Forever/MouseUI.lua - the picture of the mouse you drop spells onto.

  Drag a spell out of the spellbook and drop it on the button you mean to press. Right-click a slot
  to clear it. The tabs across the top are the modifier: no modifier, shift, ctrl, alt - so the
  same five buttons and two wheel directions give twenty-eight places to put a spell.

  Drawn rather than drawn-from-art: two buttons, a wheel and two thumb buttons out of plain
  textures, because a shape you recognise beats an icon grid that you have to read.

  Nothing here casts anything. Dropping a spell writes a bind; the bind becomes a secure attribute
  on the grid cells (or an override binding, for the wheel), and Blizzard's own code does the rest
  when you click. That is the only way an addon is allowed to help, on this client or any other.
]]
local ADDON, NS = ...
NS = NS or {}
local FM = NS.FM

-- The family's palette, asked for PER CALL rather than captured: BiSTheme loads after us
-- alphabetically, so a colour grabbed at file load is the fallback violet forever.
local FALLBACK = { ink = { 0.93, 0.91, 0.96 }, muted = { 0.59, 0.56, 0.68 },
                   accent = { 0.73, 0.50, 1.00 } }
local function rgb(name)
    local T = _G.BiSTheme
    if T and T.rgb and T.hex and T.hex[name] then return T.rgb(name) end
    local f = FALLBACK[name] or FALLBACK.ink
    return f[1], f[2], f[3]
end
local BODY, SLOT_BG, SLOT_ON = { 0.11, 0.09, 0.14 }, { 0.16, 0.14, 0.20 }, { 0.20, 0.16, 0.30 }

local function texture(parent, layer, r, g, b, a)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    t:SetVertexColor(r, g, b, a or 1)
    return t
end

--- The icon for a bind. Ask WITHOUT the rank: "Healing Wave(Rank 3)" is a cast string, not a
--- spell name, and the client answers nothing for it - which is why a ranked bind showed as text.
local function spellIcon(cast)
    if not cast then return nil end
    local name = FM.Split(cast)
    if not name then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, name)
        if ok and tex then return tex end
    end
    if GetSpellTexture then
        local ok, tex = pcall(GetSpellTexture, name)
        if ok and tex then return tex end
    end
    return nil
end

--------------------------------------------------------------------
-- where the window sits
--------------------------------------------------------------------

-- Arn, 19 Sep 2026, with the spellbook open and the binder beside it: "if we open the spellbook
-- window and we have the bind window open can we anchor it to this spot ... defualt place the
-- last place it was in".
--
-- Two rules, in that order:
--   1. while the spellbook is open, sit against its right edge - because that is where you are
--      looking when you are dragging spells out of it
--   2. otherwise, the last place you put it
--
-- The book is found BY NAME, because it is built on demand by one of Blizzard's own addons, and
-- which name it has is a question about the client rather than about us: this one has
-- TogglePlayerSpellsFrame, an older one has SpellBookFrame, and asking for all of them costs
-- nothing.
FM.BOOKS = { "PlayerSpellsFrame", "SpellBookFrame", "ClassSpellBookFrame" }

--- The spellbook frame, if one of them is open right now.
function FM.Book()
    for _, name in ipairs(FM.BOOKS) do
        local f = _G[name]
        if type(f) == "table" and f.IsShown then
            local ok, shown = pcall(f.IsShown, f)
            if ok and shown then return f, name end
        end
    end
    return nil
end

--- Remember where it was dragged to - the anchor itself rather than a screen position, so it
--- lands in the same place at a different resolution.
function FM.SavePos(w)
    w = w or FM.win
    if not w or not w.GetPoint then return nil end
    local ok, point, _, rel, x, y = pcall(w.GetPoint, w)
    if not ok or not point then return nil end
    local db = NS.DB and NS.DB()
    if type(db) ~= "table" then return nil end
    db.mousePos = { point = point, rel = rel, x = x, y = y }
    return db.mousePos
end

--- Put it back where it was left, or in the middle on a first run.
function FM.Restore(w)
    w = w or FM.win
    if not w then return end
    local db = NS.DB and NS.DB()
    local pos = type(db) == "table" and db.mousePos or nil
    w:ClearAllPoints()
    if type(pos) == "table" and pos.point then
        w:SetPoint(pos.point, UIParent, pos.rel or pos.point, pos.x or 0, pos.y or 0)
    else
        w:SetPoint("CENTER")
    end
end

--- Dock against the spellbook while it is open, and go back to the remembered spot when it shuts.
--- Asked on a ticker rather than hung off a hook: the book is created the first time it is
--- opened, by an addon that may not be loaded yet, and a hook waiting for a frame to exist is
--- three moving parts where a question every fifth of a second is one.
function FM.Place(w)
    w = w or FM.win
    if not w then return nil end
    local book = FM.Book()
    if book and not w.undocked then
        if w.dockedTo ~= book then
            w:ClearAllPoints()
            w:SetPoint("TOPLEFT", book, "TOPRIGHT", 8, 0)
            w.dockedTo = book
        end
        return "docked"
    end
    if w.dockedTo then                      -- the book closed: back where it was
        w.dockedTo = nil
        FM.Restore(w)
    end
    if not book then w.undocked = nil end   -- dragging it away counts for this opening only
    return "free"
end

--- One drop target on the drawing.
local function makeSlot(parent, slot)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(slot.bind and 26 or 30, slot.bind and 12 or 20)
    f:SetPoint("CENTER", parent.mouse, "CENTER", slot.x, slot.y)
    f:RegisterForClicks("AnyUp")
    f:RegisterForDrag("LeftButton")

    f.bg = texture(f, "BACKGROUND", SLOT_BG[1], SLOT_BG[2], SLOT_BG[3], 0.95)
    f.bg:SetAllPoints()
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("CENTER")
    f.icon:SetSize(18, 18)
    f.icon:Hide()
    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.empty:SetPoint("CENTER")
    f.empty:SetText("--")
    -- A BOOSTER RIDING IN FRONT (8 Oct 2026): its own little icon in the top-left corner, so a
    -- slot reads "Nature's Swiftness, then this heal" at a glance
    -- HALF AND HALF, not a corner badge: Arn, on the 10 px badge - "super tiny, maybe we make it
    -- like half ns/half the other spell". The booster's icon covers the LEFT half of the heal's
    -- (its own left half, cropped), with a thin dark seam between them.
    f.boost = f:CreateTexture(nil, "OVERLAY")
    f.boost:SetSize(9, 18)
    f.boost:SetPoint("TOPLEFT", f.icon, "TOPLEFT", 0, 0)
    f.boost:SetTexCoord(0, 0.5, 0, 1)
    f.boost:Hide()
    f.seam = f:CreateTexture(nil, "OVERLAY", nil, 1)
    f.seam:SetColorTexture(0.05, 0.05, 0.05, 0.9)
    f.seam:SetSize(1, 18)
    f.seam:SetPoint("TOP", f.icon, "TOP", 0, 0)
    f.seam:Hide()
    -- THE RANK, and it is a BUTTON. Which Healing Wave this is matters more to a healer than
    -- which spell it is, and dropping a lower rank assumes your spellbook is set to show you one
    -- to drag. Click the little number instead: it walks the ranks this character has trained,
    -- and wraps, so it is safe to click without reading.
    f.rankBtn = CreateFrame("Button", nil, f)
    f.rankBtn:SetSize(14, 9)
    f.rankBtn:SetPoint("BOTTOMRIGHT", 2, -2)
    f.rank = f.rankBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.rank:SetPoint("CENTER")
    f.rankBtn:SetScript("OnClick", function()
        local was = FM.Get(parent.mod, slot.key)
        local now = FM.CycleRank(parent.mod, slot.key)
        parent:Refresh()
        FM.Apply()
        if was and now == was and parent.Say then
            parent:Say("only one rank of that is trained")
        end
    end)
    f.rankBtn:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("click for the next rank", rgb("accent"))
        local name = FM.Split(FM.Get(parent.mod, slot.key))
        local n = name and #FM.Ranks(name) or 0
        GameTooltip:AddLine(n > 1 and (n .. " ranks trained") or "only one rank trained",
                            rgb("muted"))
        GameTooltip:Show()
    end)
    f.rankBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    f.slot = slot

    local function take()
        -- a held ping first: it is the only payload the real cursor cannot carry
        if FM.held then
            FM.Set(parent.mod, slot.key, FM.PingBind(FM.held))
            FM.held = nil
            if ClearCursor then ClearCursor() end
            parent:Refresh()
            FM.Apply()
            return true
        end
        local spell = FM.CursorSpell()
        if not spell then return false end
        -- NATURE'S SWIFTNESS ON A HEAL GOES IN FRONT OF IT (8 Oct 2026), rather than replacing it:
        -- the slot casts the booster, then the heal, in one press. A booster on an empty slot, a
        -- ping, or another booster is an ordinary drop. A heal dropped on a boosted slot replaces
        -- both - drop the heal again to go back to a plain heal.
        local dropped = FM.Split(spell)
        local had = FM.Get(parent.mod, slot.key)
        local _, hadHeal = FM.Boost(had)
        if FM.BOOSTERS[dropped] and hadHeal and not FM.PingOf(hadHeal)
           and not FM.BOOSTERS[(FM.Split(hadHeal))] then
            spell = FM.WithBoost(dropped, hadHeal)
        end
        FM.Set(parent.mod, slot.key, spell)
        if ClearCursor then ClearCursor() end
        parent:Refresh()
        FM.Apply()
        return true
    end
    f:SetScript("OnReceiveDrag", take)
    f:SetScript("OnMouseUp", function(_, button)
        if take() then return end
        if button == "RightButton" then
            FM.Clear(parent.mod, slot.key)
            parent:Refresh()
            FM.Apply()
        end
    end)
    f:SetScript("OnEnter", function(self)
        self.bg:SetVertexColor(SLOT_ON[1], SLOT_ON[2], SLOT_ON[3], 1)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(slot.label, rgb("accent"))
        local spell = FM.Get(parent.mod, slot.key)
        local name, rank = FM.Split(spell)
        -- an empty CLICK targets the person (FM.ApplyTo); an empty wheel does nothing of ours
        local boost = FM.Boost(spell)
        if boost then GameTooltip:AddLine(boost .. " first, then", rgb("good")) end
        GameTooltip:AddLine(name or (slot.attr and "empty - a click targets them" or "empty"), rgb("ink"))
        if rank then GameTooltip:AddLine(rank, rgb("muted")) end
        if boost then GameTooltip:AddLine("drop the heal again to take " .. boost .. " off", rgb("muted")) end
        GameTooltip:AddLine(spell and "right-click to clear" or "drag a spell here",
                            rgb("muted"))
        if slot.bind then
            GameTooltip:AddLine("the wheel casts at whatever you are hovering", rgb("muted"))
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function(self)
        self.bg:SetVertexColor(SLOT_BG[1], SLOT_BG[2], SLOT_BG[3], 0.95)
        if GameTooltip then GameTooltip:Hide() end
    end)
    return f
end

function FM.Window()
    if FM.win then return FM.win end

    local w = CreateFrame("Frame", "BiSHealingMouse", UIParent)
    w:SetSize(250, 356)             -- 330 + the heal palette's row (8 Oct 2026)
    FM.Restore(w)                   -- the last place it was put, or the middle on a first run
    w:SetMovable(true)
    w:EnableMouse(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", function(self)
        self:StartMoving()
        -- dragging it is you saying where it goes, so it stops being docked to the spellbook
        -- until the book has been closed and opened again
        self.dockedTo, self.undocked = nil, true
    end)
    w:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        FM.SavePos(self)
    end)
    w.mod = ""

    local bg = texture(w, "BACKGROUND", BODY[1], BODY[2], BODY[3], 0.94)
    bg:SetAllPoints()

    local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -10)
    -- the header every BiS window carries: "BiS> " in the accent, then a word that blinks and
    -- rotates. BiSTheme.Console owns it, and the copy under Libs keeps it working when the
    -- BiSTheme addon is not installed - which is the whole point of embedding the console.
    if _G.BiSTheme and _G.BiSTheme.Console then
        w.con = _G.BiSTheme.Console(title, { width = 120, size = 10 })
        w.con:Set("name", "Healing")
        w.con:Set("mouse", "bind a click")
    else
        title:SetText("BiS> Healing")
        title:SetTextColor(rgb("accent"))
    end

    -- A CLOSE BUTTON, and Escape. UIPanelCloseButton is Blizzard's own X and needs no art from
    -- us; when a client does not ship the template we draw the X ourselves, because a window you
    -- can only shut by remembering the slash command is a window that stays open.
    local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
    if not close.SetScript then close = CreateFrame("Button", nil, w) end
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", 2, 2)
    if not close.GetNormalTexture or not close:GetNormalTexture() then
        local x = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        x:SetPoint("CENTER")
        x:SetText("x")
        x:SetTextColor(rgb("muted"))
        close:SetScript("OnEnter", function() x:SetTextColor(rgb("accent")) end)
        close:SetScript("OnLeave", function() x:SetTextColor(rgb("muted")) end)
    end
    close:SetScript("OnClick", function() w:Hide() end)
    w.close = close
    -- ESCAPE CLOSES IT, AND NOTHING ELSE DOES. This used to be one line - adding the window to
    -- UISpecialFrames, the list the client closes on Escape - and Arn found what else being on
    -- that list means: "right now if the bind window is open and i open the spell book it closes
    -- the bind window". Opening a panel like the spellbook calls CloseAllWindows(), which shuts
    -- every frame on that list. Joining it to get one key is joining Blizzard's whole panel
    -- system, and this window is not part of that system: it sits BESIDE the spellbook on
    -- purpose.
    --
    -- So the key is handled here. Escape is swallowed while the window is up; every other key
    -- propagates, so typing still reaches the chat box.
    --
    -- NOT IN COMBAT. SetPropagateKeyboardInput is protected once the lockdown is on: Arn, 21 Sep,
    -- in a dungeon - "[ADDON_ACTION_BLOCKED] AddOn 'BiSHealing' tried to call the protected function
    -- 'BiSHealingMouse:SetPropagateKeyboardInput()'", from a key pressed with the window open
    -- mid-pull. A blocked call is a popup, not an error pcall can catch, so it is simply not made
    -- there: in a fight every key passes through (the last setting, always "propagate"), and
    -- Escape closes the window without being swallowed.
    local function propagate(self, on)
        if InCombatLockdown and InCombatLockdown() then return false end
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(on) end
        return true
    end
    w:EnableKeyboard(true)
    propagate(w, true)
    w:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            propagate(self, false)
            self:Hide()
        else
            propagate(self, true)
        end
    end)
    w:SetScript("OnHide", function(self) propagate(self, true) end)

    -- under the tabs, not beside the header: the console's rotating word lives up there and the
    -- two of them were printing on top of each other
    -- ONE SHORT LINE. It said "drag a spell onto a button - or click a ping, then a button": 287 px
    -- in a 250 px window, both ends cut off (the fit check, 6 Oct 2026). How a ping is put down is
    -- in each ping's own tooltip, where there is room for it.
    local hint = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOP", 0, -62)
    hint:SetText("drop a spell or a ping on a button")
    w.hint = hint

    -- the modifier tabs
    w.tabs = {}
    for i, m in ipairs(FM.MODS) do
        local t = CreateFrame("Button", nil, w)
        t:SetSize(56, 17)
        t:SetPoint("TOPLEFT", 8 + (i - 1) * 58, -38)
        t.bg = texture(t, "BACKGROUND", SLOT_BG[1], SLOT_BG[2], SLOT_BG[3], 0.9)
        t.bg:SetAllPoints()
        t.text = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t.text:SetPoint("CENTER")
        t.text:SetText(m.label)
        t:SetScript("OnClick", function()
            w.mod = m.key
            w:Refresh()
        end)
        w.tabs[i] = t
    end

    -- the mouse itself: a body, a split for the two main buttons, a wheel between them
    -- The mouse, drawn from plain rectangles: two buttons across the top with a gap for the
    -- wheel, a waist under them, a body below, and two thumb buttons on the left flank. A shape
    -- you recognise beats a grid of icons you have to read.
    local mouse = CreateFrame("Frame", nil, w)
    mouse:SetSize(150, 190)
    mouse:SetPoint("TOP", 0, -80)
    w.mouse = mouse

    local body = texture(mouse, "BACKGROUND", 0.24, 0.21, 0.31, 1)
    body:SetSize(120, 190)
    body:SetPoint("TOP")

    local leftBtn = texture(mouse, "BORDER", 0.30, 0.26, 0.40, 1)
    leftBtn:SetSize(52, 74)
    leftBtn:SetPoint("TOPLEFT", mouse, "TOP", -59, -2)
    local rightBtn = texture(mouse, "BORDER", 0.30, 0.26, 0.40, 1)
    rightBtn:SetSize(52, 74)
    rightBtn:SetPoint("TOPRIGHT", mouse, "TOP", 59, -2)

    local wheelWell = texture(mouse, "BORDER", 0.17, 0.14, 0.23, 1)
    wheelWell:SetSize(14, 74)
    wheelWell:SetPoint("TOP", 0, -2)

    local waist = texture(mouse, "ARTWORK", BODY[1], BODY[2], BODY[3], 1)
    waist:SetSize(120, 2)
    waist:SetPoint("TOP", 0, -78)

    local flank1 = texture(mouse, "BORDER", 0.30, 0.26, 0.40, 1)
    flank1:SetSize(16, 22)
    flank1:SetPoint("TOPLEFT", mouse, "TOP", -76, -96)
    local flank2 = texture(mouse, "BORDER", 0.30, 0.26, 0.40, 1)
    flank2:SetSize(16, 22)
    flank2:SetPoint("TOPLEFT", mouse, "TOP", -76, -120)

    w.slots = {}
    for _, slot in ipairs(FM.SLOTS) do
        w.slots[slot.key] = makeSlot(w, slot)
    end

    -- THE PINGS, AS THINGS YOU CAN PUT ON A BUTTON (1 Oct 2026, Arn's design). A spell arrives on
    -- the real cursor and `FM.CursorSpell` reads it; a ping cannot, because the game's cursor only
    -- carries the game's own objects. So these are PICKED UP rather than dragged: click one, it
    -- lights, click a mouse button to drop it there. Click it again, or right-click anywhere, to
    -- put it down.
    --
    -- What they become is a macro on the cell - Blizzard's own /ping, run by Blizzard's code,
    -- which is the only road open after SendMacroPing came back forbidden (/bish ping, 1 Oct).
    w.pings = {}
    local pingHint = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pingHint:SetPoint("BOTTOMLEFT", 8, 36)
    pingHint:SetText("pings:")
    pingHint:SetTextColor(rgb("muted"))
    -- FOUR ACROSS, INSIDE THE WINDOW. They were 52 wide on a 52 step from x=44, so the fourth ended
    -- at 252 in a 250 window - two pixels hanging off the edge (the fit check, 6 Oct 2026).
    for i, p in ipairs(FM.PINGS or {}) do
        local b = CreateFrame("Button", nil, w)
        b:SetSize(50, 16)
        b:SetPoint("BOTTOMLEFT", 44 + ((i - 1) % 4) * 51, 36)
        b.bg = texture(b, "BACKGROUND", SLOT_BG[1], SLOT_BG[2], SLOT_BG[3], 0.9)
        b.bg:SetAllPoints()
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("CENTER")
        b.text:SetText(p.word)
        -- the client's own ping art when it has it, the word when it does not: not every ping
        -- type has a kit, so a missing icon is an ordinary outcome and not a failure
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(14, 14)
        b.icon:SetPoint("CENTER")
        b.icon:Hide()
        local atlas = FM.PingAtlas and FM.PingAtlas(p.key)
        if atlas and b.icon.SetAtlas then
            local okA = pcall(b.icon.SetAtlas, b.icon, atlas)
            if okA then b.icon:Show() b.text:Hide() end
        end
        b.ping = p.key
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(self, button)
            FM.held = (button == "RightButton" or FM.held == self.ping) and nil or self.ping
            w:Refresh()
        end)
        b:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(p.word .. " ping", rgb("accent"))
            GameTooltip:AddLine("click, then click a mouse button to put it there", rgb("muted"))
            GameTooltip:AddLine("the cell you click is who it pings", rgb("muted"))
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        w.pings[i] = b
    end

    -- YOUR HEALS, AT THEIR TOP RANK, READY TO DRAG (8 Oct 2026; FojjiCore's spell-rank rows). One
    -- row above the pings: drag an icon onto a mouse button - or click it, then click the button.
    -- Picked up by spell id at the highest trained rank, so the drop binds THAT rank (FM.Palette).
    w.palette = {}
    local PAL, PSTEP = 19, 21
    for i = 1, FM.PALETTE_MAX do
        local b = CreateFrame("Button", nil, w)
        b:SetSize(PAL, PAL)
        b:SetPoint("BOTTOMLEFT", 8 + (i - 1) * PSTEP, 58)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b:RegisterForDrag("LeftButton")
        b:RegisterForClicks("LeftButtonUp")
        local function pick(self)
            if self.spell then FM.PickUp(self.spell.id) end
        end
        b:SetScript("OnDragStart", pick)
        b:SetScript("OnClick", pick)
        b:SetScript("OnEnter", function(self)
            if not (GameTooltip and self.spell) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.spell.name, rgb("accent"))
            if self.spell.rank then GameTooltip:AddLine(self.spell.rank .. " - your highest", rgb("ink")) end
            GameTooltip:AddLine("drag it onto a mouse button", rgb("muted"))
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        b:Hide()
        w.palette[i] = b
    end

    local foot = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    foot:SetPoint("BOTTOM", 0, 8)
    foot:SetWidth(230)
    foot:SetText("binds are written out of combat")

    -- SAID WHERE IT IS SEEN. An empty button targets the person (FM.ApplyTo, 0.4.1), and nothing
    -- on the drawing says so. Arn, 22 Sep: "write on the bottom of the window anything not bound
    -- targets the unit". One line above the foot, in the 30 pixels under the mouse.
    local targets = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    targets:SetPoint("BOTTOM", foot, "TOP", 0, 2)
    targets:SetWidth(230)
    targets:SetText("anything not bound targets the unit")
    w.targetsNote = targets

    -- the header prompt is where this window talks back, if BiSTheme's console is loaded
    function w:Say(text)
        if self.con and self.con.Say then self.con:Say(text) end
    end

    function w:Refresh()
        for i, m in ipairs(FM.MODS) do
            local on = (m.key == self.mod)
            self.tabs[i].bg:SetVertexColor(on and SLOT_ON[1] or SLOT_BG[1],
                                           on and SLOT_ON[2] or SLOT_BG[2],
                                           on and SLOT_ON[3] or SLOT_BG[3], on and 1 or 0.9)
            self.tabs[i].text:SetTextColor(rgb(on and "accent" or "muted"))
        end
        for _, b in ipairs(self.pings or {}) do
            local on = (FM.held == b.ping)
            b.bg:SetVertexColor(on and SLOT_ON[1] or SLOT_BG[1],
                                on and SLOT_ON[2] or SLOT_BG[2],
                                on and SLOT_ON[3] or SLOT_BG[3], on and 1 or 0.9)
            b.text:SetTextColor(rgb(on and "accent" or "muted"))
        end
        for key, f in pairs(self.slots) do
            local spell = FM.Get(self.mod, key)
            local name, rank = FM.Split(spell)
            local ping = FM.PingOf(spell)
            local icon = not ping and spellIcon(spell) or nil
            if ping then
                -- the client's own art if it has it, the first four letters if not. No rank
                -- either way: showing "-" where a rank goes reads as "rank unknown" on something
                -- that was never a spell.
                local atlas = FM.PingAtlas and FM.PingAtlas(ping)
                local drew = false
                if atlas and f.icon.SetAtlas then drew = pcall(f.icon.SetAtlas, f.icon, atlas) end
                if drew then
                    f.icon:Show()
                    f.empty:Hide()
                else
                    f.icon:Hide()
                    f.empty:Show()
                    f.empty:SetText(FM.PingWord(ping):sub(1, 4))
                end
                f.rank:SetText("")
                f.rankBtn:Hide()
            elseif spell and icon then
                f.icon:SetTexture(icon)
                f.icon:Show()
                f.empty:Hide()
            elseif spell then
                f.icon:Hide()
                f.empty:Show()
                f.empty:SetText((name or spell):sub(1, 4))
            else
                f.icon:Hide()
                f.empty:Show()
                f.empty:SetText("--")
            end
            if not ping then
                -- "Rank 3" -> "3": the slot is 30 pixels wide and you already know what it means
                f.rank:SetText(rank and (rank:match("%d+") or rank) or (spell and "-" or ""))
                f.rank:SetTextColor(rgb(rank and "accent" or "muted"))
                if spell then f.rankBtn:Show() else f.rankBtn:Hide() end
            end
            local boost = FM.Boost(spell)
            local bicon = boost and spellIcon(boost) or nil
            -- only over a drawn heal icon: half of nothing is a stray half-icon
            if bicon and f.icon:IsShown() then
                f.boost:SetTexture(bicon) f.boost:Show() f.seam:Show()
            else
                f.boost:Hide() f.seam:Hide()
            end
        end
        -- the heal palette: this character's trained heals, top rank each (FM.Palette)
        local pal = FM.Palette()
        for i, b in ipairs(self.palette or {}) do
            local s = pal[i]
            b.spell = s
            local tex = s and spellIcon(s.name)
            if s and tex then b.icon:SetTexture(tex) b:Show() else b:Hide() end
        end
        -- 241 px of words in a 230 px line wrapped onto the note above it (the fit check, 6 Oct)
        foot:SetText((InCombatLockdown and InCombatLockdown())
            and "in combat: binds wait for the fight to end"
            or "binds are written out of combat")
    end

    -- Runs whether or not the prompt is there: it paints the header AND asks where the window
    -- should be sitting, and the second of those matters just as much on a client with no
    -- BiSTheme installed.
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(0.2, function()
            if not w:IsShown() then return end
            if w.con and w.con.Paint then w.con:Paint() end
            FM.Place(w)
        end)
    end

    -- HIDDEN THE MOMENT IT IS BUILT. A frame is SHOWN by default in this game, and building the
    -- window is what the first click does - so the first click found a window that was already
    -- "open", hid it, and looked like nothing happened. Arn: "have to click the mouse bind button
    -- twice for window to open".
    w:Hide()
    w:Refresh()
    FM.win = w
    return w
end

function FM.Toggle()
    local w = FM.Window()
    if w:IsShown() then
        w:Hide()
    else
        w:Refresh()
        -- placed BEFORE it is shown, and not a fifth of a second later: opening the binder while
        -- the spellbook is up should put it beside the book, not put it somewhere and then move it
        FM.Place(w)
        w:Show()
    end
    return w:IsShown()
end
