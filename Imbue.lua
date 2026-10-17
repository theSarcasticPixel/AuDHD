-- Buffs you keep up yourself, with a button that puts them back on:
--  weapon: a shaman's Rockbiter (or Flametongue, Frostbrand, Windfury) Weapon, or a wizard oil, mana oil, sharpening
--    stone or weightstone you have in your bags, whenever your main hand has none on. Click to cast the imbue, or to use the
--    oil / stone on the weapon. The user, 2026-10-17: "lets add reminders for rockbiter and wizard oil (if you have any
--    in your bags) so that when it drops off you are reminded to add it again". Two pop-ups, the imbue (the last you
--    cast, else Rockbiter) and the oil / stone (the last that went from your bags, else the best oil for a mana user /
--    stone for the rest); each its own (both can be on: the user, 2026-10-17), read off the weapon's tooltip.
--  self buffs, per class, each group a buff you keep on (any of its spells counts): a hunter's aspect, a druid's Mark
--    of the Wild and Thorns, a priest's Fortitude and Inner Fire, a paladin's blessing and aura, a mage's Arcane
--    Intellect and armor, a warlock's Demon Skin / Armor, a shaman's Lightning Shield. Up whenever it's off and you
--    have one of its spells in your book. The user, 2026-10-17: "reminders for aspects on hunter, if they dont have an
--    aspect on (and have an aspect spell in their book) it tells them"; "simlarly with druid/priest/paladin buffs".
--    Which one: the last of the group you cast (an aspect for travel, Cheetah or Pack, doesn't count), else the first
--    you know. Cast on yourself.
-- The buttons are secure (they cast): they come up and go away only out of a fight. Closed with X: back the next time
-- the buff goes on and drops off again. /wfn imbue [off|on] (the weapon), /wfn buffs [off|on] (the self buffs).
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
-- self buffs: { class, name, spells = { { name, rank 1 id } ... } in the order to pick, travel = names not to pick }.
-- Rank 1 is in your spellbook once you have any rank (Classic keeps every rank)
local GROUPS = {
  { class = "HUNTER", key = "aspect", what = "No aspect on", travel = { ["Aspect of the Cheetah"] = true, ["Aspect of the Pack"] = true },
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
-- C_Item first: this client has no global GetItemCount (the user, 2026-10-17: Lesser Wizard Oil in the bags, no
-- reminder, BUFF_PROBE "weapon=false:none"); the bags themselves when neither answers
local function count(id)
  local n = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id)) or (GetItemCount and GetItemCount(id))
  if n then return n end
  n = 0
  if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID then
    for bag = 0, 4 do
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
-- uses left: a Wizard Oil flask has 5 charges, so 2 flasks is 10 (the user, 2026-10-17: "it shows 2 left but each
-- one has 5 charges"); the flask count when the client won't say
local function uses(id)
  local n = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id, false, true)) or (GetItemCount and GetItemCount(id, false, true))
  return n or count(id)
end
local function itemName(id)
  local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
  if not n and C_Item and C_Item.GetItemInfo then n = C_Item.GetItemInfo(id) end
  return n or (GetItemInfo and GetItemInfo(id)) or ("item " .. id)
