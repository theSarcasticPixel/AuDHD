-- Automation: accept and turn in quests (the way Questie does it: gossip and quest-greeting windows, non-trivial quests,
-- the reward taken only when there's no choice, or the route's planned weapon), sell grey items and repair at
-- vendors. Hold Shift to pause it at any NPC. Settings: AuDHDDB.auto (/wfn auto ...). Everything is logged.
local _, ns = ...
local A = {}
ns.auto = A

-- reward: "value" = an upgrade if one of the choices is, else the one that sells for most; "manual" = you choose
A.DEFAULTS = { accept = true, complete = true, junk = true, repair = true, reward = "value", ammo = true }
local function on(key)
  local s = AuDHDDB and AuDHDDB.auto
  if s and s[key] ~= nil then return s[key] end
  return A.DEFAULTS[key]
end
local function paused() return IsShiftKeyDown() end
local log = function(e, f) if ns.log then ns.log.add(e, f) end end

-- a guard against loops at one NPC (a quest the game keeps offering that we can't take): at most 12 actions in 5 s
local burst, burstStart = 0, 0
local function allowed()
  local now = GetTime()
  if now - burstStart > 5 then burst, burstStart = 0, now end
  burst = burst + 1
  return burst <= 12
end

-- ------------------------------------------------------------------ quests
local handlers = {}

-- seconds between tries: 1.5 x your latency (home or world, the larger), at least 0.15 s
local function retryGap()
  local _, _, home, world = GetNetStats()
  local ms = math.max(home or 0, world or 0)
  return math.max(0.15, ms * 1.5 / 1000)
end
local MAX_TRIES = 6
local function windowOpen(name)
  local f = _G[name]
  return not f or f:IsShown()   -- unknown frame: assume open (the tries are few)
end
-- run attempt(try) now and again until it says it acted (true) or the window closes or the tries run out
local function withRetries(event, window, attempt)
  local gap = retryGap()
  local function go(try)
    if paused() or not windowOpen(window) then return end
    local acted, seen = attempt(try)
    if acted then
      if try > 1 then log("AUTO_RETRY_OK", { event = event, try = try, gap = gap, seen = seen }) end
      return
    end
    if try < MAX_TRIES then C_Timer.After(gap, function() go(try + 1) end)
    else log("AUTO_GAVE_UP", { event = event, tries = try, gap = gap, seen = seen }) end
  end
  go(1)
end

function handlers.GOSSIP_SHOW()
  if paused() or not C_GossipInfo then return end
  withRetries("GOSSIP_SHOW", "GossipFrame", function()
    local active, avail = C_GossipInfo.GetActiveQuests() or {}, C_GossipInfo.GetAvailableQuests() or {}
    local seen = { active = #active, available = #avail }
    if on("complete") then
      for _, q in ipairs(active) do
        if q.isComplete and allowed() then C_GossipInfo.SelectActiveQuest(q.questID) return true, seen end
      end
    end
    if on("accept") then
      for _, q in ipairs(avail) do
        if not q.isTrivial and not q.repeatable and allowed() then C_GossipInfo.SelectAvailableQuest(q.questID) return true, seen end
      end
    end
    -- nothing to do: done if the lists came through (an NPC with only incomplete or trivial quests), else look again
    return #active + #avail > 0, seen
  end)
end

function handlers.QUEST_GREETING()
  if paused() then return end
  withRetries("QUEST_GREETING", "QuestFrame", function()
    local nActive, nAvail = GetNumActiveQuests() or 0, GetNumAvailableQuests() or 0
    local seen = { active = nActive, available = nAvail }
    if on("complete") then
      for i = 1, nActive do
        local _, isComplete = GetActiveTitle(i)
        if isComplete and allowed() then SelectActiveQuest(i) return true, seen end
      end
    end
    if on("accept") then
      for i = 1, nAvail do
        local isTrivial, _, isRepeatable = GetAvailableQuestInfo(i)
        if not isTrivial and not isRepeatable and allowed() then SelectAvailableQuest(i) return true, seen end
      end
    end
    return nActive + nAvail > 0, seen
  end)
end

function handlers.QUEST_DETAIL()
  if paused() or not on("accept") then return end
  -- the quest's ID is 0 until the server's details arrive: wait for them
  withRetries("QUEST_DETAIL", "QuestFrame", function()
    local id = GetQuestID()
    if not id or id == 0 then return false, { questID = 0 } end
    AcceptQuest()
    return true, { questID = id }
  end)
end

function handlers.QUEST_ACCEPT_CONFIRM()
  if paused() or not on("accept") then return end
  ConfirmAcceptQuest()
end

function handlers.QUEST_PROGRESS()
  if paused() or not on("complete") then return end
  withRetries("QUEST_PROGRESS", "QuestFrame", function()
    if IsQuestCompletable() then CompleteQuest() return true end
    return false
  end)
end

A.PROFESSION_BOOKS = { [247840] = true, [247841] = true, [247846] = true }   -- Mining, Herbalism, Skinning
function handlers.QUEST_COMPLETE()
  if paused() or not on("complete") then return end
  local n = GetNumQuestChoices() or 0
  if n <= 1 then GetQuestReward(1) return end   -- as Questie does: 1 also works when there's no choice
  -- a profession book among the rewards (Mining, Herbalism, Skinning): always yours to choose, never picked for you
  -- (the user, 2026-10-23: "right now they all take mining which not everyone will do")
  for i = 1, n do
    local link = GetQuestItemLink and GetQuestItemLink("choice", i)
    local id = link and tonumber(link:match("item:(%d+)"))
    if id and A.PROFESSION_BOOKS[id] then
      log("REWARD_CHOICE_OFFERED", { q = GetQuestID(), why = "profession book" })
      return
    end
  end
  -- several rewards: the route's planned weapon, else you choose (and the choices are logged)
  local want = ns.core and ns.core.plannedReward and ns.core.plannedReward(GetQuestID())
  local choices = {}
  for i = 1, n do
    local name = GetQuestItemInfo("choice", i)
    choices[i] = name
    if want and name == want then
      log("AUTO_REWARD", { q = GetQuestID(), took = name })
      GetQuestReward(i)
      return
    end
  end
  if on("reward") == "value" then
    local i, why, rows = A.pickReward(n)
    if i then
      log("AUTO_REWARD", { q = GetQuestID(), took = choices[i], why = why, choices = rows })
      GetQuestReward(i)
      return
    end
    log("REWARD_CHOICE_OFFERED", { q = GetQuestID(), choices = choices, why = why })
    return
  end
  log("REWARD_CHOICE_OFFERED", { q = GetQuestID(), choices = choices })
end

-- ------------------------------------------------------------------ choosing a reward
-- inventory slots for an equip location
local SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 }, INVTYPE_CHEST = { 5 },
  INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
  INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
  INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
  INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18, 16 }, INVTYPE_RANGEDRIGHT = { 18, 16 },
  INVTYPE_THROWN = { 18 }, INVTYPE_TABARD = { 19 },
}
-- the game's stat names -> ForeverDB's stat IDs (the same table ForeverDB's addon uses)
local STAT = {
  ITEM_MOD_AGILITY_SHORT = 3, ITEM_MOD_STRENGTH_SHORT = 4, ITEM_MOD_INTELLECT_SHORT = 5, ITEM_MOD_SPIRIT_SHORT = 6,
  ITEM_MOD_STAMINA_SHORT = 7, ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = 12, ITEM_MOD_DODGE_RATING_SHORT = 13,
  ITEM_MOD_PARRY_RATING_SHORT = 14, ITEM_MOD_BLOCK_RATING_SHORT = 15, ITEM_MOD_HIT_RATING_SHORT = 31,
  ITEM_MOD_HIT_MELEE_RATING_SHORT = 31, ITEM_MOD_HIT_RANGED_RATING_SHORT = 31, ITEM_MOD_HIT_SPELL_RATING_SHORT = 31,
  ITEM_MOD_CRIT_RATING_SHORT = 32, ITEM_MOD_CRIT_MELEE_RATING_SHORT = 32, ITEM_MOD_CRIT_RANGED_RATING_SHORT = 32,
  ITEM_MOD_CRIT_SPELL_RATING_SHORT = 32, ITEM_MOD_HASTE_RATING_SHORT = 36, ITEM_MOD_EXPERTISE_RATING_SHORT = 37,
  ITEM_MOD_ATTACK_POWER_SHORT = 38, ITEM_MOD_RANGED_ATTACK_POWER_SHORT = 39, ITEM_MOD_SPELL_HEALING_DONE_SHORT = 41,
  ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 42, ITEM_MOD_MANA_REGENERATION_SHORT = 43, ITEM_MOD_POWER_REGEN0_SHORT = 43,
  ITEM_MOD_SPELL_POWER_SHORT = 45, ITEM_MOD_SPELL_PENETRATION_SHORT = 47, ITEM_MOD_BLOCK_VALUE_SHORT = 48,
}
local RANGED_LOC = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }

