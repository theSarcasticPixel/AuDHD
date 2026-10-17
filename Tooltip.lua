-- Mob tooltips: the quest items this mob drops for quests in your log that still need them, with the chance we know or
-- guess, and what you've had yourself so far (the user, 2026-10-16: "showing the % rating we know/guess and the actual
-- one you've had so far"):  "Dewy Lasher Frond   25%  ·  you 2/9 (22%)". A tooltip post-hook, unit and loot APIs and
-- our own data only: nothing protected.
--
-- Your own count: kills of the mob while a quest in your log still needs the item, and the corpses that had it.
-- Forever won't let addons read the combat log, so a kill is a mob you were fighting (on your or your pet's threat
-- table, and not tapped by someone else) that we see dead: your target, your mouseover, a nameplate, or a corpse you
-- loot. One that dies out of sight and isn't looted is missed. Kept in AuDHDDB.drops[npc][item] = { k, d }.
local _, ns = ...
local D = {}
ns.drops = D

local isSecret = issecretvalue or function() return false end

-- the NPC id from a creature GUID ("Creature-0-...-<npc id>-...")
local function npcOfGuid(guid)
  if not guid or isSecret(guid) then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
  return tonumber(id)
end
local function npcID(unit) return npcOfGuid(UnitGUID(unit)) end

-- still needed: the quest is in your log and the objective naming this item isn't finished
local function stillNeeded(questID, item)
  if not C_QuestLog.IsOnQuest(questID) then return false end
  local objs = C_QuestLog.GetQuestObjectives(questID)
  if not objs then return true end
  for _, o in ipairs(objs) do
    if o.text and o.text:find(item, 1, true) then return not o.finished end
  end
  return true
end

-- ------------------------------------------------------------------ your own count
local function store(npc, item)
  AuDHDDB.drops = AuDHDDB.drops or {}
  local m = AuDHDDB.drops[npc] or {}
  AuDHDDB.drops[npc] = m
  m[item] = m[item] or { k = 0, d = 0 }
  return m[item]
end
-- what you've had from npc of item: kills, drops (nil when none counted)
function D.mine(npc, item)
  local m = AuDHDDB and AuDHDDB.drops and AuDHDDB.drops[npc]
  local s = m and m[item]
  if s and s.k > 0 then return s.k, s.d end
end

local engaged = {}   -- mobs you've been fighting, by GUID: npc id (a quest-drop mob only)
local counted = {}   -- GUIDs whose death is counted
local looted = {}    -- "GUID:item" drops counted

-- a kill of npc (GUID guid): one more try for each item it drops that a quest still needs
local function kill(guid, npc)
  if counted[guid] then return end
  counted[guid] = true
  engaged[guid] = nil
  for _, d in ipairs(ns.questDrops[npc] or {}) do
    if stillNeeded(d.q, d.i) then local s = store(npc, d.i) s.k = s.k + 1 end
  end
end

local function fightingIt(unit)
  if UnitThreatSituation then
    local a, b = UnitThreatSituation("player", unit), UnitExists("pet") and UnitThreatSituation("pet", unit) or nil
    if (a ~= nil and not isSecret(a)) or (b ~= nil and not isSecret(b)) then return true end
  end
  -- no threat API: a mob in combat that's your target
  return UnitIsUnit and UnitIsUnit(unit, "target") and UnitAffectingCombat(unit)
end

-- look at one unit: note a quest-drop mob you're fighting, count it when it's dead
local function look(unit)
  if not UnitExists(unit) then return end
  local guid = UnitGUID(unit)
  local npc = npcOfGuid(guid)
  if not npc or not ns.questDrops or not ns.questDrops[npc] then return end
  if UnitIsDead(unit) then
    if engaged[guid] and not (UnitIsTapDenied and UnitIsTapDenied(unit)) then kill(guid, npc) end
  elseif not engaged[guid] and fightingIt(unit) then
    engaged[guid] = npc
  end
