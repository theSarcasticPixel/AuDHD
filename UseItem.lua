-- A button for the quest item the current step needs you to use (the route's ui: item id, un: its name): drink the
-- Earth Sapta by the Spirit Stone, a Taming Rod on the beast (the user, 2026-10-17: "it needs to be mentioned with a
-- button to use the item"). A secure item button: your click uses it (addons can't use items on their own), and its
-- item can only change out of combat.
local _, ns = ...
local M = {}
ns.useItem = M

local button, wanted, pending

local function make()
  button = ns.newFrame("UseItem", "Button", "AuDHDUseItem", UIParent, "SecureActionButtonTemplate,BackdropTemplate")
  button:SetSize(40, 40)
  button:RegisterForClicks("AnyUp", "AnyDown")
  button:SetAttribute("type", "item")
  local anchor = _G.AuDHDFrame
  if anchor then button:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, 0) else button:SetPoint("CENTER", UIParent, "CENTER", 0, -120) end
  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetAllPoints()
  button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  button.label:SetPoint("TOP", button, "BOTTOM", 0, -2)
  button:SetScript("OnEnter", function(self)
    if not self.item then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetItemByID(self.item)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  button:Hide()
end

local function count(id)
  local n = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id) or (GetItemCount and GetItemCount(id)) or 0
  return n
end

-- show the button for this item (nil: hide it); out of combat only
local function apply()
  if InCombatLockdown() then pending = true return end
  pending = false
  if not button then make() end
  local id = wanted
  if id and count(id) > 0 and not AuDHDDB.useItemOff then
    button.item = id
    button:SetAttribute("item", "item:" .. id)
    local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id))
    button.icon:SetTexture(icon or 134400)
    button.label:SetText("Use")
    button:Show()
  else
    button.item = nil
    button:Hide()
  end
end

-- called on every step change and bag change
function M.refresh()
  local step = ns.core and ns.core.current and ns.core.current()
  local id = step and step.ui
  if id ~= wanted or pending or (button and (button:IsShown() ~= (id and count(id) > 0 and not AuDHDDB.useItemOff or false))) then
    wanted = id
    apply()
  end
end

local frame = ns.newFrame("UseItem", "Frame")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, e)
  if e == "PLAYER_REGEN_ENABLED" and not pending then return end
  M.refresh()
end)
