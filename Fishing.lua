-- One-click fishing: with a fishing pole in your hands, one click of your fishing mouse button (settings: right, middle,
-- button 4 or 5) on the world casts Fishing; while your line is out the same click reels it in (the game's "interact
-- with target" on the bobber) and the catch is looted. One click, not a double click: easier on the hands (the user,
-- 2026-10-22: "double clicking is just adding to peoples RSI"). A key for it can be set in the game's Key Bindings
-- (AuDHD: Fish): the same key casts, then reels in.
-- Addons can't cast on their own: the button is bound to a hidden secure button running /cast. The right button is only
-- bound while nothing is under the cursor (a mob, an NPC, a chest: right-click still does what it always did), a long
-- press turns the camera instead of casting, and a secure handler drops the bindings the moment combat starts.
local _, ns = ...
local F = {}
ns.fishing = F
BINDING_HEADER_AUDHD = "AuDHD"
_G["BINDING_NAME_CLICK AuDHDFishCast:LeftButton"] = "Fish (cast, then reel in)"

local FISHING = 7620           -- Fishing (every rank has the same name)
local QUICK = 0.3              -- seconds: a press longer than this is the camera, not a cast
local MOVE = 12                -- pixels the cursor may move during a click
F.BUTTONS = { { "BUTTON2", "Right button" }, { "BUTTON3", "Middle button" }, { "BUTTON4", "Button 4" }, { "BUTTON5", "Button 5" } }

local castButton, owner, watcher, ticker
local down, fishingNow, lookStarted, bound
local restore                  -- CVars changed while fishing, to put back

local function log(e, t) if ns.log then ns.log.add(e, t) end end
local function isOn() return not AuDHDDB.fishOff end
local function mouseKey() return AuDHDDB.fishButton or "BUTTON2" end
local function spellName()
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(FISHING) end
  return GetSpellInfo and GetSpellInfo(FISHING)
end
local function hasPole()
  local id = GetInventoryItemID("player", 16)
  if not id then return false end
  local info = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
  local classID, subID = select(6, info(id))
  return classID == 2 and subID == 20   -- a weapon: fishing pole
end
local function knowsFishing()
  local name = spellName()
  return name and (C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(name) or GetSpellInfo and GetSpellInfo(name)) and true or false
end
local function ready() return isOn() and hasPole() and knowsFishing() and not InCombatLockdown() end

