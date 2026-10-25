---@diagnostic disable: inject-field, undefined-field, undefined-global
local addonName = ...
---@type HiddenLodgeAddon
local HiddenLodge = LibStub("AceAddon-3.0"):GetAddon(addonName) --[[@as HiddenLodgeAddon]]

-- Reminds you to drink a Fleeting flask/phial (from a raid cauldron) before
-- logging out. Shown next to the Game Menu, since that's where Log Out / Exit
-- Game live and a rested-area logout is instant, and again during the 20s
-- logout/quit countdown. Logout() itself is deliberately not replaced: a
-- pre-hook would taint the Game Menu's secure code path. Using an item needs
-- a hardware click on a secure button, so the frame is never shown or
-- reconfigured in combat.

local FRAME_WIDTH = 300
local LINE_HEIGHT = 18
local FLASK_SUBCLASS = (Enum and Enum.ItemConsumableSubclass and Enum.ItemConsumableSubclass.Flasksphials) or 3
local CONSUMABLE_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Consumable) or 0

local reminderFrame
local logoutPending = false

local function IsFleetingFlask(itemID, itemLink)
    if not itemID then return false end
    local name = C_Item.GetItemNameByID(itemID)
    if not name and itemLink then
        name = itemLink:match("%[(.-)%]")
    end
    if not name then return false end
    name = name:lower()
    if not name:find("^fleeting") then return false end

    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    if classID == CONSUMABLE_CLASS and subClassID == FLASK_SUBCLASS then
        return true
    end
    return name:find("flask") ~= nil or name:find("phial") ~= nil
end

-- Returns one entry per distinct fleeting flask in your bags, in bag order:
-- { itemID, name, icon, count, bag, slot } where bag/slot is the first stack.
local function FindFleetingFlasks()
    local found, byID = {}, {}
    local lastBag = NUM_BAG_SLOTS or 4
    for bag = 0, lastBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and IsFleetingFlask(info.itemID, info.hyperlink) then
                local entry = byID[info.itemID]
                if entry then
                    entry.count = entry.count + (info.stackCount or 1)
                else
                    entry = {
                        itemID = info.itemID,
                        name = C_Item.GetItemNameByID(info.itemID)
                            or (info.hyperlink and info.hyperlink:match("%[(.-)%]")) or "Fleeting Flask",
                        icon = info.iconFileID,
                        count = info.stackCount or 1,
                        bag = bag,
                        slot = slot,
                    }
                    byID[info.itemID] = entry
                    table.insert(found, entry)
                end
            end
        end
    end
    return found
end

local function anchorReminderFrame(frame)
    frame:ClearAllPoints()
    if GameMenuFrame and GameMenuFrame:IsShown() then
        frame:SetPoint("TOP", GameMenuFrame, "BOTTOM", 0, -8)
        return
    end
    local popup = logoutPending and StaticPopup_Visible
        and (StaticPopup_Visible("CAMP") or StaticPopup_Visible("QUIT"))
    if type(popup) == "table" and popup.GetObjectType then
        frame:SetPoint("TOP", popup, "BOTTOM", 0, -8)
        return
    end
    frame:SetPoint("TOP", UIParent, "TOP", 0, -260)
end

