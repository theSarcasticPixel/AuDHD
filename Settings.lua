-- The settings window (the minimap button's right-click, /wfn settings, and a button in the game's Options under
-- AddOns): the switches the /wfn commands have, as checkboxes. Each one reads and writes the same saved setting its
-- command does, so the two never disagree. One tab per part of the addon (the user, 2026-10-22: "using tabs rather than
-- a giant box with a bunch of checkboxes"); the tabs down the left, the open one's switches on the right.
local _, ns = ...
local S = {}
ns.settings = S

local frame
local COL, ROW = 330, 24                -- the page's width, a checkbox row
-- the tab list is as wide as its longest name needs (the user, 2026-10-22); set in create()
local SIDE, PAGE_X                      -- the tab list's width, where a page's switches start

local function sub(key) return AuDHDDB[key] or {} end
local function autoOn(key)
  local v = AuDHDDB.auto and AuDHDDB.auto[key]
  if v == nil then return ns.auto and ns.auto.DEFAULTS[key] end
  return v
end

-- each tab: its name and its rows, { section }, { label, get, set, tip } or { note = text }; extra(page, y) adds
-- sliders or number boxes under them
local TABS = {
  { "Windows", {
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
    { "Detailed map (the minimap's pictures)", function() return ns.bigmap and ns.bigmap.isOn() end,
      function(on) if ns.bigmap then ns.bigmap.set(on) end end,
      "A big map of the open world drawn from the game's own minimap pictures, with you and your route on it. Open it with /wfn bigmap or a key in Key Bindings (AuDHD: Detailed map). Drag to move around, scroll to zoom" },
    { "  ...instead of the world map", function() return ns.bigmap and ns.bigmap.replaces() end,
      function(on) if ns.bigmap then ns.bigmap.setReplace(on) end end,
      "Your world map key (M) opens the detailed map; its Game map button opens the game's own" },
    { "  ...the game's painted map when zoomed out", function() return ns.bigmap and ns.bigmap.artOn() end,
      function(on) if ns.bigmap then ns.bigmap.setArt(on) end end,
      "Zoomed out, the detailed map shows the game's painted continent map, fading into the minimap's pictures as you zoom in; zoomed in, the cities the minimap's pictures don't show (Ironforge, Undercity, Stormwind, Orgrimmar) come from the game's city maps" },
    { "Route on the world map and minimap", function() return not AuDHDDB.mapHidden end,
      function(on) AuDHDDB.mapHidden = not on or nil if ns.routemap then pcall(ns.routemap.refresh) end end },
    { "Threat on nameplates", function() return not AuDHDDB.threatHidden end,
      function(on) if ns.threat then ns.threat.command(on and "on" or "off") end end },
  }, extra = "sliders" },
  { "Automation", {
    { note = "Hold Shift to pause it (at a quest giver, a vendor)." },
    { "Accept quests", function() return autoOn("accept") end, function(on) AuDHDDB.auto.accept = on end },
    { "Turn in quests", function() return autoOn("complete") end, function(on) AuDHDDB.auto.complete = on end },
    { "Pick quest rewards", function() return autoOn("reward") ~= "manual" end,
      function(on) AuDHDDB.auto.reward = on and "value" or "manual" end,
      "On: an upgrade for your spec if one of the choices is, else the one that sells for most. Off: you choose" },
    { "Sell grey items", function() return autoOn("junk") end, function(on) AuDHDDB.auto.junk = on end },
    { "Repair", function() return autoOn("repair") end, function(on) AuDHDDB.auto.repair = on end },
    { "Buy ammo", function() return autoOn("ammo") end, function(on) AuDHDDB.auto.ammo = on end },
  } },
  -- every part of the addon can be switched off (the user, 2026-10-17: "we need settings to turn off/on pretty much
  -- every part of the addon")
  { "Reminders", {
    { "Weapon imbue and oil buttons", function() return not (AuDHDDB.buffOff and AuDHDDB.buffOff.weapon) end,
      function(on) if ns.imbue then ns.imbue.command(on and "on" or "off", "weapon") end end,
      "A button when your weapon has no imbue, oil or stone on it" },
    { "Self-buff buttons", function() return not (AuDHDDB.buffOff and ns.imbue and ns.imbue.anyBuffOff()) end,
      function(on) if ns.imbue then ns.imbue.command(on and "on" or "off", "buffs") end end,
      "A button when a buff of your own (Lightning Shield, Demon Skin, an aspect) has dropped off" },
    { "Sell and train reminders", function() return not AuDHDDB.servicesOff end,
      function(on) AuDHDDB.servicesOff = not on or nil if ns.services then ns.services.check() end end,
      "Near a vendor with full bags, or your trainer with new skills to learn" },
    { "Quest item button", function() return not AuDHDDB.useItemOff end,
      function(on) AuDHDDB.useItemOff = not on or nil if ns.useItem then ns.useItem.refresh() end end,
      "A button for the item the current step needs you to use" },
    { "Quest complete message", function() return not AuDHDDB.announceOff end,
      function(on) if ns.questDone then ns.questDone.command(on and "on" or "off") end end,
      "In your own chat" },
    { "  ...and tell my party", function() return not AuDHDDB.announcePartyOff end,
      function(on) if ns.questDone then ns.questDone.command("party " .. (on and "on" or "off")) end end,
      "Also sends it to party chat when you're in a group" },
    { "Drop chances on mob tooltips", function() return not AuDHDDB.dropsOff end,
      function(on) AuDHDDB.dropsOff = not on or nil end },
  } },
  { "Rares", {
    { "Alerts for every rare", function() return (AuDHDDB.rares or "all") == "all" end,
      function() ns.rare.command("all") end, "A pop-up and the /tar button near any rare's spawn point" },
    { "Alerts only for the route's rares", function() return AuDHDDB.rares == "route" end,
      function(on) ns.rare.command(on and "route" or "all") end },
    { "No rare alerts", function() return AuDHDDB.rares == "off" end, function(on) ns.rare.command(on and "off" or "all") end },
    { "Mouse wheel targets rares", function() return AuDHDDB.rareWheel end,
      function(on) AuDHDDB.rareWheel = on or nil if ns.rare then ns.rare.applyWheel() end end,
      "While the rare button shows, scrolling the mouse wheel clicks it (cycles /tar through nearby rares)" },
  } },
  { "Party", {
    { "Buttons to ask the party for buffs", function() return not (AuDHDDB.buffAsk and AuDHDDB.buffAsk.off) end,
      function(on) if ns.buffAsk then ns.buffAsk.command(on and "on" or "off") end end,
      "In a group with a priest, mage, druid or paladin: a click asks them in party chat for a buff you don't have" },
    { "Click-cast healing frames", function() return ns.heal and ns.heal.isOn() end,
      function(on) if ns.heal then ns.heal.command(on and "on" or "off") end end,
      "Your party in a row near the bottom of the screen: click one with a mouse button to cast that button's spell on them. Set the spells with the Click-cast spells button below" },
    { "Party quest progress", function() return not AuDHDDB.partyOff end,
      function(on) AuDHDDB.partyOff = not on or nil end,
      "What your group (with AuDHD) has done on quests you share" },
  } },
  { "Fishing", {
    { "One-click fishing", function() return ns.fishing and ns.fishing.isOn() end,
      function(on) if ns.fishing then ns.fishing.command(on and "on" or "off") end end,
      "With a fishing pole equipped: one click on the world casts, the same click reels in, the catch looted" },
    { "The button to fish with" },
    { "Right button", function() return ns.fishing and ns.fishing.button() == "BUTTON2" end,
      function() if ns.fishing then ns.fishing.command("right") end end,
      "Holding it still turns the camera; right-clicking a mob, NPC or chest works as always" },
    { "Middle button", function() return ns.fishing and ns.fishing.button() == "BUTTON3" end,
      function() if ns.fishing then ns.fishing.command("middle") end end },
    { "Mouse button 4", function() return ns.fishing and ns.fishing.button() == "BUTTON4" end,
      function() if ns.fishing then ns.fishing.command("4") end end },
    { "Mouse button 5", function() return ns.fishing and ns.fishing.button() == "BUTTON5" end,
      function() if ns.fishing then ns.fishing.command("5") end end },
    { "Put on a lure first", function() return ns.fishing and ns.fishing.lureOn() end,
      function(on) if ns.fishing then ns.fishing.command("lure " .. (on and "on" or "off")) end end,
      "No lure on the pole and one in your bags: the click puts the best one your skill can use on, the next click casts" },
    { "Fishing level" },
    { "Under the minimap (with a pole)", function() return ns.fishing and ns.fishing.zoneOn() end,
      function(on) if ns.fishing then ns.fishing.command("zone " .. (on and "on" or "off")) end end,
      "The skill this zone needs before fish stop getting away, and yours (red: too low)" },
    { "On the world map", function() return ns.fishing and ns.fishing.mapOn() end,
      function(on) if ns.fishing then ns.fishing.command("map " .. (on and "on" or "off")) end end,
      "In the top right corner, for the zone the map shows, pole or not" },
    { note = "One-click fishing works only while a fishing pole is equipped and you're out of combat. A key for it: Key Bindings, AuDHD, Fish." },
    { "Sound" },
    { "Louder splash while a pole is equipped", function() return ns.fishing and ns.fishing.isLoud() end,
      function(on) if ns.fishing then ns.fishing.command("loud " .. (on and "on" or "off")) end end,
      "Sound effects at the volume below, music and ambience down to a third, sound on with the game in the background. All put back when the pole comes off" },
  }, extra = "splash" },
  { "Warlock", {
    { "Soul shard counter", function() return ns.shards and ns.shards.isOn() end,
      function(on) if ns.shards then ns.shards.command(on and "on" or "off") end end,
      "Your shards in your bags, a warning when low, extras deleted past your max so Drain Soul keeps working. Mouse wheel on it sets the max, Shift + wheel the low mark" },
    { "Lock the shard counter", function() return ns.shards and ns.shards.isLocked() end,
      function(on) if ns.shards then ns.shards.command(on and "lock" or "unlock") end end },
  }, extra = "shards" },
}

local checks = {}
local function refresh()
  for _, c in ipairs(checks) do c:SetChecked(c.get() and true or false) end
  if frame and frame.arrowScale then
    -- the saved size (moving the slider here mustn't write it back)
    frame.syncing = true
    frame.arrowScale:SetValue((AuDHDDB.arrow and AuDHDDB.arrow.scale) or 1)
    if frame.rangeGap and ns.range then frame.rangeGap:SetValue(sub("range").gap or ns.range.PLATE_GAP) end
    if frame.splash and ns.fishing then frame.splash:SetValue(ns.fishing.volume()) end
    if frame.shardMax and ns.shards then
      local mx, lo = ns.shards.values()
      if not frame.shardMax:HasFocus() then frame.shardMax:SetText(tostring(mx)) end
      if not frame.shardLow:HasFocus() then frame.shardLow:SetText(tostring(lo)) end
    end
    frame.syncing = nil
  end
end

local function heading(page, text, y)
  local h = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  h:SetPoint("TOPLEFT", PAGE_X, y - 6)
  h:SetText(text)
  return y - 26
end

local function rows(page, items, y)
  for _, it in ipairs(items) do
    if it.note then
      local n = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      n:SetPoint("TOPLEFT", PAGE_X, y - 4)
      n:SetWidth(COL - 10)
      n:SetJustifyH("LEFT")
      n:SetText(it.note)
      y = y - math.max(ROW, n:GetStringHeight() + 12)
    elseif not it[2] then
      y = heading(page, it[1], y - 4)
    else
      local c = ns.newFrame("Settings", "CheckButton", nil, page, "UICheckButtonTemplate")
      c:SetSize(22, 22)
      c:SetPoint("TOPLEFT", PAGE_X - 2, y)
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
        refresh()   -- the rare and fishing-button choices are one of several: the others change too
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

-- the arrow's size (the same as /wfn arrow scale, 0.4 to 3; here 0.5 to 2.5) and the range guide's height over the
-- target's nameplate (user, 2026-10-17: "raise/lower it with a slider")
local function slider(page, y, title, name, lo, hi, step, ends, show, set)
  local label = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("TOPLEFT", PAGE_X, y - 8)
  label:SetText(title)
  local value = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  value:SetPoint("LEFT", label, "RIGHT", 8, 0)
  local s = ns.newFrame("Settings", "Slider", name, page, "OptionsSliderTemplate")
  s:SetPoint("TOPLEFT", PAGE_X + 4, y - 30)
  s:SetWidth(COL - 60)
  s:SetMinMaxValues(lo, hi)
  s:SetValueStep(step)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  for suffix, text in pairs({ Low = ends[1], High = ends[2], Text = "" }) do
    local f = _G[name .. suffix]
    if f then f:SetText(text) end
  end
  s:SetScript("OnValueChanged", function(_, v)
    v = math.floor(v / step + 0.5) * step
    value:SetText(show(v))
    if frame.syncing then return end
    set(v)
  end)
  return s, y - 60
end

local EXTRA = {}
function EXTRA.sliders(page, y)
  y = y - 6
  frame.arrowScale, y = slider(page, y, "Arrow size", "AuDHDArrowScale", 0.5, 2.5, 0.1, { "small", "big" },
    function(v) return ("%.1fx"):format(v) end,
    function(v) if ns.arrow then ns.arrow.command(("scale %.1f"):format(v)) end end)
  frame.rangeGap, y = slider(page, y, "Range guide height", "AuDHDRangeGap", -60, 80, 2, { "lower", "higher" },
    function(v) return ("%+d"):format(v) end,
    function(v) if ns.range then ns.range.setGap(v) end end)
  return y
end
-- the splash's volume (sound effects) while the pole is out (the user, 2026-10-22: "a volume slider for the fish sound")
function EXTRA.splash(page, y)
  frame.splash, y = slider(page, y, "Splash volume", "AuDHDSplashVolume", 10, 100, 5, { "quiet", "loud" },
    function(v) return ("%d%%"):format(v) end,
    function(v) if ns.fishing then ns.fishing.command("volume " .. v) end end)
  return y
end
-- soul shards: how many to keep, and how few is low (the user, 2026-10-17: "a number input field in the settings")
function EXTRA.shards(page, y)
  local function numberBox(text, x, cmd)
    local l = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l:SetPoint("TOPLEFT", x, y - 12)
    l:SetText(text)
    local b = ns.newFrame("Settings", "EditBox", nil, page, "InputBoxTemplate")
    b:SetSize(32, 20)
    b:SetPoint("LEFT", l, "RIGHT", 10, 0)
    b:SetAutoFocus(false)
    b:SetNumeric(true)
    b:SetMaxLetters(2)
    local function apply(self)
      local v = tonumber(self:GetText())
      if v and ns.shards then ns.shards.command(cmd .. " " .. v) end
      refresh()
    end
    b:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    b:SetScript("OnEditFocusLost", apply)
    return b
  end
  y = heading(page, "Soul shards", y - 4)
  frame.shardMax = numberBox("Keep at most", PAGE_X + 4, "max")
  frame.shardLow = numberBox("Low at", PAGE_X + 124, "low")
  return y - 34
end

local function pick(i)
  for j, t in ipairs(frame.tabs) do
    t.page:SetShown(j == i)
    if j == i then t.button:LockHighlight() else t.button:UnlockHighlight() end
  end
  AuDHDDB.settingsTab = i ~= 1 and i or nil
end

local function create()
  frame = ns.newFrame("Settings", "Frame", "AuDHDSettings", UIParent, "BackdropTemplate")
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
  local close = ns.newFrame("Settings", "Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function() frame:Hide() end)
  -- the tab buttons first: their names' width sets the list's
  frame.tabs = {}
  local widest = 0
  for i, tab in ipairs(TABS) do
    local b = ns.newFrame("Settings", "Button", nil, frame, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", 14, -44 - (i - 1) * 28)
    b:SetText(tab[1])
    b:SetScript("OnClick", function()
      PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
      pick(i)
    end)
    local fs = b:GetFontString()
    widest = math.max(widest, fs and fs:GetStringWidth() or 70)
    frame.tabs[i] = { button = b }
  end
  SIDE = math.ceil(widest) + 24
  PAGE_X = 14 + SIDE + 12
  for _, t in ipairs(frame.tabs) do t.button:SetSize(SIDE, 24) end
  -- a line between the tabs and the page
  local line = frame:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(1, 1, 1, 0.15)
  line:SetPoint("TOPLEFT", 14 + SIDE + 6, -44)
  line:SetPoint("BOTTOMLEFT", 14 + SIDE + 6, 44)
  line:SetWidth(1)
  local bottom = -44
  for i, tab in ipairs(TABS) do
    local page = ns.newFrame("Settings", "Frame", nil, frame)
    page:SetAllPoints(frame)
    local y = heading(page, tab[1], -38)
    y = rows(page, tab[2], y)
    if tab.extra then y = EXTRA[tab.extra](page, y) end
    bottom = math.min(bottom, y)
    frame.tabs[i].page = page
  end
  bottom = math.min(bottom, -44 - #TABS * 28) - 8
  local routes = ns.newFrame("Settings", "Button", nil, frame, "UIPanelButtonTemplate")
  routes:SetSize(110, 22)
  routes:SetPoint("TOPLEFT", 12, bottom)
  routes:SetText("Pick a route")
  routes:SetScript("OnClick", function()
    if not ns.picker then return end
    frame:Hide()
    ns.picker.show(function() S.show() end)
  end)
  local heals = ns.newFrame("Settings", "Button", nil, frame, "UIPanelButtonTemplate")
  heals:SetSize(130, 22)
  heals:SetPoint("LEFT", routes, "RIGHT", 8, 0)
  heals:SetText("Click-cast spells")
  heals:SetScript("OnClick", function()
    if not ns.heal then return end
    frame:Hide()
    ns.heal.setup(function() S.show() end)
  end)
  frame:SetSize(PAGE_X + COL + 10, -bottom + 34)
  pick(TABS[AuDHDDB.settingsTab or 1] and AuDHDDB.settingsTab or 1)
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
  local panel = ns.newFrame("Settings", "Frame")
  local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("TOPLEFT", 16, -16)
  text:SetText("AuDHD's settings have their own window (also: right-click the minimap button, or /wfn settings).")
  local b = ns.newFrame("Settings", "Button", nil, panel, "UIPanelButtonTemplate")
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
