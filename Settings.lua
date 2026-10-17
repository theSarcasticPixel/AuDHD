-- The settings window (the minimap button's right-click, /wfn settings, and a button in the game's Options under
-- AddOns): the switches the /wfn commands have, as checkboxes. Each one reads and writes the same saved setting its
-- command does, so the two never disagree.
local _, ns = ...
local S = {}
ns.settings = S

local frame
local WIDTH, COL, ROW = 470, 230, 24

local function sub(key) return AuDHDDB[key] or {} end
local function autoOn(key)
  local v = AuDHDDB.auto and AuDHDDB.auto[key]
  if v == nil then return ns.auto and ns.auto.DEFAULTS[key] end
  return v
end

-- { section } or { label, get, set, tip }: column 1, then column 2
local LEFT = {
  { "Windows" },
  { "Route window", function() local f = _G.AuDHDFrame return f and f:IsShown() end,
    function(on) local f = _G.AuDHDFrame if f and f:IsShown() ~= on then ns.ui.toggle() end end },
  { "Arrow", function() return not sub("arrow").hidden end, function(on) ns.arrow.command(on and "show" or "hide") end },
  { "Lock the arrow", function() return sub("arrow").locked end, function(on) ns.arrow.command(on and "lock" or "unlock") end,
    "Locked: clicks go through it, and it can't be dragged" },
  { "Range guide", function() return not sub("range").hidden end,
    function(on) if ns.range then ns.range.command(on and "show" or "hide") end end },
  { "Lock the range guide", function() return sub("range").locked end,
    function(on) if ns.range then ns.range.command(on and "lock" or "unlock") end end },
  { "Minimap button", function() return not sub("minimap").hide end,
    function(on) AuDHDDB.minimap = AuDHDDB.minimap or { angle = 200 }; AuDHDDB.minimap.hide = not on or nil
      if ns.minimap then ns.minimap.apply() end end, "Off: /wfn minimap brings it back" },
  { "Maps" },
  { "Route on the world map and minimap", function() return not AuDHDDB.mapHidden end,
    function(on) AuDHDDB.mapHidden = not on or nil if ns.routemap then pcall(ns.routemap.refresh) end end },
  { "Threat on nameplates", function() return not AuDHDDB.threatHidden end,
    function(on) if ns.threat then ns.threat.command(on and "on" or "off") end end },  { "Party" },
  { "Buttons to ask the party for buffs", function() return not (AuDHDDB.buffAsk and AuDHDDB.buffAsk.off) end,
    function(on) if ns.buffAsk then ns.buffAsk.command(on and "on" or "off") end end,
    "In a group with a priest, mage, druid or paladin: a click asks them in party chat for a buff you don't have" },
}
local RIGHT = {
  { "Automation (hold Shift to pause it)" },
  { "Accept quests", function() return autoOn("accept") end, function(on) AuDHDDB.auto.accept = on end },
  { "Turn in quests", function() return autoOn("complete") end, function(on) AuDHDDB.auto.complete = on end },
  { "Pick quest rewards", function() return autoOn("reward") ~= "manual" end,
    function(on) AuDHDDB.auto.reward = on and "value" or "manual" end,
    "On: an upgrade for your spec if one of the choices is, else the one that sells for most. Off: you choose" },
  { "Sell grey items", function() return autoOn("junk") end, function(on) AuDHDDB.auto.junk = on end },
  { "Repair", function() return autoOn("repair") end, function(on) AuDHDDB.auto.repair = on end },
  { "Buy ammo", function() return autoOn("ammo") end, function(on) AuDHDDB.auto.ammo = on end },
  { "Rares" },
  { "Alerts for every rare", function() return (AuDHDDB.rares or "all") == "all" end,
    function() ns.rare.command("all") end, "A pop-up and the /tar button near any rare's spawn point" },
  { "Alerts only for the route's rares", function() return AuDHDDB.rares == "route" end,
    function(on) ns.rare.command(on and "route" or "all") end },
  { "No rare alerts", function() return AuDHDDB.rares == "off" end, function(on) ns.rare.command(on and "off" or "all") end },
  { "Mouse wheel targets rares", function() return AuDHDDB.rareWheel end,
    function(on) AuDHDDB.rareWheel = on or nil if ns.rare then ns.rare.applyWheel() end end,
    "While the rare button shows, scrolling the mouse wheel clicks it (cycles /tar through nearby rares)" },
}