end
function D.scan()
  if not ns.questDrops then return end
  for _, u in ipairs({ "target", "mouseover", "pettarget", "focus" }) do pcall(look, u) end
  if C_NamePlate and C_NamePlate.GetNamePlates then
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    for _, p in ipairs(ok and plates or {}) do
      local unit = p.namePlateUnitToken or (p.UnitFrame and p.UnitFrame.unit)
      if unit and not isSecret(unit) then pcall(look, unit) end
    end
  end
end

-- a loot window: each quest-drop corpse counts as a kill (if we missed it), and the quest items it had as drops
function D.loot()
  if not ns.questDrops then return end
  local corpses, had = {}, {}
  for i = 1, (GetNumLootItems() or 0) do
    local link = GetLootSlotLink(i)
    local name = link and not isSecret(link) and link:match("%[(.-)%]")
    local src = { GetLootSourceInfo(i) }
    for k = 1, #src, 2 do
      local guid = src[k]
      local npc = npcOfGuid(guid)
      if npc and ns.questDrops[npc] then
        corpses[guid] = npc
        if name then had[guid .. ":" .. name] = { npc = npc, item = name } end
      end
    end
  end
  -- drops first: the quest still needs the item while it's in the window (taking it may finish the objective)
  for key, h in pairs(had) do
    if not looted[key] then
      for _, d in ipairs(ns.questDrops[h.npc]) do
        if d.i == h.item and stillNeeded(d.q, d.i) then
          looted[key] = true
          local s = store(h.npc, h.item)
          s.d = s.d + 1
          break
        end
      end
    end
  end
  for guid, npc in pairs(corpses) do kill(guid, npc) end
end

function D.enable()
  local f = ns.newFrame("Tooltip", "Frame")
  for _, e in ipairs({ "LOOT_OPENED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_REMOVED", "UNIT_HEALTH" }) do
    pcall(f.RegisterEvent, f, e)
  end
  f:SetScript("OnEvent", function(_, event, unit)
    if event == "LOOT_OPENED" then
      local ok, err = pcall(D.loot)
      if not ok and ns.log then ns.log.add("DROPS_ERROR", { err = tostring(err) }) end
    elseif event == "NAME_PLATE_UNIT_REMOVED" or event == "UNIT_HEALTH" then
      if unit and not isSecret(unit) then pcall(look, unit) end
    else
      pcall(D.scan)
    end
  end)
  -- threat and death come without an event we can rely on: look a few times a second
  local acc = 0
  f:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.25 then return end
    acc = 0
    pcall(D.scan)
  end)
end

-- ------------------------------------------------------------------ the tooltip
-- the lines for unit: { item, chances, quest title } for each quest item it drops that you still need
function D.lines(unit)
  local out = {}
  local id = ns.questDrops and npcID(unit)
  for _, d in ipairs(id and ns.questDrops[id] or {}) do
    if stillNeeded(d.q, d.i) then
      local title = C_QuestLog.GetTitleForQuestID(d.q) or ("quest " .. d.q)
      local known = ("%d%%%s"):format(math.floor(d.p + 0.5), d.m and "" or " (est.)")
      local k, got = D.mine(id, d.i)
      local mine = k and ("  |cff88ccffyou %d/%d (%d%%)|r"):format(got, k, math.floor(100 * got / k + 0.5)) or ""
      out[#out + 1] = { ("|cffffd100%s|r"):format(d.i), known .. mine, title }
    end
  end
  return out
end
local function addLines(tooltip)
  if tooltip ~= GameTooltip then return end
  local _, unit = tooltip:GetUnit()
  if not unit or isSecret(unit) then return end
  for _, l in ipairs(D.lines(unit)) do
    tooltip:AddDoubleLine(l[1], l[2], 1, 1, 1, 1, 1, 1)
    tooltip:AddLine("   " .. l[3], 0.6, 0.6, 0.6)
  end
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
    local ok, err = pcall(addLines, tooltip)
    if not ok and ns.log then ns.log.add("TOOLTIP_ERROR", { err = tostring(err) }) end
  end)
elseif GameTooltip then
  GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip) pcall(addLines, tooltip) end)
end
