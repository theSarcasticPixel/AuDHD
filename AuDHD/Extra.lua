-- Quests you want on top of the guide. Each stop of the quest (pick up, its work, hand in) goes where it adds the least
-- walking to the steps ahead, not before you're the level for it; it comes up when the guide reaches that point, or sooner
-- when you pass within reach. Worked out here in the game from your own place in the guide: nothing is planned in advance.
local _, ns = ...
local X = {}
ns.extra = X

local function say(msg) print("|cff66ccffAuDHD|r: " .. msg) end
local function engine() local e = AuDHDEngine return e and e.Engine, e and e.QuestDB, e end
local function inLog(q) return C_QuestLog.GetLogIndexForQuestID(q) ~= nil end
local function done(q) return C_QuestLog.IsQuestFlaggedCompleted(q) end

-- not game facts: our own judgement. How many levels under a quest you may start its work, how near (yards) counts as
-- passing it, how long an objective takes (seconds per thing to do) for the time told to you, how far ahead to look
local LEVELS_UNDER, PASSING, SECONDS_EACH, LOOK_AHEAD = 2, 120, 25, 80

-- ------------------------------------------------------------------ your extra quests, per character
local function list()
  AuDHDDB.extras = AuDHDDB.extras or {}
  local key = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
  AuDHDDB.extras[key] = AuDHDDB.extras[key] or {}
  return AuDHDDB.extras[key]
end
X.list = list
-- the stops you put off or ticked, per character: [q] = { done = { [kind] = true }, until = step index, away }
local function held()
  AuDHDDB.extrasHeld = AuDHDDB.extrasHeld or {}
  local key = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
  AuDHDDB.extrasHeld[key] = AuDHDDB.extrasHeld[key] or {}
  return AuDHDDB.extrasHeld[key]
end

