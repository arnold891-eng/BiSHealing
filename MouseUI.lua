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
    -- the rank, small, in the corner of the icon: which Healing Wave this is matters more to a
    -- healer than which spell it is
    f.rank = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.rank:SetPoint("BOTTOMRIGHT", 1, -1)
    f.slot = slot

    local function take()
        local spell = FM.CursorSpell()
        if not spell then return false end
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
        GameTooltip:AddLine(name or "empty", rgb("ink"))
        if rank then GameTooltip:AddLine(rank, rgb("muted")) end
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
    w:SetSize(250, 300)
    w:SetPoint("CENTER")
    w:SetMovable(true)
    w:EnableMouse(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", w.StopMovingOrSizing)
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
    -- Escape closes it too, the way every other window in the game does
    if type(_G.UISpecialFrames) == "table" then
        tinsert(_G.UISpecialFrames, "BiSHealingMouse")
    end

    -- under the tabs, not beside the header: the console's rotating word lives up there and the
    -- two of them were printing on top of each other
    local hint = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOP", 0, -62)
    hint:SetText("drag a spell from your spellbook onto a button")

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

    local foot = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    foot:SetPoint("BOTTOM", 0, 8)
    foot:SetWidth(230)
    foot:SetText("binds are written out of combat")

    function w:Refresh()
        for i, m in ipairs(FM.MODS) do
            local on = (m.key == self.mod)
            self.tabs[i].bg:SetVertexColor(on and SLOT_ON[1] or SLOT_BG[1],
                                           on and SLOT_ON[2] or SLOT_BG[2],
                                           on and SLOT_ON[3] or SLOT_BG[3], on and 1 or 0.9)
            self.tabs[i].text:SetTextColor(rgb(on and "accent" or "muted"))
        end
        for key, f in pairs(self.slots) do
            local spell = FM.Get(self.mod, key)
            local name, rank = FM.Split(spell)
            local icon = spellIcon(spell)
            if spell and icon then
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
            -- "Rank 3" -> "3": the slot is 30 pixels wide and you already know what it means
            f.rank:SetText(rank and (rank:match("%d+") or rank) or "")
            f.rank:SetTextColor(rgb("accent"))
        end
        foot:SetText((InCombatLockdown and InCombatLockdown())
            and "in combat: binds are queued until the fight ends"
            or "binds are written out of combat")
    end

    if w.con and C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(0.2, function()
            if w:IsShown() and w.con and w.con.Paint then w.con:Paint() end
        end)
    end

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
        w:Show()
    end
    return w:IsShown()
end
