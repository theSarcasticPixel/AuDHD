-- A button for the quest item the current step needs you to use: drink the Earth Sapta by the Spirit Stone, a Taming
-- Rod on the beast. The step's items come from its open goals (Guide.lua: step.uses): a "use" goal's item, or one its
-- note names that has a Use: effect. A secure item button: your click uses it (addons can't use items on their own),
-- and its item can only change out of combat. It sits by the route window's top left corner.
local _, ns = ...
local M = {}
ns.useItem = M

local button, wanted, pending

local function make()
  button = ns.newFrame("UseItem", "Button", "AuDHDUseItem", UIParent, "SecureActionButtonTemplate,BackdropTemplate")
  button:SetSize(40, 40)
  button:RegisterForClicks("AnyUp", "AnyDown")
  button:SetAttribute("type", "item")
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

-- beside the route window (it may be made after this button), else below the middle of the screen
local function place()
  local anchor = _G.AuDHDFrame
  button:ClearAllPoints()
  if anchor then button:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, 0) else button:SetPoint("CENTER", UIParent, "CENTER", 0, -120) end
end

-- show the button for this item (nil: hide it); out of combat only
local function apply()
  if InCombatLockdown() then pending = true return end
  pending = false
  if not button then make() end
  local id = wanted
  if id and not AuDHDDB.useItemOff then
    button.item = id
    button:SetAttribute("item", "item:" .. id)
    local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id))
    button.icon:SetTexture(icon or 134400)
    button.label:SetText("Use")
    place()
    button:Show()
  else
    button.item = nil
    button:Hide()
  end
end

-- its Use: effect, if it has one (newer clients have only C_Item's:)
local function useSpell(id)
  local f = (C_Item and C_Item.GetItemSpell) or GetItemSpell
  return f and f(id)
end

-- the item to show: the step's first one that's in your bags, a "use" goal's or one with a Use: effect
local function itemFor(step)
  for _, u in ipairs(step and step.uses or {}) do
    if count(u.id) > 0 and (u.sure or useSpell(u.id)) then return u.id end
  end
  return nil
end
M.itemFor = itemFor   -- (the smoke test)

-- called on every step change and bag change
function M.refresh()
  local step = ns.core and ns.core.current and ns.core.current()
  local id = itemFor(step)
  if id ~= wanted or pending or (button and button:IsShown() ~= (id ~= nil and not AuDHDDB.useItemOff)) then
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