-- your spec's weights: AuDHDDB.spec (/wfn spec), else the class's first spec in ForeverDB's list
function A.spec()
  local _, class = UnitClass("player")
  local specs = ns.weights and ns.weights[class] or {}
  local want = AuDHDDB and AuDHDDB.spec
  for _, sp in ipairs(specs) do if want and sp.name:lower() == want:lower() then return sp end end
  return specs[1]
end

-- an item's value for your spec: its stats x weights, plus weapon DPS x the DPS weight when the weapon fits the
-- spec's role (ranged weapons for ranged DPS, melee weapons otherwise)
function A.score(link)
  if not link then return 0 end
  local sp = A.spec()
  if not sp then return 0 end
  local ok, stats = pcall(C_Item.GetItemStats, link)
  if not ok or type(stats) ~= "table" then return 0 end
  local total = 0
  for k, v in pairs(stats) do
    local id = STAT[k]
    if id and sp.w[id] then total = total + sp.w[id] * v end
  end
  local dps = stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT
  if dps and sp.w.dps then
    local _, _, _, loc = C_Item.GetItemInfoInstant(link)
    local ranged = RANGED_LOC[loc] or false
    if ranged == (sp.role == "Ranged DPS") then total = total + sp.w.dps * dps
    -- the other kind of weapon still matters (a Hunter melees what reaches them): a quarter of the weight (a guess)
    else total = total + 0.25 * sp.w.dps * dps end
  end
  return total
