-------------------------------------------------------------------------------
--  EllesmereUIQoL_DungeonIO.lua
--  Overlays the player's per-dungeon M+ score on each dungeon tile in the
--  Blizzard Mythic+ map selection screen (ChallengesFrame), matching the
--  style of the RaiderIO addon but using Blizzard's own native score data.
-------------------------------------------------------------------------------
local EUI = EllesmereUI

-- Color brackets duplicated from EllesmereUIBlizzardSkin_CharacterSheet.lua
-- so this file has no cross-module dependency on the BlizzardSkin addon.
local MP_COLOR_BRACKETS = {
    { 3850, "ff8000" }, { 3695, "f9753f" }, { 3575, "f16961" },
    { 3455, "e75e7f" }, { 3335, "db529c" }, { 3215, "cc47b9" },
    { 3095, "b83dd6" }, { 2965, "9c3eed" }, { 2845, "715be5" },
    { 2725, "2c6dde" }, { 2565, "3b7fcd" }, { 2445, "5292b9" },
    { 2325, "5ca6a4" }, { 2205, "5fba8d" }, { 2085, "5cce75" },
    { 1965, "50e258" }, { 1845, "35f72d" }, { 1725, "3eff26" },
    { 1600, "5eff43" }, { 1475, "74ff58" }, { 1350, "88ff6b" },
    { 1225, "98ff7d" }, { 1100, "a8ff8d" }, { 975,  "b6ff9e" },
    { 850,  "c3ffae" }, { 725,  "cfffbd" }, { 600,  "dbffcd" },
    { 475,  "e7ffdd" }, { 350,  "f2ffec" }, { 225,  "fdfffc" },
    { 200,  "ffffff" },
}

local function GetMPScoreHex(score)
    for i = 1, #MP_COLOR_BRACKETS do
        if score >= MP_COLOR_BRACKETS[i][1] then
            return MP_COLOR_BRACKETS[i][2]
        end
    end
    return "ffffff"
end

local function ResolveFont()
    return (EUI and EUI.GetFontPath and EUI.GetFontPath("extras")) or "Fonts\\FRIZQT__.TTF"
end

local function ResolveOutline()
    return (EUI and EUI.GetFontOutlineFlag and EUI.GetFontOutlineFlag("extras")) or "OUTLINE"
end

local function IsEnabled()
    if not EllesmereUIDB then return true end
    return EllesmereUIDB.dungeonIOOverlay ~= false
end

-------------------------------------------------------------------------------
--  Score data cache  [mapChallengeModeID] = highest per-slot score
-------------------------------------------------------------------------------
local dungeonScores = {}

local function BuildScoreMap()
    wipe(dungeonScores)
    if not (C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary) then return end
    local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
    if not summary or not summary.runs then return end
    for _, run in ipairs(summary.runs) do
        local id = run.mapChallengeModeID
        if id then
            -- Each mapID may appear twice (one Fortified slot, one Tyrannical slot).
            -- mythicPlusRating is that slot's score contribution; keep the higher one.
            local s = math.floor(run.mythicPlusRating or 0)
            local ex = dungeonScores[id]
            if not ex or s > ex then
                dungeonScores[id] = s
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Overlay label pool  [mapChallengeModeID] = FontString
-------------------------------------------------------------------------------
local overlayLabels = {}

local function AcquireLabel(button, mapID)
    if overlayLabels[mapID] then return overlayLabels[mapID] end
    local fs = button:CreateFontString(nil, "OVERLAY")
    fs:SetFont(ResolveFont(), 12, ResolveOutline())
    fs:SetPoint("BOTTOM", button, "BOTTOM", 0, 10)
    overlayLabels[mapID] = fs
    return fs
end

-------------------------------------------------------------------------------
--  Frame discovery helpers
-------------------------------------------------------------------------------

-- Build a set of valid season mapIDs for child-iteration fallback.
local function BuildValidMapSet()
    local set = {}
    if C_ChallengeMode and C_ChallengeMode.GetMapTable then
        for _, id in ipairs(C_ChallengeMode.GetMapTable()) do
            set[id] = true
        end
    end
    return set
end