end
-- this client: C_Item (the global GetItemIcon gave a "?" on the oil's button, the user 2026-10-17)
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
-- whenever it's off, not only as it drops off (the user, 2026-10-17: "ive got no rockbiter or wizard oil on and i
-- have nothing telling me to put it on")
-- the imbue and the oil / stone are pop-ups of their own (the user, 2026-10-17: "they should be individual pop-ups not
-- one that has them both"); each goes only when its own is on
K.weapon = { when = "off" }
local lastLeft   -- seconds the weapon's buff had left when last seen (the log: ran out, or wrongly seen as gone)
local onEnchant  -- the enchant id the game reports on the main hand now (Minor Wizard Oil: 2623)
-- oils' and stones' enchant ids (anything else on the weapon is your imbue); db().enchants learns more as you put them on
local ITEM_ENCHANTS = { [2623] = true, [2624] = true, [2625] = true, [2626] = true, [2627] = true, [2628] = true,
  [2629] = true, [40] = true, [13] = true, [14] = true, [483] = true, [1643] = true, [19] = true, [20] = true,
  [21] = true, [484] = true, [1703] = true }
-- What's on the main hand, read off its tooltip: the imbue and the oil / stone each have a line, and both can be on at
-- once (the user, 2026-10-17: "it also says 'replaces minor wizard oil' which i've already told you IS NOT TRUE - THEY
-- STACK"). GetWeaponEnchantInfo names only one of them (with Rockbiter and the oil on it said 2623, the oil), so it's
-- only the fallback when the tooltip can't be read. { imbue = true/false, item = true/false, lines = "..." } or nil
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
  local st = { imbue = false, item = false, found = {} }
  for _, t in ipairs(lines) do
    if type(t) == "string" and not (issecretvalue and issecretvalue(t)) then
      for _, w in ipairs(IMBUE_WORDS) do if t:find(w, 1, true) then st.imbue = true st.found[#st.found + 1] = t end end
      for _, w in ipairs(ITEM_WORDS) do if t:find(w, 1, true) then st.item = true st.found[#st.found + 1] = t end end
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
-- every imbue you know is a button of its own, the one you cast last first; all go once one is on the weapon (the user,
-- 2026-10-17: "i now have rockbiter and flametongue, it only offers flametongue button though, it should show both
-- choices, disappearing once one is on your weapon")
local IMBUE_ORDER = { "Rockbiter Weapon", "Flametongue Weapon", "Frostbrand Weapon", "Windfury Weapon" }
local function knownImbues()
  local d, out = db(), {}
  if d.spell and known(IMBUES, d.spell) then out[1] = d.spell end
  for _, name in ipairs(IMBUE_ORDER) do if name ~= d.spell and known(IMBUES, name) then out[#out + 1] = name end end
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
-- which of the two is on the weapon now (db().cur: "imbue" as you cast it, "item" as an oil or stone goes from your
-- bags; nil when the weapon is bare or it isn't known): only its own pop-up goes when it's on (the user, 2026-10-17:
-- "it removed the rockbite button when i applied wizard oil via the button, it should only remove the button you click")
-- Which one it is, decided as the weapon gets it: the more recent of your imbue cast and your click on the oil's button
-- (or an oil gone from your bags), within RECENT seconds. The bags can update after the weapon shows the oil, so the
-- oil's own button marks it (the user, 2026-10-17: "as soon as i used that button the rockbiter one disappeared")
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
-- which one is on: from the enchant id the game reports (the user, 2026-10-17: after a reload "a pop up saying i need
-- to apply rockbiter and minor wizard oil but i already have rockbiters on"; the guess from recent clicks was gone),
-- else the guess; not known at all: both go
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
end
local KINDS = {}   -- in order: weapon, then the self buffs (the buttons stack down)
KINDS[1] = "weapon"
for n = 2, #IMBUE_ORDER do KINDS[#KINDS + 1] = "weapon" .. n end
KINDS[#KINDS + 1] = "oil"
for _, g in ipairs(GROUPS) do KINDS[#KINDS + 1] = "buff_" .. g.class .. "_" .. g.key end

-- ------------------------------------------------------------------ the buttons
local function makeButton(kind)
  local k = K[kind]
  local b = ns.newFrame("Imbue", "Button", "AuDHD_" .. kind .. "Button", UIParent, "SecureActionButtonTemplate,BackdropTemplate")
  b:SetSize(380, 34)
  if b.SetBackdrop then
    b:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    b:SetBackdropColor(0.05, 0.12, 0.25, 0.92)
  end
  local key = kind .. "Button"
  local pos = AuDHDDB[key]
  -- stacked down from under the rare button's place, one row per kind your class has
  local row = 0
  for _, other in ipairs(KINDS) do
    if other == kind then break end
    if K[other].on() ~= nil then row = row + 1 end
  end
  if pos then b:SetPoint(pos.p, UIParent, pos.rp, pos.x, pos.y) else b:SetPoint("TOP", UIParent, "TOP", 0, -140 - 38 * row) end
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetMovable(true)
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
  b:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    AuDHDDB[key] = { p = p, rp = rp, x = x, y = y }
  end)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(22, 22)
  b.icon:SetPoint("LEFT", 6, 0)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
  b.text:SetPoint("RIGHT", -28, 0)
  b.text:SetJustifyH("LEFT")
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetPoint("TOPLEFT", 3, -3)
  hl:SetPoint("BOTTOMRIGHT", -3, 3)
  hl:SetColorTexture(0.4, 0.7, 1, 0.18)
  local close = ns.newFrame("Imbue", "Button", nil, b, "UIPanelCloseButton")
  close:SetSize(22, 22)
  close:SetPoint("RIGHT", -2, 0)
  close:SetScript("OnClick", function() k.closed = true I.hide(kind) end)
  -- the oil's button: what goes on the weapon next is the oil
  if kind == "oil" then b:SetScript("PreClick", function() db().tItem = GetTime() end) end
  b:Hide()
  return b
end

function I.hide(kind)
  local k = K[kind]
  k.pending = nil
  if k.button and k.button.on then
    -- in a fight the game won't hide it: gone from sight now, hidden after the fight (the user, 2026-10-17: "once you
    -- cast rockbiter the warning should disappear")
    if InCombatLockdown() then k.pending = "hide" k.button:SetAlpha(0) return end
    k.button.on = false
    k.button:Hide()
  end
end
-- a spell's own icon: this client has C_Spell, not the old global GetSpellTexture; a question mark if neither knows it
-- (the fallback was Rockbiter's icon, so a warlock's Demon Skin showed it: the user, 2026-10-17)
local function spellIcon(name)
  local t = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(name)
  if not t and GetSpellTexture then t = GetSpellTexture(name) end
  return t or 134400
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
  else
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", ("/use item:%d\n/use 16"):format(src.item))
    b.msg = ("No oil or stone on your weapon: click to put on %s (%d left)"):format(itemName(src.item), uses(src.item))
    b.icon:SetTexture(itemIcon(src.item))
  end
  b.text:SetText(b.msg)
  b:SetAlpha(1)
  if b.on then return end
  b.on = true
  b:Show()
  PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
  log(k.buff and "BUFF_OFF" or "IMBUE_GONE", { spell = src.spell, item = src.item, left = not k.buff and lastLeft or nil })
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
  -- off for OFF_TICKS checks in a row before it comes up: not for a moment's blink (the user, 2026-10-17: "the rock
  -- biter pop up came up even though i had rockbiter on")
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
function I.sourceOf(key)
  for _, v in pairs(K) do if v.group and v.group.key == key and v.on() ~= nil then return v.source() end end
end

-- /wfn imbue [off|on]: the weapon; /wfn buffs [off|on]: the self buffs (no word: show what's off now)
function I.command(arg, which)
  local kinds = {}
  for _, kind in ipairs(KINDS) do if (which == "buffs") == (K[kind].buff == true) then kinds[#kinds + 1] = kind end end
  local what = which == "buffs" and "self buff" or "weapon buff"
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