-- something the right button is for under the cursor: a unit, or an object the game shows a tooltip for
local function somethingThere()
  if UnitExists("mouseover") then return true end
  -- (a tooltip left fading after the cursor moved away doesn't count)
  return GameTooltip and GameTooltip:IsShown() and GameTooltip:GetOwner() == UIParent and GameTooltip:GetAlpha() >= 0.99 or false
end

-- the key you bound to AuDHD: Fish
local function fishKeys()
  return { GetBindingKey and GetBindingKey("CLICK AuDHDFishCast:LeftButton") }
end

-- what your fishing button (and key) do now; only touched when it changes
local held
local function bind()
  if InCombatLockdown() or not owner or held() then return end
  local want
  if ready() then
    local key = mouseKey()
    if fishingNow then want = "reel"
    elseif key ~= "BUTTON2" or not somethingThere() then want = "cast" end
  end
  local tag = want and (want .. mouseKey()) or nil
  if tag == bound then return end
  bound = tag
  ClearOverrideBindings(owner)
  if want == "reel" then
    -- the line is out: reel in
    SetOverrideBinding(owner, true, mouseKey(), "INTERACTTARGET")
    for _, k in ipairs(fishKeys()) do SetOverrideBinding(owner, true, k, "INTERACTTARGET") end
  elseif want == "cast" then
    SetOverrideBindingClick(owner, true, mouseKey(), "AuDHDFishCast", "LeftButton")
  end
end

-- soft targeting on, so "interact with target" finds the bobber; put back when you put the pole away
local function softTarget(on)
  if not SetCVar or not GetCVar then return end
  if on then
    if restore then return end
    local old = GetCVar("SoftTargetInteract")
    if old == nil or tonumber(old) == 3 then return end
    restore = { SoftTargetInteract = old }
    pcall(SetCVar, "SoftTargetInteract", "3")
  elseif restore and not InCombatLockdown() then
    for k, v in pairs(restore) do pcall(SetCVar, k, v) end
    restore = nil
  end
end

-- the splash louder while a pole is in your hands (the user, 2026-10-22): sound effects up to the splash volume (the
-- settings' slider, 100% by default), music and the
-- ambience (the water's own noise) down to a third, sound kept on with the game in the background. What they were is
-- saved, so a crash with the pole out still puts them back at the next login.
local LOUD = { Sound_EnableAllSound = function() return "1" end, Sound_EnableSFX = function() return "1" end,
               Sound_EnableSoundWhenGameIsInBG = function() return "1" end, Sound_SFXVolume = function() return ("%.2f"):format(F.volume() / 100) end,
               Sound_MusicVolume = function(v) return ("%.2f"):format((tonumber(v) or 0) / 3) end,
               Sound_AmbienceVolume = function(v) return ("%.2f"):format((tonumber(v) or 0) / 3) end }
local function loud(on)
  if not SetCVar or not GetCVar then return end
  if on then
    if AuDHDDB.fishSound then return end
    local old = {}
    for k, f in pairs(LOUD) do
      local v = GetCVar(k)
      if v ~= nil then old[k] = v pcall(SetCVar, k, f(v)) end
    end
    AuDHDDB.fishSound = old
  elseif AuDHDDB.fishSound then
    for k, v in pairs(AuDHDDB.fishSound) do pcall(SetCVar, k, v) end
    AuDHDDB.fishSound = nil
  end
end

-- your fishing skill: { rank, rank with the lure's bonus }, from the skill list
local function skill()
  local want = spellName()
  if not (GetNumSkillLines and GetSkillLineInfo) or not want then return nil end
  for i = 1, GetNumSkillLines() do
    local name, header, _, rank, _, mod = GetSkillLineInfo(i)
    if not header and name == want then return rank, rank + (mod or 0) end
  end
end

-- lures: the biggest bonus your skill can use (the game's skill needed to put each one on)
local LURES = {
  { 6533, 100, 100 },   -- Aquadynamic Fish Attractor: +100, needs 100
  { 6532, 75, 100 },    -- Bright Baubles: +75, needs 100
  { 7307, 75, 100 },    -- Flesh Eating Worm: +75, needs 100
  { 6811, 50, 50 },     -- Aquadynamic Fish Lens: +50, needs 50
  { 6530, 50, 50 },     -- Nightcrawlers: +50, needs 50
  { 6529, 25, 1 },      -- Shiny Bauble: +25
}
local function count(id)
  if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) or 0 end
  return GetItemCount and GetItemCount(id) or 0
end
-- the lure to put on now: none when the pole has one, or none is in your bags
local function lureToUse()
  if AuDHDDB.fishLureOff or not GetWeaponEnchantInfo then return nil end
  if GetWeaponEnchantInfo() then return nil end   -- the main hand (the pole) has one
  local rank = skill() or 0
  for _, l in ipairs(LURES) do
    if rank >= l[3] and count(l[1]) > 0 then return l[1] end
  end
end

-- a long press or a drag isn't a cast: the click goes through with nothing to do (attributes can change in PreClick
-- out of combat; the bindings are gone in combat anyway)
local function quickClick()
  if not down then return true end
  local x, y = GetCursorPosition()
  return GetTime() - down.t <= QUICK and (x - down.x) ^ 2 + (y - down.y) ^ 2 <= MOVE ^ 2
end

local function make()
  castButton = CreateFrame("Button", "AuDHDFishCast", UIParent, "SecureActionButtonTemplate")
  castButton:RegisterForClicks("AnyUp")
  -- on the release, whatever "cast on key down" is set to (else the game drops the release: nothing happens)
  castButton:SetAttribute("useOnKeyDown", false)
  castButton:SetAttribute("type", "macro")
  castButton:SetScript("PreClick", function(self)
    if InCombatLockdown() then return end
    -- nothing while something is being cast (the lure going on: a second click mustn't cut it short)
    local busy = UnitCastingInfo and UnitCastingInfo("player")
    self:SetAttribute("type", quickClick() and not busy and "macro" or nil)
    -- no lure on the pole and one in your bags: this click puts it on, the next one casts
    local lure = lureToUse()
    local name = spellName()
    if lure then self:SetAttribute("macrotext", "/use item:" .. lure .. "\n/use 16")
    elseif name then self:SetAttribute("macrotext", "/cast " .. name) end
  end)
  castButton:SetScript("PostClick", function(self)
    if not InCombatLockdown() then self:SetAttribute("type", "macro") end
  end)
  -- shown (a hidden button may not take the click) but invisible and out of the mouse's way
  castButton:SetSize(1, 1)
  castButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
  castButton:SetAlpha(0)
  castButton:EnableMouse(false)
  owner = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
  owner:SetAttribute("_onstate-combat", [[ if newstate == "on" then self:ClearBindings() end ]])
  RegisterStateDriver(owner, "combat", "[combat] on; off")
end

-- the cast: the spell's name in your language
local function setMacro()
  local name = spellName()
  if name and castButton and not InCombatLockdown() then castButton:SetAttribute("macrotext", "/cast " .. name) end
end

local function buttonName(b)
  return ({ RightButton = "BUTTON2", MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" })[b]
end

-- the camera turn we started on a held right button ends when the button is up, read from the button itself 20 times
-- a second: the game may not send the release while the camera turns, and the binding may have changed since (the
-- user, 2026-10-22: the camera stayed locked after letting go)
local lookTicker
local function releaseLook()
  if lookTicker then if lookTicker.Cancel then lookTicker:Cancel() end lookTicker = nil end
  if lookStarted then lookStarted = nil if IsMouselooking() then MouselookStop() end end
end
local function startLook()
  MouselookStart() lookStarted = true
  if lookTicker then return end
  lookTicker = C_Timer.NewTicker(0.05, function()
    if not IsMouseButtonDown("RightButton") then releaseLook() down = nil end
  end)
end

local MOUSE = { BUTTON2 = "RightButton", BUTTON3 = "MiddleButton", BUTTON4 = "Button4", BUTTON5 = "Button5" }
-- your fishing button is held down now: its binding stays as it is until you let go
function held()
  return (down or lookStarted) and IsMouseButtonDown(MOUSE[mouseKey()]) or false
end

local function mouse(e, button)
  if buttonName(button) ~= mouseKey() then return end
  if e == "GLOBAL_MOUSE_UP" then
    -- (the cast button's PreClick has read the press by now)
    C_Timer.After(0, function() down = nil bind() end)
    return releaseLook()
  end
  if not bound then return end
  local x, y = GetCursorPosition()
  local t = GetTime()
  down = { t = t, x = x, y = y }
  -- held: turn the camera (the button is bound to the cast, which would stop the right button turning it)
  if mouseKey() == "BUTTON2" then
    C_Timer.After(QUICK, function()
      if down and down.t == t and IsMouseButtonDown("RightButton") and not IsMouselooking() then startLook() end
    end)
  end
end

local showZone, showLevels
local function watch()
  loud(not AuDHDDB.fishLoudOff and hasPole())
  if showZone then showZone() end
  local want = ready()
  for _, e in ipairs({ "GLOBAL_MOUSE_DOWN", "GLOBAL_MOUSE_UP", "UPDATE_MOUSEOVER_UNIT" }) do
    if want then watcher:RegisterEvent(e) else watcher:UnregisterEvent(e) end
  end
  if want then setMacro() softTarget(true) else softTarget(false) fishingNow = nil end
  -- the right button: re-checked as the cursor moves over things (objects don't send an event)
  if want and mouseKey() == "BUTTON2" then
    if not ticker then ticker = C_Timer.NewTicker(0.1, bind) end
  elseif ticker then
    if ticker.Cancel then ticker:Cancel() end
    ticker = nil
  end
  bind()
end

local function isFishingCast(unit, spellID)
  if unit ~= "player" then return false end
  local name = spellID and (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID) or GetSpellInfo and GetSpellInfo(spellID))
  return name ~= nil and name == spellName()
end

watcher = ns.newFrame("Fishing", "Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "SPELLS_CHANGED",
                     "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "LOOT_READY", "UPDATE_BINDINGS", "PLAYER_LOGOUT",
                     "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "SKILL_LINES_CHANGED" }) do
  watcher:RegisterEvent(e)
end
watcher:SetScript("OnEvent", function(_, e, a, b, c)
  if e == "GLOBAL_MOUSE_DOWN" or e == "GLOBAL_MOUSE_UP" then return mouse(e, a) end
  if e == "UPDATE_MOUSEOVER_UNIT" then return bind() end
  if e == "ZONE_CHANGED_NEW_AREA" or e == "ZONE_CHANGED" or e == "ZONE_CHANGED_INDOORS" or e == "SKILL_LINES_CHANGED" then
    return showLevels()
  end
  if e == "PLAYER_LOGIN" then loud(false) make() showLevels() return watch() end   -- (put back what a crash left loud)
  if e == "PLAYER_LOGOUT" then return loud(false) end
  if not owner then return end
  if e == "UNIT_SPELLCAST_CHANNEL_START" then
    if isFishingCast(a, c) then fishingNow = true bind() log("FISH_CAST", {}) end
    return
  end
  if e == "UNIT_SPELLCAST_CHANNEL_STOP" then
    if fishingNow and isFishingCast(a, c) then fishingNow = nil bind() end
    return
  end
  if e == "LOOT_READY" then
    -- the catch: looted for you (the reel was one click; no loot window to click through)
    if isOn() and IsFishingLoot and IsFishingLoot() then
      for i = GetNumLootItems(), 1, -1 do LootSlot(i) end
    end
    return
  end
  if e == "PLAYER_REGEN_DISABLED" then fishingNow, bound, down = nil, nil, nil releaseLook() return end   -- (the secure handler cleared them)
  watch()
end)

-- the fishing skill each zone needs before fish stop getting away (the classic game's values; lakes in cities and
-- starting zones are the easiest). By the map's ID.
local ZONE_SKILL = {
  [1411] = 25, [1412] = 25, [1420] = 25, [1426] = 25, [1429] = 25, [1438] = 25,                 -- starting zones
  [1453] = 25, [1454] = 25, [1455] = 25, [1456] = 25, [1457] = 25, [1458] = 25,                 -- cities
  [1413] = 75, [1421] = 75, [1432] = 75, [1436] = 75, [1439] = 75,                              -- Barrens, Silverpine, Loch Modan, Westfall, Darkshore
  [1424] = 150, [1431] = 150, [1433] = 150, [1437] = 150, [1440] = 150, [1442] = 150,           -- Hillsbrad, Duskwood, Redridge, Wetlands, Ashenvale, Stonetalon
  [1416] = 225, [1417] = 225, [1434] = 225, [1435] = 225, [1441] = 225, [1443] = 225, [1445] = 225, -- Alterac, Arathi, Stranglethorn, Swamp of Sorrows, Thousand Needles, Desolace, Dustwallow
  [1422] = 300, [1425] = 300, [1444] = 300, [1446] = 300, [1447] = 300, [1448] = 300, [1449] = 300, [1450] = 300, -- W. Plaguelands, Hinterlands, Feralas, Tanaris, Azshara, Felwood, Un'Goro, Moonglade
  [1423] = 330, [1428] = 330, [1430] = 330, [1451] = 330, [1452] = 330,                         -- E. Plaguelands, Burning Steppes, Deadwind, Silithus, Winterspring
}
F.ZONE_SKILL = ZONE_SKILL
-- a zone's map, also from a smaller map inside it (a cave, a town)
local function zoneSkill(mapID)
  for _ = 1, 4 do
    if not mapID then return nil end
    if ZONE_SKILL[mapID] then return ZONE_SKILL[mapID] end
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    mapID = info and info.parentMapID
  end
end
-- The zone's number in the colours of a quest's difficulty, from your skill without a lure (the user, 2026-10-22):
-- red: too high even with the best lure you have; orange: fine with a lure in your bags (or the one on the pole);
-- yellow: about your skill; green: below it, fewer skill-ups; grey: far below, none. (GREEN and GREY are how far your
-- skill is past the zone's: a guess, to be checked in game.)
local GREEN, GREY = 25, 75
local function bestLure(rank)
  for _, l in ipairs(LURES) do
    if rank >= l[3] and count(l[1]) > 0 then return l[2] end
  end
  return 0
end
F.bestLure = bestLure
local function levelColor(need, rank, total)
  local reach = rank + math.max(total - rank, bestLure(rank))
  if reach < need then return "|cffff1919", "too high" end
  if rank < need then return "|cffff8040", "lure needed" end
  if rank < need + GREEN then return "|cffffff00", "on par" end
  if rank < need + GREY then return "|cff40bf40", "fewer skill-ups" end
  return "|cff9d9d9d", "no skill-ups"
end
F.levelColor = levelColor
-- "Fishing: 75 (you: 68)", the 75 coloured as above
local function levelText(need)
  if not need then return nil end
  local rank, total = skill()
  if not rank then return ("Fishing: %d"):format(need) end
  local color = levelColor(need, rank, total)
  return ("Fishing: %s%d|r (you: %d%s)"):format(color, need, total, total ~= rank and " with lure" or "")
end

-- under the minimap, while a pole is in your hands (setting "fishZoneOff")
local zoneLabel, zoneValue
function showZone()
  if not zoneLabel then
    zoneLabel = ns.newFrame("Fishing", "Frame", nil, UIParent)
    zoneLabel:SetSize(200, 16)
    zoneLabel:SetPoint("TOP", Minimap, "BOTTOM", 0, -22)
    zoneLabel.text = zoneLabel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    zoneLabel.text:SetAllPoints(zoneLabel)
  end
  local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  local text = not AuDHDDB.fishZoneOff and hasPole() and levelText(zoneSkill(mapID)) or nil
  zoneValue = text
  zoneLabel.text:SetText(text or "")
  zoneLabel:SetShown(text ~= nil)
end
F.zoneText = function() return zoneValue end

-- the top right corner of the world map, for the zone it shows (pole or not; setting "fishMapOff")
local mapLabel, mapValue
local function showMap()
  local wm = WorldMapFrame
  if not wm then return end
  if not mapLabel then
    local sc = wm.ScrollContainer
    local parent = sc and sc.GetFrameLevel and sc or wm
    mapLabel = ns.newFrame("Fishing", "Frame", nil, parent)
    mapLabel:SetSize(240, 20)
    mapLabel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -8)
    mapLabel:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
    mapLabel.text = mapLabel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mapLabel.text:SetPoint("TOPRIGHT")
    mapLabel.text:SetJustifyH("RIGHT")
    -- the map can change while open (zooming out, the dropdown): looked at again 4 times a second
    local last, wait = nil, 0
    mapLabel:SetScript("OnUpdate", function(_, dt)
      wait = wait - dt
      if wait > 0 then return end
      wait = 0.25
      local id = wm.GetMapID and wm:GetMapID()
      if id ~= last then last = id showMap() end
    end)
    mapLabel.last = function() last = nil end
  end
  local id = not AuDHDDB.fishMapOff and wm.GetMapID and wm:GetMapID()
  local text = id and levelText(zoneSkill(id)) or nil
  mapValue = text
  mapLabel.text:SetText(text or "")
  mapLabel.text:SetShown(text ~= nil)
end
F.mapText = function() return mapValue end

function showLevels() showZone() showMap() end

-- what one-click fishing sees now: which part is missing when a click does nothing
local function status()
  local id = GetInventoryItemID("player", 16)
  local item = id and (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id) or GetItemInfo and GetItemInfo(id)) or nil
  local parts = {
    "on: " .. (isOn() and "yes" or "no"),
    "pole: " .. (hasPole() and "yes" or "no") .. (item and (" (" .. item .. ")") or id and "" or " (nothing in the main hand)"),
    "Fishing spell: " .. (knowsFishing() and "yes" or "no") .. " (" .. tostring(spellName()) .. ")",
    "button: " .. mouseKey(),
    "now: " .. (bound and bound:gsub("BUTTON%d", "") or "nothing bound") .. (fishingNow and ", line out" or ""),
    "in combat: " .. (InCombatLockdown() and "yes" or "no"),
    "set up: " .. (owner and castButton and "yes" or "no") .. ", cast: " .. tostring(castButton and castButton:GetAttribute("macrotext")),
  }
  if mouseKey() == "BUTTON2" and somethingThere() then parts[#parts + 1] = "the right button is left alone: something is under the cursor" end
  return "fishing: " .. table.concat(parts, "; ")
end

-- /wfn fish [on|off|right|middle|4|5|status|loud on|off|volume <10-100>|lure on|off|zone on|off|map on|off]
function F.command(arg)
  arg = (arg or ""):lower()
  if arg == "status" then return status() end
  local vol = tonumber(arg:match("^volume%s*(%d+)$"))
  if vol then
    vol = math.max(10, math.min(100, vol))
    AuDHDDB.fishVolume = vol ~= 100 and vol or nil
    -- already loud: just the new level (what to put back stays what it was)
    if AuDHDDB.fishSound and SetCVar then pcall(SetCVar, "Sound_SFXVolume", ("%.2f"):format(vol / 100)) end
    return ("splash volume %d%%"):format(vol)
  end
  for word, key in pairs({ lure = "fishLureOff", zone = "fishZoneOff", map = "fishMapOff" }) do
    local v = arg:match("^" .. word .. "%s*(%a*)$")
    if v then
      if v == "on" or v == "off" then AuDHDDB[key] = v == "off" or nil end
      showLevels()
      return ("fishing %s: %s"):format(word, AuDHDDB[key] and "off" or "on")
    end
  end
  local l = arg:match("^loud%s*(%a*)$")
  if l then
    if l == "on" or l == "off" then AuDHDDB.fishLoudOff = l == "off" or nil end
    if owner then watch() end
    return "louder splash with a pole: " .. (AuDHDDB.fishLoudOff and "off" or "on")
  end
  if arg == "on" or arg == "off" then AuDHDDB.fishOff = arg == "off" or nil end
  local pick = ({ right = "BUTTON2", middle = "BUTTON3", ["4"] = "BUTTON4", ["5"] = "BUTTON5" })[arg]
  if pick then AuDHDDB.fishButton = pick ~= "BUTTON2" and pick or nil end
  if owner then bound = nil watch() end
  local name
  for _, b in ipairs(F.BUTTONS) do if b[1] == mouseKey() then name = b[2] end end
  local state = isOn() and ("on, " .. name:lower()) or "off"
  if isOn() and not hasPole() then return "one-click fishing " .. state .. " (it works while a fishing pole is equipped)" end
  return "one-click fishing " .. state
end
function F.isOn() return isOn() end
function F.isLoud() return not AuDHDDB.fishLoudOff end
function F.volume() return AuDHDDB.fishVolume or 100 end
function F.lureOn() return not AuDHDDB.fishLureOff end
function F.zoneOn() return not AuDHDDB.fishZoneOff end
function F.mapOn() return not AuDHDDB.fishMapOff end
function F.button() return mouseKey() end
