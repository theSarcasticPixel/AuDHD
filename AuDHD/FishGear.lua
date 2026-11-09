-- Fishing gear: a small round button (drag it anywhere; a key for it in Key Bindings, AuDHD: Go fishing) puts on the
-- best fishing pole in your bags, and the next press puts your own weapons back. While a pole is in your hands (put on
-- by the button or by hand) the best +fishing piece in your bags goes on in each slot where it beats what you wear, and
-- what you wore goes back on when the pole comes off. What you wore is kept per character (AuDHDDB.fishGear), so a
-- reload or a crash while fishing can still put it back. Out of combat only, as the game allows.
-- Also the +fishing food or drink one-click fishing has you eat before the lure and the cast.
-- Items are told by their tooltips: a line naming Fishing with a number ("Equip:" for gear, "Use:" for food), so
-- nothing is listed by name.
local _, ns = ...
local G = {}
ns.fishGear = G
_G["BINDING_NAME_CLICK AuDHDGoFishing:LeftButton"] = "Go fishing / stop fishing"

local FISHING = 7620
local SLOT = { INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_CHEST = 5, INVTYPE_ROBE = 5,
               INVTYPE_WAIST = 6, INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_CLOAK = 15 }
local TWO = { INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 } }

local function say(msg) print("|cff66ccffAuDHD|r: " .. msg) end
local function log(e, t) if ns.log then ns.log.add(e, t) end end
function G.buttonOn() return not AuDHDDB.fishBtnOff end
function G.gearOn() return not AuDHDDB.fishGearOff end
function G.foodOn() return not AuDHDDB.fishFoodOff end

local function fishName()
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(FISHING) end
  return GetSpellInfo and GetSpellInfo(FISHING)
end
local function itemID(link) return link and tonumber(link:match("item:(%d+)")) end
local function info(item)
  local f = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
  if not (f and item) then return nil end
  local _, _, _, equipLoc, _, classID, subID = f(item)
  return equipLoc, classID, subID
end
local function isPole(link)
  local _, classID, subID = info(link)
  return classID == 2 and subID == 20
end
G.isPole = isPole
local function poleInHands() return isPole(GetInventoryItemLink("player", 16)) end

