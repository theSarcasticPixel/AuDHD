-- Rare scanner (the user, 2026-10-16: "something akin to rarescanner be looking for him as you run around so you dont
-- miss him"): every rare you come across gets a short alert; a rare the route needs (ns.routes[..].rares: Blackmoss the
-- Fetid for The Moss-twined Heart) a loud one - raid-warning sound, a big message, the taskbar flashing and a /tar line
-- in chat - for as long as its quest isn't done, whether or not you're on its step.
-- Where it looks: your target, mouseover and every enemy nameplate a few times a second (turn enemy nameplates on to
-- see them furthest), and the minimap's rare markers (vignettes) where the client has them. We can't target for you
-- (protected): the alert says where to look. Unit, nameplate and vignette APIs only: nothing protected.
local _, ns = ...
local R = {}
ns.rare = R

local isSecret = issecretvalue or function() return false end
local log = function(e, f) if ns.log then ns.log.add(e, f) end end
local REALERT = 300   -- seconds before the same rare (by GUID) alerts again

local function npcOfGuid(guid)
  if not guid or isSecret(guid) then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
  return tonumber(id)
end

-- the route's rares still needed: npc id -> { n, q, sp }
local function wanted(npc)
  local r = ns.core and ns.core.route()
  local w = r and r.rares and r.rares[npc]
  if not w then return nil end
  if C_QuestLog.IsQuestFlaggedCompleted(w.q) then return nil end
  -- a quest it starts (an item it drops): needed until you have the quest; a quest it's part of: while you're on it
  -- and it isn't finished
  local onIt = C_QuestLog.GetLogIndexForQuestID(w.q) ~= nil
  if onIt and C_QuestLog.IsComplete(w.q) then return nil end
  return w
end

local seen = {}   -- GUID -> when we alerted
local function mode() return AuDHDDB.rares or "all" end   -- all | route | off

function R.alert(guid, npc, name, how)
  if mode() == "off" then return end
  local now = GetTime()
  if seen[guid] and now - seen[guid] < REALERT then return end
  local w = wanted(npc)
  if not w and mode() == "route" then return end
  seen[guid] = now
  name = name or (w and w.n) or "a rare"
  if w then
    local title = C_QuestLog.GetTitleForQuestID(w.q) or ("quest " .. w.q)
    local msg = ("RARE: %s - you need it for %s"):format(name, title)
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
      RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo.RAID_WARNING)
    else
      UIErrorsFrame:AddMessage(msg, 1, 0.3, 0.1)
    end
    PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
    if FlashClientIcon then FlashClientIcon() end
    print(("|cff66ccffAuDHD|r: |cffff4040%s|r (%s) - |cffffd100/tar %s|r"):format(msg, how, name))
  else
    UIErrorsFrame:AddMessage(("Rare: %s"):format(name), 1, 0.82, 0)
    PlaySound(SOUNDKIT and SOUNDKIT.UI_RAID_BOSS_WHISPER_WARNING or 37881)
    print(("|cff66ccffAuDHD|r: rare nearby: |cffffd100%s|r (%s)"):format(name, how))
  end
  R.showButton(name ~= "a rare" and name or nil, npc)
  log("RARE_SEEN", { npc = npc, name = name, wanted = w and w.q or nil, how = how })
end

-- one unit: a live rare you could attack
local RARE = { rare = true, rareelite = true }
local function look(unit, how)
  if not UnitExists(unit) or UnitIsDead(unit) then return end
  local c = UnitClassification(unit)
  if isSecret(c) or not RARE[c] then return end
  if UnitCanAttack and not UnitCanAttack("player", unit) then return end
  local guid = UnitGUID(unit)
  local npc = npcOfGuid(guid)
  if npc then R.alert(guid, npc, UnitName(unit), how) end
end

function R.scan()
  pcall(look, "target", "your target")
  pcall(look, "mouseover", "under your mouse")
  if C_NamePlate and C_NamePlate.GetNamePlates then
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    for _, p in ipairs(ok and plates or {}) do
      local unit = p.namePlateUnitToken or (p.UnitFrame and p.UnitFrame.unit)
      if unit and not isSecret(unit) then pcall(look, unit, "nameplate") end
    end
  end
end

-- the minimap's markers: rares out of nameplate range, where the client has vignettes
function R.vignettes()
  if not (C_VignetteInfo and C_VignetteInfo.GetVignettes) then return end
  for _, vg in ipairs(C_VignetteInfo.GetVignettes() or {}) do
    local info = C_VignetteInfo.GetVignetteInfo(vg)
    local guid = info and info.objectGUID
    local npc = npcOfGuid(guid)
    if npc then R.alert(guid, npc, info.name, "on the minimap") end
  end