local checks = {}
local function refresh()
  for _, c in ipairs(checks) do c:SetChecked(c.get() and true or false) end
  if frame and frame.arrowScale then
    -- the saved size (moving the slider here mustn't write it back)
    frame.syncing = true
    frame.arrowScale:SetValue((AuDHDDB.arrow and AuDHDDB.arrow.scale) or 1)
    if frame.rangeGap and ns.range then frame.rangeGap:SetValue(sub("range").gap or ns.range.PLATE_GAP) end
    frame.syncing = nil
  end
end

local function column(items, x)
  local y = -44
  for _, it in ipairs(items) do
    if not it[2] then
      local h = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      h:SetPoint("TOPLEFT", x, y - 6)
      h:SetText(it[1])
      y = y - 26
    else
      local c = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
      c:SetSize(22, 22)
      c:SetPoint("TOPLEFT", x - 2, y)
      local label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      label:SetPoint("LEFT", c, "RIGHT", 2, 0)
      label:SetWidth(COL - 34)
      label:SetJustifyH("LEFT")
      label:SetWordWrap(false)
      label:SetText(it[1])
      c.get, c.set = it[2], it[3]
      c:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT and (self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF) or 856)
        AuDHDDB.auto = AuDHDDB.auto or {}
        self.set(self:GetChecked() and true or false)
        refresh()   -- the rare choices are one of three: the others change too
      end)
      if it[4] then
        c:SetScript("OnEnter", function(self)
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          GameTooltip:SetText(it[1])
          GameTooltip:AddLine(it[4], 1, 1, 1, true)
          GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
      end
      checks[#checks + 1] = c
      y = y - ROW
    end
  end
  return y
end

local function create()
  frame = CreateFrame("Frame", "AuDHDSettings", UIParent, "BackdropTemplate")
  frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                      tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  frame:SetBackdropColor(0, 0, 0, 0.92)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  frame:SetFrameStrata("DIALOG")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetScript("OnShow", refresh)
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("AuDHD settings")
  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function() frame:Hide() end)
  local y1, y2 = column(LEFT, 14), column(RIGHT, 14 + COL)
  -- the arrow's size: the same as /wfn arrow scale (0.4 to 3); here 0.5 to 2.5
  local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("TOPLEFT", 14, y1 - 8)
  label:SetText("Arrow size")
  local value = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  value:SetPoint("LEFT", label, "RIGHT", 8, 0)
  local slider = CreateFrame("Slider", "AuDHDArrowScale", frame, "OptionsSliderTemplate")
  slider:SetPoint("TOPLEFT", 18, y1 - 30)
  slider:SetWidth(COL - 40)
  slider:SetMinMaxValues(0.5, 2.5)
  slider:SetValueStep(0.1)
  if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
  for suffix, text in pairs({ Low = "small", High = "big", Text = "" }) do
    local f = _G["AuDHDArrowScale" .. suffix]
    if f then f:SetText(text) end
  end
  slider:SetScript("OnValueChanged", function(_, v)
    v = math.floor(v * 10 + 0.5) / 10
    value:SetText(("%.1fx"):format(v))
    if frame.syncing then return end
    if ns.arrow then ns.arrow.command(("scale %.1f"):format(v)) end
  end)
  frame.arrowScale = slider
  y1 = y1 - 60
  -- the range guide's height over the target's nameplate (user, 2026-10-17: "raise/lower it with a slider")
  local gLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  gLabel:SetPoint("TOPLEFT", 14, y1 - 8)
  gLabel:SetText("Range guide height")
  local gValue = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gValue:SetPoint("LEFT", gLabel, "RIGHT", 8, 0)
  local gap = CreateFrame("Slider", "AuDHDRangeGap", frame, "OptionsSliderTemplate")
  gap:SetPoint("TOPLEFT", 18, y1 - 30)
  gap:SetWidth(COL - 40)
  gap:SetMinMaxValues(-60, 80)
  gap:SetValueStep(2)
  if gap.SetObeyStepOnDrag then gap:SetObeyStepOnDrag(true) end
  for suffix, text in pairs({ Low = "lower", High = "higher", Text = "" }) do
    local f = _G["AuDHDRangeGap" .. suffix]
    if f then f:SetText(text) end
  end
  gap:SetScript("OnValueChanged", function(_, v)
    v = math.floor(v / 2 + 0.5) * 2
    gValue:SetText(("%+d"):format(v))
    if frame.syncing then return end
    if ns.range then ns.range.setGap(v) end
  end)
  frame.rangeGap = gap
  y1 = y1 - 60
  local bottom = math.min(y1, y2) - 8
  local routes = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  routes:SetSize(110, 22)
  routes:SetPoint("TOPLEFT", 12, bottom)
  routes:SetText("Pick a route")
  routes:SetScript("OnClick", function() if ns.picker then ns.picker.show() end end)
  frame:SetSize(WIDTH, -bottom + 34)
  -- Escape closes it
  if UISpecialFrames then table.insert(UISpecialFrames, "AuDHDSettings") end
  frame:Hide()
end

function S.show()
  if not frame then create() end
  frame:Show()
  refresh()
end
function S.toggle()
  if frame and frame:IsShown() then frame:Hide() else S.show() end
end

-- the game's Options > AddOns: a page with a button that opens this window (where the Settings API is there)
function S.register()
  if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
  local panel = CreateFrame("Frame")
  local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("TOPLEFT", 16, -16)
  text:SetText("AuDHD's settings have their own window (also: right-click the minimap button, or /wfn settings).")
  local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  b:SetSize(160, 24)
  b:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -12)
  b:SetText("Open the settings")
  b:SetScript("OnClick", function()
    if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
    S.show()
  end)
  local category = Settings.RegisterCanvasLayoutCategory(panel, "AuDHD")
  Settings.RegisterAddOnCategory(category)
end
