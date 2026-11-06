--[[
  BiS Healing :: Sounds.lua - THE SOUND EXPLORER (5 Nov 2026), `/bish sounds`.

  Arn, 5 Nov: "those are files in my computer do not make them public i jsut want to test them and then we use the
  ingame sounds that sound similar, i want a sound explorer for wow sounds where i can play the sound i uploaded and
  then i click on a in game sound to see if they sound similar".

  So: his two test sounds at the top (Media\click.ogg, Media\request.ogg - on his PC only, git ignores the folder), and
  under them every sound the game names in SOUNDKIT, searchable. Click a row: hear it. Shift-click: use it for "click";
  Ctrl-click: use it for "request". A pick takes over from his .ogg in the BiS> in test at once (FI.SOUNDS[..].picked)
  and is printed, so the id can be written into the addon for everyone. A typed number plays any kit id the table does
  not name. Nothing here is saved: the picks are for this session, and the id goes into the code.
]]

local ADDON, NS = ...
NS = NS or {}
local FX = {}
NS.FX = FX

FX.W, FX.H = 430, 300          -- 1.43:1, the family's window shape
FX.ROWS, FX.ROW_H = 10, 18
FX.offset, FX.filter = 0, ""
FX.picks = {}

-- a few kits worth hearing even where SOUNDKIT is missing or names nothing (ids heard on Forever: 839, 8959, 3081)
FX.EXTRA = {
    { name = "(options tick)", id = 856 }, { name = "(options untick)", id = 857 },
    { name = "(whisper bell)", id = 3081 }, { name = "(raid warning)", id = 8959 }, { name = "(heard 839)", id = 839 },
}

local function T(name)
    local th = rawget(_G, "BiSTheme")
    if th and th.rgb then
        local r, g, b = th.rgb(name)
        if r then return r, g, b end
    end
    return 0.72, 0.5, 1
end

