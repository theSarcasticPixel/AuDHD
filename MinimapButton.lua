-- A button on the minimap's ring (the user, 2026-10-16: "add a button to the ring of the minimap to show/hide the WFN
-- UI as well as open a settings page"): left-click shows or hides the route window and the arrow, right-click opens
-- the settings (Settings.lua), Shift-click the route picker. Drag it round the ring; where it sits is saved.
local _, ns = ...
local M = {}
ns.minimap = M

local button
local function db()
  AuDHDDB.minimap = AuDHDDB.minimap or { angle = 200 }
  return AuDHDDB.minimap
end

-- on the ring: the minimap's radius plus a little, at the saved angle (degrees, 0 = east, counter-clockwise)
local function place()
  local a = math.rad(db().angle or 200)
  local r = (Minimap:GetWidth() or 140) / 2 + 10
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

-- while dragging: the angle from the minimap's centre to the cursor
local function follow()
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local s = Minimap:GetEffectiveScale()
  if not (mx and cx and s) then return end
  db().angle = math.deg(math.atan2(cy / s - my, cx / s - mx)) % 360
  place()
end

-- the WFN windows: the route window and the arrow, together
function M.toggleUI()
  local f = _G.AuDHDFrame
  local hide = f and f:IsShown()
  if ns.ui then ns.ui.toggle() end
  if ns.arrow then ns.arrow.command(hide and "hide" or "show") end
end

function M.create()
  if button then return end
  button = ns.newFrame("MinimapButton", "Button", "AuDHDMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local bg = button:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(20, 20)
  bg:SetPoint("TOPLEFT", 7, -5)
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
  icon:SetSize(17, 17)
  icon:SetPoint("TOPLEFT", 7, -6)
  icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
  button.icon = icon
  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")

  button:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then
      if ns.settings then ns.settings.toggle() end
    elseif IsShiftKeyDown() then
      if ns.picker then ns.picker.toggle() end
    else
      M.toggleUI()
    end
  end)
  button:SetScript("OnDragStart", function(self)
    self:LockHighlight()
    self:SetScript("OnUpdate", follow)
  end)
  button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    self:UnlockHighlight()
  end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("AuDHD")
    GameTooltip:AddLine("Left-click: show / hide the route window and arrow", 1, 1, 1)
    GameTooltip:AddLine("Right-click: settings", 1, 1, 1)
    GameTooltip:AddLine("Shift-click: pick a route", 1, 1, 1)
    GameTooltip:AddLine("Drag: move round the minimap", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  place()
  M.apply()
end

-- shown unless turned off in the settings
function M.apply()
  if not button then return end
  if db().hide then button:Hide() else button:Show() end
end
