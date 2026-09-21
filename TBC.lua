-- BiSHealing / TBC.lua - the WHOLE of this addon on a TBC client, and that is deliberate.
--
-- BiSHealing_TBC.toc loads this file and nothing else, so on TBC the Forever edition does nothing
-- at all: no grid, no mouse, no saved variables. On 20 Sep 2026 it loaded here in full, met the
-- older BiS Healing's saved table and emptied it - four thousand fights of history, one logout.
--
-- It says so once at login rather than staying silent, because an addon ticked in the list that
-- appears to do nothing reads as broken. It touches no global but its own frame, and no saved
-- variable at all.
local notice = CreateFrame("Frame")
notice:RegisterEvent("PLAYER_LOGIN")
notice:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    local say = (DEFAULT_CHAT_FRAME and function(t) DEFAULT_CHAT_FRAME:AddMessage(t) end) or print
    say("|cff9482c9BiS Healing|r is the WoW Forever edition and is |cfff08cb0inactive in this"
        .. " client|r. Nothing of it has loaded, and your saved data is untouched.")
end)