--- Every named sound: { name, id }, by name. Read once from the game's own SOUNDKIT table.
function FX.All()
    if FX.all then return FX.all end
    local out, seen = {}, {}
    local kits = rawget(_G, "SOUNDKIT")
    if type(kits) == "table" then
        for name, id in pairs(kits) do
            if type(name) == "string" and type(id) == "number" and not seen[id] then
                seen[id] = true
                out[#out + 1] = { name = name, id = id }
            end
        end
    end
    for _, e in ipairs(FX.EXTRA) do
        if not seen[e.id] then seen[e.id] = true out[#out + 1] = { name = e.name, id = e.id } end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    FX.all = out
    return out
end

--- The list as the search box narrows it: a word in the name, or the id itself.
function FX.Shown()
    local want = tostring(FX.filter or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local all, out = FX.All(), {}
    if FX.typed then out[1] = { name = "typed id", id = FX.typed, typed = true } end
    for _, e in ipairs(all) do
        if want == "" or e.name:lower():find(want, 1, true) or tostring(e.id) == want then out[#out + 1] = e end
    end
    return out
end

--- Hear one game sound, on the effects channel.
function FX.Play(id)
    if type(id) ~= "number" or not PlaySound then return false end
    local ok, will = pcall(PlaySound, id, "SFX")
    FX.last = id
    return ok and will ~= false
end

--- Hear one of Arn's own test files.
function FX.PlayMine(which)
    local FI = NS.FI
    local s = FI and FI.SOUNDS and FI.SOUNDS[which]
    if not (s and PlaySoundFile) then return false end
    local ok, will = pcall(PlaySoundFile, s.file, "SFX")
    if not (ok and will) then
        NS.Print("sounds: your %s.ogg did not play - is it in BiSHealing\\Media, and was the game restarted since it was put there?", which)
        return false
    end
    return true
end

--- Use a game sound for "click" or "request" in the BiS> in test, from now on (this session).
function FX.Pick(which, e)
    local FI = NS.FI
    local s = FI and FI.SOUNDS and FI.SOUNDS[which]
    if not (s and e) then return false end
    s.picked = e.id
    FX.picks[which] = e
    FX.Play(e.id)
    NS.Print("sounds: |cffffd100%s|r = %s (|cff4fd0cf%d|r) - the test uses it now; tell Claude the id to keep it", which, e.name, e.id)
    FX.Paint()
    return true
end

--- A row's click: play; shift = use for click; ctrl = use for request.
function FX.ClickRow(r)
    local e = r and r.entry
    if not e then return end
    if IsShiftKeyDown and IsShiftKeyDown() then return FX.Pick("click", e) end
    if IsControlKeyDown and IsControlKeyDown() then return FX.Pick("request", e) end
    FX.Play(e.id)
    FX.Paint()
end

local function text(parent, template)
    return parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
end

local function box(parent, w)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(w, 20)
    e:SetAutoFocus(false)
    return e
end

function FX.Win()
    if FX.win then return FX.win end
    local f = CreateFrame("Frame", "BiSHealingSounds", UIParent)
    f:SetSize(FX.W, FX.H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
    f.title = text(f, "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 12, -10)
    f.title:SetText("BiS> sounds - which game sound is like yours")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    -- yours, at the top
    f.mine = {}
    for i, which in ipairs({ "click", "request" }) do
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(120, 20)
        b:SetPoint("TOPLEFT", 12 + (i - 1) * 126, -30)
        b:SetText("play your " .. which)
        b:SetScript("OnClick", function() FX.PlayMine(which) end)
        f.mine[which] = b
    end
    -- the search and a typed id
    f.find = box(f, 150)
    f.find:SetPoint("TOPLEFT", 18, -58)
    f.find:SetScript("OnTextChanged", function(self) FX.filter = self:GetText() or "" FX.offset = 0 FX.Paint() end)
    f.find:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.findWord = text(f)
    f.findWord:SetPoint("LEFT", f.find, "RIGHT", 6, 0)
    f.findWord:SetText("search (bell, click, chime...)")
    f.id = box(f, 60)
    f.id:SetPoint("TOPRIGHT", -14, -58)
    if f.id.SetNumeric then f.id:SetNumeric(true) end
    f.id:SetScript("OnEnterPressed", function(self)
        local n = tonumber(self:GetText() or "")
        FX.typed = n
        FX.offset = 0
        if n then FX.Play(n) end
        FX.Paint()
        self:ClearFocus()
    end)
    f.id:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.idWord = text(f)
    f.idWord:SetPoint("RIGHT", f.id, "LEFT", -8, 0)
    f.idWord:SetText("any id")
    -- the list
    f.rows = {}
    for i = 1, FX.ROWS do
        local r = CreateFrame("Button", nil, f)
        r:SetSize(FX.W - 24, FX.ROW_H)
        r:SetPoint("TOPLEFT", 12, -82 - (i - 1) * FX.ROW_H)
        r.lit = r:CreateTexture(nil, "BACKGROUND")
        r.lit:SetAllPoints()
        r.lit:SetColorTexture(1, 1, 1, 0.10)
        r.lit:SetAlpha(0)
        r.name = text(r)
        r.name:SetJustifyH("LEFT")
        r.name:SetPoint("LEFT", 4, 0)
        r.name:SetWidth(FX.W - 110)
        r.id = text(r)
        r.id:SetJustifyH("RIGHT")
        r.id:SetPoint("RIGHT", -4, 0)
        r.id:SetWidth(70)
        r:RegisterForClicks("AnyUp")
        r:SetScript("OnClick", function(self) FX.ClickRow(self) end)
        r:SetScript("OnEnter", function(self) self.lit:SetAlpha(1) end)
        r:SetScript("OnLeave", function(self) self.lit:SetAlpha(self.entry and self.entry.id == FX.last and 0.6 or 0) end)
        f.rows[i] = r
    end
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        local n = #FX.Shown()
        FX.offset = math.max(0, math.min(math.max(0, n - FX.ROWS), FX.offset - delta * 3))
        FX.Paint()
    end)
    -- the foot: how to use it, the count, what is picked
    f.count = text(f)
    f.count:SetJustifyH("LEFT")
    f.count:SetPoint("BOTTOMLEFT", 12, 30)
    f.count:SetWidth(FX.W - 24)
    f.picked = text(f)
    f.picked:SetJustifyH("LEFT")
    f.picked:SetPoint("BOTTOMLEFT", 12, 12)
    f.picked:SetWidth(FX.W - 24)
    f:Hide()
    FX.win = f
    return f
end

function FX.Paint()
    local f = FX.win
    if not f then return end
    local list = FX.Shown()
    local r1, g1, b1 = T("accent")
    for i, r in ipairs(f.rows) do
        local e = list[FX.offset + i]
        r.entry = e
        if e then
            r.name:SetText(e.name)
            r.id:SetText(tostring(e.id))
            if e.typed then r.name:SetTextColor(r1, g1, b1) else r.name:SetTextColor(1, 1, 1) end
            r.lit:SetAlpha(e.id == FX.last and 0.6 or 0)
            r:Show()
        else
            r:Hide()
        end
    end
    local from = #list > 0 and (FX.offset + 1) or 0
    f.count:SetText(("%d-%d of %d   click: hear it   shift-click: use for click   ctrl-click: use for request   wheel: scroll")
        :format(from, math.min(#list, FX.offset + FX.ROWS), #list))
    local c, q = FX.picks.click, FX.picks.request
    f.picked:SetText(("click: %s     request: %s"):format(c and (c.name .. " " .. c.id) or "your click.ogg",
        q and (q.name .. " " .. q.id) or "your request.ogg"))
end

function FX.Toggle(want)
    local f = FX.Win()
    if want == nil then want = not f:IsShown() end
    if want then f:Show() FX.Paint() else f:Hide() end
    return f:IsShown()
end
