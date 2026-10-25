---@diagnostic disable: inject-field, undefined-field, undefined-global
local addonName = ...

---@class HiddenLodgeIntegration
---@field addon string
---@field init fun(self: HiddenLodgeAddon): (boolean|string)?
---@field initialized boolean

---@class HiddenLodgeAddon
---@field db table
---@field mainWindow table|nil
---@field Constants table
---@field integrations table<string, HiddenLodgeIntegration>

local aceAddon = LibStub and LibStub("AceAddon-3.0", true)

if not aceAddon then
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ADDON_LOADED")
    frame:SetScript("OnEvent", function(_, event, loadedAddonName)
        if event ~= "ADDON_LOADED" or loadedAddonName ~= addonName then
            return
        end

        DEFAULT_CHAT_FRAME:AddMessage("|cffff3333HiddenLodge|r requires Ace3. Install the Ace3 addon first.")
    end)
    return
end

local HiddenLodge = aceAddon:NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0") --[[@as HiddenLodgeAddon]]

local function ensureDefaults(db)
    db.ui = db.ui or {}
    db.ui.windowPoint = db.ui.windowPoint or nil

    db.preparedness = db.preparedness or {}
    db.preparedness.byFull = db.preparedness.byFull or {}
    db.preparedness.byName = db.preparedness.byName or {}
    db.preparedness.sync = db.preparedness.sync or {}
    db.preparedness.sync.source = db.preparedness.sync.source or ""
    db.preparedness.sync.syncedAt = db.preparedness.sync.syncedAt or 0
    db.preparedness.sync.entries = db.preparedness.sync.entries or 0

    db.greatVaultScore = db.greatVaultScore or {}
    db.greatVaultScore.byFull = db.greatVaultScore.byFull or {}
    db.greatVaultScore.byName = db.greatVaultScore.byName or {}
    db.greatVaultScore.sync = db.greatVaultScore.sync or {}
    db.greatVaultScore.sync.source = db.greatVaultScore.sync.source or ""
    db.greatVaultScore.sync.syncedAt = db.greatVaultScore.sync.syncedAt or 0
    db.greatVaultScore.sync.entries = db.greatVaultScore.sync.entries or 0

    db.attendanceScore = db.attendanceScore or {}
    db.attendanceScore.byFull = db.attendanceScore.byFull or {}
    db.attendanceScore.byName = db.attendanceScore.byName or {}
    db.attendanceScore.sync = db.attendanceScore.sync or {}
    db.attendanceScore.sync.source = db.attendanceScore.sync.source or ""
    db.attendanceScore.sync.syncedAt = db.attendanceScore.sync.syncedAt or 0
    db.attendanceScore.sync.entries = db.attendanceScore.sync.entries or 0

    db.raidSignup = db.raidSignup or {}
    db.raidSignup.byFullStatus = db.raidSignup.byFullStatus or {}
    db.raidSignup.byNameStatus = db.raidSignup.byNameStatus or {}
    db.raidSignup.byFullSignedAt = db.raidSignup.byFullSignedAt or {}
    db.raidSignup.byNameSignedAt = db.raidSignup.byNameSignedAt or {}
    db.raidSignup.sync = db.raidSignup.sync or {}
    db.raidSignup.sync.source = db.raidSignup.sync.source or ""
    db.raidSignup.sync.syncedAt = db.raidSignup.sync.syncedAt or 0
    db.raidSignup.sync.entries = db.raidSignup.sync.entries or 0
    db.raidSignup.sync.raidName = db.raidSignup.sync.raidName or ""
    db.raidSignup.sync.raidStartUtc = db.raidSignup.sync.raidStartUtc or 0

    db.droptimizer = db.droptimizer or {}
    db.droptimizer.byItemByFullDelta = db.droptimizer.byItemByFullDelta or {}
    db.droptimizer.byItemByNameDelta = db.droptimizer.byItemByNameDelta or {}
    db.droptimizer.byItemByFullPct = db.droptimizer.byItemByFullPct or {}
    db.droptimizer.byItemByNamePct = db.droptimizer.byItemByNamePct or {}
    db.droptimizer.sync = db.droptimizer.sync or {}
    db.droptimizer.sync.source = db.droptimizer.sync.source or ""
    db.droptimizer.sync.syncedAt = db.droptimizer.sync.syncedAt or 0
    db.droptimizer.sync.entries = db.droptimizer.sync.entries or 0
    db.droptimizer.sync.items = db.droptimizer.sync.items or 0

    db.altNoteSync = db.altNoteSync or {}
    db.altNoteSync.preferredByName = db.altNoteSync.preferredByName or {}
    db.altNoteSync.mainByName = db.altNoteSync.mainByName or {}
    db.altNoteSync.nicknameByName = db.altNoteSync.nicknameByName or {}
    db.altNoteSync.sync = db.altNoteSync.sync or {}
    db.altNoteSync.sync.source = db.altNoteSync.sync.source or ""
    db.altNoteSync.sync.syncedAt = db.altNoteSync.sync.syncedAt or 0
    db.altNoteSync.sync.entries = db.altNoteSync.sync.entries or 0
    db.altNoteSync.lastAppliedSyncedAt = db.altNoteSync.lastAppliedSyncedAt or 0

    db.cauldron = db.cauldron or {}
    db.cauldron.days = db.cauldron.days or {}
    db.cauldron.debugLog = db.cauldron.debugLog or {}

    db.flaskReminder = db.flaskReminder or {}
    if db.flaskReminder.enabled == nil then
        db.flaskReminder.enabled = true
    end
