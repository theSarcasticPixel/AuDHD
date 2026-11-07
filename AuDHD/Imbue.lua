-- Buffs you keep up yourself, with a button that puts them back on:
-- weapon: a shaman's Rockbiter (or Flametongue, Frostbrand, Windfury) Weapon, or a wizard oil, mana oil, sharpening
-- stone or weightstone you have in your bags, whenever your main hand has none on. Click to cast the imbue, or to use
-- the oil / stone on the weapon.; each its own (both can be on:), read off the weapon's tooltip. self buffs, per class,
-- each group a buff you keep on (any of its spells counts): a hunter's aspect, a druid's Mark of the Wild and Thorns, a
-- priest's Fortitude and Inner Fire, a paladin's blessing and aura, a mage's Arcane Intellect and armor, a warlock's
-- Demon Skin / Armor, a shaman's Lightning Shield. Up whenever it's off and you have one of its spells in your book.;
-- "simlarly with druid/priest/paladin buffs". Which one: the last of the group you cast (an aspect for travel, Cheetah
-- or Pack, doesn't count), else the first you know. Cast on yourself.
-- food: food in your bags that makes you Well Fed, and no Well Fed on you: click to eat it.; and a weapon imbue scroll
-- that fits your main hand while it has no imbue on (below, "scrolls").
-- The buttons are secure (they cast): they come up and go away only out of a fight. Closed with X: back the next time
-- the buff goes on and drops off again. /audhd imbue [off|on] (the weapon), /audhd buffs [off|on] (the self buffs).
local _, ns = ...
local I = {}
ns.imbue = I
local log = function(e, f) if ns.log then ns.log.add(e, f) end end

-- spell ids, every rank -> name (cast by name: the highest rank you know)
local function ranks(t)
  local out = {}
  for name, ids in pairs(t) do for _, id in ipairs(ids) do out[id] = name end end
  return out
end
local IMBUES = ranks({
  ["Rockbiter Weapon"] = { 8017, 8018, 8019, 10399, 16314, 16315, 16316 },
  ["Flametongue Weapon"] = { 8024, 8027, 8030, 16339, 16341, 16342 },
  ["Frostbrand Weapon"] = { 8033, 8038, 10456, 16355, 16356 },
  ["Windfury Weapon"] = { 8232, 8235, 10486, 16362 },
})
-- self buffs: { class, name, spells = { { name, rank 1 id } ... } in the order to pick, travel = names not to pick,
-- list = every other one you know in a list under the button, to click instead }. Rank 1 is in your spellbook once you
-- have any rank (Classic keeps every rank). The aspects listed
local GROUPS = {
  { class = "HUNTER", key = "aspect", what = "No aspect on", list = true, travel = { ["Aspect of the Cheetah"] = true, ["Aspect of the Pack"] = true },
    spells = { { "Aspect of the Hawk", 13165 }, { "Aspect of the Monkey", 13163 }, { "Aspect of the Wild", 20043 },
               { "Aspect of the Beast", 13161 }, { "Aspect of the Cheetah", 5118 }, { "Aspect of the Pack", 13159 } } },
  { class = "DRUID", key = "mark", spells = { { "Mark of the Wild", 1126 }, { "Gift of the Wild", 21849 } } },
  { class = "DRUID", key = "thorns", spells = { { "Thorns", 467 } } },
  { class = "PRIEST", key = "fortitude", spells = { { "Power Word: Fortitude", 1243 }, { "Prayer of Fortitude", 21562 } } },
  { class = "PRIEST", key = "innerfire", spells = { { "Inner Fire", 588 } } },
  { class = "PALADIN", key = "blessing", what = "No blessing on",
    spells = { { "Blessing of Might", 19740 }, { "Blessing of Wisdom", 19742 }, { "Blessing of Kings", 20217 },
               { "Blessing of Salvation", 1038 }, { "Blessing of Light", 19977 }, { "Blessing of Sanctuary", 20911 } } },
  { class = "PALADIN", key = "aura", what = "No aura on",
    spells = { { "Devotion Aura", 465 }, { "Retribution Aura", 7294 }, { "Concentration Aura", 19746 }, { "Sanctity Aura", 20218 },
               { "Shadow Resistance Aura", 19876 }, { "Frost Resistance Aura", 19888 }, { "Fire Resistance Aura", 19891 } } },
  { class = "MAGE", key = "intellect", spells = { { "Arcane Intellect", 1459 }, { "Arcane Brilliance", 23028 } } },
  { class = "MAGE", key = "armor", what = "No armor on", spells = { { "Frost Armor", 168 }, { "Ice Armor", 7302 }, { "Mage Armor", 6117 } } },
  { class = "WARLOCK", key = "armor", what = "No armor on", spells = { { "Demon Skin", 687 }, { "Demon Armor", 706 } } },
  { class = "SHAMAN", key = "shield", spells = { { "Lightning Shield", 324 } } },
}
-- weapon items, best first per kind
local OILS = { 20749, 20750, 20748, 20746, 20747, 20744, 20745 }   -- wizard and mana oils
local STONES = { 18262, 12404, 12643, 7964, 7965, 2871, 3241, 2863, 3240, 2862, 3239 }   -- sharpening stones, weightstones
local ITEMS = {}
for _, id in ipairs(OILS) do ITEMS[id] = true end
for _, id in ipairs(STONES) do ITEMS[id] = true end

local function db()
  AuDHDDB.imbue = AuDHDDB.imbue or {}
  return AuDHDDB.imbue
end
local function knownId(id)
  return (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) or false
end
local function known(map, name)
  for id, n in pairs(map) do
    if n == name and knownId(id) then return true end
  end
  return false
end
-- C_Item first: this client has no global GetItemCount; the bags themselves when neither answers
local function count(id)
  local n = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id)) or (GetItemCount and GetItemCount(id))
  if n then return n end
  n = 0
  if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID then
    for _, bag in ipairs(ns.bagIDs()) do
      for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
        if C_Container.GetContainerItemID(bag, slot) == id then
          local info = C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
          n = n + (info and info.stackCount or 1)
        end
      end
    end
  end
  return n