end

-- ------------------------------------------------------------------ near a rare's spawn point
-- (the user, 2026-10-16: "add rarespawn locations to the map and a pop up when we get within 200 yars of one of their
-- spawn points"): every rare's spawn points from Questie (RareData.lua). One pop-up per rare as you come within NEAR
-- yards of one of its spawn points; it can pop up again once you've been REARM yards from all of them. Rares far below
-- your level (GREY levels) only when the route needs them.
local NEAR, REARM, GREY = 200, 500, 8
local where      -- npc -> { { c, x, y } } its spawn points in world coordinates (worked out once)
local armed = {} -- npc -> false after its pop-up, until you're REARM yards away
local function spawnWorld()
  if where then return where end
  where = {}
  for npc, r in pairs(ns.rareData or {}) do
    local list = {}
    for _, g in ipairs(r.sp) do
      for k = 1, #g.p - 1, 2 do
        local c, x, y = ns.core.worldPos(g.m, g.p[k] / 100, g.p[k + 1] / 100)
        if c then list[#list + 1] = { c = c, x = x, y = y } end
      end
    end
    if #list > 0 then where[npc] = list end
  end
  return where
end
local COMPASS = { "N", "NW", "W", "SW", "S", "SE", "E", "NE" }
-- world X grows north, Y grows west
local function compass(dx, dy)
  local a = math.atan2 and math.atan2(dy, dx) or math.atan(dy, dx)
  return COMPASS[math.floor((a / (2 * math.pi)) * 8 + 0.5) % 8 + 1]
end

function R.spawnPopup(npc, d, dir)
  local r = ns.rareData[npc]
  local w = wanted(npc)
  local lv = r.lv and (r.lv[1] == r.lv[2] and tostring(r.lv[1]) or (r.lv[1] .. "-" .. r.lv[2])) or "?"
  local msg = ("Rare spawn point %d yd %s: %s (%s%s)"):format(math.floor(d), dir, r.n, lv, r.e and " elite" or "")
  if w then msg = msg .. " - you need it for " .. (C_QuestLog.GetTitleForQuestID(w.q) or ("quest " .. w.q)) end
  if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
    RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo.RAID_WARNING)
  else
    UIErrorsFrame:AddMessage(msg, 1, 0.82, 0)
  end
  PlaySound(w and (SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959) or (SOUNDKIT and SOUNDKIT.UI_RAID_BOSS_WHISPER_WARNING or 37881))
  print(("|cff66ccffAuDHD|r: |cffffd100%s|r - it may not be up"):format(msg))
  R.showButton(r.n, npc)
  log("RARE_SPAWN_NEAR", { npc = npc, name = r.n, d = math.floor(d), wanted = w and w.q or nil })
end

function R.checkSpawns()
  if mode() == "off" or not ns.rareData then return end
  local me = ns.core.playerWorld()
  if not me then return end
  local level = UnitLevel("player") or 1
  for npc, list in pairs(spawnWorld()) do
    local best, bx, by
    for _, s in ipairs(list) do
      if s.c == me.c then
        local dx, dy = s.x - me.x, s.y - me.y
        local d = math.sqrt(dx * dx + dy * dy)
        if not best or d < best then best, bx, by = d, dx, dy end
      end
    end
    if best and best <= NEAR and armed[npc] ~= false then
      local r = ns.rareData[npc]
      local w = wanted(npc)
      armed[npc] = false
      if (w or mode() ~= "route") and (w or not r.lv or r.lv[2] >= level - GREY) then R.spawnPopup(npc, best, compass(bx, by)) end
    elseif not best or best > REARM then
      armed[npc] = nil
    end
  end
  R.buttonTick()
end

-- ------------------------------------------------------------------ the target button
-- (the user, 2026-10-16: "when near a rarespawn, lets have a button show up that clicking it does /tar *rarespawn
-- name*"): a secure macro button - your click runs "/tar <name>", as if you typed it; the addon itself never targets.
-- Secure buttons can't be changed in combat: a rare found then gets its button when the fight ends. It stays until
-- its x. Several near: each click targets one and
-- moves on to the next (not in combat: the button can't change then). Drag to move.
local button, wheel, wheelToggle
-- the rares near you, in the order found: { npc, name, at }; the button targets list[idx], and each click moves it on
-- to the next (the user, 2026-10-16: "if there is more than one in range have it cycle between them with each click")
local list, idx, dirty = {}, 1, false

-- after a click: the macro ran on this press (down or up, by the game's "act on key down" setting): next rare, and
-- whether it found this one
local function clicked(self, down, sound)
  local onDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
  if (down and true or false) ~= (onDown and true or false) then return end
  local name = self.name
  if sound then PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856) end
  R.nextButton()
  C_Timer.After(0.1, function() R.clickResult(name) end)
end

-- the mouse wheel (the user, 2026-10-16: "a button ... that swaps it to trigger on mouse wheel up/down"): an unseen
-- secure button with the same macro, the wheel bound to it while the rare button shows (override bindings, owned by
-- it: the wheel zooms again once it's gone). Bindings can't change in combat: then after it.
local function wheelOn() return AuDHDDB.rareWheel and #list > 0 end
function R.applyWheel()
  if not wheel then return end
  if InCombatLockdown() then dirty = true return end
  if ClearOverrideBindings and SetOverrideBindingClick then
    ClearOverrideBindings(wheel)
    if wheelOn() then
      SetOverrideBindingClick(wheel, true, "MOUSEWHEELUP", "AuDHDRareWheel")
      SetOverrideBindingClick(wheel, true, "MOUSEWHEELDOWN", "AuDHDRareWheel")
    end
  end
  if wheelToggle then
    local label = wheelToggle:GetFontString()
    if AuDHDDB.rareWheel then
      wheelToggle:LockHighlight()
      if label then label:SetTextColor(0.25, 1, 0.25) end
    else
      wheelToggle:UnlockHighlight()
      if label then label:SetTextColor(1, 0.82, 0) end
    end
  end
end

local function makeButton()
  if button then return button end
  button = CreateFrame("Button", "AuDHDRareButton", UIParent, "SecureActionButtonTemplate,BackdropTemplate")
  button:SetSize(270, 34)
  if button.SetBackdrop then
    button:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                         tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    button:SetBackdropColor(0.25, 0, 0, 0.9)
  end
  local pos = AuDHDDB.rareButton
  if pos then button:SetPoint(pos.p, UIParent, pos.rp, pos.x, pos.y) else button:SetPoint("TOP", UIParent, "TOP", 0, -180) end
  button:RegisterForClicks("AnyUp", "AnyDown")
  button:SetAttribute("type", "macro")
  button:SetMovable(true)
  button:RegisterForDrag("LeftButton")
  button:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
  button:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    AuDHDDB.rareButton = { p = p, rp = rp, x = x, y = y }
  end)
  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetSize(22, 22)
  button.icon:SetPoint("LEFT", 6, 0)
  button.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
  button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  button.text:SetPoint("LEFT", button.icon, "RIGHT", 6, 0)
  button.text:SetPoint("RIGHT", -76, 0)
  button.text:SetJustifyH("LEFT")
  -- feel like a button (the user, 2026-10-16: "clicking it has no feedback"): lit on hover, pressed in while held, a
  -- click sound, and under it whether the click found the rare
  local hl = button:CreateTexture(nil, "HIGHLIGHT")
  hl:SetPoint("TOPLEFT", 3, -3)
  hl:SetPoint("BOTTOMRIGHT", -3, 3)
  hl:SetColorTexture(1, 0.8, 0.3, 0.18)
  button:HookScript("OnMouseDown", function(self)
    self.icon:SetPoint("LEFT", 7, -1)
    if self.SetBackdropColor then self:SetBackdropColor(0.12, 0, 0, 0.95) end
  end)
  button:HookScript("OnMouseUp", function(self)
    self.icon:SetPoint("LEFT", 6, 0)
    if self.SetBackdropColor then self:SetBackdropColor(0.25, 0, 0, 0.9) end
  end)
  button.status = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  button.status:SetPoint("TOP", button, "BOTTOM", 0, -3)
  local close =CreateFrame("Button", nil, button, "UIPanelCloseButton")
  close:SetSize(22, 22)
  close:SetPoint("RIGHT", -2, 0)
  close:SetScript("OnClick", function() R.hideButton() end)
  -- the wheel toggle: on (lit, green) the mouse wheel targets too; again to go back to clicks only
  wheelToggle = CreateFrame("Button", nil, button, "UIPanelButtonTemplate")
  wheelToggle:SetSize(50, 20)
  wheelToggle:SetPoint("RIGHT", close, "LEFT", -2, 0)
  wheelToggle:SetText("Wheel")
  wheelToggle:SetScript("OnClick", function()
    AuDHDDB.rareWheel = not AuDHDDB.rareWheel or nil
    PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
    local msg = AuDHDDB.rareWheel and "|cff40ff40Mouse wheel targets it too|r" or "|cffffd100Click only: the wheel zooms again|r"
    if InCombatLockdown() then msg = msg .. " |cffaaaaaa(after this fight)|r" end
    button.status:SetText(msg)
    R.applyWheel()
  end)
  wheelToggle:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Mouse wheel targeting", 1, 1, 1)
    GameTooltip:AddLine(AuDHDDB.rareWheel and "On: scrolling up or down targets the rare (and the next one), not the camera zoom, while this button shows. Click to turn off."
      or "Off: click to make scrolling up or down target the rare while this button shows.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  wheelToggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Click: /tar " .. (self.name or ""), 1, 1, 1)
    if AuDHDDB.rareWheel then GameTooltip:AddLine("Mouse wheel: the same", 0.25, 1, 0.25) end
    if #list > 1 then GameTooltip:AddLine(("%d rares near: each click targets the next"):format(#list), 0.6, 0.8, 1) end
    GameTooltip:AddLine("Drag to move", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  button:SetScript("PostClick", function(self, _, down) clicked(self, down, true) end)
  button:Hide()
  -- what the wheel clicks: shown (a binding clicks only a shown button) but not seen
  wheel = CreateFrame("Button", "AuDHDRareWheel", UIParent, "SecureActionButtonTemplate")
  wheel:SetSize(1, 1)
  wheel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
  wheel:SetAlpha(0)
  wheel:EnableMouse(false)
  wheel:RegisterForClicks("AnyUp", "AnyDown")
  wheel:SetAttribute("type", "macro")
  wheel:SetScript("PostClick", function(self, _, down) clicked(self, down, false) end)
  return button
end

function R.applyButton()
  if InCombatLockdown() then dirty = true return end
  dirty = false
  if #list == 0 then
    if button then button:Hide() end
    R.applyWheel()
    return
  end
  if idx > #list then idx = 1 end
  local b = makeButton()
  local e = list[idx]
  b.name, wheel.name = e.name, e.name
  b:SetAttribute("macrotext", "/tar " .. e.name)
  wheel:SetAttribute("macrotext", "/tar " .. e.name)
  b.text:SetText(("Target %s%s"):format(e.name, #list > 1 and ("  |cffaaaaaa(%d/%d)|r"):format(idx, #list) or ""))
  b:Show()
  R.applyWheel()
end
function R.showButton(name, npc)
  if not name then return end
  for _, e in ipairs(list) do
    if e.npc == npc or e.name == name then e.at = GetTime() return end
  end
  list[#list + 1] = { npc = npc, name = name, at = GetTime() }
  R.applyButton()
end
-- after a click (the macro has run): the next one
function R.nextButton()
  if #list > 1 then idx = idx % #list + 1 end
  R.applyButton()
end
-- under the button for a few seconds: targeted, or not found (not up, or out of range)
local statusToken = 0
function R.clickResult(name)
  if not (button and button.status and name) then return end
  local t = UnitExists("target") and UnitName("target")
  local got = t and not isSecret(t) and t == name
  button.status:SetText(got and ("|cff40ff40Targeted %s|r"):format(name) or ("|cffff6040%s isn't up nearby|r"):format(name))
  statusToken = statusToken + 1
  local mine = statusToken
  C_Timer.After(3, function() if statusToken == mine and button then button.status:SetText("") end end)
  return got
end
function R.hideButton()
  list, idx = {}, 1
  R.applyButton()
end
-- after combat: what waited. The button stays until its x, however long and however far you go (the user,
-- 2026-10-16: "lets make it stay until we press the x even if we run away")
function R.buttonTick()
  if dirty then R.applyButton() end
end

function R.enable()
  local f = CreateFrame("Frame")
  for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED", "VIGNETTE_MINIMAP_UPDATED", "VIGNETTES_UPDATED", "PLAYER_REGEN_ENABLED" }) do
    pcall(f.RegisterEvent, f, e)
  end
  f:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_ENABLED" then pcall(R.buttonTick)
    elseif event == "NAME_PLATE_UNIT_ADDED" then pcall(look, unit, "nameplate")
    elseif event:find("^VIGNETTE") then pcall(R.vignettes)
    else pcall(R.scan) end
  end)
  local acc, n = 0, 0
  f:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.5 then return end
    acc = 0
    pcall(R.scan)
    n = n + 1
    if n % 2 == 0 then
      local ok, err = pcall(R.checkSpawns)
      if not ok then log("RARE_ERROR", { err = tostring(err) }) end
    end
  end)
end

-- /wfn rares all | route | off
function R.command(rest)
  if rest == "all" or rest == "route" or rest == "off" then AuDHDDB.rares = rest end
  local r = ns.core and ns.core.route()
  local names = {}
  for npc, w in pairs(r and r.rares or {}) do
    if wanted(npc) then names[#names + 1] = w.n end
  end
  return ("rare alerts: %s (/wfn rares all | route | off); the route still needs: %s"):format(mode(),
    #names > 0 and table.concat(names, ", ") or "none")
end