end

function HiddenLodge:RegisterIntegration(name, integration)
    if type(name) ~= "string" or name == "" then
        return false, "Integration name must be a non-empty string."
    end
    if type(integration) ~= "table" then
        return false, "Integration must be a table."
    end
    if type(integration.init) ~= "function" then
        return false, "Integration.init must be a function."
    end

    self.integrations = self.integrations or {}
    self.integrations[name] = integration
    return true
end

function HiddenLodge:InitializeIntegration(name)
    local integrations = self.integrations or {}
    local integration = integrations[name]
    if not integration then
        return false, "Integration not registered: " .. tostring(name)
    end
    if integration.initialized then
        return true
    end

    local ace = LibStub and LibStub("AceAddon-3.0", true)
    if not ace then
        return false, "AceAddon-3.0 is not available."
    end
    if not ace:GetAddon(integration.addon, true) then
        return false, integration.addon .. " is not loaded."
    end

    local ok, err = pcall(integration.init, self)
    if not ok then
        return false, err
    end

    integration.initialized = true
    return true
end

function HiddenLodge:InitializeLoadedIntegrations()
    local integrations = self.integrations or {}
    for name in pairs(integrations) do
        self:InitializeIntegration(name)
    end
end

function HiddenLodge:OnInitialize()
    HiddenLodgeDB = HiddenLodgeDB or {}
    self.db = HiddenLodgeDB
    self.integrations = self.integrations or {}
    ensureDefaults(self.db)

    self:RegisterChatCommand("hl", "HandleSlashCommand")
    self:Print("loaded. Use /hl")
end

function HiddenLodge:OnEnable()
    self:RegisterEvent("ADDON_LOADED", "HandleAddonLoaded")
    self:InitializeLoadedIntegrations()
    if self.OnEnableAltNoteSync then
        self:OnEnableAltNoteSync()
    end
    if self.OnEnableCauldronTracker then
        self:OnEnableCauldronTracker()
    end
    if self.OnEnableFlaskReminder then
        self:OnEnableFlaskReminder()
    end
end

function HiddenLodge:HandleAddonLoaded(_, loadedAddonName)
    local integrations = self.integrations or {}
    for name, integration in pairs(integrations) do
        if integration.addon == loadedAddonName then
            self:InitializeIntegration(name)
        end
    end
end

function HiddenLodge:HandleSlashCommand(input)
    local command = input and strlower(strtrim(input)) or ""

    if command == "" or command == "show" then
        self:ToggleMainWindow()
        return
    end

    if command == "hide" then
        self:HideMainWindow()
        return
    end

    if command == "cauldron" then
        if self.ToggleCauldronFrame then
            self:ToggleCauldronFrame()
        end
        return
    end

    if command == "raidcomp" then
        if self.ShowRaidCompFrame then
            self:ShowRaidCompFrame()
        end
        return
    end

    if command == "flask" then
        if self.ToggleFlaskReminderEnabled then
            self:ToggleFlaskReminderEnabled()
        end
        return
    end

    self:Print("Usage: /hl [show|hide|cauldron|raidcomp|flask]")
end