-- the places of the steps ahead, with the level the guide has reached by then
local function ahead()
  local E = engine()
  local out = {}
  local g = E and E.GetGuide()
  local cur = E and E.GetStepIndex()
  if not (g and cur) then return out end
  local level = UnitLevel("player") or 1
  for i = cur, math.min(#g.steps, cur + LOOK_AHEAD) do
    local at
    for _, goal in ipairs(g.steps[i].goals) do
      if goal.t == "accept" and goal.minLevel and goal.minLevel > level then level = goal.minLevel end
      if goal.map and goal.x and goal.y and not at then at = { map = goal.map, x = goal.x, y = goal.y, f = goal.f } end
    end
    if at then out[#out + 1] = { i = i, at = at, level = level } end
  end
  return out
end

-- the cheapest place for one stop, from step index `after` on: its extra yards on the way between two steps. Of a stop's
-- several spawn spots, the one nearest that part of the route is what counts.
local function place(spawns, route, after, needLevel)
  local best
  for k, r in ipairs(route) do
    if r.i >= after and r.level >= needLevel then
      local nxt = route[k + 1]
      local base = nxt and ns.geo.yards(r.at, nxt.at) or 0
      for _, s in ipairs(spawns) do
        local a = ns.geo.yards(r.at, s)
        local b = nxt and ns.geo.yards(s, nxt.at) or 0
        if a and b and base then
          local extra = a + b - base
          if not best or extra < best.extra then best = { extra = extra, at = r.i, spot = s } end
        end
      end
    end
  end
  return best
end

-- this quest's stops still to do, each with where it goes
local function plan(q)
  local _, db = engine()
  local rec = db and db.GetQuest(q)
  if not rec or done(q) then return nil end
  local route = ahead()
  local stops, after, yards, missing = {}, 0, 0, false
  local function add(kind, spawns, need, text)
    if #spawns == 0 then missing = true return end
    local p = place(spawns, route, after, need)
    if not p then p = { extra = 0, at = route[#route] and route[#route].i or 0, spot = spawns[1], late = true } end
    after = p.at
    yards = yards + math.max(0, p.extra)
    local m, x, y = ns.geo.live(p.spot)
    stops[#stops + 1] = { k = kind, at = p.at, m = m, x = x, y = y, t = text, spot = p.spot }
  end
  local title = rec.title or ("quest " .. q)
  local min, lvl = rec.minLevel or 1, rec.level or rec.minLevel or 1
  if not inLog(q) then add("accept", ns.track.startSpawns(q), min, "Pick up " .. title) end
  -- a profession quest (raise a skill, make things) has no place to send you: only its hand-in, once it's ready
  -- (professions are the player's choice)
  if not (inLog(q) and ns.core.readyToHandIn(q)) and #rec.objectives > 0 and not rec.skill then
    add("do", ns.track.objectiveSpawns(q), math.max(min, lvl - LEVELS_UNDER), "Do " .. title)
  end
  add("turnin", ns.track.finishSpawns(q), min, "Hand in " .. title)
  local things = 0
  for _, o in ipairs(rec.objectives) do things = things + (o.count or 1) end
  -- run speed in yards a second: 7 on foot
  local seconds = yards / 7 + things * SECONDS_EACH
  local xp = ns.questFacts and ns.questFacts.xpByLevel[lvl]
  return { q = q, title = title, stops = stops, seconds = seconds, xp = xp, level = lvl, missing = missing }
end
X.plan = plan

-- ------------------------------------------------------------------ what comes up now
local plans = {}
local function replan()
  plans = {}
  for q in pairs(list()) do
    if done(q) then list()[q] = nil held()[q] = nil else plans[q] = plan(q) end
  end
end
X.replan = replan
-- A stop the guide has reached that's out of the way waits: going there, then on to the guide's next place, against
-- going straight on, timed by the router with flights, boats and the hearth. It comes up once that's DETOUR_MAX seconds
-- or less, when you pass within reach, or at the guide's last step so it's never lost. Not a game fact: our own
-- judgement (about 3 min). Looked at again every DETOUR_LOOK seconds at most; nil when the router can't tell (it comes
-- up as before)
local DETOUR_MAX, DETOUR_LOOK = 180, 10
local detours = {}   -- "q:kind" -> { at = GetTime(), s = seconds or false, logged }
function X.detour(q, stop)
  local A = AuDHDEngine
  local N = A and A.Nav
  if not (N and N.EstimateTravel and stop.m and stop.x and stop.y) then return nil end
  local key = q .. ":" .. stop.k
  local now = GetTime()
  local c = detours[key]
  if c and now - c.at < DETOUR_LOOK then return c.s or nil end
  local to = stop.spot or { map = stop.m, x = stop.x, y = stop.y }
  local there = N.EstimateTravel(nil, to)
  local nxt = ahead()[1]
  local s = there
  if there and nxt then
    local on, straight = N.EstimateTravel(to, nxt.at), N.EstimateTravel(nil, nxt.at)
    s = on and straight and there + on - straight or nil
  end
  detours[key] = { at = now, s = s or false, logged = c and c.logged }
  return s
end
-- the guide has reached the stop (cur at or past its place) and it isn't out of the way, or it's the guide's last step
local function reached(q, stop, cur, last)
  if cur < stop.at then return false end
  if last then return true end
  local s = X.detour(q, stop)
  if not s or s <= DETOUR_MAX then return true end
  local c = detours[q .. ":" .. stop.k]
  if c and not c.logged and ns.log then
    c.logged = true
    ns.log.add("EXTRA_FAR", { q = q, k = stop.k, s = math.floor(s) })
  end
  return false
end
X.reached = reached   -- (the smoke test)
-- the stop due now, as a step: the guide has reached its place, or you're passing it
function X.due()
  local E = engine()
  local cur = E and E.GetStepIndex()
  if not cur then return nil end
  -- only on top of a levelling guide: a class, reputation or profession guide you picked leads, and your extras wait
  -- for the next levelling guide
  local g = E.GetGuide()
  if g and g.category and g.category ~= "Leveling" then return nil end
  for q, p in pairs(plans) do
    local h = held()[q]
    local stop
    for _, s in ipairs(p.stops) do
      local open = (s.k == "accept" and not inLog(q)) or (s.k == "do" and inLog(q) and not ns.core.readyToHandIn(q))
        or (s.k == "turnin" and inLog(q) and ns.core.readyToHandIn(q))
      if open and not (h and h.done and h.done[s.k]) then stop = s break end
    end
    if stop then
      local step = { i = -1000 - q, q = q, k = stop.k, t = stop.t, m = stop.m, x = stop.x, y = stop.y }
      local d = ns.core.distance(step)
      -- put off (Later): back once the guide is 5 steps on, or you come by again after going away
      local waiting = h and h["until"] and cur < h["until"]
      if waiting and d then
        if d > 2 * PASSING then h.away = true elseif h.away and d <= PASSING then waiting, h["until"] = false, nil end
      end
      if not waiting and ((d and d <= PASSING) or reached(q, stop, cur, g and g.steps and cur >= #g.steps)) then return step end
    end
  end
end

-- Done, Skip and Later on an extra quest's stop act on it, never on the guide step under it
local LATER_STEPS = 5   -- not a game fact: our own judgement
local function title(q) return plans[q] and plans[q].title or ("quest " .. q) end
function X.skip(q)
  local name = title(q)
  list()[q], held()[q] = nil, nil
  replan()
  if ns.log then ns.log.add("EXTRA_SKIP", { q = q }) end
  return name .. " is off your extra quests (it stays in your quest log). /audhd extra add " .. q .. " brings it back"
end
function X.later(q)
  local E = engine()
  local cur = E and E.GetStepIndex() or 0
  local h = held()[q] or {}
  h["until"], h.away = cur + LATER_STEPS, false
  held()[q] = h
  if ns.log then ns.log.add("EXTRA_LATER", { q = q }) end
  return title(q) .. " comes back in " .. LATER_STEPS .. " steps, or when you come by again"
end
function X.done(q, kind)
  local h = held()[q] or {}
  h.done = h.done or {}
  h.done[kind or "do"] = true
  held()[q] = h
  if ns.log then ns.log.add("EXTRA_DONE", { q = q, k = kind }) end
  return nil
end

-- ------------------------------------------------------------------ adding and removing
local function findByName(text)
  local _, db = engine()
  if not db then return nil end
  text = text:lower()
  for _, id in ipairs(db.QuestIds()) do
    local t = db.GetQuestTitle(id)
    if t and t:lower() == text then return id end
  end
end
function X.add(q)
  local _, db = engine()
  if db and db.Load then pcall(db.Load) end
  local rec = db and db.GetQuest(q)
  if not rec then return "we don't have that quest in our data" end
  if done(q) then return "you've already done " .. rec.title end
  list()[q] = true
  held()[q] = nil
  replan()
  local p = plans[q]
  if ns.log then ns.log.add("EXTRA_ADD", { q = q }) end
  if ns.core then ns.core.advance("extra") end
  if not p then return rec.title .. " added" end
  local parts = { ("%s added: about %d min more"):format(p.title, math.ceil(p.seconds / 60)) }
  if p.xp then parts[#parts + 1] = ("for about %d XP"):format(p.xp) end
  if p.missing then
    parts[#parts + 1] = "(we don't know all its places)"
    if ns.share and ns.share.askToLog then ns.share.askToLog(q, "We don't know all the places for this quest.") end
  end
  return table.concat(parts, " ")
end
function X.remove(q)
  list()[q], held()[q] = nil, nil
  replan()
  return "removed"
end
function X.command(rest)
  local cmd, arg = (rest or ""):match("^(%S*)%s*(.-)$")
  if cmd == "add" and arg ~= "" then
    local q = tonumber(arg) or findByName(arg)
    if not q then return "no quest called " .. arg end
    return X.add(q)
  elseif cmd == "remove" and tonumber(arg) then
    return X.remove(tonumber(arg))
  end
  local names = {}
  for q, p in pairs(plans) do names[#names + 1] = ("%s (%d)"):format(p.title, q) end
  return (#names > 0 and ("extra quests: " .. table.concat(names, ", ")) or "no extra quests") .. " (/audhd extra add <quest name or id>, /audhd extra remove <id>)"
end

-- a quest you took yourself that the guide doesn't have: add it?
StaticPopupDialogs["AUDHD_EXTRA"] = {
  text = "%s isn't in your guide. Fit it in where it adds the least time?",
  button1 = "Add it",
  button2 = "No",
  OnAccept = function(self, data) say(X.add(data.q)) end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
function X.onAccepted(q)
  if not q or list()[q] then return end
  local E = engine()
  if not (E and E.GetGuide()) then return end
  local wanted = false
  local g = E.GetGuide()
  for _, s in ipairs(g.steps) do
    for _, goal in ipairs(s.goals) do
      if goal.quest == q then wanted = true break end
    end
    if wanted then break end
  end
  if wanted then return end
  local title = C_QuestLog.GetTitleForQuestID(q) or ("Quest " .. q)
  local dlg = StaticPopup_Show("AUDHD_EXTRA", title)
  if dlg then dlg.data = { q = q } end
end

function X.enable()
  local E, db, A = engine()
  if not E then return end
  if db and db.Load then pcall(db.Load) end
  replan()
  if A then
    A.On("QUESTDB_LOADED", replan)
    A.On("GUIDE_CHANGED", replan)
  end
  local f = ns.newFrame("Extra", "Frame")
  f:RegisterEvent("QUEST_ACCEPTED")
  f:SetScript("OnEvent", function(_, _, a, b) pcall(X.onAccepted, b or a) end)
end