-- ------------------------------------------------------------------ reading tooltips
local scanTip
-- the lines of a tooltip: from C_TooltipInfo[api](...), else our own hidden tooltip's method of the same name
local function lines(api, ...)
  local out = {}
  local ti = C_TooltipInfo and C_TooltipInfo[api]
  if ti then
    local ok, data = pcall(ti, ...)
    if ok and type(data) == "table" and type(data.lines) == "table" then
      for _, l in ipairs(data.lines) do
        local c = type(l.leftColor) == "table" and l.leftColor or {}
        out[#out + 1] = { t = l.leftText or "", r = c.r or 1, g = c.g or 1, b = c.b or 1 }
      end
      return out
    end
  end
  if not CreateFrame then return out end
  if not scanTip then
    scanTip = ns.newFrame("FishGear", "GameTooltip", "AuDHDFishTip", nil, "GameTooltipTemplate")
    scanTip:SetOwner(WorldFrame or UIParent, "ANCHOR_NONE")
  end
  scanTip:ClearLines()
  if not (scanTip[api] and pcall(scanTip[api], scanTip, ...)) then return out end
  for i = 1, (scanTip:NumLines() or 0) do
    local fs = _G["AuDHDFishTipTextLeft" .. i]
    if fs and fs:GetText() then
      local r, g, b = fs:GetTextColor()
      out[#out + 1] = { t = fs:GetText(), r = r or 1, g = g or 1, b = b or 1 }
    end
  end
  return out
end
G.lines = lines

-- the +fishing a tooltip's lines give: the number next to the word Fishing, on a line past the item's name that isn't
-- a "Requires Fishing (n)" line; with use, only a "Use:" line. 0 when none.
local REQUIRES = (ITEM_MIN_SKILL or "Requires %s (%d)"):match("^(.-)%%") or ""
local function fishValue(ls, use)
  local word = fishName()
  if not word then return 0 end
  local useTag = ITEM_SPELL_TRIGGER_ONUSE
  for i = 2, #ls do
    local t = ls[i].t
    local s, e = t:find(word, 1, true)
    if s and not (REQUIRES ~= "" and t:sub(1, #REQUIRES) == REQUIRES)
        and not (use and useTag and t:sub(1, #useTag) ~= useTag) then
      local n = t:sub(e + 1):match("(%d+)") or t:sub(1, s - 1):match("(%d+)%D*$")
      if n then return tonumber(n) end
    end
  end
  return 0
end
G.fishValue = fishValue
-- a red line (a level or skill you don't have, armour you can't wear): the game won't let you put it on
local function saysNo(ls)
  for _, l in ipairs(ls) do if l.r > 0.9 and l.g < 0.25 and l.b < 0.25 then return true end end
  return false
end

local gearCache, foodCache = {}, {}   -- link -> { value, can wear }; item id -> value
local function gearValue(link)
  if not link then return 0, true end
  local c = gearCache[link]
  if not c then
    local ls = lines("GetHyperlink", link)
    c = { fishValue(ls), not saysNo(ls) }
    if #ls > 0 then gearCache[link] = c end
  end
  return c[1], c[2]
end

-- ------------------------------------------------------------------ bags
local function bags()
  local out = {}
  for b = 0, NUM_BAG_SLOTS or 4 do out[#out + 1] = b end
  return out
end
local function eachBagItem(fn)
  if not (C_Container and C_Container.GetContainerItemLink) then return end
  for _, b in ipairs(bags()) do
    for s = 1, (C_Container.GetContainerNumSlots(b) or 0) do
      local link = C_Container.GetContainerItemLink(b, s)
      if link and fn(link, b, s) then return end
    end
  end
end
-- where link is in your bags: the same link first, else the same item
local function findInBags(link)
  local at, near
  eachBagItem(function(l, b, s)
    if l == link then at = { b, s } return true end
    if not near and itemID(l) == itemID(link) then near = { b, s } end
  end)
  return at or near
end
local function freeSlot()
  if not C_Container then return nil end
  for _, b in ipairs(bags()) do
    local free, family = C_Container.GetContainerNumFreeSlots(b)
    if (free or 0) > 0 and (family or 0) == 0 then return b end
  end
end

-- the best pole in your bags: the most +fishing, any pole when none has a bonus
local function bestPole()
  local best, value
  eachBagItem(function(link)
    if isPole(link) then
      local v, ok = gearValue(link)
      if ok and (not best or v > value) then best, value = link, v end
    end
  end)
  return best, value
end
G.bestPole = bestPole
local function anyPole() return poleInHands() or bestPole() ~= nil end

-- ------------------------------------------------------------------ putting things on, one at a time
-- the game locks an item while it moves, so each change waits for the one before to show in its slot
local queue, current, tries, ticker = {}, nil, 0, nil
local failed = {}   -- links that wouldn't go on this session: not tried again
local function inSlot(slot, link)
  local now = GetInventoryItemLink("player", slot)
  if link == false then return now == nil end
  return now ~= nil and (now == link or itemID(now) == itemID(link))
end
local function equip(link, slot)
  local at = findInBags(link)
  if not at then return false end
  if CursorHasItem and CursorHasItem() then ClearCursor() end
  C_Container.PickupContainerItem(at[1], at[2])
  EquipCursorItem(slot)
  if CursorHasItem and CursorHasItem() then ClearCursor() return false end
  return true
end
local function unequip(slot)
  local b = freeSlot()
  if not b then return false end
  if CursorHasItem and CursorHasItem() then ClearCursor() end
  PickupInventoryItem(slot)
  if b == 0 then PutItemInBackpack()
  else
    local toInv = C_Container.ContainerIDToInventoryID or ContainerIDToInventoryID
    PutItemInBag(toInv(b))
  end
  if CursorHasItem and CursorHasItem() then ClearCursor() return false end
  return true
end
local check
local function step()
  if InCombatLockdown() then return end   -- (carried on after combat)
  if current then
    if inSlot(current.slot, current.link) then current = nil
    else
      tries = tries + 1
      if tries < 10 then return end
      if current.link then failed[current.link] = true end
      log("FISH_GEAR_FAILED", { slot = current.slot, link = current.link or "off" })
      current = nil
    end
  end
  while #queue > 0 do
    local a = table.remove(queue, 1)
    if not inSlot(a.slot, a.link) then
      local ok = a.link and equip(a.link, a.slot) or (a.link == false and unequip(a.slot))
      if ok then current, tries = a, 0 return end
      if a.link then failed[a.link] = true end
      if a.missing then say(a.missing) end
    end
  end
  if ticker then if ticker.Cancel then ticker:Cancel() end ticker = nil end
  C_Timer.After(0.2, function() check() end)
end
local function run()
  if #queue == 0 or ticker then return end
  ticker = C_Timer.NewTicker(0.2, step)
  step()
end
local function busy() return #queue > 0 or current ~= nil end
G.busy = busy

-- per character: weapons = the last ones that weren't a pole; worn = what fishing gear replaced, by slot (false: empty)
local function state()
  AuDHDDB.fishGear = AuDHDDB.fishGear or {}
  local key = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
  local s = AuDHDDB.fishGear[key] or {}
  AuDHDDB.fishGear[key] = s
  return s
end
G.state = state
local function rememberWeapons(s)
  if poleInHands() then return end
  s.weapons = { [16] = GetInventoryItemLink("player", 16) or false, [17] = GetInventoryItemLink("player", 17) or false }
end

-- the best +fishing piece in your bags for each slot where it beats what you wear
local function wear(s)
  local byLoc = {}
  eachBagItem(function(link)
    local loc = info(link)
    if (SLOT[loc] or TWO[loc]) and not failed[link] then
      local v, ok = gearValue(link)
      if v > 0 and ok then
        byLoc[loc] = byLoc[loc] or {}
        table.insert(byLoc[loc], { link = link, v = v })
      end
    end
  end)
  local function put(slot, link)
    s.worn = s.worn or {}
    if s.worn[slot] == nil then s.worn[slot] = GetInventoryItemLink("player", slot) or false end
    queue[#queue + 1] = { slot = slot, link = link }
  end
  for loc, list in pairs(byLoc) do
    table.sort(list, function(a, b) return a.v > b.v end)
    if SLOT[loc] then
      if list[1].v > gearValue(GetInventoryItemLink("player", SLOT[loc])) then put(SLOT[loc], list[1].link) end
    else
      -- two slots: the best piece where you wear the least
      local slots = {}
      for _, sl in ipairs(TWO[loc]) do slots[#slots + 1] = { sl = sl, v = gearValue(GetInventoryItemLink("player", sl)) } end
      table.sort(slots, function(a, b) return a.v < b.v end)
      for i = 1, 2 do
        if list[i] and list[i].v > slots[i].v then put(slots[i].sl, list[i].link) end
      end
    end
  end
end

-- what fishing gear replaced, back on (a slot that was empty: the fishing piece off, if there's room)
local function restoreGear(s)
  for slot, link in pairs(s.worn or {}) do
    if link then
      queue[#queue + 1] = { slot = slot, link = link, missing = "couldn't find " .. link .. " in your bags to put back on" }
    elseif gearValue(GetInventoryItemLink("player", slot)) > 0 then
      queue[#queue + 1] = { slot = slot, link = false }
    end
  end
  s.worn = nil
end

function check()
  if InCombatLockdown() or busy() or not AuDHDDB then return end
  local s = state()
  if poleInHands() then
    if G.gearOn() then wear(s) end
  else
    rememberWeapons(s)
    if s.worn then restoreGear(s) end
  end
  run()
  G.show()
end
G.check = check

-- the button: the best pole on, or your own weapons and gear back
function G.go()
  if InCombatLockdown() then return say("not in combat") end
  if busy() then return end
  local s = state()
  if poleInHands() then
    local w = s.weapons or {}
    if w[16] and findInBags(w[16]) then
      queue[#queue + 1] = { slot = 16, link = w[16] }
      if w[17] then queue[#queue + 1] = { slot = 17, link = w[17] } end
    else
      -- no weapon of yours to swap back: the pole into your bags
      if not freeSlot() then return say("no room in your bags for the fishing pole") end
      queue[#queue + 1] = { slot = 16, link = false }
    end
    restoreGear(s)
    log("FISH_GEAR", { go = "off" })
  else
    local pole = bestPole()
    if not pole then return say("no fishing pole in your bags") end
    if GetInventoryItemLink("player", 17) and not freeSlot() then
      return say("no room in your bags for your off-hand: the fishing pole takes both hands")
    end
    rememberWeapons(s)
    queue[#queue + 1] = { slot = 16, link = pole }
    log("FISH_GEAR", { go = "on" })
  end
  run()
end

-- ------------------------------------------------------------------ food
local function itemSpellName(id)
  local f = C_Item and C_Item.GetItemSpell
  return f and f(id) or nil
end
local function auraNames()
  local out = {}
  for i = 1, 40 do
    local name
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
      local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
      name = a and a.name
    elseif UnitBuff then
      name = UnitBuff("player", i)
    end
    if not name then break end
    out[#out + 1] = name
  end
  return out
end
-- a buff on you whose tooltip names Fishing
local function fishBuffOn()
  local word = fishName()
  if not word then return false end
  for i = 1, #auraNames() do
    for _, l in ipairs(lines("GetUnitBuff", "player", i)) do
      if l.t:find(word, 1, true) then return true end
    end
  end
  return false
end
local lastFood
-- the +fishing food or drink to have now (its item id), or "wait" while you're still eating it; nil for none
function G.food()
  if not G.foodOn() or not C_Container then return nil end
  if fishBuffOn() then return nil end
  local eating = lastFood and itemSpellName(lastFood)
  if eating then
    for _, n in ipairs(auraNames()) do if n == eating then return "wait" end end
  end
  local best, value
  eachBagItem(function(link)
    local id = itemID(link)
    local _, classID = info(link)
    if id and classID == 0 then
      local v = foodCache[id]
      if v == nil then
        local ls = lines("GetHyperlink", link)
        v = fishValue(ls, true)
        if #ls > 0 then foodCache[id] = v end
      end
      if v > 0 and (not best or v > value) then best, value = id, v end
    end
  end)
  lastFood = best or lastFood
  return best
end

-- ------------------------------------------------------------------ the button
local btn
local function makeButton()
  btn = ns.newFrame("FishGear", "Button", "AuDHDGoFishing", UIParent)
  btn:SetSize(31, 31)
  btn:SetFrameStrata("MEDIUM")
  btn:RegisterForClicks("LeftButtonUp")
  btn:SetMovable(true)
  btn:SetClampedToScreen(true)
  btn:RegisterForDrag("LeftButton")
  btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local bg = btn:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(20, 20)
  bg:SetPoint("TOPLEFT", 7, -5)
  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\Icons\\Trade_Fishing")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", bg, "CENTER")
  icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
  btn.icon = icon
  local border = btn:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  local pos = AuDHDDB.fishBtnPos
  if pos then btn:SetPoint(pos.p, UIParent, pos.rp, pos.x, pos.y)
  else btn:SetPoint("TOPRIGHT", Minimap, "BOTTOMLEFT", -4, -4) end
  btn:SetScript("OnDragStart", function(self) self:StartMoving() end)
  btn:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self.dragEnd = GetTime()
    local p, _, rp, x, y = self:GetPoint()
    AuDHDDB.fishBtnPos = { p = p, rp = rp, x = x, y = y }
  end)
  -- (the release that ends a drag isn't a press)
  btn:SetScript("OnClick", function(self)
    if self.dragEnd and GetTime() - self.dragEnd < 0.3 then return end
    G.go()
  end)
  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(poleInHands() and "Stop fishing" or "Go fishing")
    GameTooltip:AddLine(poleInHands() and "Your own weapons and gear back on"
      or "The best fishing pole in your bags on, and your +fishing gear", 1, 1, 1, true)
    GameTooltip:AddLine("Drag to move", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
-- shown while a pole is in your hands or your bags
function G.show()
  if not btn then return end
  btn:SetShown(G.buttonOn() and anyPole())
  if poleInHands() then btn:LockHighlight() else btn:UnlockHighlight() end
end

local f = ns.newFrame("FishGear", "Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED" }) do f:RegisterEvent(e) end
f:SetScript("OnEvent", function(_, e)
  if e == "PLAYER_LOGIN" then makeButton() end
  if e == "PLAYER_REGEN_ENABLED" and busy() then return run() end
  -- (several changes come at once: looked at once they've settled)
  C_Timer.After(0.3, check)
end)
