--[[
  BiS Healing :: Ask.lua - BiS> in, THE TEST (5 Nov 2026). Plan: _bisdev/docs/bisin.md.

  Arn, 5 Nov, with both accounts logged in: "can we set up a test for bis healing where i can click a button on the
  bis now and it askes the priest and shows a 3d face of me that it can click to try and cast fortitude as if its
  innervate". So: LibBiSComm 17's BiS> in protocol (OPT / REQ / CLAIM / CANCEL) end to end between two real
  clients, with Power Word: Fortitude standing in for Innervate - a low priest has Fortitude, and nobody here has a
  druid with Innervate yet.

  TEST ONLY. `/bish intest` (on / off / status), never saved - every login starts off, and both characters type it.
  It teaches THIS client's copy of the lib one more spell, `fort` (lib.BISIN), which no other client knows: a REQ
  for "fort" is dropped by anyone not running the test. The real thing is BiSTheme's shared Ask piece (bisin.md
  step 3) - this file proves the wire and the face first.

  - THE ASKER (any class: the test asks on anyone's behalf). BiS> now gets "Ask" - Fortitude's icon - while an
    opted-in priest in the group gives it. The click only SENDS (REQ): nothing secure, so it works in a fight too.
    Hover: who gives it, and after the click who is coming.
  - THE GIVER (whoever knows Fortitude). BiS> now gets the asker's 3D face, pre-aimed out of combat
    (`/cast [@unit] Power Word: Fortitude`). Dim until they ask, lit while the ask is open; the click casts and
    sends CLAIM - the first claim wins - and the asker's side says who is coming, then takes the ask back.
  - OUT OF REACH: out of combat the click aims at nobody and says so (probe round 1: an out-of-range `[@party1]`
    cast landed on the priest himself). In a fight the aim stays as it was built - a secure button cannot re-aim.
]]

local ADDON, NS = ...
NS = NS or {}
local FI = {}
NS.FI = FI

FI.SPELL = "fort"
FI.ID, FI.NAME = 1243, "Power Word: Fortitude"     -- rank 1, measured on Forever 4 Nov (Buffs.lua)
FI.on = false
FI.EDGE = 3        -- the gold frame round a face that is asking, in pixels; the model sits inside it