end
-- uses left: a Wizard Oil flask has 5 charges, so 2 flasks is 10; the flask count when the client won't say
local function uses(id)
  local n = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id, false, true)) or (GetItemCount and GetItemCount(id, false, true))
  return n or count(id)
end
local function itemName(id)
  local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
  if not n and C_Item and C_Item.GetItemInfo then n = C_Item.GetItemInfo(id) end
  return n or (GetItemInfo and GetItemInfo(id)) or ("item " .. id)
end
-- this client: C_Item (the global GetItemIcon gave a "?" on the oil's button)
local function itemIcon(id)
  local t = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
  if not t and C_Item and C_Item.GetItemInfoInstant then t = select(5, C_Item.GetItemInfoInstant(id)) end
  if not t and GetItemIcon then t = GetItemIcon(id) end
  return t or 134400
end
local function usesMana()
  local _, class = UnitClass("player")
  return class ~= "WARRIOR" and class ~= "ROGUE"
end
local function busy()
  return (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) or (UnitOnTaxi and UnitOnTaxi("player"))
end

-- ------------------------------------------------------------------ the kinds
-- each: on() -> true (the buff is on), false (it's off), nil (doesn't apply: no weapon, not your class, none known);
-- source() -> { spell = name } or { item = id } or nil; when: "drop" (only as it drops off) or "off" (whenever it's off)
local K = {}
-- whenever it's off, not only as it drops off
-- the imbue and the oil / stone are pop-ups of their own; each goes only when its own is on
K.weapon = { when = "off" }
local lastLeft   -- seconds the weapon's buff had left when last seen (the log: ran out, or wrongly seen as gone)
local onEnchant  -- the enchant id the game reports on the main hand now (Minor Wizard Oil: 2623)
-- oils' and stones' enchant ids (anything else on the weapon is your imbue); db().enchants learns more as you put them on
local ITEM_ENCHANTS = { [2623] = true, [2624] = true, [2625] = true, [2626] = true, [2627] = true, [2628] = true,
  [2629] = true, [40] = true, [13] = true, [14] = true, [483] = true, [1643] = true, [19] = true, [20] = true,
  [21] = true, [484] = true, [1703] = true }
-- What's on the main hand, read off its tooltip: the imbue and the oil / stone each have a line, and both can be on at
-- once. GetWeaponEnchantInfo names only one of them (with Rockbiter and the oil on it said 2623, the oil), so it's only
-- the fallback when the tooltip can't be read. { imbue = true/false, item = true/false, lines = "..." } or nil
local IMBUE_WORDS = { "Rockbiter", "Flametongue", "Frostbrand", "Windfury" }
local ITEM_WORDS = { "Wizard Oil", "Mana Oil", "Sharpened", "Weighted" }
local scanTip
local function tipLines()
  local out = {}
  if C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
    local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", 16)
    if ok and data and data.lines then
      for i, l in ipairs(data.lines) do if i > 1 and l.leftText then out[#out + 1] = l.leftText end end
      if #data.lines > 0 then return out end
    end
  end
  if CreateFrame and not scanTip then
    local ok, t = pcall(CreateFrame, "GameTooltip", "AuDHDScanTip", nil, "GameTooltipTemplate")
    scanTip = ok and t or false
  end
  if scanTip and scanTip.SetInventoryItem and scanTip.NumLines then
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    local n = pcall(scanTip.SetInventoryItem, scanTip, "player", 16) and tonumber(scanTip:NumLines()) or 0
    if n > 0 then
      for i = 2, n do
        local fs = _G["AuDHDScanTipTextLeft" .. i]
        local t = fs and fs:GetText()
        if t then out[#out + 1] = t end
      end
      return out
    end
  end
  return nil
end
local seen, seenAt, seenLog
local function weaponSeen()
  local now = GetTime()
  if seenAt and now - seenAt < 0.5 then return seen end
  seenAt = now
  local lines = tipLines()
  if not lines then seen = nil return nil end
  local st = { imbue = false, item = false, timed = false, found = {} }
  for _, t in ipairs(lines) do
    if type(t) == "string" and not (issecretvalue and issecretvalue(t)) then
      local known
      for _, w in ipairs(IMBUE_WORDS) do if t:find(w, 1, true) then st.imbue, known = true, true st.found[#st.found + 1] = t end end
      for _, w in ipairs(ITEM_WORDS) do if t:find(w, 1, true) then st.item, known = true, true st.found[#st.found + 1] = t end end
      -- anything else on for a while ("... (59 min)"): a mage's imbue scroll (its words aren't known yet)
      if not known and t:find("%(%d+ %a+%)$") then st.timed = true st.found[#st.found + 1] = t end
    end
  end
  seen = st
  -- for the log, as it changes: what the tooltip said is on the weapon
  local key = table.concat(st.found, " | "):gsub("%s*%([%d%.]+ %a+%)", "")   -- not the time left: it changes every second
  if key ~= seenLog then seenLog = key log("WEAPON_SEEN", { lines = key }) end
  return st
end
local function enchantOn()
  if not GetInventoryItemID or not GetInventoryItemID("player", 16) or not GetWeaponEnchantInfo then return nil end
  local has, ms, _, enchant = GetWeaponEnchantInfo()
  if has then lastLeft = ms and math.floor(ms / 1000) end
  onEnchant = has and enchant or nil
  return has and true or false
end
function K.weapon.on()
  local has = enchantOn()
  if has == nil then return nil end
  local st = weaponSeen()
  if st then return st.imbue end
  return has
end
-- every imbue you know is a button of its own, always in the same order, so each keeps its place (the last cast first
-- swapped them about:); all go once one is on the weapon
local IMBUE_ORDER = { "Rockbiter Weapon", "Flametongue Weapon", "Frostbrand Weapon", "Windfury Weapon" }
local function knownImbues()
  local out = {}
  for _, name in ipairs(IMBUE_ORDER) do if known(IMBUES, name) then out[#out + 1] = name end end
  return out
end
function K.weapon.source()
  local name = knownImbues()[1]
  return name and { spell = name } or nil
end
for n = 2, #IMBUE_ORDER do
  K["weapon" .. n] = {
    when = "off",
    on = function() if not knownImbues()[n] then return nil end return K.weapon.on() end,
    source = function() local name = knownImbues()[n] return name and { spell = name } or nil end,
    mine = function() return K.weapon.mine() end,
  }
end
K.oil = { when = "off" }
function K.oil.on()
  local has = enchantOn()
  if has == nil then return nil end
  local st = weaponSeen()
  if st then return st.item end
  return has
end
function K.oil.source()
  local d = db()
  if d.item and count(d.item) > 0 then return { item = d.item } end
  for _, list in ipairs(usesMana() and { OILS, STONES } or { STONES, OILS }) do
    for _, id in ipairs(list) do if count(id) > 0 then return { item = id } end end
  end
end
-- an oil or stone that went from your bags as the weapon got its buff: the one to put back next time
local counts
-- which of the two is on the weapon now (db.cur: "imbue" as you cast it, "item" as an oil or stone goes from your bags;
-- nil when the weapon is bare or it isn't known): only its own pop-up goes when it's on Which one it is, decided as the
-- weapon gets it: the more recent of your imbue cast and your click on the oil's button (or an oil gone from your
-- bags), within RECENT seconds. The bags can update after the weapon shows the oil, so the oil's own button marks it
local RECENT = 20
local wasOn
function K.weapon.watch(on)
  local d, t = db(), GetTime()
  local now = {}
  for id in pairs(ITEMS) do now[id] = count(id) end
  if counts then
    for id, n in pairs(now) do if n < (counts[id] or 0) then d.item, d.tItem = id, t end end
  end
  counts = now
  if on and wasOn == false then
    local ti, tm = d.tImbue or -1e9, d.tItem or -1e9
    if math.max(ti, tm) >= t - RECENT then d.cur = ti > tm and "imbue" or "item" end
    local _, _, _, enchant = GetWeaponEnchantInfo()
    if enchant and d.cur then d.enchants = d.enchants or {} d.enchants[enchant] = d.cur end
    log("IMBUE_ON", { cur = d.cur, enchant = enchant, spell = d.spell, item = d.item })
  elseif on == false then
    d.cur = nil
  end
  if on ~= nil then wasOn = on end
end
-- which one is on: from the enchant id the game reports, else the guess; not known at all: both go
local function onKind()
  local e = onEnchant
  if e then
    local learned = db().enchants and db().enchants[e]
    if learned then return learned end
    return ITEM_ENCHANTS[e] and "item" or "imbue"
  end
  return db().cur
end
-- read off the tooltip, each is its own: always "mine"
function K.weapon.mine() return weaponSeen() ~= nil or onKind() ~= "item" end
function K.oil.mine() return weaponSeen() ~= nil or onKind() ~= "imbue" end

local function spellName(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  return GetSpellInfo and (GetSpellInfo(id)) or nil
end
local function buffName(i)
  if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
    local a = C_UnitAuras.GetBuffDataByIndex("player", i)
    return a and a.name, a ~= nil
  end
  if UnitBuff then
    local name = UnitBuff("player", i)
    return name, name ~= nil
  end
  return nil, false
end
local function buffsOn()
  local on = {}
  for i = 1, 40 do
    local name, more = buffName(i)
    if not more then break end
    if name then on[name] = true end
  end
  return on
end
local BYNAME = {}   -- spell name -> its group
for gi, g in ipairs(GROUPS) do
  local kind = "buff_" .. g.class .. "_" .. g.key
  local k = { when = "off", group = g, buff = true }
  K[kind] = k
  for _, sp in ipairs(g.spells) do BYNAME[sp[1]] = k end
  local function knownNames()
    local out = {}
    for _, sp in ipairs(g.spells) do if knownId(sp[2]) then out[#out + 1] = sp[1] end end
    return out
  end
  function k.on()
    local _, class = UnitClass("player")
    if class ~= g.class or #knownNames() == 0 then return nil end
    local on = buffsOn()
    for _, sp in ipairs(g.spells) do if on[sp[1]] then return true end end
    return false
  end
  function k.source()
    local last = db().last and db().last[kind]
    local names = knownNames()
    for _, n in ipairs(names) do if n == last then return { spell = n, unit = "player" } end end
    for _, n in ipairs(names) do if not (g.travel and g.travel[n]) then return { spell = n, unit = "player" } end end
    if names[1] then return { spell = names[1], unit = "player" } end
  end
  function k.text(src) return ("%s: click for %s"):format(g.what or ("No " .. src.spell), src.spell) end
  -- the list under the button: every one you know, in the group's order
  if g.list then
    function k.list()
      local out = {}
      for _, n in ipairs(knownNames()) do out[#out + 1] = { spell = n } end
      return out
    end
  end
end
-- food that makes you Well Fed, by its tooltip (English: "...you will become well fed..."); item id -> true / false,
-- kept once the tooltip has loaded
local wellFeds = {}
local function itemLines(id)
  if C_TooltipInfo and C_TooltipInfo.GetItemByID then
    local ok, data = pcall(C_TooltipInfo.GetItemByID, id)
    if ok and data and data.lines and #data.lines > 0 then
      local out = {}
      for _, l in ipairs(data.lines) do if l.leftText then out[#out + 1] = l.leftText end end
      return out
    end
  end
  if CreateFrame and scanTip == nil then
    local ok, t = pcall(CreateFrame, "GameTooltip", "AuDHDScanTip", nil, "GameTooltipTemplate")
    scanTip = ok and t or false
  end
  if scanTip and scanTip.SetItemByID and scanTip.NumLines then
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    local n = pcall(scanTip.SetItemByID, scanTip, id) and tonumber(scanTip:NumLines()) or 0
    if n > 0 then
      local out = {}
      for i = 1, n do
        local fs = _G["AuDHDScanTipTextLeft" .. i]
        local t = fs and fs:GetText()
        if t then out[#out + 1] = t end
      end
      return out
    end
  end
end
-- consumables only (item class 0): a recipe's tooltip shows the food it makes, Well Fed and all
local function consumable(id)
  local get = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
  local classID = get and select(6, get(id))
  return classID == nil or classID == 0
end
local function wellFed(id)
  if wellFeds[id] ~= nil then return wellFeds[id] end
  if not consumable(id) then wellFeds[id] = false return false end
  local lines = itemLines(id)
  if not lines then return false end   -- not loaded yet: asked again next time
  local yes = false
  for _, t in ipairs(lines) do
    if type(t) == "string" and not (issecretvalue and issecretvalue(t)) and t:lower():find("well fed", 1, true) then yes = true break end
  end
  wellFeds[id] = yes
  return yes
end
I.wellFed = wellFed   -- (the smoke test)
-- the food you prefer, ticked in Settings > Reminders from the Well Fed food in your bags: first on the food button,
-- the rest after it. item id -> its name (for the list when you have none left)
local function prefs()
  db().foodPref = db().foodPref or {}
  return db().foodPref
end
-- the Well Fed food in your bags you can eat: the ones you prefer first, then the highest level, then the most
local function foods()
  local by, level = {}, UnitLevel("player") or 1
  if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID) then return {} end
  for _, bag in ipairs(ns.bagIDs()) do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      local id = C_Container.GetContainerItemID(bag, slot)
      if id and by[id] == nil then
        local minLevel = C_Item and C_Item.GetItemInfo and select(5, C_Item.GetItemInfo(id))
        by[id] = ((tonumber(minLevel) or 0) <= level and wellFed(id)) and (tonumber(minLevel) or 0) or false
      end
    end
  end
  local out = {}
  for id, lv in pairs(by) do if lv then out[#out + 1] = { id = id, lv = lv, n = count(id) } end end
  local pref = prefs()
  table.sort(out, function(a, b)
    local pa, pb = pref[a.id] and 1 or 0, pref[b.id] and 1 or 0
    if pa ~= pb then return pa > pb end
    if a.lv ~= b.lv then return a.lv > b.lv end
    if a.n ~= b.n then return a.n > b.n end
    return a.id < b.id
  end)
  return out
end
-- for Settings: { { id, name, n, pref } } the food in your bags as the button orders it, then food you prefer and have
-- none of
function I.foodChoices()
  local out, seen, pref = {}, {}, prefs()
  for _, f in ipairs(foods()) do
    seen[f.id] = true
    out[#out + 1] = { id = f.id, name = itemName(f.id), n = f.n, pref = pref[f.id] and true or false }
  end
  for id, name in pairs(pref) do
    if not seen[id] then out[#out + 1] = { id = id, name = type(name) == "string" and name or itemName(id), n = 0, pref = true } end
  end
  return out
end
function I.setFoodPref(id, on)
  prefs()[id] = on and itemName(id) or nil
  I.check()
end
local FED = { ["Well Fed"] = true, ["Food"] = true, ["Food & Drink"] = true }   -- the buff, or eating for it
K.food = { when = "off", food = true }
function K.food.on()
  if #foods() == 0 then return nil end
  for name in pairs(buffsOn()) do if FED[name] then return true end end
  return false
end
function K.food.source()
  local f = foods()[1]
  return f and { item = f.id } or nil
end

-- ------------------------------------------------------------------ scrolls
-- Buff scrolls. Which, by the item and its tooltip, not a list, so new ones count: a consumable scroll (its subclass,
-- or "Scroll of" in its name) whose Use: line lasts minutes or hours and doesn't speak of a weapon or a summon. Its
-- buff: the spell it casts, by name (all ranks of Stamina share "Stamina"); the highest rank you can use. Not reminded
-- with that buff on, nor the class buff it won't stack with. Unticked in Settings: never reminded of it. Every
-- deciphered scroll is Mage only, so the game's "can't use" keeps them from other classes. Not Comprehension: it's for
-- deciphering, not a fight.
-- The Familiars (Rat, Frog, Cat: +Intellect for an hour, a new one replaces the one out; the guides) are one buff
-- between them, "Familiar", the best you can read; their items can be companion pets (item class 15). Out: a buff of
-- yours with "Familiar" in its name, else one read in the last hour (not known yet whether it shows as a buff). Weapon
-- imbue scrolls ("Scroll of Imbue ...": an hour on the weapon; the guides) have a button of their own, with the
-- weapon's (below)
local CLASS_BUFF = {
  Stamina = { "Power Word: Fortitude", "Prayer of Fortitude" },
  Intellect = { "Arcane Intellect", "Arcane Brilliance" },
  Spirit = { "Divine Spirit", "Prayer of Spirit" },
  Strength = { "Strength of Earth" },
  Agility = { "Grace of Air" },
}
-- each imbue's weapon, by the name after "Scroll of Imbue " (the guides; an imbue not here: what its Use: line says, else
-- any weapon). Item subclasses: 10 staff, 15 dagger, 7 / 8 one- / two-handed sword
local IMBUE_WEAPON = { staff = { [10] = true }, dagger = { [15] = true }, sword = { [7] = true, [8] = true } }
local IMBUE_FOR = {
  ["Lesser Flame"] = "staff", Frost = "staff", Striking = "staff", Baleflame = "staff", Flame = "staff", Accuracy = "staff",
  Quickening = "staff", Balefrost = "staff", ["Greater Flame"] = "staff", ["Greater Frost"] = "staff", Precision = "staff",
  Spellbreak = "staff", Chillknife = "dagger", Iceknife = "dagger", Manablade = "dagger", Spark = "sword",
}
local scrollInfos = {}   -- item id -> { buff, imbue = "staff" / "dagger" / "sword" / true } or false; kept once known
local familiarSpells = {}   -- a Familiar scroll's spell name -> true (read: the familiar's out for an hour)
local function scrollInfo(id)
  if scrollInfos[id] ~= nil then return scrollInfos[id] end
  local get = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
  local _, _, _, _, _, classID, subID = get(id)
  if classID == nil then return false end   -- not loaded: asked again
  local name = itemName(id) or ""
  local familiar = name:find("Familiar", 1, true) ~= nil
  if not ((classID == 0 and (subID == 4 or name:find("^Scroll of"))) or (classID == 15 and familiar)) then
    scrollInfos[id] = false
    return false
  end
  local lines = itemLines(id)
  local spell = C_Item and C_Item.GetItemSpell and C_Item.GetItemSpell(id)
  if not lines or type(spell) ~= "string" or (issecretvalue and issecretvalue(spell)) then return false end
  local use
  for _, t in ipairs(lines) do
    if type(t) == "string" and not (issecretvalue and issecretvalue(t)) and t:find("^Use:") then use = t:lower() break end
  end
  local info = false
  local imbue = name:match("^Scroll of Imbue (.+)$")
  if imbue then
    local w = IMBUE_FOR[imbue]
    if not w and use then for word in pairs(IMBUE_WEAPON) do if use:find(word, 1, true) then w = word end end end
    info = { buff = imbue, imbue = w or true }
  elseif familiar then
    familiarSpells[spell] = true
    info = { buff = "Familiar" }
  elseif use and (use:find("%d+ min") or use:find("%d+ hour")) and not use:find("weapon", 1, true)
      and not use:find("summon", 1, true) and not use:find("comprehension", 1, true) and not name:find("Comprehension", 1, true) then
    info = { buff = spell }
  end
  scrollInfos[id] = info
  return info
end
-- a buff scroll's buff, or false (an imbue scroll isn't one)
local function scrollBuff(id)
  local info = scrollInfo(id)
  return info and not info.imbue and info.buff or false
end
I.scrollBuff = scrollBuff   -- (the smoke test)
I.scrollInfo = scrollInfo
local function scrollOff()
  db().scrollOff = db().scrollOff or {}
  return db().scrollOff
end
local function usable(id)
  local f = (C_Item and C_Item.IsUsableItem) or IsUsableItem
  if not f then return true end
  return f(id) and true or false
end
-- the buff scrolls in your bags you can read: { { id, buff, lv, n } }, the best of each buff; with the unticked ones too
-- when asked (Settings). imbues: the weapon imbue scrolls instead, the best of each imbue
local function scrolls(withOff, imbues)
  local best, seen, level, off = {}, {}, UnitLevel("player") or 1, scrollOff()
  if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID) then return {} end
  for _, bag in ipairs(ns.bagIDs()) do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      local id = C_Container.GetContainerItemID(bag, slot)
      if id and not seen[id] then
        seen[id] = true
        local info = scrollInfo(id)
        local minLevel = tonumber(C_Item and C_Item.GetItemInfo and select(5, C_Item.GetItemInfo(id))) or 0
        if info and (info.imbue ~= nil) == (imbues == true) and minLevel <= level and usable(id) and (withOff or not off[id]) then
          local buff = info.buff
          local s = { id = id, buff = buff, lv = minLevel, n = count(id), imbue = info.imbue }
          local key = withOff and id or buff
          local b = best[key]
          if not b or s.lv > b.lv or (s.lv == b.lv and s.n > b.n) then best[key] = s end
        end
      end
    end
  end
  local out = {}
  for _, s in pairs(best) do out[#out + 1] = s end
  table.sort(out, function(a, b) if a.buff ~= b.buff then return a.buff < b.buff end return a.lv > b.lv end)
  return out
end
-- a familiar out: a buff with its name, or one read in the last hour
local FAMILIAR_TIME = 3600
local function familiarOut(on)
  for name in pairs(on) do if type(name) == "string" and name:find("Familiar", 1, true) then return true end end
  local at = db().familiarAt
  return at and time and time() - at < FAMILIAR_TIME or false
end
-- the ones whose buff (or its class buff) isn't on you; and how many buffs your scrolls give at all
local function missingScrolls()
  local on, out = buffsOn(), {}
  local all = scrolls()
  for _, s in ipairs(all) do
    local blocked = on[s.buff]
    if s.buff == "Familiar" and familiarOut(on) then blocked = true end
    for _, c in ipairs(CLASS_BUFF[s.buff] or {}) do if on[c] then blocked = true end end
    if not blocked then out[#out + 1] = s end
  end
  return out, #all
end
K.scroll = { when = "off", scroll = true }
function K.scroll.on()
  local missing, all = missingScrolls()
  if all == 0 then return nil end
  return #missing == 0
end
function K.scroll.source()
  local s = missingScrolls()[1]
  return s and { item = s.id, buff = s.buff } or nil
end
-- for Settings: every buff and imbue scroll in your bags, ticked = reminded of it; and unticked ones you have none of
function I.scrollChoices()
  local out, seen, off = {}, {}, scrollOff()
  for _, list in ipairs({ scrolls(true), scrolls(true, true) }) do
    for _, s in ipairs(list) do
      seen[s.id] = true
      out[#out + 1] = { id = s.id, name = itemName(s.id), n = s.n, pref = not off[s.id] }
    end
  end
  for id, name in pairs(off) do
    if not seen[id] then out[#out + 1] = { id = id, name = type(name) == "string" and name or itemName(id), n = 0, pref = false } end
  end
  return out
end
function I.setScrollOn(id, on)
  scrollOff()[id] = not on and itemName(id) or nil
  I.check()
end

-- A weapon imbue scroll (a mage's) that fits your main hand, while the weapon has no imbue on: its own pop-up, like the
-- oil's; the other imbues that fit listed under it. On: the weapon's tooltip has a timed line ("... (59 min)") that
-- isn't an oil's or a stone's; when the tooltip can't be read, any temporary enchant. It and an oil stack: each is its
-- own, as with a shaman's imbue
local function mainHandType()
  local id = GetInventoryItemID and GetInventoryItemID("player", 16)
  if not id then return nil end
  local get = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
  local _, _, _, _, _, classID, subID = get(id)
  return classID == 2 and subID or false
end
local function imbueScrolls()
  local sub = mainHandType()
  if sub == nil then return {} end
  local out = {}
  for _, s in ipairs(scrolls(false, true)) do
    if s.imbue == true or (sub and IMBUE_WEAPON[s.imbue] and IMBUE_WEAPON[s.imbue][sub]) then out[#out + 1] = s end
  end
  table.sort(out, function(a, b) if a.lv ~= b.lv then return a.lv > b.lv end if a.n ~= b.n then return a.n > b.n end return a.id < b.id end)
  return out
end
K.scrollImbue = { when = "off", imbueScroll = true }
function K.scrollImbue.on()
  if #imbueScrolls() == 0 then return nil end
  local has = enchantOn()
  if has == nil then return nil end
  local st = weaponSeen()
  if st then return st.imbue or st.timed end
  return has
end
function K.scrollImbue.source()
  local s = imbueScrolls()[1]
  return s and { item = s.id, buff = s.buff } or nil
end
I.imbueScrolls = imbueScrolls   -- (the smoke test)

local KINDS = {}   -- in order: weapon, then the self buffs, then food, then scrolls (the buttons stack down)
KINDS[1] = "weapon"
for n = 2, #IMBUE_ORDER do KINDS[#KINDS + 1] = "weapon" .. n end
KINDS[#KINDS + 1] = "oil"
KINDS[#KINDS + 1] = "scrollImbue"
for _, g in ipairs(GROUPS) do KINDS[#KINDS + 1] = "buff_" .. g.class .. "_" .. g.key end
KINDS[#KINDS + 1] = "food"
KINDS[#KINDS + 1] = "scroll"

-- ------------------------------------------------------------------ the buttons
-- a square action button: the icon, a short name under it, the count on it (an oil's charges), the whole sentence in
-- its tooltip, a small close badge on its corner; side by side, not long bars
local SIZE, GAP = 40, 64
local function makeButton(kind)
  local k = K[kind]
  local b = ns.newFrame("Imbue", "Button", "AuDHD_" .. kind .. "Button", UIParent, "SecureActionButtonTemplate,BackdropTemplate")
  b:SetSize(SIZE, SIZE)
  if b.SetBackdrop then
    b:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    b:SetBackdropBorderColor(1, 0.75, 0.1, 1)   -- gold: it wants a click
  end
  local key = kind .. "Btn"   -- not the old bars' places (they were 380 wide)
  local pos = AuDHDDB[key]
  -- in a row under the rare button's place, one per kind your class has
  local col = 0
  for _, other in ipairs(KINDS) do
    if other == kind then break end
    if K[other].on() ~= nil then col = col + 1 end
  end
  if pos then b:SetPoint(pos.p, UIParent, pos.rp, pos.x, pos.y) else b:SetPoint("TOP", UIParent, "TOP", -96 + GAP * col, -150) end
  -- on release only: a press that turns into a drag mustn't cast
  -- (the game's "cast on key down" setting makes a secure button act only on the press, so up alone did nothing:)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("useOnKeyDown", false)
  b:SetMovable(true)
  b:SetClampedToScreen(true)
  b:RegisterForDrag("LeftButton")
  -- while dragged the button does nothing: the release that ends the drag is a click on it too, so its action comes
  -- back only on the next frame, after that click
  b:SetScript("OnDragStart", function(self)
    if InCombatLockdown() then return end
    self.dragType = self:GetAttribute("type")
    self:SetAttribute("type", nil)
    self:StartMoving()
  end)
  b:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    C_Timer.After(0, function()
      if self.dragType and not InCombatLockdown() and not self:GetAttribute("type") then self:SetAttribute("type", self.dragType) end
      self.dragType = nil
    end)
    local p, _, rp, x, y = self:GetPoint()
    AuDHDDB[key] = { p = p, rp = rp, x = x, y = y }
  end)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", 2, -2)
  b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)   -- the icon's own grey rim trimmed off
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.count:SetPoint("BOTTOMRIGHT", -3, 3)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.text:SetPoint("TOP", b, "BOTTOM", 0, -3)
  b.text:SetWidth(GAP - 4)
  b.text:SetJustifyH("CENTER")
  b.text:SetMaxLines(2)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(self.tip or "", 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local close = ns.newFrame("Imbue", "Button", nil, b, "UIPanelCloseButton")
  close:SetSize(20, 20)
  close:SetPoint("CENTER", b, "TOPRIGHT", 0, 0)
  close:SetFrameLevel(b:GetFrameLevel() + 2)
  close:SetScript("OnClick", function() k.closed = true I.hide(kind) end)
  -- the oil's button: what goes on the weapon next is the oil
  if kind == "oil" then b:SetScript("PreClick", function(self) if not self.dragType then db().tItem = GetTime() end end) end
  b:Hide()
  return b
end

-- the food button's list: the other Well Fed food in your bags, one row each under the button (its name under it
-- first), the icon to click and the name beside it. Children of the button: they move, hide and fade with it
-- a spell's own icon: this client has C_Spell, not the old global GetSpellTexture; a question mark if neither knows it
-- (the fallback was Rockbiter's icon, so a warlock's Demon Skin showed it:)
local function spellIcon(name)
  local t = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(name)
  if not t and GetSpellTexture then t = GetSpellTexture(name) end
  return t or 134400
end
local ROW = 30
local rowsOf = {}   -- kind -> its button's rows
local function listRow(kind, b, i)
  rowsOf[kind] = rowsOf[kind] or {}
  local rows = rowsOf[kind]
  if rows[i] then return rows[i] end
  local r = ns.newFrame("Imbue", "Button", nil, b, "SecureActionButtonTemplate")
  r:SetSize(26, 26)
  r:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 7, -32 - (i - 1) * ROW)
  r:RegisterForClicks("AnyUp", "AnyDown")
  r:SetAttribute("useOnKeyDown", false)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetAllPoints()
  r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  r:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  r:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
  r.count = r:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  r.count:SetPoint("BOTTOMRIGHT", -1, 1)
  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.name:SetPoint("LEFT", r, "RIGHT", 6, 0)
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.item and GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.item) else GameTooltip:SetText(self.name:GetText() or "") end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = r
  return r
end
-- (out of a fight only: I.show waits for the fight's end). list: { { id, n } } items or { { spell } } spells cast on
-- you, all but the button's own (first: its item id or spell name)
local function buttonList(kind, b, list, first)
  local n = 0
  for _, f in ipairs(list) do
    if (f.id or f.spell) ~= first then
      n = n + 1
      local r = listRow(kind, b, n)
      if f.spell then
        r.item = nil
        r:SetAttribute("type", "spell")
        r:SetAttribute("spell", f.spell)
        r:SetAttribute("unit", "player")
        r.icon:SetTexture(spellIcon(f.spell))
        r.count:SetText("")
        r.label = f.spell
      else
        r.item = f.id
        r:SetAttribute("type", "macro")
        r:SetAttribute("macrotext", ("/use item:%d"):format(f.id))
        r.icon:SetTexture(itemIcon(f.id))
        r.count:SetText(f.n)
        r.label = itemName(f.id) or "?"
      end
      r.name:SetText(r.label)
      r.on = true
      r:Show()
    end
  end
  local rows = rowsOf[kind] or {}
  for i = n + 1, #rows do rows[i].on = false rows[i]:Hide() end
  return n
end
-- the smoke test: the list's names, top down
function I.listRows(kind)
  local out = {}
  for _, r in ipairs(rowsOf[kind or "food"] or {}) do if r.on then out[#out + 1] = r.label end end
  return out
end
function I.foodRows() return I.listRows("food") end

function I.hide(kind)
  local k = K[kind]
  k.pending = nil
  if k.button and k.button.on then
    -- in a fight the game won't hide it: gone from sight now, hidden after the fight
    if InCombatLockdown() then k.pending = "hide" k.button:SetAlpha(0) return end
    k.button.on = false
    k.button:Hide()
  end
end
function I.show(kind, src)
  local k = K[kind]
  if InCombatLockdown() then k.pending = "show" return end
  k.button = k.button or makeButton(kind)
  local b = k.button
  if src.spell then
    b:SetAttribute("type", "spell")
    b:SetAttribute("spell", src.spell)
    b:SetAttribute("unit", src.unit)   -- your own buffs on you, whoever you have targeted
    b.msg = k.text and k.text(src) or ("No %s on: click to cast it"):format(src.spell)
    b.icon:SetTexture(spellIcon(src.spell))
    b.short = src.spell:gsub(" Weapon$", "")
    b.tip = src.spell
    b.count:SetText("")
    if k.list and buttonList(kind, b, k.list(), src.spell) > 0 then b.tip = b.tip .. "\nOr click one of the others under it" end
  else
    b:SetAttribute("type", "macro")
    b.icon:SetTexture(itemIcon(src.item))
    if k.food then
      b:SetAttribute("macrotext", ("/use item:%d"):format(src.item))
      b.msg = ("Not Well Fed: click to eat %s (%d left)"):format(itemName(src.item), count(src.item))
      b.short = itemName(src.item) or "Food"
      b.count:SetText(count(src.item))
      b.tip = ("Eat %s for Well Fed (%d left)"):format(itemName(src.item) or "food", count(src.item))
      if buttonList("food", b, foods(), src.item) > 0 then b.tip = b.tip .. "\nOr click one of the others under it" end
    elseif k.scroll then
      b:SetAttribute("macrotext", ("/use item:%d"):format(src.item))
      b.msg = ("No %s: click to read %s (%d left)"):format(src.buff or "buff", itemName(src.item), count(src.item))
      b.short = (itemName(src.item) or "Scroll"):gsub("^Scroll of ", "")
      b.count:SetText(count(src.item))
      b.tip = ("Read %s for %s (%d left)"):format(itemName(src.item) or "the scroll", src.buff or "its buff", count(src.item))
      if buttonList("scroll", b, (missingScrolls()), src.item) > 0 then b.tip = b.tip .. "\nThe scrolls for your other missing buffs are under it" end
    elseif k.imbueScroll then
      b:SetAttribute("macrotext", ("/use item:%d\n/use 16"):format(src.item))
      b.msg = ("No imbue on your weapon: click to read %s (%d left)"):format(itemName(src.item), count(src.item))
      b.short = (itemName(src.item) or "Imbue"):gsub("^Scroll of Imbue ", "")
      b.count:SetText(count(src.item))
      b.tip = ("Read %s on your weapon (%d left)"):format(itemName(src.item) or "the scroll", count(src.item))
      if buttonList("scrollImbue", b, imbueScrolls(), src.item) > 0 then b.tip = b.tip .. "\nOr click one of the others under it" end
    else
      b:SetAttribute("macrotext", ("/use item:%d\n/use 16"):format(src.item))
      b.msg = ("No oil or stone on your weapon: click to put on %s (%d left)"):format(itemName(src.item), uses(src.item))
      b.short = (itemName(src.item) or "Oil"):gsub("^Minor ", ""):gsub("^Lesser ", "")
      b.count:SetText(uses(src.item))
      b.tip = ("%s (%d left)"):format(itemName(src.item) or "Oil", uses(src.item))
    end
  end
  -- shown again mid-drag (a buff ran out): still nothing on the release that ends the drag
  if b.dragType then b.dragType = b:GetAttribute("type") b:SetAttribute("type", nil) end
  b.text:SetText(b.short)
  b:SetAlpha(1)
  if b.on then return end
  b.on = true
  b:Show()
  ns.playAlert()
  log(k.food and "FOOD_OFF" or k.scroll and "SCROLL_OFF" or k.imbueScroll and "SCROLL_IMBUE_OFF" or k.buff and "BUFF_OFF" or "IMBUE_GONE", { spell = src.spell, item = src.item, left = not k.buff and lastLeft or nil })
end

local OFF_TICKS = 2
local function tick(kind)
  local k = K[kind]
  if k.off then return end
  local on = k.on()
  if k.watch then k.watch(on, k.was) end
  if on == nil then
    k.was = nil
    if k.button and k.button.on then I.hide(kind) end
    return
  end
  -- off for OFF_TICKS checks in a row before it comes up: not for a moment's blink
  k.offTicks = not on and (k.offTicks or 0) + 1 or 0
  if on and k.mine and not k.mine() then
    -- only when the tooltip can't be read: something is on but not known which, so this pop-up stays as it is
  elseif on then
    k.closed = nil
    if k.button and k.button.on then I.hide(kind) end
  elseif not k.closed and not busy() and k.offTicks >= OFF_TICKS and (k.when == "off" or k.was or (k.button and k.button.on)) then
    local src = k.source()
    if src then I.show(kind, src) end
  end
  k.was = on
end
function I.check() for _, kind in ipairs(KINDS) do tick(kind) end end

-- the smoke test: what a button says (nil when it's not up)
function I.text(kind)
  kind = kind or "weapon"
  if not K[kind] then for k2, v in pairs(K) do if v.group and v.group.key == kind then kind = k2 end end end
  local b = K[kind] and K[kind].button
  return b and b.on and b.msg or nil
end
-- a self buff reminder switched off (the settings' checkbox: off when any is)
function I.anyBuffOff()
  for _, kind in ipairs(KINDS) do if K[kind].buff and K[kind].off then return true end end
  return false
end
function I.sourceOf(key)
  for _, v in pairs(K) do if v.group and v.group.key == key and v.on() ~= nil then return v.source() end end
end

-- /audhd imbue [off|on]: the weapon; /audhd buffs [off|on]: the self buffs; /audhd food [off|on]: Well Fed (no word:
-- show what's off now)
local function groupOf(kind) local k = K[kind] return k.food and "food" or k.scroll and "scrolls" or k.buff and "buffs" or "weapon" end
function I.command(arg, which)
  which = (which == "buffs" or which == "food" or which == "scrolls") and which or "weapon"
  local kinds = {}
  for _, kind in ipairs(KINDS) do if groupOf(kind) == which then kinds[#kinds + 1] = kind end end
  local what = which == "buffs" and "self buff" or which == "food" and "food buff" or which == "scrolls" and "scroll buff" or "weapon buff"
  arg = (arg or ""):lower()
  AuDHDDB.buffOff = AuDHDDB.buffOff or {}
  if arg == "off" or arg == "on" then
    for _, kind in ipairs(kinds) do
      K[kind].off = arg == "off" or nil
      AuDHDDB.buffOff[kind] = K[kind].off
      if arg == "off" then I.hide(kind) end
    end
    return what .. " reminders " .. arg
  end
  local said = {}
  for _, kind in ipairs(kinds) do
    local k = K[kind]
    local src = k.on() == false and k.source()
    if src then k.closed = nil I.show(kind, src) said[#said + 1] = src.spell or itemName(src.item) end
  end
  if #said > 0 then return what .. ": " .. table.concat(said, ", ") end
  if which == "food" then return "you're Well Fed already (or have no food that does it in your bags)" end
  if which == "scrolls" then return "your scroll buffs are all on (or you have no buff scrolls in your bags)" end
  return which == "buffs" and "your buffs are all on (or you have none to keep up)" or "no weapon buff to put on (on already, or no imbue known and no oil or stone in your bags)"
end

local frame = ns.newFrame("Imbue", "Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:SetScript("OnEvent", function(_, event, unit, _, spellID)
  if event == "PLAYER_LOGIN" then
    for kind in pairs(AuDHDDB.buffOff or {}) do if K[kind] then K[kind].off = true end end
    C_Timer.NewTicker(1, function() pcall(I.check) end)
    -- what it sees, once, for the log: which kinds apply to you and what they'd put on
    C_Timer.After(5, function()
      pcall(function()
        local seen = {}
        for _, kind in ipairs(KINDS) do
          local k = K[kind]
          local on = k.on()
          if on ~= nil then
            local src = k.source()
            seen[#seen + 1] = ("%s=%s:%s"):format(kind, tostring(on), src and (src.spell or src.item) or "none")
          end
        end
        local items = {}
        for _, list in ipairs({ OILS, STONES }) do
          for _, id in ipairs(list) do if count(id) > 0 then items[#items + 1] = id .. "x" .. count(id) end end
        end
        log("BUFF_PROBE", { kinds = table.concat(seen, " "), rockbiter = knownId(8017) and true or false, items = table.concat(items, " ") })
      end)
    end)
  elseif event == "PLAYER_REGEN_ENABLED" then
    -- after the fight: what had to wait
    for kind, k in pairs(K) do
      local p = k.pending
      k.pending = nil
      if p == "hide" then I.hide(kind) elseif p == "show" and k.on() == false then local src = k.source() if src then I.show(kind, src) end end
    end
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" then
    -- cast: off the screen now, not at the next tick
    C_Timer.After(0.3, function() pcall(I.check) end)
    -- a Familiar read: out for the next hour, if it doesn't show as a buff
    local cast = spellName(spellID)
    if cast and familiarSpells[cast] and time then db().familiarAt = time() end
    if IMBUES[spellID] then
      db().spell, db().tImbue = IMBUES[spellID], GetTime()
      if K.weapon.on() then db().cur = "imbue" end
    end
    -- the last of a group you cast, by name (any rank)
    local name = spellName(spellID)
    local k = name and BYNAME[name]
    if k and not (k.group.travel and k.group.travel[name]) then
      local d = db()
      d.last = d.last or {}
      for kind, v in pairs(K) do if v == k then d.last[kind] = name end end
    end
  end
end)
