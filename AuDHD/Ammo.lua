-- Ammo (Hunters): how many arrows / bullets you carry, a warning when it runs low (with the nearest vendor that sells
-- your kind), "/audhd ammo" to point the arrow at that vendor, and buying back up at a vendor (setting auto.ammo, on by
-- default: as much as your quiver or ammo pouch holds, else AuDHDDB.ammoTarget, else 1000; never spending what
-- your next class skills cost, unless you say so in the popup that tells you). Our own frames and the merchant API
-- only: nothing protected.
local _, ns = ...
local M = {}
ns.ammo = M

local WARN, CRITICAL = 200, 50
local log = function(e, f) if ns.log then ns.log.add(e, f) end end

-- the ammo your ranged weapon fires: "arrow" (bows, crossbows), "bullet" (guns), or nil (no ranged weapon)
function M.kind()
  for _, slot in ipairs({ 18, 16 }) do
    local link = GetInventoryItemLink("player", slot)
    if link then
      local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(link)
      if classID == 2 then
        if subID == 2 or subID == 18 then return "arrow" end
        if subID == 3 then return "bullet" end
      end
    end
  end
end

-- how many of that kind you carry (all bags; projectiles are item class 6: 2 arrows, 3 bullets)
function M.count(kind)
  kind = kind or M.kind()
  if not kind then return nil end
  local want = kind == "arrow" and 2 or 3
  local n = 0
  for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID then
        local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(info.itemID)
        if classID == 6 and subID == want then n = n + (info.stackCount or 1) end
      end
    end
  end
  return n
end

-- what your quivers / ammo pouches hold (slots x stack), or nil when you have none; bag families: 1 arrows, 2 bullets
function M.capacity(kind, stack)
  kind = kind or M.kind()
  local bit = kind == "bullet" and 2 or 1
  local slots = 0
  for bag = 1, (NUM_BAG_SLOTS or 4) do
    local n = C_Container.GetContainerNumSlots(bag) or 0
    local _, fam = C_Container.GetContainerNumFreeSlots(bag)
    if n > 0 and fam and math.floor(fam / bit) % 2 == 1 then slots = slots + n end
  end
  return slots > 0 and slots * (stack or 200) or nil
end
-- how many to carry: your own /audhd setting, else a full quiver, else 1000
function M.target(kind, stack)
  return AuDHDDB.ammoTarget or M.capacity(kind, stack) or 1000
end

-- ------------------------------------------------------------------ what the next class skills cost
-- kept back from ammo. The trainer's real prices once you've seen a trainer (it lists the ones you can't learn yet
-- too), else a rough guess (5c x level^2 a spell: ~7s at 12, 20s at 20, 80s at 40).
local function known(id)
  if IsPlayerSpell then local ok, k = pcall(IsPlayerSpell, id) if ok and k ~= nil then return k end end
  if IsSpellKnown then local ok, k = pcall(IsSpellKnown, id) if ok then return k end end
end
local function priceAt(lv)
  local seen = AuDHDDB.trainCost and AuDHDDB.trainCost[lv]
  return seen or 5 * lv * lv
end
-- copper, and the level it's for: spells of your level and below you haven't bought (what the trainer listed as
-- available when you last saw one at this level; else the spell list), else the next level that brings new ones
function M.trainReserve()
  local _, class = UnitClass("player")
  local list = ns.classSpells and ns.classSpells[class]
  if not list then return 0 end
  local level = UnitLevel("player")
  local seen = AuDHDDB.trainOwed
  local visited = seen and seen.lv or 0
  local owed, next = seen and seen.lv == level and seen.c or 0, nil
  for _, r in ipairs(list) do
    local lv, id = r[1], r[2]
    if lv <= level then
      if lv > visited and known(id) == false then owed = owed + priceAt(lv) end
    elseif not next or lv < next then next = lv end
  end
  if owed > 0 then return owed, level end
  if not next then return 0 end
  local cost = 0
  for _, r in ipairs(list) do if r[1] == next and known(r[2]) ~= true then cost = cost + priceAt(next) end end
  return cost, next
end
-- at a trainer: what one spell costs at each level (the most a spell costs there: ranks of the same level vary little)
local function readTrainer()
  if not (GetNumTrainerServices and GetTrainerServiceCost and GetTrainerServiceLevelReq) then return end
  local seen, owed = {}, 0
  for i = 1, (GetNumTrainerServices() or 0) do
    local _, _, cat = GetTrainerServiceInfo(i)
    local lv, cost = GetTrainerServiceLevelReq(i), GetTrainerServiceCost(i)
    if cat ~= "header" and lv and cost and cost > 0 then seen[lv] = math.max(seen[lv] or 0, cost) end
    -- what you could buy now and haven't
    if cat == "available" and cost then owed = owed + cost end
  end
  AuDHDDB.trainOwed = { lv = UnitLevel("player"), c = owed }
  if next(seen) then
    AuDHDDB.trainCost = AuDHDDB.trainCost or {}
    for lv, c in pairs(seen) do AuDHDDB.trainCost[lv] = c end
  end