--- CLICKY (Arn, 5 Nov: "add clicky sounds when i click the stuff" - "if i give you an ogg can we use that?"). Our own
--- .ogg in the addon folder plays on Forever (heard 23 Oct, FojjiCore's 01.ogg); only the GAME's file paths are silent.
--- So Media\click.ogg is tried first, and until it is there PlaySoundFile says no and the game's own click plays. SFX,
--- never Master: muting sound effects mutes this too.
--- Arn's two (5 Nov): click.ogg when anyone clicks these buttons, request.ogg for the giver when someone asks.
FI.SOUNDS = {
    click   = { file = "Interface\\AddOns\\BiSHealing\\Media\\click.ogg",   kit = 856 },   -- the options window's tick
    request = { file = "Interface\\AddOns\\BiSHealing\\Media\\request.ogg", kit = 3081 },  -- a whisper's bell
}
FI.SOUND_FILE = FI.SOUNDS.click.file
FI.SOUND_KIT = FI.SOUNDS.click.kit
function FI.Sound(name)
    local s = FI.SOUNDS[name]
    if not s then return nil end
    if PlaySoundFile then
        local ok, will = pcall(PlaySoundFile, s.file, "SFX")
        if ok and will then return "file" end
    end
    if PlaySound then
        if pcall(PlaySound, s.kit, "SFX") then return "kit" end
    end
    return nil
end
function FI.Click() return FI.Sound("click") end

local function plain(v)
    if NS.Plain then return NS.Plain(v) end
    return v
end

local function ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil end
    return a, b
end

local function lib()
    local l = rawget(_G, "LibBiSComm")
    if l and l.BisInSet and l.BISIN then return l end
    return nil
end
FI.Lib = lib

local function me()
    local l = lib()
    return l and l.FullName and l.FullName("player") or nil
end

local function say(msg, ...)
    if NS.Print then NS.Print("BiS> in test: " .. msg, ...) end
end

--- Teach this client's lib the test spell, once. The lib keeps its spells in one table (lib.BISIN) and lists them in
--- lib.BISIN_ORDER; both are read at every message, so an entry added here is heard from the next line on.
function FI.Teach(l)
    l = l or lib()
    if not l then return false end
    if not l.BISIN[FI.SPELL] then
        l.BISIN[FI.SPELL] = { id = FI.ID, class = "PRIEST", cd = 0, target = true, test = true }
    end
    local seen = false
    for _, k in ipairs(l.BISIN_ORDER or {}) do if k == FI.SPELL then seen = true end end
    if not seen and l.BISIN_ORDER then table.insert(l.BISIN_ORDER, FI.SPELL) end
    return true
end

local function knowsFort()
    return (NS.FB and NS.FB.Knows and NS.FB.Knows(FI.NAME)) and true or false
end

----------------------------------------------------------------- who is who --

local function groupUnits()
    local out = {}
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do out[#out + 1] = "raid" .. i end
    else
        for i = 1, 4 do out[#out + 1] = "party" .. i end
    end
    return out
end

--- The group unit wearing this whole name ("Name Surname", as the lib's messages carry it), or nil.
function FI.UnitOf(name)
    local l = lib()
    if not (l and type(name) == "string") then return nil end
    for _, u in ipairs(groupUnits()) do
        if UnitExists and UnitExists(u) then
            local n = l.FullName and l.FullName(u)
            if n and n == name then return u end
        end
    end
    return nil
end

--- Should the asker's button be there? Test on, I ask, and an opted-in giver of Fortitude is in the group.
function FI.ShowAsk()
    local l = lib()
    if not (FI.on and l) then return false end
    local m = l:BisInMe()
    if not (m.on and m.ask) then return false end
    local _, _, givers = l:BisInReady(FI.SPELL)
    return #givers > 0
end

--- Whose face the giver sees: someone with an open ask first, else the first asker in the group. name, unit, request.
function FI.Asker()
    local l = lib()
    if not (FI.on and l) then return nil end
    local m = l:BisInMe()
    if not (m.on and m.give[FI.SPELL]) then return nil end
    for _, r in ipairs(l:BisInRequests(FI.SPELL)) do
        local u = FI.UnitOf(r.owner)
        if u then return r.owner, u, r end
    end
    for _, a in ipairs(l:BisInAskers()) do
        local u = FI.UnitOf(a.name)
        if u then return a.name, u, nil end
    end
    return nil
end

function FI.ShowFace()
    return FI.Asker() ~= nil
end

--- For FN.Mine: is this BiS> now button wanted now?
function FI.Show(key)
    if key == "inask" then return FI.ShowAsk() end
    if key == "inface" then return FI.ShowFace() end
    return false
end

--- The open, unclaimed ask from this person, if any.
local function openFrom(name)
    local l = lib()
    if not (l and name) then return nil end
    for _, r in ipairs(l:BisInRequests(FI.SPELL)) do
        if r.owner == name then return r end
    end
    return nil
end

------------------------------------------------------------------- switching --

--- `/bish intest on|off`: in the lib's BiS> in as an asker (always, for the test) and a giver of what this character
--- knows - Fortitude included. BiS> now is switched on too: the buttons live there.
function FI.Set(on)
    local l = lib()
    if not l then return nil, "no LibBiSComm" end
    if on then
        FI.Teach(l)
        FI.Hook(l)
        l:BisInSet(true, { ask = true })
        local m = l:BisInMe()
        if knowsFort() and not m.give[FI.SPELL] then
            local give = {}
            for k in pairs(m.give) do give[k] = true end
            give[FI.SPELL] = true
            l:BisInSet(true, { ask = true, give = give })
        end
        local d = NS.DB and NS.DB()
        if type(d) == "table" and d.now ~= true then d.now = true end
    else
        l:BisInSet(false)
        FI.myReq = nil
    end
    FI.on = on and true or false
    FI.Soon()
    return FI.on
end

--- What the test knows right now, for /bish intest status.
function FI.Status()
    local l = lib()
    if not l then return { "no LibBiSComm loaded" } end
    local m = l:BisInMe()
    local out = {}
    local give = {}
    for k in pairs(m.give or {}) do give[#give + 1] = k end
    table.sort(give)
    out[#out + 1] = ("%s - you ask: %s, you give: %s, BiS channel %s"):format(FI.on and "on" or "off",
        m.ask and "yes" or "no", #give > 0 and table.concat(give, ", ") or "nothing", l:Enabled() and "on" or "OFF")
    local ready, _, givers = l:BisInReady(FI.SPELL)
    out[#out + 1] = ("givers of Fortitude here: %s (%d ready)"):format(#givers > 0 and table.concat(givers, ", ") or "none", ready)
    local names = {}
    for _, a in ipairs(l:BisInAskers()) do
        local u = FI.UnitOf(a.name)
        local v = u and FI.Visible(u)
        local sight = not u and " (not found in the group)"
            or (" (" .. u .. ", the game " .. (v == true and "can see them" or v == false and "can't see them" or "hides whether it can see them") .. ")")
        names[#names + 1] = a.name .. sight
    end
    local FN = NS.FN
    local b = FN and FN.buttons and FN.buttons.inface
    if b and b:IsShown() then
        out[#out + 1] = ("face: %s - %s"):format(tostring(b.inName or "nobody"), b.modelSeen and "drawn" or "the icon, trying again every " .. FI.RETRY .. " s")
    end
    out[#out + 1] = ("askers here: %s"):format(#names > 0 and table.concat(names, ", ") or "none")
    return out
end

------------------------------------------------------------------- the asker --

--- The Ask click: REQ to the group. Plain Lua - nothing secure - so a fight changes nothing.
function FI.Ask()
    local l = lib()
    if not (FI.on and l) then return nil end
    if FI.myReq and l:BisInRequest(FI.myReq) then
        say("already asked - waiting for an answer")
        return FI.myReq
    end
    local id, why = l:BisInAsk(FI.SPELL)
    if not id then
        say("can't ask - %s", tostring(why))
        return nil
    end
    FI.myReq = id
    local _, _, givers = l:BisInReady(FI.SPELL)
    say("asked |cffffd100%s|r for Fortitude", table.concat(givers, ", "))
    FI.Soon()
    return id
end

local function askTip(self)
    if not GameTooltip then return end
    local l = lib()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Ask for Fortitude (BiS> in test)")
    if l then
        local ready, _, givers = l:BisInReady(FI.SPELL)
        GameTooltip:AddLine(("%d ready: %s"):format(ready, table.concat(givers, ", ")), 1, 1, 1, true)
    end
    if FI.coming then GameTooltip:AddLine(FI.coming .. " is coming.", 0.3, 0.9, 0.8, true) end
    GameTooltip:AddLine("Standing in for Innervate. /bish intest off to stop.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end

------------------------------------------------------------------- the giver --

local function inRange(unit)
    local f = (C_Spell and C_Spell.IsSpellInRange) or IsSpellInRange
    local v = plain(ask(f, FI.NAME, unit))
    return v == true or v == 1
end

--- Aim the face at the asker, with a rank they may wear. Out of combat only (at every layout and in PreClick).
function FI.Aim(b)
    if not (b and b.SetAttribute) then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    local name, unit = FI.Asker()
    local reach = unit and inRange(unit)
    local cast = FI.NAME
    local FU, FM = NS.FU, NS.FM
    if unit and FU and FU.RankFor and FU.Family then
        local level = plain(ask(UnitLevel, unit))
        local rank = FU.RankFor(FU.Family("fort"), type(level) == "number" and level or nil)
        if FM and FM.Cast then cast = FM.Cast(FI.NAME, rank) end
    end
    b:SetAttribute("*type1", "macro")
    b:SetAttribute("*macrotext1", (unit and reach) and ("/cast [@" .. unit .. "] " .. cast) or "")
    b.inName, b.inUnit, b.inFar = name, unit, (unit and not reach) and true or false
    return true
end

--- Can the game draw this person right now? true / false, or nil when it will not say (a hidden answer).
function FI.Visible(unit)
    local v = ask(UnitIsVisible, unit)
    if NS.Secret and NS.Secret(v) then return nil end
    return v == true
end

--- THEIR FACE, MADE EARLY AND KEPT (Arn, 5 Nov, looking at the icon where Chainheal's face should be: "it should make
--- their face becuase we cant do it in combat, so we have to generate every person face first"). The model is asked for
--- as soon as the person is in the test, whatever the distance, and Fortitude's icon shows behind it until the game has
--- drawn them once while it could see them; after that the face stays, near or far. A model is not a secure frame, so
--- this may run in a fight too - only the aim is frozen there. Runs after the button is shown (a model on a hidden frame
--- may never load), at every look, and every FI.RETRY seconds until they have been seen.
function FI.Face(b)
    if not (b and b.model) then return false end
    local unit = b.inUnit
    if not unit then
        b.model:Hide()
        if b.art then b.art:Show() end
        b.modelFor, b.modelSeen = nil, nil
        return false
    end
    local seen = FI.Visible(unit) == true
    if b.modelFor ~= b.inName or (seen and not b.modelSeen) then
        b.model:Show()
        pcall(b.model.ClearModel, b.model)
        pcall(b.model.SetUnit, b.model, unit)
        if b.model.SetPortraitZoom then pcall(b.model.SetPortraitZoom, b.model, 1) end
        b.modelFor, b.modelSeen = b.inName, seen or nil
    end
    b.model:Show()
    if b.art then
        if b.modelSeen then b.art:Hide() else b.art:Show() end      -- the icon shows through until the face is real
    end
    return b.modelSeen == true
end

--- The click on the face: the secure half casts (written out of combat); this half claims the ask.
function FI.Claim(b)
    local l = lib()
    if not (FI.on and l and b) then return false end
    local r = openFrom(b.inName)
    if not r then return false end
    -- OUT OF REACH, NOTHING WAS CAST - so nothing is claimed (Arn's first live run, 5 Nov: "out of reach - walk closer"
    -- then "claimed ... Fortitude on its way"). The ask stays open for whoever can reach them. In a fight reach is the
    -- client's secret, so a click there claims as before.
    if b.inFar and not (InCombatLockdown and InCombatLockdown()) then return false end
    local mine = l:BisInClaim(r.id)
    if mine then say("claimed |cffffd100%s|r's ask - Fortitude on its way", tostring(b.inName)) end
    FI.Soon()
    return mine
end

local function faceTip(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Fortitude on " .. tostring(self.inName or "nobody") .. " (BiS> in test)")
    if openFrom(self.inName) then GameTooltip:AddLine("They are asking - click to cast.", 1, 0.82, 0, true)
    else GameTooltip:AddLine("Lights up when they ask.", 1, 1, 1, true) end
    if self.inFar then GameTooltip:AddLine("Out of reach right now.", 1, 0.4, 0.4, true) end
    GameTooltip:Show()
end

----------------------------------------------------------- BiS> now's half --

--- Dress a BiS> now button (Now.lua's makeButton): "inask" or "inface".
function FI.Arm(b, key)
    if not b then return end
    b.inKey = key
    if b.art and b.art.SetTexture and C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, FI.ID)
        if ok and tex then pcall(b.art.SetTexture, b.art, tex) end
    end
    if key == "inask" then
        if not b.word and b.CreateFontString then
            b.word = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.word:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
            if b.word.SetFont then pcall(b.word.SetFont, b.word, STANDARD_TEXT_FONT, 9, "OUTLINE") end
        end
        if b.HookScript and not b.inHooked then
            b.inHooked = true
            b:HookScript("PostClick", function() FI.Click() FI.Ask() end)
            b:HookScript("OnEnter", askTip)
            b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        end
    elseif key == "inface" then
        -- LIT, SO YOU CAN SEE IT (Arn's run, 5 Nov: the ask arrived, "negative not bright"). A 3D model barely follows
        -- its button's alpha, so dim and lit looked the same on a face. A gold frame round it, drawn on the button and
        -- left uncovered by the model (inset FI.EDGE), says "they are asking"; its alpha is all that changes, which is
        -- legal in a fight.
        if not b.lit and b.CreateTexture then
            b.lit = {}
            for _, side in ipairs({ "top", "bottom", "left", "right" }) do
                local t = b:CreateTexture(nil, "OVERLAY")
                t:SetColorTexture(1, 0.82, 0, 1)
                t:SetAlpha(0)
                b.lit[side] = t
            end
            local e, w = b.lit, FI.EDGE
            e.top:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
            e.top:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
            e.top:SetHeight(w)
            e.bottom:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
            e.bottom:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
            e.bottom:SetHeight(w)
            e.left:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
            e.left:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
            e.left:SetWidth(w)
            e.right:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
            e.right:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
            e.right:SetWidth(w)
        end
        if not b.model and CreateFrame then
            local m = CreateFrame("PlayerModel", nil, b)
            m:SetPoint("TOPLEFT", b, "TOPLEFT", FI.EDGE, -FI.EDGE)
            m:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -FI.EDGE, FI.EDGE)
            if m.EnableMouse then m:EnableMouse(false) end           -- the click is the button's
            m:Hide()
            b.model = m
        end
        if b.HookScript and not b.inHooked then
            b.inHooked = true
            b:HookScript("PreClick", function(self)
                FI.Aim(self)
                if self.inFar and not (InCombatLockdown and InCombatLockdown()) then
                    say("%s is out of reach - walk closer", tostring(self.inName))
                end
            end)
            b:HookScript("PostClick", function(self) FI.Click() FI.Claim(self) end)
            b:HookScript("OnEnter", faceTip)
            b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        end
        FI.Aim(b)
    end
end

--- Paint: alpha only, legal in a fight. The face is lit while its person asks; the Ask button counts who is ready.
function FI.Paint(b)
    if not b then return end
    local l = lib()
    if b.inKey == "inface" then
        local asking = openFrom(b.inName) ~= nil
        b:SetAlpha(asking and 1 or 0.35)
        for _, t in pairs(b.lit or {}) do t:SetAlpha(asking and 1 or 0) end
        -- the model's own transparency, where the client has it (the button's alpha barely reaches a 3D model)
        if b.model and b.model.SetModelAlpha then pcall(b.model.SetModelAlpha, b.model, asking and 1 or 0.45) end
        b.asking = asking
    elseif b.inKey == "inask" then
        local ready = l and l:BisInReady(FI.SPELL) or 0
        if b.word then b.word:SetText(ready > 0 and tostring(ready) or "") end
        b:SetAlpha((FI.myReq and l and l:BisInRequest(FI.myReq)) and 0.6 or 1)
    end
end

--- Something changed: a message, the group, the fight ended. Out of combat a button that should come or go means a
--- layout; one that stays is re-aimed. In a fight only the paint (alpha) moves.
function FI.Soon()
    local FN = NS.FN
    if not (FN and FN.Layout) then return false end
    if InCombatLockdown and InCombatLockdown() then
        if FN.Paint then FN.Paint() end
        return false
    end
    local relayout = false
    for key, want in pairs({ inask = FI.ShowAsk(), inface = FI.ShowFace() }) do
        local b = FN.buttons and FN.buttons[key]
        local shown = (b and b:IsShown()) and true or false
        if want ~= shown then relayout = true
        elseif b and shown and key == "inface" then FI.Aim(b) FI.Face(b) end
    end
    if relayout then FN.Layout() elseif FN.Paint then FN.Paint() end
    return true
end

--- The lib's BiS> in news, heard once.
function FI.Event(what, r)
    if not FI.on then return end
    local l = lib()
    local mine = me()
    if what == "claim" and type(r) == "table" and r.owner == mine and r.id == FI.myReq then
        FI.coming = r.claim and r.claim.by or "?"
        say("|cff4fd0cf%s|r is casting Fortitude on you", FI.coming)
        FI.myReq = nil
        if l then l:BisInCancel(r.id, "claimed") end
    elseif what == "ask" and type(r) == "table" and r.owner ~= mine and r.spell == FI.SPELL then
        local m = l and l:BisInMe()
        if m and m.give[FI.SPELL] then
            FI.Sound("request")
            say("|cffffd100%s|r asks for Fortitude - their face is lit in BiS> now", tostring(r.owner))
        end
    end
    FI.Soon()
end

function FI.Hook(l)
    if FI.hooked or not (l and l.RegisterCallback) then return end
    FI.hooked = true
    l:RegisterCallback("BISIN", function(what, r) FI.Event(what, r) end)
end

do
    local w = CreateFrame("Frame")
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED" }) do pcall(w.RegisterEvent, w, e) end
    w:SetScript("OnEvent", function() if FI.on then FI.Soon() end end)
    FI.watcher = w
    -- a face not drawn yet is tried again every FI.RETRY seconds (someone walking into sight fires no event); one look
    -- at one button, and only while the test is on and that face is still the icon
    FI.RETRY = 2
    if C_Timer and C_Timer.NewTicker then
        FI.ticker = C_Timer.NewTicker(FI.RETRY, function() FI.Retry() end)
    end
end

function FI.Retry()
    if not FI.on then return false end
    local FN = NS.FN
    local b = FN and FN.buttons and FN.buttons.inface
    if not (b and b:IsShown() and b.inUnit and not b.modelSeen) then return false end
    return FI.Face(b)
end