local function ensureReminderFrame()
    if reminderFrame then
        return reminderFrame
    end

    local c = HiddenLodge and HiddenLodge.GetUIConstants and HiddenLodge:GetUIConstants() or nil
    local innerInset = (c and c.INNER_PADDING) or 12
    local buttonHeight = (c and c.BUTTON_HEIGHT) or 24

    reminderFrame = CreateFrame("Frame", "HiddenLodgeFlaskReminderFrame", UIParent, "BackdropTemplate")
    reminderFrame:SetWidth(FRAME_WIDTH)
    reminderFrame:SetFrameStrata("DIALOG")
    reminderFrame:SetFrameLevel(100)
    reminderFrame:SetClampedToScreen(true)
    reminderFrame:EnableMouse(true)
    reminderFrame:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8x8",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    if c then
        reminderFrame:SetBackdropColor(unpack(c.COLOR_BG))
        reminderFrame:SetBackdropBorderColor(unpack(c.COLOR_BORDER))
    else
        reminderFrame:SetBackdropColor(0.02, 0.05, 0.09, 0.97)
        reminderFrame:SetBackdropBorderColor(0.70, 0.57, 0.24, 0.95)
    end
    reminderFrame:Hide()

    reminderFrame.title = reminderFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    reminderFrame.title:SetPoint("TOPLEFT", reminderFrame, "TOPLEFT", innerInset, -innerInset)
    reminderFrame.title:SetPoint("TOPRIGHT", reminderFrame, "TOPRIGHT", -innerInset, -innerInset)
    reminderFrame.title:SetJustifyH("LEFT")
    reminderFrame.title:SetTextColor(0.95, 0.82, 0.44)
    reminderFrame.title:SetText("Fleeting flask in your bags")

    reminderFrame.items = reminderFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    reminderFrame.items:SetPoint("TOPLEFT", reminderFrame.title, "BOTTOMLEFT", 0, -6)
    reminderFrame.items:SetPoint("TOPRIGHT", reminderFrame.title, "BOTTOMRIGHT", 0, -6)
    reminderFrame.items:SetJustifyH("LEFT")
    reminderFrame.items:SetSpacing(4)

    reminderFrame.hint = reminderFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    reminderFrame.hint:SetPoint("TOPLEFT", reminderFrame.items, "BOTTOMLEFT", 0, -6)
    reminderFrame.hint:SetPoint("TOPRIGHT", reminderFrame.items, "BOTTOMRIGHT", 0, -6)
    reminderFrame.hint:SetJustifyH("LEFT")
    reminderFrame.hint:SetTextColor(0.78, 0.84, 0.93)
    reminderFrame.hint:SetText("Drink it before logging out so it isn't wasted.")

    -- Secure so the click itself uses the item; UseItem/UseContainerItem are
    -- protected and can't be called from addon code.
    local useBtn = CreateFrame("Button", "HiddenLodgeFlaskReminderUseButton", reminderFrame,
        "UIPanelButtonTemplate,SecureActionButtonTemplate")
    useBtn:SetSize(130, buttonHeight)
    useBtn:SetPoint("BOTTOMLEFT", reminderFrame, "BOTTOMLEFT", innerInset, innerInset)
    useBtn:SetText("Use Flask")
    HiddenLodge:ApplyPrimaryButtonStyle(useBtn)
    useBtn:RegisterForClicks("AnyUp", "AnyDown")
    useBtn:SetAttribute("type", "item")
    useBtn:HookScript("PostClick", function()
        -- Bag contents update a moment after the use goes through.
        C_Timer.After(0.5, function()
            HiddenLodge:RefreshFlaskReminder()
        end)
    end)
    reminderFrame.useBtn = useBtn

    local dismissBtn = CreateFrame("Button", nil, reminderFrame, "UIPanelButtonTemplate")
    dismissBtn:SetSize(90, buttonHeight)
    dismissBtn:SetPoint("BOTTOMRIGHT", reminderFrame, "BOTTOMRIGHT", -innerInset, innerInset)
    dismissBtn:SetText("Dismiss")
    HiddenLodge:ApplySecondaryButtonStyle(dismissBtn)
    dismissBtn:SetScript("OnClick", function()
        HiddenLodge:HideFlaskReminder()
    end)
    reminderFrame.dismissBtn = dismissBtn

    return reminderFrame
end