end

-- the nearest vendor that sells your kind (same continent), with its distance
function M.nearestVendor(kind)
  kind = kind or M.kind()
  if not kind or not ns.ammoVendors then return nil end
  local best, bd
  for _, v in ipairs(ns.ammoVendors) do
    if (kind == "arrow" and v.a) or (kind == "bullet" and v.b) then
      local d = ns.core.bearing({ m = v.m, x = v.x, y = v.y })
      if d and (not bd or d < bd) then best, bd = v, d end
    end
  end
  return best, bd
end

-- the line the route window shows, and the warning when it's low
local warnedAt
function M.status()
  local kind = M.kind()
  if not kind then return nil end
  local n = M.count(kind) or 0
  local colour = n < CRITICAL and "ff4040" or n < WARN and "ffd040" or "aaaaaa"
  local text = ("|cff%s%ss: %d|r"):format(colour, kind == "arrow" and "Arrow" or "Bullet", n)
  if n < WARN then
    local v, d = M.nearestVendor(kind)
    if v then text = text .. ("  |cff%sbuy at %s, %d yd (/audhd ammo)|r"):format(colour, v.n, math.floor(d)) end
  end
  return text, n, kind
end

function M.check()
  local _, n, kind = M.status()
  if not n then return end
  local level = n < CRITICAL and CRITICAL or n < WARN and WARN or nil
  if level and warnedAt ~= level then
    warnedAt = level
    local v = M.nearestVendor(kind)
    local msg = ("Low on %ss: %d left%s"):format(kind, n, v and (" - nearest vendor " .. v.n) or "")
    UIErrorsFrame:AddMessage(msg, 1, level == CRITICAL and 0.25 or 0.8, 0.2)
    if level == CRITICAL then ns.playAlert() end
    log("AMMO_LOW", { kind = kind, count = n })
  elseif not level then
    warnedAt = nil
  end
end

-- point the arrow at the nearest vendor until you buy (or /audhd ammo off)
function M.goVendor(off)
  if off then ns.core.override = nil; return ns.arrow and "the arrow follows the route again" or "ammo: nothing to stop" end
  local v, d = M.nearestVendor()
  if not v then return "no ammo vendor known nearby" end
  if not ns.arrow then return ("the nearest ammo vendor: %s (%d yd)"):format(v.n, math.floor(d or 0)) end
  ns.core.override = { m = v.m, x = v.x, y = v.y, t = "Buy ammo from " .. v.n }
  return ("arrow points at %s (%d yd); /audhd ammo off to go back to the route"):format(v.n, math.floor(d or 0))
end

local function coins(c) return ns.services and ns.services.coins and ns.services.coins(c) or (c .. "c") end
local function buyN(i, qty)
  local bought = 0
  while bought < qty do
    local n = math.min(qty - bought, 200)
    BuyMerchantItem(i, n)
    bought = bought + n
  end
  return bought
end
-- money held back left you short: a popup says how many and why, and Buy anyway gets the rest (as much as you can pay)
local held
StaticPopupDialogs.AUDHD_AMMO_ANYWAY = {
  text = "%s", button1 = "Buy anyway", button2 = "Not now",
  OnAccept = function() M.buyAnyway() end,
  timeout = 0, whileDead = 1, hideOnEscape = 1,
}
function M.buyAnyway()
  local h = held
  held = nil
  if not (h and MerchantFrame and MerchantFrame:IsShown() and GetMerchantItemLink(h.i) == h.link) then
    print("|cff66ccffAuDHD|r: the vendor's window closed, so no ammo was bought")
    return 0
  end
  local qty = h.perItem > 0 and math.min(h.left, math.floor(GetMoney() / h.perItem)) or h.left
  if qty <= 0 then return 0 end
  local bought = buyN(h.i, qty)
  log("AMMO_BOUGHT", { kind = h.kind, item = h.link, count = bought, copper = math.floor(bought * h.perItem), anyway = true })
  return bought
