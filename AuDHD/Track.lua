-- Keeping you on track. Where you've wandered off from: one plain message saying what your step is and how far, never a
-- replay of what you missed. A timed quest in your log comes before everything: straight to finishing and handing it in.
-- A step whose place we don't know says so and asks you to log it (Share.lua).
local _, ns = ...
local T = {}
ns.track = T

local function say(msg) print("|cff66ccffAuDHD|r: " .. msg) end
local function Q() local e = AuDHDEngine return e and e.QuestDB end

-- ------------------------------------------------------------------ places, from the quest database
local function bestSpawn(spawns, from)
  local best, bestD
  for _, s in ipairs(spawns or {}) do
    local d = from and ns.geo.yards(from, s) or 0
    if d and (not bestD or d < bestD) then best, bestD = s, d end
  end
  return best
end
T.bestSpawn = bestSpawn
local function refSpawns(ref)
  local db = Q()
  if not db or not ref then return nil end
  local e = ref > 0 and db.GetNpc(ref) or db.GetObject(-ref)
  return e and e.spawns
end
T.refSpawns = refSpawns
-- every place a quest's objective can be done, flat
function T.objectiveSpawns(q)
  local db = Q()
  local rec = db and db.GetQuest(q)
  local out = {}
  for _, o in ipairs(rec and rec.objectives or {}) do
    if o.kind == "kill" then
      for _, s in ipairs(refSpawns(o.id) or {}) do out[#out + 1] = s end
    elseif o.kind == "object" then
      for _, s in ipairs(refSpawns(-o.id) or {}) do out[#out + 1] = s end
    elseif o.kind == "item" then
      for _, d in ipairs(db.GetItemDroppers(o.id) or {}) do
        if d.id then for _, s in ipairs(refSpawns(d.id) or {}) do out[#out + 1] = s end end
      end
    elseif o.kind == "event" and o.map then
      out[#out + 1] = { map = o.map, x = o.x, y = o.y, f = o.f }
    end
  end
  return out, rec
end
function T.finishSpawns(q)
  local db = Q()
  local rec = db and db.GetQuest(q)
  local out = {}
  if not rec then return out end
  for _, id in ipairs(rec.finish.npc) do for _, s in ipairs(refSpawns(id) or {}) do out[#out + 1] = s end end
  for _, id in ipairs(rec.finish.object) do for _, s in ipairs(refSpawns(-id) or {}) do out[#out + 1] = s end end
  return out
end
function T.startSpawns(q)
  local db = Q()
  local rec = db and db.GetQuest(q)
  local out = {}
  if not rec then return out end
  for _, id in ipairs(rec.start.npc) do for _, s in ipairs(refSpawns(id) or {}) do out[#out + 1] = s end end
  for _, id in ipairs(rec.start.object) do for _, s in ipairs(refSpawns(-id) or {}) do out[#out + 1] = s end end
  return out
end

-- ------------------------------------------------------------------ timed quests
local function inLog(q) return C_QuestLog.GetLogIndexForQuestID(q) ~= nil end
local function isTimed(q)
  return ns.questFacts and ns.questFacts.timed[q] ~= nil
end
T.isTimed = isTimed
-- the timed quest in your log, as a step: to its hand-in when it's ready, else to its work
function T.priority()
  local here = ns.geo and ns.geo.here()
  for q in pairs(ns.questFacts and ns.questFacts.timed or {}) do
    if inLog(q) then
      local db = Q()
      local title = C_QuestLog.GetTitleForQuestID(q) or (db and db.GetQuestTitle(q)) or ("quest " .. q)
      local ready = ns.core.readyToHandIn(q)
      local at = bestSpawn(ready and T.finishSpawns(q) or T.objectiveSpawns(q), here)
      local step = { i = -q, q = q, k = ready and "turnin" or "do",
        t = (ready and "Hand in %s now: it's timed, so nothing else first" or "Finish %s now: it's timed, so nothing else first"):format(title) }
      if at then step.m, step.x, step.y = ns.geo.live(at) end
      local w = not ready and ns.questFacts.ways and ns.questFacts.ways[q]
      if w then
        step.note, step.home = w.note, { m = step.m, x = step.x, y = step.y }
        T.onWay(step)
      end
      return step
    end
  end
end

-- how long is left on a timed quest: seconds, and true when the game said so (false: counted from when you took it, by
-- the quest's time limit in QuestFacts). The game's newer call first, then the old timer list (Log.lua reads it), then
-- the count
local toldHow = {}
local function took() AuDHDDB.timedTook = AuDHDDB.timedTook or {} return AuDHDDB.timedTook end
local function who() return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?") end
function T.tookQuest(q)
  if not isTimed(q) then return end
  local t = took()
  t[who() .. ":" .. q] = time()
end
function T.timeLeft(q)
  local left, how
  if C_QuestLog.GetTimeAllowed then
    local ok, total, elapsed = pcall(C_QuestLog.GetTimeAllowed, q)
    if ok and tonumber(total) and tonumber(total) > 0 and tonumber(elapsed) then left, how = total - elapsed, "game" end
  end
  local s = not left and ns.questTimers and ns.questTimers[q]
  if s then left, how = s - (GetTime() - (ns.questTimersAt or GetTime())), "timers" end
  if not left then
    local at, limit = took()[who() .. ":" .. q], ns.questFacts.timed[q]
    if not (at and limit) then return nil end
    left, how = limit - (time() - at), "count"
  end
  if not toldHow[q] and ns.log then
    toldHow[q] = true
    ns.log.add("QUEST_TIME", { q = q, secs = math.floor(left), how = how })
  end
  return math.max(0, left), how ~= "count"
end
-- for under the step: "Time left: 18:32" (orange, red under 2 minutes; "about" when counted), or nil
function T.timeText(q)
  local left, sure = T.timeLeft(q)
  if not left then return nil end
  local secs = math.floor(left)
  return ("|cff%sTime left: %s%d:%02d|r"):format(secs < 120 and "ff2020" or "ff8000", sure and "" or "about ", math.floor(secs / 60), secs % 60)
end

-- ------------------------------------------------------------------ a way round (QuestFacts ways)
local NEAR_WAY, NEXT_WAY = 150, 25   -- yards: on the way when this near a point of it; a point this near is passed
local ways = {}   -- quest -> its points with world places and the yards left along the way after each, or false
local function wayOf(q)
  if ways[q] ~= nil then return ways[q] end
  local w = ns.questFacts.ways and ns.questFacts.ways[q]
  if not (w and ns.walk) then return nil end
  local pts = {}
  for part in w.pts:gmatch("[^;]+") do
    local m, list = part:match("^(%d+):(.+)$")
    for x, y in (list or ""):gmatch("([%d%.]+),([%d%.]+)") do
      local p = { m = tonumber(m), x = tonumber(x), y = tonumber(y) }
      p.c, p.X, p.Y = ns.walk.toWorld(p.m, p.x, p.y)
      if not p.c then ways[q] = false return false end
      pts[#pts + 1] = p
    end
  end
  local left = 0
  for i = #pts, 1, -1 do
    local n = pts[i + 1]
    if n then left = left + math.sqrt((n.X - pts[i].X) ^ 2 + (n.Y - pts[i].Y) ^ 2) end
    pts[i].left = left
  end
  ways[q] = pts
  return pts
end
-- the next point of the way from where you are: the one after the nearest, the last until you're at it; nil off the way
function T.wayPoint(q)
  local pts = wayOf(q)
  if not pts then return nil end
  local c, X, Y = ns.walk.player()
  if not c then return nil end
  local best, bi = NEAR_WAY ^ 2, nil
  for i, p in ipairs(pts) do
    local d = p.c == c and (p.X - X) ^ 2 + (p.Y - Y) ^ 2
    if d and d <= best then best, bi = d, i end
  end
  if not bi then return nil end
  local p = pts[math.min(bi + 1, #pts)]
  if bi == #pts and best < NEXT_WAY ^ 2 then return nil end
  return p
end
-- a timed step with a way: aimed at the way's next point while you're on it, else where it was going (step.home).
-- Moved in place, so the arrow and the planner follow the same step (Route.lua reads the target's place each time)
function T.onWay(step)
  local p = step.home and T.wayPoint(step.q)
  if p then
    step.m, step.x, step.y, step.after = p.m, p.x, p.y, p.left
  elseif step.home then
    step.m, step.x, step.y, step.after = step.home.m, step.home.x, step.home.y, nil
  end
end

-- ------------------------------------------------------------------ wandered off
-- not game facts: how far counts as off track is our own judgement (yards; seconds the distance must not shrink)
local FAR, NEAR, PATIENCE, CLOSING = 1000, 300, 60, 50
local away = { since = nil, dist = nil, told = false, stepI = nil }
local function status()
  local step = ns.core.current()
  if not step then return nil end
  if not (step.m and step.x and step.y) then return step, nil end
  return step, ns.core.distance(step)
end
-- the message, also what /audhd where says
function T.where()
  local step, d = status()
  if not step then return "no guide running: /audhd guides to pick one" end
  local info = ns.core.route()
  local _, _, pos, total = ns.core.current()
  local head = ("%s, step %s of %s: %s."):format(info and info.title or "Your guide", tostring(pos or "?"), tostring(total or "?"), step.t)
  if d then return head .. (" It's %d yards away and the arrow points there."):format(d) end
  if step.m then return head .. " It's on another continent: the arrow picks up once you're there." end
  return head
end
function T.tick()
  local step, d = status()
  if not step or (step.i or 0) < 0 then away.since, away.told = nil, false return end
  if away.stepI ~= step.i then away.stepI, away.since, away.dist, away.told = step.i, nil, nil, false end
  local far = (step.m and d == nil) or (d and d > FAR)
  if d and d < NEAR then away.since, away.dist, away.told = nil, nil, false return end
  if not far then away.since, away.dist = nil, nil return end
  local now = GetTime()
  -- heading back counts as on track: only sitting still or going the other way is off it
  if not away.since or (d and away.dist and d < away.dist - CLOSING) then away.since, away.dist = now, d return end
  if not away.told and now - away.since >= PATIENCE and not (InCombatLockdown and InCombatLockdown()) and not (UnitOnTaxi and UnitOnTaxi("player")) then
    away.told = true
    if ns.log then ns.log.add("OFF_TRACK", { n = step.i, q = step.q, d = d }) end
    say("back on track? " .. T.where())
  end
end
T.state = away   -- (the smoke test)

-- ------------------------------------------------------------------ what we don't know
local asked = {}
function T.checkUnknown(step)
  if not (step and step.q and step.unknown) or asked[step.q] then return end
  local spawns = T.objectiveSpawns(step.q)
  if #spawns > 0 then
    local at = bestSpawn(spawns, ns.geo and ns.geo.here())
    if at then step.m, step.x, step.y = ns.geo.live(at) end
    return
  end
  asked[step.q] = true
  if ns.log then ns.log.add("NO_PLACE", { q = step.q }) end
  if ns.share and ns.share.askToLog then
    ns.share.askToLog(step.q, "We don't know where this quest's objective is.")
  else
    say("we don't know where this quest's objective is.")
  end
end

function T.enable()
  C_Timer.NewTicker(5, function() pcall(T.tick) end)
  -- the way's next point as you walk (T.onWay)
  C_Timer.NewTicker(0.5, function()
    local t = ns.core.goalTarget
    if t and t.home then T.onWay(t) end
  end)
  -- when you come back: where you were, once
  C_Timer.After(6, function()
    local step = ns.core.current()
    if step and not AuDHDDB.welcomeOff then say("welcome back. " .. T.where()) end
  end)
end
