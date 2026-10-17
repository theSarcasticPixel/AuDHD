-- The research logger: what you actually do while following a route, for calibrating the planner (seconds per kill,
-- travel, XP) and fixing its data (quest givers, objective places, drops, gathering nodes, vendors).
-- Written to AuDHDLog (SavedVariables): the game saves it on /reload, logout or exit.
--
-- Every entry: { t = server time, e = event name, lv = level, xp = XP into the level, m = uiMap, x, y, ... }.
-- Anything the game hides from addons (secret values) is left out, never guessed.
local _, ns = ...
local L = {}
ns.log = L

local isSecret = issecretvalue or function() return false end
local function clean(v)
  if v == nil or isSecret(v) then return nil end
  return v
end
local function round1(v) return v and math.floor(v * 1000 + 0.5) / 10 or nil end

-- where you are: uiMap and map position (0..100), or nil where the game won't say (instances)
function L.where()
  local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
  if not ok or not clean(m) then return nil end
  local ok2, pos = pcall(C_Map.GetPlayerMapPosition, m, "player")
  if not ok2 or not pos then return m end
  local x, y = pos:GetXY()
  return m, round1(clean(x)), round1(clean(y))
end

local session
function L.start()
  AuDHDLog = AuDHDLog or { v = 1, sessions = {} }
  local name, realm = UnitFullName("player")
  local _, build = GetBuildInfo()
  local _, race = UnitRace("player")
  local _, class = UnitClass("player")
  session = { started = GetServerTime(), char = name, realm = realm, race = race, class = class, build = build,
              route = AuDHDDB and AuDHDDB.route, entries = {} }
  table.insert(AuDHDLog.sessions, session)
  -- the oldest sessions go once the log is over KEEP entries (about 1.3 MB): it's all loaded every session and written on every
  -- /reload (62 sessions, 3.3 MB by 2026-10-16); tools/read_log.mjs has copied them to data/logs already
  local KEEP, total = 6000, 0
  for i = #AuDHDLog.sessions, 1, -1 do
    total = total + #(AuDHDLog.sessions[i].entries or {})
    if total > KEEP and i < #AuDHDLog.sessions then
      for _ = 1, i do table.remove(AuDHDLog.sessions, 1) end
      break
    end
  end
  L.add("SESSION_START", { money = GetMoney(), bind = clean(GetBindLocation()),
                           char = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?") })
end

-- one entry, with time, level, XP and position filled in
function L.add(event, fields)
  if not session then return end
  local e = fields or {}
  e.e = event
  e.t = GetServerTime()
  e.lv = UnitLevel("player")
  e.xp = UnitXP("player")
  local m, x, y = L.where()
  e.m, e.x, e.y = m, x, y
  table.insert(session.entries, e)
  return e
end

function L.count()
  return session and #session.entries or 0, AuDHDLog and #AuDHDLog.sessions or 0
end

-- ------------------------------------------------------------------ helpers for the events below
local function npcIdOf(guid)
  guid = clean(guid)
  if type(guid) ~= "string" then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind == "Creature" or kind == "Vehicle" or kind == "GameObject" then return tonumber(id), kind end
  return nil, kind
end
L.npcIdOf = npcIdOf

local function unitInfo(unit)
  if not UnitExists(unit) then return nil end
  local id, kind = npcIdOf(UnitGUID(unit))
  return { id = id, kind = kind, name = clean(UnitName(unit)), level = clean(UnitLevel(unit)),
           class = clean(UnitClassification(unit)) }
end

local function questObjectives(questID)
  local ok, objs = pcall(C_QuestLog.GetQuestObjectives, questID)
  if not ok or type(objs) ~= "table" then return nil end
  local out = {}
  for i, o in ipairs(objs) do
    out[i] = { text = clean(o.text), type = clean(o.type), have = clean(o.numFulfilled), need = clean(o.numRequired),
               done = clean(o.finished) }
  end
  return out
end
L.questObjectives = questObjectives

-- objective progress: what changed since the last look (gives exact places for objectives)
local lastObj = {}
local function scanObjectives()
  local ok, n = pcall(C_QuestLog.GetNumQuestLogEntries)
  if not ok or not n then return end
  for i = 1, n do
    local info = C_QuestLog.GetInfo(i)
    if info and not info.isHeader and info.questID then
      local q = info.questID
      local objs = questObjectives(q)
      if objs then
        lastObj[q] = lastObj[q] or {}
        for j, o in ipairs(objs) do
          local prev = lastObj[q][j]
          -- a count going up, or an objective without one (e.g. "Tame a ...") turning done
          local wasDone = lastObj[q]["d" .. j]
          if (o.have and prev and o.have > prev) or (o.done and wasDone == false) then
            L.add("OBJECTIVE", { q = q, i = j, text = o.text, have = o.have, need = o.need, done = o.done })
          end
          lastObj[q][j] = o.have or false
          lastObj[q]["d" .. j] = o.done and true or false
        end
      end
    end
  end
end

-- ------------------------------------------------------------------ events
local lastMoney, lastXP, lastLevel = nil, nil, nil
local questNpc        -- the NPC (or object) you last talked to about a quest
local frame = CreateFrame("Frame")
local handlers = {}

function handlers.QUEST_DETAIL() questNpc = unitInfo("npc") end
function handlers.QUEST_PROGRESS() questNpc = unitInfo("npc") end
function handlers.QUEST_COMPLETE() questNpc = unitInfo("npc") end
function handlers.GOSSIP_SHOW() questNpc = unitInfo("npc") end

function handlers.QUEST_ACCEPTED(questID)
  local title = clean(C_QuestLog.GetTitleForQuestID(questID))
  L.add("QUEST_ACCEPTED", { q = questID, title = title, npc = questNpc, objectives = questObjectives(questID) })
  lastObj[questID] = {}
  local objs = questObjectives(questID)
  if objs then for j, o in ipairs(objs) do lastObj[questID][j] = o.have end end
end
function handlers.QUEST_TURNED_IN(questID, xpReward, moneyReward)
  L.add("QUEST_TURNED_IN", { q = questID, xpReward = clean(xpReward), money = clean(moneyReward), npc = questNpc })
  lastObj[questID] = nil
end
function handlers.QUEST_REMOVED(questID) L.add("QUEST_REMOVED", { q = questID }) end

-- quest timers, from the game (no data source lists them; Scalding Mornbrew's 5 minutes, the user 2026-10-17): kept in
-- ns.questTimers (questID -> seconds left) so a timed quest takes over the route, and logged once per quest
ns.questTimers = {}
local timerLogged = {}
local function scanTimers()
  local timers = {}
  if GetQuestTimers and GetQuestIndexForTimer then
    local ok, list = pcall(function() return { GetQuestTimers() } end)
    for k, secs in ipairs(ok and list or {}) do
      local ok2, index = pcall(GetQuestIndexForTimer, k)
      local info = ok2 and index and C_QuestLog.GetInfo(index)
      local q = info and info.questID
      if q and tonumber(secs) then
        timers[q] = tonumber(secs)
        if not timerLogged[q] then
          timerLogged[q] = true
          L.add("QUEST_TIMER", { q = q, secs = math.floor(secs) })
        end
      end
    end
  end
  ns.questTimers = timers
end

-- where the game's quest map points for each quest in your log (its waypoint, or the POI icon), logged once per spot:
-- real places for Forever's own quests the data lacks (Mountaineer Cornelius, "in the Grizzled Den" but not in the
-- wendigo cave, the user 2026-10-17). Whatever this client has; nothing if it has none
local poiLogged = {}
local function scanPOIs()
  local ok, n = pcall(C_QuestLog.GetNumQuestLogEntries)
  for i = 1, (ok and n or 0) do
    local info = C_QuestLog.GetInfo(i)
    local q = info and not info.isHeader and info.questID
    if q then
      local m, x, y, src
      if C_QuestLog.GetNextWaypoint then
        local ok2, wm, wx, wy = pcall(C_QuestLog.GetNextWaypoint, q)
        if ok2 and wm and wx then m, x, y, src = wm, wx, wy, "waypoint" end
      end
      if not x and QuestPOIGetIconInfo then
        local ok3, _, px, py = pcall(QuestPOIGetIconInfo, q)
        if ok3 and px then m, x, y, src = C_Map.GetBestMapForUnit("player"), px, py, "poi" end
      end
      if x and not isSecret(x) then
        local key = ("%d:%.1f:%.1f"):format(q, x * 100, y * 100)
        if not poiLogged[key] then
          poiLogged[key] = true
          L.add("QUEST_POI", { q = q, pm = m, px = math.floor(x * 1000) / 10, py = math.floor(y * 1000) / 10, src = src,
            done = C_QuestLog.IsComplete(q) or nil })
        end
      end
    end
  end
end

local scanQueued = false
function handlers.QUEST_LOG_UPDATE()
  if scanQueued then return end
  scanQueued = true
  C_Timer.After(0.5, function() scanQueued = false; scanObjectives(); scanTimers(); pcall(scanPOIs) end)
end

function handlers.PLAYER_XP_UPDATE(unit)
  if unit and unit ~= "player" then return end
  local xp, level = UnitXP("player"), UnitLevel("player")
  if lastXP and level == lastLevel and xp > lastXP then
    L.add("XP", { gain = xp - lastXP, rested = clean(GetXPExhaustion()), combat = InCombatLockdown() or nil })
  end
  lastXP, lastLevel = xp, level
end
function handlers.PLAYER_LEVEL_UP(level)
  L.add("LEVEL_UP", { level = level })
  lastXP, lastLevel = UnitXP("player"), level
end
-- "X dies, you gain N experience." (kill XP with the creature's name)
function handlers.CHAT_MSG_COMBAT_XP_GAIN(text) L.add("KILL_XP", { text = clean(text) }) end
function handlers.CHAT_MSG_LOOT(text) L.add("LOOT", { text = clean(text) }) end
function handlers.CHAT_MSG_SKILL(text) L.add("SKILL", { text = clean(text) }) end
function handlers.CHAT_MSG_MONEY(text) L.add("LOOT_MONEY", { text = clean(text) }) end

function handlers.PLAYER_MONEY()
  local m = GetMoney()
  if lastMoney and m ~= lastMoney then L.add("MONEY", { delta = m - lastMoney, total = m }) end
  lastMoney = m
end

-- what you looted from (creatures, and gathering nodes as game objects)
function handlers.LOOT_OPENED()
  local items = {}
  for i = 1, (GetNumLootItems() or 0) do
    local link = clean(GetLootSlotLink(i))
    local src = { GetLootSourceInfo(i) }
    local sources = {}
    for k = 1, #src, 2 do
      local id, kind = npcIdOf(src[k])
      if id then sources[#sources + 1] = { id = id, kind = kind } end
    end
    items[#items + 1] = { link = link, from = sources }
  end
  L.add("LOOT_OPENED", { items = items })
end

function handlers.PLAYER_TARGET_CHANGED()
  local u = unitInfo("target")
  if u and u.id and not UnitIsFriend("player", "target") then L.add("TARGET", { unit = u }) end
end

-- casts out of combat: crafting, gathering, taming, hearthstone, professions
function handlers.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
  if unit ~= "player" or InCombatLockdown() then return end
  spellID = clean(spellID)
  if not spellID then return end
  local name = C_Spell and C_Spell.GetSpellName and clean(C_Spell.GetSpellName(spellID))
  L.add("CAST", { spell = spellID, name = name, target = unitInfo("target") })
end

function handlers.PLAYER_EQUIPMENT_CHANGED(slot)
  if slot == 16 or slot == 17 or slot == 18 then
    L.add("EQUIP", { slot = slot, link = clean(GetInventoryItemLink("player", slot)) })
  end
end
function handlers.MERCHANT_SHOW() L.add("MERCHANT", { npc = unitInfo("npc") }) end
function handlers.TRAINER_SHOW() L.add("TRAINER", { npc = unitInfo("npc") }) end
function handlers.TAXIMAP_OPENED() L.add("FLIGHT_MASTER", { npc = unitInfo("npc") }) end
function handlers.PLAYER_CONTROL_LOST() if UnitOnTaxi("player") then L.add("FLIGHT_START") end end
function handlers.PLAYER_CONTROL_GAINED() L.add("CONTROL_GAINED", { taxi = UnitOnTaxi("player") or nil }) end
function handlers.CONFIRM_BINDER() L.add("BIND_OFFERED", { npc = unitInfo("npc") }) end
function handlers.PLAYER_DEAD() L.add("DIED") end
function handlers.PLAYER_UNGHOST() L.add("ALIVE", { from = "ghost" }) end
function handlers.PLAYER_ALIVE() if not UnitIsDeadOrGhost("player") then L.add("ALIVE") end end
function handlers.ZONE_CHANGED_NEW_AREA() L.add("ZONE", { zone = clean(GetZoneText()), sub = clean(GetSubZoneText()) }) end
function handlers.PLAYER_REGEN_DISABLED() L.add("COMBAT_START", { target = unitInfo("target") }) end
-- the fight that just ended, from Blizzard's damage meter (C_DamageMeter: the raw combat log is closed to addons in
-- Forever): its length, your damage and DPS, your pet's if it's listed apart, and the damage you took
local DM_DAMAGE, DM_TAKEN = 0, 7   -- Enum.DamageMeterType.DamageDone, .DamageTaken
local function lastFight()
  if not (C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions) then return nil end
  local okA, avail = pcall(C_DamageMeter.IsDamageMeterAvailable)
  if okA and avail == false then return nil end
  local ok, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
  if not ok or type(sessions) ~= "table" or #sessions == 0 then return nil end
  local last = sessions[1]
  for _, sn in ipairs(sessions) do if (sn.sessionID or 0) > (last.sessionID or 0) then last = sn end end
  local fight = { session = last.sessionID, secs = clean(last.durationSeconds) }
  local function sources(kind)
    local okS, sess = pcall(C_DamageMeter.GetCombatSessionFromID, last.sessionID, kind)
    if not okS or type(sess) ~= "table" then return nil end
    return sess.combatSources or {}
  end
  for _, src in ipairs(sources(DM_DAMAGE) or {}) do
    if src.isLocalPlayer then
      fight.dmg, fight.dps = clean(src.totalAmount), clean(src.amountPerSecond)
    elseif src.classification == "pet" or (src.sourceGUID and not isSecret(src.sourceGUID) and src.sourceGUID == UnitGUID("pet")) then
      fight.petDmg = clean(src.totalAmount)
    end
  end
  for _, src in ipairs(sources(DM_TAKEN) or {}) do
    if src.isLocalPlayer then fight.taken = clean(src.totalAmount) end
  end
  return fight
end

function handlers.PLAYER_REGEN_ENABLED()
  local e = L.add("COMBAT_END", { hp = clean(UnitHealth("player")), hpMax = clean(UnitHealthMax("player")) })
  -- the meter settles a moment after combat ends
  C_Timer.After(1, function()
    local ok, fight = pcall(lastFight)
    if ok and fight and e then e.fight = fight end
  end)
end

-- No combat log: in Forever even registering for COMBAT_LOG_EVENT_UNFILTERED is Blizzard-only (the "blocked from an
-- action" pop-up). Kills come from the XP messages, fights from combat start / end and C_DamageMeter.

frame:SetScript("OnEvent", function(_, event, ...)
  local h = handlers[event]
  if h then
    local ok, err = pcall(h, ...)
    if not ok and session then L.add("LOGGER_ERROR", { event = event, err = tostring(err) }) end
  end
end)

function L.enable()
  for event in pairs(handlers) do pcall(frame.RegisterEvent, frame, event) end
  lastMoney, lastXP, lastLevel = GetMoney(), UnitXP("player"), UnitLevel("player")
  -- the trail: where you are every 10 seconds when you've moved (gives real travel times and paths)
  local lastM, lastX, lastY
  C_Timer.NewTicker(10, function()
    local m, x, y = L.where()
    if not x then return end
    if m ~= lastM or not lastX or math.abs(x - lastX) + math.abs(y - lastY) > 0.4 then
      L.add("POS", { combat = InCombatLockdown() or nil, taxi = UnitOnTaxi("player") or nil, mounted = IsMounted() or nil,
                     ammo = ns.ammo and ns.ammo.count() or nil })
      lastM, lastX, lastY = m, x, y
    end
  end)
  -- every 5 minutes: the addon's memory, all addons' Lua memory and your frame rate, so a slow-down over a long session
  -- shows whether it's ours (our memory climbing) or the client's (fps down, ours flat). The user, 2026-10-17: 15 fps
  -- after hours of play, /reload didn't help, a restart did
  C_Timer.NewTicker(300, function()
    local mine
    if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
      UpdateAddOnMemoryUsage()
      mine = math.floor(GetAddOnMemoryUsage("AuDHD"))
    end
    L.add("HEALTH", { memKB = mine, luaKB = math.floor(collectgarbage("count")),
                      fps = GetFramerate and math.floor(GetFramerate()) or nil })
  end)
  scanObjectives()
end
