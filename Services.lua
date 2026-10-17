-- Reminders when you pass a service (the user, 2026-10-17): bags full or nearly full within 100 yards of a vendor -
-- sell; class skills to learn within 100 yards of your class trainer - train. Once per visit: it comes back after you've
-- been 200 yards away (or when it changes: bags filling up again, a new level's skills).
local _, ns = ...
local M = {}
ns.services = M
local log = function(e, f) if ns.log then ns.log.add(e, f) end end
local isSecret = issecretvalue or function() return false end

local NEAR, AWAY = 100, 200

-- world positions (yards), cached per entry
local function worldPos(m, x, y)
  local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, m, CreateVector2D(x, y))
  if not ok or not pos then return nil end
  local wx, wy = pos:GetXY()
  return cont, wx, wy
end
local function placeOf(e)
  if e.c == nil then
    local c, wx, wy = worldPos(e.m, e.x / 100, e.y / 100)
    e.c, e.wx, e.wy = c or false, wx, wy
  end
  return e.c and e
end
local function player()
  local m = C_Map.GetBestMapForUnit("player")
  if not m or isSecret(m) then return nil end
  local p = C_Map.GetPlayerMapPosition(m, "player")
  if not p then return nil end
  local px, py = p:GetXY()
  if isSecret(px) then return nil end
  local c, wx, wy = worldPos(m, px, py)
  return c and { c = c, wx = wx, wy = wy }
end
local function nearest(list, P)
  local best, bd
  for _, e in ipairs(list or {}) do
    local w = placeOf(e)
    if w and w.c == P.c then
      local dx, dy = w.wx - P.wx, w.wy - P.wy
      local d = math.sqrt(dx * dx + dy * dy)
      if not bd or d < bd then best, bd = e, d end
    end
  end
  return best, bd
end

-- plain bags only (no quivers or ammo pouches): free slots and all slots
function M.bagSpace()
  local free, total = 0, 0
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    local n = C_Container.GetContainerNumSlots(bag) or 0
    local f, fam = C_Container.GetContainerNumFreeSlots(bag)
    if n > 0 and (not fam or fam == 0) then free, total = free + (f or 0), total + n end
  end
  return free, total
end
-- nearly full: 2 slots or a tenth of your bags left, whichever is more
function M.bagsFull()
  local free, total = M.bagSpace()
  return total > 0 and free <= math.max(2, math.floor(total / 10)), free
end

-- skills to learn now: what the Ammo module keeps back for them, when it's for your level
function M.skillsOwed()
  if not (ns.ammo and ns.ammo.trainReserve) then return false end
  local ok, cost, forLevel = pcall(ns.ammo.trainReserve)
  return ok and cost and cost > 0 and forLevel == UnitLevel("player") or false
end

-- a pop-up per kind, with Go to (your /way arrow to it) and Ignore (not again for IGNORE seconds). Said once per visit;
-- passing from one vendor to the next only changes its text (the user, 2026-10-17: "when getting a vendor notification
-- they get a bit spammy, have it be a pop-up that you can click go to > ignore - if you hit ignore it doesn't come up
-- again for 2 minutes")
local IGNORE = 120
local shown = {}     -- kind -> { e = the service, key = what was said }
local ignored = {}   -- kind -> GetTime() until which it stays quiet
local pops = {}      -- kind -> its pop-up frame
local SLOT = { vendor = 0, trainer = 1 }
local function popup(kind)
  if pops[kind] then return pops[kind] end
  local f = ns.newFrame("Services", "Frame", "AuDHDService_" .. kind, UIParent, "BackdropTemplate")
  f:SetSize(300, 64)
  f:SetPoint("TOP", UIParent, "TOP", 0, -230 - 70 * (SLOT[kind] or 0))
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.05, 0.05, 0.1, 0.92)
  end
  f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.text:SetPoint("TOP", 0, -10)
  f.text:SetWidth(284)
  local function button(label, x, onClick)
    local b = ns.newFrame("Services", "Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(90, 20)
    b:SetPoint("BOTTOM", f, "BOTTOM", x, 8)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
  end
  f.go = button("Go to", -50, function()
    local s = shown[kind]
    if s and ns.way then ns.way.set(s.e.m, s.e.x, s.e.y, s.e.n) end
    log("SERVICE_GOTO", { kind = kind, npc = s and s.e.n })
    f.open = false f:Hide()
  end)
  f.ignore = button("Ignore", 50, function()
    ignored[kind] = GetTime() + IGNORE
    log("SERVICE_IGNORE", { kind = kind })
    f.open = false f:Hide()
  end)
  f:Hide()
  pops[kind] = f
  return f
end
local function remind(kind, e, d, key, text)
  if ignored[kind] and GetTime() < ignored[kind] then return end
  local s = shown[kind]
  if s and s.key == key then
    -- the same thing to say: only the nearest place and the yards change, quietly
    s.e = e
    if pops[kind] then pops[kind].msg = text pops[kind].text:SetText(text) end
    return
  end
  shown[kind] = { e = e, key = key }
  local f = popup(kind)
  f.msg, f.open = text, true
  f.text:SetText(text)
  f:Show()
  PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
  log("SERVICE_NEAR", { kind = kind, npc = e.n, yd = math.floor(d), key = key })
end
local function drop(kind)
  shown[kind] = nil
  if pops[kind] then pops[kind].open = false pops[kind]:Hide() end
end
local function forget(kind, P)
  local s = shown[kind]
  if not s then return end
  local w = placeOf(s.e)
  if not w or w.c ~= P.c or math.sqrt((w.wx - P.wx) ^ 2 + (w.wy - P.wy) ^ 2) > AWAY then drop(kind) end
end
-- the smoke test: what a pop-up says (nil when it's not up), and its buttons
function M.popupText(kind) local f = pops[kind] return f and f.open and f.msg or nil end
function M.click(kind, which)
  local b = pops[kind] and pops[kind][which]
  local fn = b and (b.scripts and b.scripts.OnClick or b:GetScript("OnClick"))
  if fn then fn(b) end
end

function M.check()
  if UnitOnTaxi and UnitOnTaxi("player") then return end
  local P = player()
  if not P then return end
  forget("vendor", P)
  forget("trainer", P)
  local full, free = M.bagsFull()
  if full then
    local v, d = nearest(ns.vendors, P)
    if v and d <= NEAR then
      remind("vendor", v, d, "full", ("Bags %s (%d free): sell at %s, %d yd"):format(free == 0 and "full" or "nearly full", free, v.n, math.floor(d)))
    end
  elseif shown.vendor then
    drop("vendor")
  end
  if M.skillsOwed() then
    local _, class = UnitClass("player")
    local cur = ns.core and ns.core.current and ns.core.current()
    local t, d = nearest(ns.classTrainers and ns.classTrainers[class], P)
    -- the route's own "Train at" step says it already
    if t and d <= NEAR and not (cur and cur.k == "train") then
      remind("trainer", t, d, "lv" .. UnitLevel("player"), ("Skills to learn: %s is %d yd away"):format(t.n, math.floor(d)))
    end
  elseif shown.trainer then
    drop("trainer")
  end
end

local frame = ns.newFrame("Services", "Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
  C_Timer.NewTicker(2, function() pcall(M.check) end)
end)