-- Rebuilds the frame's contents from current bags. Returns false (and hides
-- the frame) when there's nothing to remind about.
function HiddenLodge:RefreshFlaskReminder()
    if not reminderFrame or not reminderFrame:IsShown() then
        return false
    end
    if InCombatLockdown() then
        return false
    end

    local flasks = FindFleetingFlasks()
    if #flasks == 0 then
        reminderFrame:Hide()
        return false
    end

    local lines = {}
    for _, entry in ipairs(flasks) do
        local icon = entry.icon and string.format("|T%s:16:16|t ", tostring(entry.icon)) or ""
        local count = entry.count > 1 and string.format(" x%d", entry.count) or ""
        table.insert(lines, icon .. entry.name .. count)
    end
    reminderFrame.items:SetText(table.concat(lines, "\n"))

    local first = flasks[1]
    reminderFrame.useBtn:SetAttribute("item", first.bag .. " " .. first.slot)
    reminderFrame.useBtn:SetText(#flasks > 1 and "Use First Flask" or "Use Flask")

    local c = self.GetUIConstants and self:GetUIConstants() or nil
    local innerInset = (c and c.INNER_PADDING) or 12
    local buttonHeight = (c and c.BUTTON_HEIGHT) or 24
    local textHeight = reminderFrame.title:GetStringHeight() + 6
        + math.max(reminderFrame.items:GetStringHeight(), #flasks * LINE_HEIGHT) + 6
        + reminderFrame.hint:GetStringHeight()
    reminderFrame:SetHeight(innerInset + textHeight + 10 + buttonHeight + innerInset)
    return true
end

function HiddenLodge:ShowFlaskReminder()
    if not (self.db and self.db.flaskReminder and self.db.flaskReminder.enabled) then
        return
    end
    -- The frame owns a secure button, so it can't be shown or have its
    -- attributes changed in combat. You can't log out in combat anyway.
    if InCombatLockdown() then
        return
    end
    if #FindFleetingFlasks() == 0 then
        return
    end

    local frame = ensureReminderFrame()
    anchorReminderFrame(frame)
    frame:Show()
    self:RefreshFlaskReminder()
end

function HiddenLodge:HideFlaskReminder()
    if reminderFrame and reminderFrame:IsShown() and not InCombatLockdown() then
        reminderFrame:Hide()
    end
end

function HiddenLodge:ToggleFlaskReminderEnabled()
    self.db.flaskReminder.enabled = not self.db.flaskReminder.enabled
    if not self.db.flaskReminder.enabled then
        self:HideFlaskReminder()
    end
    self:Print("Fleeting flask logout reminder " .. (self.db.flaskReminder.enabled and "enabled." or "disabled."))
end

-- ===== Event handling =====

function HiddenLodge:HandleFlaskReminderLogoutStart()
    logoutPending = true
    self:ShowFlaskReminder()
end

function HiddenLodge:HandleFlaskReminderLogoutCancel()
    logoutPending = false
    if not (GameMenuFrame and GameMenuFrame:IsShown()) then
        self:HideFlaskReminder()
    end
end

function HiddenLodge:HandleFlaskReminderBagUpdate()
    self:RefreshFlaskReminder()
end

function HiddenLodge:HandleFlaskReminderCombatStart()
    -- PLAYER_REGEN_DISABLED fires just before lockdown, the last chance to
    -- hide a frame with a secure child.
    if reminderFrame and reminderFrame:IsShown() then
        reminderFrame:Hide()
    end
end

function HiddenLodge:OnEnableFlaskReminder()
    if GameMenuFrame then
        GameMenuFrame:HookScript("OnShow", function()
            HiddenLodge:ShowFlaskReminder()
        end)
        -- Clicking Log Out hides the Game Menu; keep the reminder up through
        -- the countdown (PLAYER_CAMPING may fire before or after this).
        GameMenuFrame:HookScript("OnHide", function()
            if not logoutPending then
                HiddenLodge:HideFlaskReminder()
            elseif reminderFrame and reminderFrame:IsShown() and not InCombatLockdown() then
                anchorReminderFrame(reminderFrame)
            end
        end)
    end

    self:RegisterEvent("PLAYER_CAMPING", "HandleFlaskReminderLogoutStart")
    self:RegisterEvent("PLAYER_QUITING", "HandleFlaskReminderLogoutStart")
    self:RegisterEvent("LOGOUT_CANCEL", "HandleFlaskReminderLogoutCancel")
    self:RegisterEvent("BAG_UPDATE_DELAYED", "HandleFlaskReminderBagUpdate")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "HandleFlaskReminderCombatStart")
end