end
M.held = function() return held end   -- (the smoke test)
local function holdBack(h, bought)
  local why = {}
  if h.reserve > 0 then
    why[#why + 1] = coins(h.reserve) .. (h.forLevel and h.forLevel > UnitLevel("player")
      and (" for your level " .. h.forLevel .. " class skills") or " for the class skills you haven't trained yet")
  end
  if h.weapon then why[#why + 1] = coins(h.weapon) .. " for the weapon your route buys next" end
  local name = h.kind == "arrow" and "arrows" or "bullets"
  local head = bought > 0 and ("Bought %d of the %d %s you need."):format(bought, bought + h.left, name)
    or ("Didn't buy %s."):format(name)
  local reason = #why > 0 and (" AuDHD keeps " .. table.concat(why, " and ") .. ".") or ""
  local anyway = math.min(h.left, h.perItem > 0 and math.floor(GetMoney() / h.perItem) or h.left)
  if anyway <= 0 then
    print(("|cff66ccffAuDHD|r: %s%s You can't pay for more."):format(head, reason))
    return
  end
  held = h
  StaticPopup_Show("AUDHD_AMMO_ANYWAY", ("%s%s\n\nBuy %d more anyway, for %s?"):format(head, reason, anyway,
    coins(math.ceil(anyway * h.perItem))))
end

-- at a vendor: buy the best ammo of your kind you can use, up to the target
local function autoBuy()
  held = nil
  local on = AuDHDDB.auto and AuDHDDB.auto.ammo
  if on == false or IsShiftKeyDown() then return end
  local kind = M.kind()
  if not kind then return end
  local want = kind == "arrow" and 2 or 3
  local best, bestReq
  for i = 1, (GetMerchantNumItems() or 0) do
    local link = GetMerchantItemLink(i)
    if link then
      local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(link)
      local _, _, _, _, minLevel = C_Item.GetItemInfo(link)
      if classID == 6 and subID == want and (minLevel or 0) <= UnitLevel("player") and (not bestReq or (minLevel or 0) > bestReq) then
        best, bestReq = i, minLevel or 0
      end
    end
  end
  if not best then return end
  local stackMax = select(8, C_Item.GetItemInfo(GetMerchantItemLink(best)))
  local target = M.target(kind, stackMax)
  local have = M.count(kind) or 0
  if have >= target then return end
  local info = C_MerchantFrame and C_MerchantFrame.GetItemInfo and C_MerchantFrame.GetItemInfo(best)
  local price, stack = info and info.price, info and info.stackCount
  if not price then local _, _, p, s = GetMerchantItemInfo(best); price, stack = p, s end
  stack = (stack and stack > 0) and stack or 1
  local need = target - have
  local perItem = (price or 0) / stack
  local budget, weapon = GetMoney(), nil
  for k = 0, 3 do
    local s = ns.core.peek(k)
    if s and s.k == "buyweapon" and s.pc then budget, weapon = budget - s.pc, s.pc; break end
  end
  local reserve, forLevel = M.trainReserve()
  budget = budget - reserve
  -- but never short of arrows to earn that money with: up to 1000 (or a smaller quiver) while they cost under a quarter
  -- of your money, else a couple of hundred to kill with while you save up
  local floor = math.min(target, 1000)
  local floorCost = (floor - have) * perItem
  if have < floor and budget < floorCost and floorCost <= GetMoney() / 4 then budget = floorCost
  elseif budget < 0 and have < 200 then budget = 200 * perItem end
  local affordable = perItem > 0 and math.floor(math.max(budget, 0) / perItem) or need
  local qty = math.max(0, math.min(need, affordable))
  local h = { i = best, link = GetMerchantItemLink(best), kind = kind, perItem = perItem, left = need - qty,
              reserve = reserve, forLevel = forLevel, weapon = weapon }
  if qty <= 0 then
    log("AMMO_CANT_AFFORD", { kind = kind, need = need, reserve = reserve, forLevel = forLevel })
    holdBack(h, 0)
    return
  end
  local bought = buyN(best, qty)
  if h.left > 0 then holdBack(h, bought) end
  log("AMMO_BOUGHT", { kind = kind, item = GetMerchantItemLink(best), count = bought, copper = math.floor(bought * perItem),
    target = target, reserve = reserve, forLevel = forLevel })
  if ns.core.override and ns.core.override.t and ns.core.override.t:find("^Buy ammo") then ns.core.override = nil end
end

local frame = ns.newFrame("Ammo", "Frame")
frame:SetScript("OnEvent", function(_, event)
  if event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
    pcall(readTrainer)
  elseif event == "MERCHANT_SHOW" then
    local ok, err = pcall(autoBuy)
    if not ok then log("AMMO_ERROR", { err = tostring(err) }) end
  elseif event == "MERCHANT_CLOSED" then
    held = nil
    if StaticPopup_Hide then StaticPopup_Hide("AUDHD_AMMO_ANYWAY") end
  else
    pcall(M.check)
    if ns.ui then ns.ui.refresh() end
  end
end)
function M.enable()
  for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "TRAINER_SHOW", "TRAINER_UPDATE" }) do pcall(frame.RegisterEvent, frame, e) end
  pcall(M.check)
end