-- Returns a list of { btn, mapID } pairs found in ChallengesFrame.
-- Strategy A: well-known global name pattern (ChallengesFrameMapButton1 ...).
-- Strategy B: iterate ChallengesFrame children for frames carrying a mapID field.
local function DiscoverMapButtons()
    local buttons = {}

    -- Strategy A
    local i = 1
    while _G["ChallengesFrameMapButton" .. i] do
        local btn = _G["ChallengesFrameMapButton" .. i]
        local mapID = btn.mapID or btn.challengeMapID or btn:GetID()
        if mapID and mapID ~= 0 then
            buttons[#buttons + 1] = { btn = btn, mapID = mapID }
        end
        i = i + 1
    end

    if #buttons > 0 then return buttons end

    -- Strategy B: walk children looking for frames that carry a mapID field or
    -- whose GetID() matches a current season dungeon.
    local validMaps = BuildValidMapSet()
    local function ScanFrame(f)
        for _, child in next, { f:GetChildren() } do
            local mapID = child.mapID or child.challengeMapID
            if not mapID then
                local id = child.GetID and child:GetID() or 0
                if id ~= 0 and validMaps[id] then mapID = id end
            end
            if mapID and validMaps[mapID] then
                buttons[#buttons + 1] = { btn = child, mapID = mapID }
            else
                ScanFrame(child)
            end
        end
    end
    ScanFrame(ChallengesFrame)

    return buttons
end

-------------------------------------------------------------------------------
--  Main refresh
-------------------------------------------------------------------------------
local function RefreshOverlays()
    if not ChallengesFrame or not ChallengesFrame:IsShown() then return end

    if not IsEnabled() then
        for _, fs in pairs(overlayLabels) do fs:Hide() end
        return
    end

    BuildScoreMap()

    local buttons = DiscoverMapButtons()
    local activeIDs = {}

    for _, entry in ipairs(buttons) do
        local ok, err = pcall(function()
            local fs = AcquireLabel(entry.btn, entry.mapID)
            local score = dungeonScores[entry.mapID]
            if score and score > 0 then
                local hex = GetMPScoreHex(score)
                fs:SetText(string.format("|cff%s%d|r", hex, score))
            else
                fs:SetText("|cff808080—|r")
            end
            fs:Show()
            activeIDs[entry.mapID] = true
        end)
        if not ok then
            -- Button reference became stale; clear cached label so it's recreated.
            overlayLabels[entry.mapID] = nil
        end
    end

    -- Hide labels for dungeon tiles no longer in the discovered list.
    for id, fs in pairs(overlayLabels) do
        if not activeIDs[id] then fs:Hide() end
    end
end

-- Expose for live-apply from options toggle.
EllesmereUI._applyDungeonIOOverlay = RefreshOverlays

-------------------------------------------------------------------------------
--  Hook installation
-------------------------------------------------------------------------------
local function HookChallengesFrame()
    if not ChallengesFrame then return end
    ChallengesFrame:HookScript("OnShow", RefreshOverlays)
    -- Hook Blizzard's own map-button update method when present (most
    -- forward-compatible approach — fires after Blizzard repositions tiles).
    if ChallengesFrame.UpdateMapButtons then
        hooksecurefunc(ChallengesFrame, "UpdateMapButtons", RefreshOverlays)
    end
end

-------------------------------------------------------------------------------
--  Event registration  (mirrors the pattern in EllesmereUIQoL.lua lines 615-633)
-------------------------------------------------------------------------------
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    f:SetScript("OnEvent", function(self, event, arg1)
        if event == "ADDON_LOADED" and arg1 == "Blizzard_ChallengesUI" then
            self:UnregisterEvent("ADDON_LOADED")
            HookChallengesFrame()
            RefreshOverlays()
        elseif event == "CHALLENGE_MODE_COMPLETED" or event == "PLAYER_SPECIALIZATION_CHANGED" then
            if ChallengesFrame and ChallengesFrame:IsShown() then
                RefreshOverlays()
            end
        end
    end)

    -- Handle the case where Blizzard_ChallengesUI was already loaded (e.g. /reload).
    if IsAddOnLoaded and IsAddOnLoaded("Blizzard_ChallengesUI") then
        f:UnregisterEvent("ADDON_LOADED")
        HookChallengesFrame()
    end
end