end

-- an item's tooltip lines: { text, r, g, b } (left and right halves each), from C_TooltipInfo, else from reading a
-- hidden tooltip of our own (Forever may not have C_TooltipInfo)
local scanTip
local function tooltipLines(link)
  local out = {}
  if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
    local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
    if ok and type(data) == "table" and type(data.lines) == "table" then
      for _, line in ipairs(data.lines) do
        for _, half in ipairs({ { line.leftText, line.leftColor }, { line.rightText, line.rightColor } }) do
          local c = type(half[2]) == "table" and half[2] or {}
          if half[1] or half[2] then out[#out + 1] = { t = half[1] or "", r = c.r or 1, g = c.g or 1, b = c.b or 1 } end
        end
      end
      return out
    end
  end
  if not CreateFrame then return out end
  if not scanTip then
    scanTip = ns.newFrame("Auto", "GameTooltip", "AuDHDScanTip", nil, "GameTooltipTemplate")
    scanTip:SetOwner(WorldFrame or UIParent, "ANCHOR_NONE")
  end
  scanTip:ClearLines()
  if not pcall(scanTip.SetHyperlink, scanTip, link) then return out end
  for i = 1, (scanTip:NumLines() or 0) do
    for _, side in ipairs({ "Left", "Right" }) do
      local fs = _G["AuDHDScanTip" .. side .. i]
      if fs and fs:IsShown() and fs:GetText() then
        local r, g, b = fs:GetTextColor()
        out[#out + 1] = { t = fs:GetText(), r = r or 1, g = g or 1, b = b or 1 }
      end
    end
  end
  return out
end

-- the game's own answer: a red line on the item's tooltip (a weapon skill you haven't trained, a level you haven't
-- reached, an armor type you can't wear) means you can't use it
local function tooltipSaysNo(link)
  for _, l in ipairs(tooltipLines(link)) do
    if l.r > 0.9 and l.g < 0.25 and l.b < 0.25 then return true end
  end
  return false
end

-- ------------------------------------------------------------------ bags and quivers
-- a bag's slots ("12 Slot Quiver") and its family (bits: 1 arrows, 2 bullets; 0 any item)
local function bagInfo(link)
  local slots
  for _, l in ipairs(tooltipLines(link)) do
    slots = slots or tonumber(l.t:match("(%d+) Slot"))
  end
  local fam = (C_Item.GetItemFamily and C_Item.GetItemFamily(link)) or (GetItemFamily and GetItemFamily(link)) or 0
  return slots, fam
end
local function isAmmoBag(fam) return fam and fam % 4 > 0 end
-- what you carry now: your biggest ammo bag (0: none) and your smallest plain bag (0: an empty bag slot)
local function bagsNow()
  local quiver, smallest = 0, nil
  for bag = 1, (NUM_BAG_SLOTS or 4) do
    local n = C_Container.GetContainerNumSlots(bag) or 0
    local _, fam = C_Container.GetContainerNumFreeSlots(bag)
    if n > 0 and isAmmoBag(fam) then quiver = math.max(quiver, n)
    elseif not fam or fam == 0 then smallest = math.min(smallest or n, n) end
  end
  return quiver, smallest or 0
end
-- a bag reward's worth against what you carry: slots gained, x 0.5 to set against stat scores (a guess: a 4-slot
-- bigger quiver beats a +1 Agility ring); nil when it isn't a bag you'd use
local BAG_LOC = { INVTYPE_BAG = true, INVTYPE_QUIVER = true }
function A.bagGain(link)
  local slots, fam = bagInfo(link)
  if not slots then return nil end
  local quiver, smallest = bagsNow()
  local _, class = UnitClass("player")
  if isAmmoBag(fam) then
    if class ~= "HUNTER" then return nil end
    -- one that holds your kind of ammo
    local kind = ns.ammo and ns.ammo.kind()
    if kind and fam % 4 ~= (kind == "arrow" and 1 or 2) and fam % 4 ~= 3 then return nil end
    return (slots - quiver) * 0.5, slots, quiver
  elseif fam == 0 then
    return (slots - smallest) * 0.5, slots, smallest
  end
end

-- can you wear / wield it: not if the game's tooltip says so; else ForeverDB's proficiency table (subclass -> level)
local function canUse(link)
  if tooltipSaysNo(link) then return false end
  local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(link)
  local _, class = UnitClass("player")
  local p = ns.prof and ns.prof[class]
  if not p or not classID then return true end
  local need
  if classID == 4 and subID and subID >= 1 and subID <= 4 then need = p.armor[subID] or 999
  elseif classID == 2 and subID then need = p.weapon[subID] or 999 end
  return not need or UnitLevel("player") >= need
end

-- the best score you already have for an equip location: worn in its slots (the weaker of two rings or trinkets, as
-- that's the one a new one replaces) and in your bags
local function haveFor(equipLoc)
  local slots = SLOTS[equipLoc]
  if not slots then return nil end
  local worn
  for _, slot in ipairs(slots) do
    local sc = A.score(GetInventoryItemLink("player", slot))
    worn = worn and math.min(worn, sc) or sc
  end
  local best = worn or 0
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.hyperlink then
        local _, _, _, loc = C_Item.GetItemInfoInstant(info.hyperlink)
        if loc == equipLoc and canUse(info.hyperlink) then best = math.max(best, A.score(info.hyperlink)) end
      end
    end
  end
  return best
end
-- a piece of gear in your bags you'd put on: you can use it and it beats what you wear in its slot (the bank-alt mail
-- reminder keeps these)
function A.wouldWear(link)
  local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
  local slots = SLOTS[equipLoc]
  if not slots or not canUse(link) then return false end
  local worn
  for _, slot in ipairs(slots) do
    local sc = A.score(GetInventoryItemLink("player", slot))
    worn = worn and math.min(worn, sc) or sc
  end
  return A.score(link) > (worn or 0)
end

-- a drink (restores mana): Food & Drink whose use is "Drink" (or "Refreshment", both)
local function isDrink(link)
  local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(link)
  if classID ~= 0 or subID ~= 5 then return false end
  local f = (C_Item and C_Item.GetItemSpell) or GetItemSpell
  local spell = f and f(link)
  return spell == "Drink" or spell == "Refreshment"
end
-- a class that drinks: everyone but Warriors and Rogues
local function usesMana()
  local _, class = UnitClass("player")
  return class ~= "WARRIOR" and class ~= "ROGUE"
end

-- the choice to take, and why; nil when the game hasn't described the items yet
-- no upgrade and you use mana: a drink before anything that only sells for more (the user, 2026-10-17: "water is far
-- better than food")
function A.pickReward(n)
  local drinkI, drinkPrice = nil, -1
  local mana = usesMana()
  local bestUp, bestGain, bestValue, bestPrice, rows = nil, 0, nil, -1, {}
  local upWhy, anyValue, anyPrice = nil, nil, -1
  for i = 1, n do
    local link = GetQuestItemLink("choice", i)
    if not link then return nil, "item not loaded", rows end
    local _, _, _, _, _, _, _, _, equipLoc, _, sellPrice = C_Item.GetItemInfo(link)
    if sellPrice == nil then return nil, "item not loaded", rows end
    local row = { link = link, slot = equipLoc, price = sellPrice }
    local equip = equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
    local usable = not equip or canUse(link)
    if BAG_LOC[equipLoc] then
      local gain, slots, have = A.bagGain(link)
      row.bag, row.have = slots, have
      if gain and gain > bestGain then bestUp, bestGain, upWhy = i, gain, ("%d slots, you have %d"):format(slots, have) end
    elseif SLOTS[equipLoc] and usable then
      row.score, row.have = A.score(link), haveFor(equipLoc) or 0
      local gain = row.score - row.have
      if gain > bestGain then bestUp, bestGain, upWhy = i, gain, nil end
    end
    row.usable = usable or nil
    if mana and isDrink(link) then
      row.drink = true
      if sellPrice > drinkPrice then drinkI, drinkPrice = i, sellPrice end
    end
    -- no upgrade: the best seller you can use (a sword you can't wield isn't worth more to you than a quiver)
    if usable and sellPrice > bestPrice then bestValue, bestPrice = i, sellPrice end
    if sellPrice > anyPrice then anyValue, anyPrice = i, sellPrice end
    rows[i] = row
  end
  local sp = A.spec()
  if bestUp then
    return bestUp, upWhy and ("bigger bag (%s)"):format(upWhy) or ("upgrade for %s (+%.1f)"):format(sp and sp.name or "?", bestGain), rows
  end
  if drinkI then return drinkI, "drink (no upgrade, you use mana)", rows end
  if bestValue then return bestValue, "highest value you can use (no upgrade)", rows end
  return anyValue, "highest value (none usable)", rows
end

-- ------------------------------------------------------------------ vendors
-- open between MERCHANT_SHOW and MERCHANT_CLOSED (MerchantFrame may not be shown yet when MERCHANT_SHOW fires)
local merchantOpen = false

local function junkInBags()
  local queue = {}
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.quality == 0 and not info.hasNoValue then
        queue[#queue + 1] = { bag, slot, info.itemID, info.stackCount or 1 }
      end
    end
  end
  return queue
end

-- what the junk in your bags sells for (copper)
function A.junkValue()
  local value = 0
  for _, it in ipairs(junkInBags()) do value = value + (select(11, C_Item.GetItemInfo(it[3])) or 0) * it[4] end
  return value
end

local function sellJunk()
  local queue = junkInBags()
  if #queue == 0 then return end
  local value = 0
  for _, it in ipairs(queue) do value = value + (select(11, C_Item.GetItemInfo(it[3])) or 0) * it[4] end
  -- check afterwards what's left, so a failed sale shows up in the log
  local function report(how)
    C_Timer.After(2, function()
      local left = #junkInBags()
      log(left == 0 and "SOLD_JUNK" or "SOLD_JUNK_PARTIAL", { items = #queue - left, left = left, copper = value, how = how })
    end)
  end
  -- the client's own "sell all junk" (one server request), when it has it
  if C_MerchantFrame and C_MerchantFrame.SellAllJunkItems then
    local ok, err = pcall(C_MerchantFrame.SellAllJunkItems)
    if ok then report("SellAllJunkItems") return end
    log("JUNK_ERROR", { err = tostring(err) })
  end
  -- else one at a time, a few per tick: the server drops sales sent in one burst
  local i = 0
  local function step()
    if not merchantOpen then return end
    for _ = 1, 6 do
      i = i + 1
      local it = queue[i]
      if not it then report("UseContainerItem") return end
      C_Container.UseContainerItem(it[1], it[2])
    end
    C_Timer.After(0.25, step)
  end
  step()
end

function handlers.MERCHANT_CLOSED() merchantOpen = false end

function handlers.MERCHANT_SHOW()
  merchantOpen = true
  if paused() then return end
  if on("repair") and CanMerchantRepair() then
    local cost, can = GetRepairAllCost()
    if can and cost and cost > 0 and GetMoney() >= cost then
      RepairAllItems()
      log("REPAIRED", { copper = cost })
    end
  end
  -- a moment after opening, once the merchant's item list has arrived
  if on("junk") then C_Timer.After(0.3, function() if merchantOpen then local ok, err = pcall(sellJunk); if not ok then log("JUNK_ERROR", { err = tostring(err) }) end end end) end
end

local frame = ns.newFrame("Auto", "Frame")
frame:SetScript("OnEvent", function(_, event, ...)
  local h = handlers[event]
  if not h then return end
  local ok, err = pcall(h, ...)
  if not ok then log("AUTO_ERROR", { event = event, err = tostring(err) }) end
end)
function A.enable()
  for event in pairs(handlers) do pcall(frame.RegisterEvent, frame, event) end
end
