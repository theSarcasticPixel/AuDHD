-- Plugs the guide engine (AuDHDEngine, based on Polestar) into the core: turns its step views into the steps the window,
-- arrow and maps read, starts a guide at login, and has the classic-style guide picker (the Routes button).
local _, ns = ...
local G = {}
ns.guide = G

local function engine() local e = AuDHDEngine return e and e.Engine, e and e.Guides, e end

-- ------------------------------------------------------------------ distance between two places { map, x, y }
ns.geo = {}
local function world(p)
  local _, _, A = engine()
  if A and A.Compat and p and p.map and p.x and p.y then return A.Compat.MapToWorld(p.map, p.x, p.y, p.f) end
end
function ns.geo.yards(a, b)
  local ca, ax, ay = world(a)
  local cb, bx, by = world(b)
  if not ca or ca ~= cb then return nil end
  return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end
-- a place as the live map's x, y: the data's Era map frames can sit a little off the game's own
function ns.geo.live(p)
  if not (p and p.map and p.x and p.y) then return nil end
  if p.f ~= "e" then return p.map, p.x, p.y end
  local _, _, A = engine()
  local c, wx, wy = world(p)
  local x, y
  if c and A then x, y = A.Compat.WorldToMap(c, wx, wy, p.map) end
  if x and y then return p.map, x, y end
  return p.map, p.x, p.y
end
function ns.geo.here()
  local _, _, A = engine()
  return A and A.PlayerPoint and A.PlayerPoint()
end

-- ------------------------------------------------------------------ steps
local KIND = { accept = "accept", turnin = "turnin", kill = "do", collect = "do", complete = "do", use = "do", interact = "do",
  train = "train", sethome = "bind", getfp = "discover", vendor = "visit", buy = "visit" }
local OPEN = { active = true, pending = true }

local function clean(t) return t and (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) or "" end
-- a kill goal whose quest counts something else for the creature ("Kodos Tamed", not "Aged Kodo slain") reads as the
-- quest log's objective, then the quest: "Kodos Tamed: 0/5 (Kodo Roundup)"
local function questWording(g)
  if g.t ~= "kill" or not (g.quest and g.oi and C_QuestLog and C_QuestLog.GetQuestObjectives) then return nil end
  local ok, objs = pcall(C_QuestLog.GetQuestObjectives, g.quest)
  local o = ok and type(objs) == "table" and objs[g.oi]
  local text = o and type(o.text) == "string" and clean(o.text):gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", "")
  if not text or text == "" or text:lower():find("slain", 1, true) then return nil end
  local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(g.quest)
  return text, title
end
local function goalLine(g)
  local t = clean(g.text)
  local own, title = questWording(g)
  if own then t = own end
  local p = g.progress
  if p and p.kind == "wait" then
    t = ("%s: %d s left"):format(t, p.cur)
  elseif p then
    t = ("%s: %s/%s"):format(t, tostring(p.cur), tostring(p.max))
  end
  if own and title then t = ("%s (%s)"):format(t, title) end
  if g.optional then t = t .. " (optional)" end
  return t
end
-- the items an open goal may have you use, for UseItem.lua's button: a "use" goal's item (sure), and items its note or
-- text names (the Taming Rod in "tame it with the {item:15908}"), which the button shows only if they have a Use: effect
local function itemsToUse(raw, out)
  if not raw then return end
  local seen = {}
  for _, u in ipairs(out) do seen[u.id] = true end
  local function add(id, sure)
    if id and not seen[id] then seen[id] = true out[#out + 1] = { id = id, sure = sure } end
  end
  if raw.t == "use" then add(raw.item, true) end
  for _, s in ipairs({ raw.note or "", raw.text or "" }) do
    for id in s:gmatch("{item:(%d+)}") do add(tonumber(id), false) end
  end
  -- what the quest hands you to do it with, from the quest data: Forever gives each taming quest its own rod (266253
  -- for the wolf), not the 15908 the note names. Only for goals doing the quest's work, not walking back to hand it in
  local db = KIND[raw.t] == "do" and raw.quest and AuDHDEngine and AuDHDEngine.QuestDB
  local rec = db and db.QuestRecord and db.F and db.QuestRecord(raw.quest)
  local v = rec and rec[db.F.ITEMS]
  if type(v) == "number" then add(v, false) end
  if type(v) == "table" then for _, id in ipairs(v) do add(id, false) end end
end

-- a goal's line, but a guide hearth the engine walks you to (the Hearthstone cooling down, bound elsewhere, or the inn
-- close by) says so: "Walk to Darkshire", its waypoint's label
local function lineOf(g, i, wp)
  if g.t == "hearth" and g.hearthText and wp and wp.stepIndex == i and wp.goalIndex == g.index and wp.label then
    return clean(wp.label)
  end
  return goalLine(g)
end

-- one step of the engine as the rest of the addon reads it: its open goals in one text, the goal the arrow leads to first
local function stepOf(i, wp)
  local E = engine()
  local v = E and E.GetStepView(i)
  if not v then return nil end
  local guide = E.GetGuide()
  local raws = guide and guide.steps and guide.steps[i] and guide.steps[i].goals or {}
  local aim = v.current and v.goals[v.current]
  local lines, rows, ui = {}, {}, {}
  local hearth
  if aim and OPEN[aim.status] then itemsToUse(raws[aim.index], ui) end   -- (the goal the arrow leads to first)
  for _, g in ipairs(v.goals) do
    if OPEN[g.status] and not g.folded and not g.header and g.t ~= "note" then
      aim = aim or g
      if g.t == "hearth" then hearth = true end
      local text = lineOf(g, i, wp)
      lines[#lines + 1] = text
      -- (a hearth's line under it: "Hearthstone ready in 37 min; the trip takes 6 min: set off now")
      rows[#rows + 1] = { text = text, q = g.quest, g = g.index, k = KIND[g.t] or g.t, note = g.note and clean(g.note),
        warn = g.noticeText or g.unavailableText or (g.hearthText and clean(g.hearthText)) }
      itemsToUse(raws[g.index], ui)
    end
  end
  if #lines == 0 and clean(v.title) == "" then return nil end
  -- nothing left open: a step looked back at (Back, or the one you were looking at before a restart). It has no place
  -- of its own, so Core.setWaypoint leads on to the next place to go
  local finished = #v.goals > 0
  for _, g in ipairs(v.goals) do if OPEN[g.status] then finished = false break end end
  local text = #lines > 0 and table.concat(lines, "; ") or clean(v.title)
  local step = { i = i, t = text, rows = #rows > 0 and rows or nil, title = clean(v.title), q = aim and aim.quest,
    k = aim and (KIND[aim.t] or aim.t) or (finished and "done") or "goto", finished = finished or nil,
    goal = aim and aim.index, uses = #ui > 0 and ui or nil, hearth = hearth }
  local at = wp or aim
  if at and at.map and at.x and at.y then
    step.m, step.x, step.y = ns.geo.live(at)
  elseif aim and aim.quest and aim.t ~= "accept" then
    -- only with no place at all, the engine's waypoint included: Track.lua looks in the quest data, then asks you to log it
    step.unknown = true
  end
  -- the map's numbered stops (RouteMap.lua): each open goal with a place, the arrow's first, then in the step's order.
  -- One step can be "tame the wolf, hand it in at Goldshire, take the next": three stops, not one pin at the wolves.
  local stops = {}
  local function stop(g, place)
    local m, x, y = ns.geo.live(place)
    if m then stops[#stops + 1] = { i = i, t = lineOf(g, i, wp), k = KIND[g.t] or g.t, q = g.quest, m = m, x = x, y = y } end
  end
  if aim and OPEN[aim.status] then stop(aim, (wp and wp.map) and wp or aim) end
  for _, g in ipairs(v.goals) do
    if g ~= aim and OPEN[g.status] and not g.folded and not g.header and g.t ~= "note" then stop(g, g) end
  end
  step.stops = #stops > 0 and stops or nil
  return step
end

G.stepOf = stepOf   -- (the smoke test)

local last   -- the step built for this engine state: rebuilt when the engine says something changed
-- what's on top of the guide (a timed or extra quest) and what comes next are worked out at most twice a second, or at
-- once when something changes: the arrow asks for them every frame
local REFRESH = 0.5
local top, topAt, topI   -- { step, via } or false, when it was worked out, and for which guide step
local ahead = {}         -- peek's answers for that same moment, by k: { step, j } or false
local function forget() top, topAt, topI, ahead = nil, nil, nil, {} end
local function onTopNow(i)
  local now = GetTime()
  if top ~= nil and topI == i and now - topAt < REFRESH then return top end
  ahead = {}
  local first = ns.track and ns.track.priority()
  if first then top = { first, "timed" }
  else
    local extra = ns.extra and ns.extra.due()
    top = extra and { extra, "extra" } or false
  end
  topAt, topI = now, i
  return top
end
local changed   -- (below: the engine says something changed)
local provider = {}
local function guideStep(E, i)
  if not last or last.i ~= i then
    last = stepOf(i, E.GetWaypoint())
    if last and ns.track then ns.track.checkUnknown(last) end
  end
  return last
end
function provider.current()
  local E = engine()
  if not E or not E.GetGuide() then return nil end
  local i = E.GetStepIndex()
  if not i then return nil end
  local t = onTopNow(i)
  if t then return t[1], i, i, E.GetStepCount(), t[2] end
  return guideStep(E, i), i, i, E.GetStepCount()
end
local function open(v) return v and v.status ~= "done" and v.status ~= "na" and not v.skipped end
local function peekNow(E, i, k)
  -- a timed or extra quest on top: the guide's own step under it comes next, never left out
  local top = onTopNow(i) and open(E.GetStepView(i))
  if top and k == 1 then return guideStep(E, i), i end
  -- carry on from the step before's answer, so each step is looked at once and not again for every k
  local prev = nil
  if k > 1 then prev = ahead[k - 1] end
  if prev == false then return nil end   -- (none at k - 1: none further on)
  local from, n = i + 1, 0
  if prev and prev[2] > i then from, n = prev[2] + 1, k - 1 - (top and 1 or 0) end
  if top then k = k - 1 end
  for j = from, E.GetStepCount() do
    if open(E.GetStepView(j)) then
      local s = stepOf(j)
      if s then
        n = n + 1
        if n == k then return s, j end
      end
    end
  end
end
function provider.peek(k)
  local E = engine()
  local i = E and E.GetStepIndex()
  if not i then return nil end
  onTopNow(i)   -- (clears the answers below when they're due again)
  local a = ahead[k]
  if a == nil then
    local s, j = peekNow(E, i, k)
    a = s and { s, j } or false
    ahead[k] = a
  end
  if a then return a[1], a[2] end
end
function provider.ahead(limit)
  local out, k = {}, 1
  local cur = provider.current()
  if cur then out[1] = cur end
  while not limit or #out < limit do
    local s = provider.peek(k)
    if not s then break end
    out[#out + 1] = s
    k = k + 1
    if k > 40 then break end
  end
  return out
end
function provider.info()
  local E = engine()
  local g = E and E.GetGuide()
  if not g then return nil end
  return { title = clean(g.title or g.id), steps = g.steps, ends = {} }
end
function provider.isDone(step) local E = engine() local v = E and step and E.GetStepView(step.i) return v and v.status == "done" end
function provider.memLeft() return nil end
-- Done, Skip and Later act on what is shown: a timed or extra quest on top of the guide, else the guide's step. On a
-- guide step Done and Skip take one task, the top one: Done ticks it off, Skip on a quest's task skips that quest in
-- the whole route (the engine's SkipQuest; /audhd unskip brings it back), Skip on a task with no quest ticks it off.
-- Later stays the whole step
local function say(msg) print("|cff66ccffAuDHD|r: " .. msg) end
local unskips = {}   -- the quests Skip took this session, last first: /audhd unskip
local function questName(q, fallback)
  return (C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(q)) or fallback or ("quest " .. q)
end
-- one task of the guide's step ticked off ([done] after it in the window, or Done on the top one)
local function skipQuest(q, fallback)
  local E = engine()
  E.SkipQuest(q)
  table.insert(unskips, 1, q)
  say(("skipped %s in the whole route (/audhd unskip brings it back)"):format(questName(q, fallback)))
  changed()
  return true
end
local function inLog(q)
  return C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(q) ~= nil
end
function G.tickGoal(i, g)
  local E = engine()
  if not (E and i and g) or i ~= E.GetStepIndex() then return false end
  -- a pick-up ticked by hand counts only once the quest is in your log (the engine's rule), so one you can't take never
  -- moved on: it's skipped in the route instead
  local guide = E.GetGuide()
  local goal = guide and guide.steps and guide.steps[i] and guide.steps[i].goals[g]
  if goal and goal.t == "accept" and goal.quest and not inLog(goal.quest) then return skipQuest(goal.quest, goal.title) end
  local ok = E.ToggleGoal(i, g)
  changed()
  return ok
end
local function topTask(reason)
  local E = engine()
  if not E then return end
  local i = E.GetStepIndex()
  local st = i and guideStep(E, i)
  local r = st and st.rows and st.rows[1]
  if not (r and r.g) then E.Skip() return end   -- nothing open in it (a step looked back at): the whole step, as before
  if reason == "skipped" and r.q then skipQuest(r.q, r.text) else G.tickGoal(i, r.g) end
end
function G.unskip()
  local q = table.remove(unskips, 1)
  local E = engine()
  if not (q and E) then return "nothing skipped this session" end
  E.SkipQuest(q, false)
  changed()
  return questName(q) .. " is back in the route"
end
local function onTop()
  local cur = provider.current and select(5, provider.current())
  if cur == "timed" or cur == "extra" then return cur, (provider.current()) end
end
G.onTop = onTop   -- (the smoke test)
function provider.markDone(reason)
  local via, step = onTop()
  forget()
  if via == "timed" then
    say("a timed quest stays until it's handed in: abandon it in your quest log to drop it")
  elseif via == "extra" then
    local msg
    if reason == "skipped" then msg = ns.extra.skip(step.q) else msg = ns.extra.done(step.q, step.k) end
    if msg then say(msg) end
    if ns.core then ns.core.onStepChanged() end
  else
    topTask(reason)
  end
end
function provider.later()
  local via, step = onTop()
  forget()
  if via == "timed" then
    say("a timed quest stays until it's handed in: abandon it in your quest log to drop it")
  elseif via == "extra" then
    say(ns.extra.later(step.q))
    if ns.core then ns.core.onStepChanged() end
  else
    local E = engine()
    if E then E.Skip() end
  end
end
function provider.back() local E = engine() if E then E.Prev() end end
function provider.jump(n) local E = engine() if E then E.Goto(n) end end
-- a step that only says "go to" a portal: done once you're at the portal's far end. A portal moves you the moment you
-- touch it, so the goto's few yards can be missed between looks, and the engine's own fallback waits for the whole next
-- step. Portals only: a dock is where a boat leaves and where it lands, so which end you're meant to be at isn't known.
local PORTAL_IN, FAR_END = 15, 150   -- yards: a goto this near a portal's way in; the far end this near the player
local function farEnd(c, wx, wy)
  local _, _, A = engine()
  local N = A and A.Nav
  local D = N and N.GetTravelData and N.GetTravelData()
  for _, p in ipairs(D and D.portals or {}) do
    local a = p.a
    if type(a) == "table" and a.c == c and a.wx and (a.wx - wx) ^ 2 + (a.wy - wy) ^ 2 <= PORTAL_IN ^ 2 then return p.b end
  end
end
function G.passPortals()
  local E, _, A = engine()
  local g = E and E.GetGuide()
  local i = g and E.GetStepIndex()
  local step = i and g.steps and g.steps[i]
  local v = step and E.GetStepView(i)
  if not (v and v.status ~= "done" and A.Compat and A.Compat.GetPlayerWorldPosition) then return false end
  local pc, px, py = A.Compat.GetPlayerWorldPosition()
  if not pc then return false end
  local open = {}
  for n, goal in ipairs(step.goals or {}) do
    local st = v.goals and v.goals[n] and v.goals[n].status
    if goal.t == "goto" then
      if st ~= "done" and st ~= "skipped" and st ~= "na" then
        local c, wx, wy = world(goal)
        local e = c and farEnd(c, wx, wy)
        if not (e and e.c == pc and e.wx and (e.wx - px) ^ 2 + (e.wy - py) ^ 2 <= FAR_END ^ 2) then return false end
        open[#open + 1] = n
      end
    elseif goal.t ~= "note" then
      return false
    end
  end
  for _, n in ipairs(open) do E.ToggleGoal(i, n) end
  return #open > 0
end

-- a "Use" with no quest whose "Collect" (no quest either) straight after it in the step is done: the use made that
-- item, so it's done too. The engine only ticks such a use by hand
function G.passUses()
  local E = engine()
  local g = E and E.GetGuide()
  local i = g and E.GetStepIndex()
  local step = i and g.steps and g.steps[i]
  local goals = step and step.goals or {}
  local found
  for k = 1, #goals - 1 do
    local use, nxt = goals[k], goals[k + 1]
    if use.t == "use" and not use.quest and nxt.t == "collect" and not nxt.quest then found = true break end
  end
  if not found then return false end
  local v = E.GetStepView(i)
  local n = 0
  for k = 1, #goals - 1 do
    local use, nxt = goals[k], goals[k + 1]
    local a, b = v and v.goals and v.goals[k], v and v.goals and v.goals[k + 1]
    if use.t == "use" and not use.quest and nxt.t == "collect" and not nxt.quest and a and OPEN[a.status] and b and b.status == "done" then
      E.ToggleGoal(i, k)
      n = n + 1
    end
  end
  return n > 0
end

-- Steps that are only waypoints (a walk written for someone without the flight path there yet) are ticked off when
-- going straight to the first step with work after them is clearly faster, flights and the hearth counted by the
-- router. Faster: the router's time via every waypoint, against straight to the work's first open place, at least
-- WALK_SAVE seconds and WALK_FRAC of it shorter. Looked at again every WALK_LOOK seconds at most. The walk's last place
-- within WAY_IN yards of the work is its way in (a cave's mouth, a door): never ticked off, as the router can't tell the
-- work is below ground or behind a wall. The walks before it are, timed to the way in
local WALK_SAVE, WALK_FRAC, WALK_LOOK, WAY_IN = 30, 0.2, 10, 300
local walkLooked, walkKey
local function placeOf(goal)
  if goal and goal.map and goal.x and goal.y then return { map = goal.map, x = goal.x, y = goal.y, f = goal.f } end
end
-- a step's open goals: "walk" (only gotos, with their places), "work" (anything else, its first open place), or nil
-- (nothing open: done, skipped, not for you)
local function stepKind(E, g, i)
  local step = g.steps[i]
  local v = step and E.GetStepView(i)
  if not v or v.status == "done" or v.status == "skipped" or v.status == "na" then return nil end
  -- work's place: its first open goal with one that isn't a goto, else its first goto's
  local walk, work, place, wayIn = {}, false, nil, nil
  for n, goal in ipairs(step.goals or {}) do
    local st = v.goals and v.goals[n] and v.goals[n].status
    if OPEN[st] and goal.t ~= "note" then
      if goal.t == "goto" then
        walk[#walk + 1] = { n = n, p = placeOf(goal) }
        wayIn = wayIn or placeOf(goal)
      else
        work = true
        place = place or placeOf(goal)
      end
    end
  end
  if work then return "work", place or wayIn end
  if #walk == 0 then return nil end
  return "walk", walk
end
function G.flyPastWalks(force)
  local E, _, A = engine()
  local g = E and E.GetGuide()
  local i = g and E.GetStepIndex()
  local N = A and A.Nav
  if not (i and g.steps and N and N.EstimateTravel) then return false end
  local key = tostring(g.id) .. ":" .. i
  local now = GetTime()
  if not force and key == walkKey and walkLooked and now - walkLooked < WALK_LOOK then return false end
  walkKey, walkLooked = key, now
  local kind, walk = stepKind(E, g, i)
  if kind ~= "walk" then return false end
  -- the run of walking steps from here, and the first step with work after it
  local run, points, target = {}, {}, nil
  for s = i, #g.steps do
    local k, what = stepKind(E, g, s)
    if k == "walk" then
      for _, w in ipairs(what) do
        run[#run + 1] = { s = s, n = w.n, p = w.p }
        if w.p then points[#points + 1] = w.p end
      end
    elseif k == "work" then
      target = what
      break
    end
  end
  if not target or #points == 0 then return false end
  local wayIn = points[#points]
  local near = ns.geo.yards(wayIn, target)
  if near and near <= WAY_IN then
    points[#points] = nil
    for k = #run, 1, -1 do
      if run[k].p == wayIn then table.remove(run, k) break end
    end
    target = wayIn
    if #points == 0 then return false end
  end
  local via = N.EstimateTravel(nil, points[1])
  for k = 2, #points do
    local leg = via and N.EstimateTravel(points[k - 1], points[k])
    via = leg and via + leg or nil
  end
  local last = via and N.EstimateTravel(points[#points], target)
  via = last and via + last or nil
  local direct = N.EstimateTravel(nil, target)
  if not (via and direct) or direct + WALK_SAVE > via or direct > via * (1 - WALK_FRAC) then return false end
  for _, r in ipairs(run) do E.ToggleGoal(r.s, r.n) end
  if ns.log then ns.log.add("WALK_PASSED", { from = i, steps = #run, via = math.floor(via), direct = math.floor(direct) }) end
  return true
end

-- the engine says itself when its step changes; a timed or extra quest coming up is seen here
local shown
function provider.advance()
  forget()
  pcall(G.passPortals)
  pcall(G.passUses)
  pcall(G.flyPastWalks)
  local step = provider.current()
  -- a timed or extra quest's stops (pick up, do, hand in) share its number: the stop is part of the key, so the arrow
  -- moves on with it
  local key = step and step.i
  if key and key < 0 then key = key .. ":" .. tostring(step.k) end
  if key ~= shown then shown = key return true end
  return false
end
function provider.hasWork(q) local E = engine() return E and E.WantsQuest("complete", q) end

function changed()
  last = nil
  forget()
  if ns.core then ns.core.onStepChanged() end
end

-- ------------------------------------------------------------------ the picker: a plain list, grouped by kind of guide
-- (Class guides in a sub-list per class, yours first; a guide for several classes is under each of them)
local P = {}
local win, rows = nil, {}
local ORDER = { "Leveling", "Class", "Reputation", "Collectibles", "Professions", "Other" }
local function byLevel(a, b)
  local la, lb = a.minLevel or 0, b.minLevel or 0
  if la ~= lb then return la < lb end
  return tostring(a.title or a.id) < tostring(b.title or b.id)
end
local function className(token)
  if token == "" then return "Any class" end
  local names = LOCALIZED_CLASS_NAMES_MALE
  return (names and names[token]) or (token:sub(1, 1) .. token:sub(2):lower())
end
-- { header, key, depth, under = { keys } } for a heading, { guide, depth, under } for a guide
local function list()
  local _, Guides = engine()
  local groups = {}
  for _, h in ipairs(Guides and Guides.List() or {}) do
    local c = h.category or "Leveling"
    -- (not the guides built on the spot: dungeon pick-up, hand-in and attunement, from the Dungeons window)
    if c ~= "Lookup" then
      groups[c] = groups[c] or {}
      table.insert(groups[c], h)
    end
  end
  local names, seen = {}, {}
  for _, c in ipairs(ORDER) do if groups[c] then names[#names + 1] = c seen[c] = true end end
  for c in pairs(groups) do if not seen[c] then names[#names + 1] = c end end
  local out = {}
  for _, c in ipairs(names) do
    out[#out + 1] = { header = c, key = c, depth = 0, under = {} }
    table.sort(groups[c], byLevel)
    if c == "Class" then
      local by, tokens = {}, {}
      for _, h in ipairs(groups[c]) do
        local classes = type(h.classes) == "table" and #h.classes > 0 and h.classes or { "" }
        for _, t in ipairs(classes) do
          if not by[t] then by[t] = {} tokens[#tokens + 1] = t end
          table.insert(by[t], h)
        end
      end
      local mine = UnitClass and select(2, UnitClass("player"))
      table.sort(tokens, function(a, b)
        if (a == mine) ~= (b == mine) then return a == mine end
        if (a == "") ~= (b == "") then return b == "" end
        return className(a) < className(b)
      end)
      for _, t in ipairs(tokens) do
        local key = c .. "/" .. t
        out[#out + 1] = { header = className(t), key = key, depth = 1, under = { c } }
        for _, h in ipairs(by[t]) do out[#out + 1] = { guide = h, depth = 1, under = { c, key } } end
      end
    else
      for _, h in ipairs(groups[c]) do out[#out + 1] = { guide = h, depth = 0, under = { c } } end
    end
  end
  return out
end
function P.choices()
  local out, seen = {}, {}
  for _, e in ipairs(list()) do
    if e.guide and not seen[e.guide] then seen[e.guide] = true out[#out + 1] = e.guide end
  end
  return out
end
-- a guide's name, with the race it's for when it's made for one or two (two Dun Morogh guides: Dwarf and Gnome), unless
-- its name says so already or names its faction; one for most of a faction stays as it is
local RACE = { NightElf = "Night Elf", Scourge = "Undead" }
local ALSO = { Scourge = "Forsaken" }
local function named(e)
  local t = clean(e.title or e.id)
  local races = type(e.races) == "table" and e.races or {}
  if #races == 0 or #races > 2 or t:find("(Alliance)", 1, true) or t:find("(Horde)", 1, true) then return t end
  local names = {}
  for _, r in ipairs(races) do
    local name = RACE[r] or r
    if t:find(name, 1, true) or (ALSO[r] and t:find(ALSO[r], 1, true)) then return t end
    names[#names + 1] = name
  end
  return ("%s (%s)"):format(t, table.concat(names, ", "))
end
G.named = named   -- (the smoke test)

-- the sections you opened, kept between visits and logins; every section starts closed
local function opened()
  if not AuDHDDB then return {} end
  if type(AuDHDDB.pickerOpen) ~= "table" then AuDHDDB.pickerOpen = {} end
  return AuDHDDB.pickerOpen
end
local PLUS, MINUS = "Interface\\Buttons\\UI-PlusButton-Up", "Interface\\Buttons\\UI-MinusButton-Up"
local INDENT = 16
-- the title bar's button: opens every section while one is closed, else closes them all
local function setAll(button, allOpen)
  local kind = allOpen and "Minus" or "Plus"
  button:SetNormalTexture("Interface\\Buttons\\UI-" .. kind .. "Button-Up")
  button:SetPushedTexture("Interface\\Buttons\\UI-" .. kind .. "Button-Down")
  button.allOpen = allOpen
end
local fill
function fill()
  local open = opened()
  local y, n, allOpen = -2, 0, true
  for _, e in ipairs(list()) do
    if e.header and not open[e.key] then allOpen = false end
    local seen = true
    for _, k in ipairs(e.under) do if not open[k] then seen = false end end
    if seen then
      n = n + 1
      local b = rows[n]
      if not b then
        b = ns.newFrame("Guide", "Button", nil, win.content)
        b:SetSize(330, 18)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b.icon = b:CreateTexture(nil, "OVERLAY")
        b.icon:SetSize(14, 14)
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.label:SetJustifyH("LEFT")
        rows[n] = b
      end
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", 4, y)
      y = y - 18
      local x = e.depth * INDENT
      b.icon:ClearAllPoints()
      b.icon:SetPoint("LEFT", x, 0)
      b.label:ClearAllPoints()
      b.label:SetPoint("TOPLEFT", x + 18, 0)
      b.label:SetPoint("BOTTOMRIGHT")
      if e.header then
        b.icon:SetTexture(open[e.key] and MINUS or PLUS)
        b.icon:Show()
        b.label:SetFontObject(e.depth == 0 and "GameFontNormal" or "GameFontNormalSmall")
        b.label:SetText(e.header)
        local key = e.key
        b:SetScript("OnClick", function()
          open[key] = (not open[key]) or nil
          fill()
        end)
      else
        local g = e.guide
        local lv = g.minLevel and (" |cffaaaaaa(" .. g.minLevel .. (g.maxLevel and ("-" .. g.maxLevel) or "") .. ")|r") or ""
        b.icon:Hide()
        b.label:SetFontObject("GameFontHighlightSmall")
        b.label:SetText("  " .. named(g) .. lv)
        b:SetScript("OnClick", function() G.follow(g.id) win:Hide() end)
      end
      b:Show()
    end
  end
  for k = n + 1, #rows do rows[k]:Hide() end
  win.content:SetHeight(-y + 4)
  setAll(win.all, allOpen)
end
local function toggleAll()
  local open, close = opened(), win.all.allOpen
  for _, e in ipairs(list()) do
    if e.header then open[e.key] = (not close) or nil end
  end
  fill()
end
function P.show(onClose)
  if not win then
    win = ns.newFrame("Guide", "Frame", "AuDHDGuidePicker", UIParent, "BasicFrameTemplateWithInset")
    win:SetSize(380, 460)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -6)
    title:SetText("Pick a guide")
    win.all = ns.newFrame("Guide", "Button", nil, win)
    win.all:SetSize(16, 16)
    win.all:SetPoint("TOPLEFT", 8, -4)
    win.all:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    win.all:SetScript("OnClick", toggleAll)
    win.all:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(self.allOpen and "Close all sections" or "Open all sections")
      GameTooltip:Show()
    end)
    win.all:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local scroll = ns.newFrame("Guide", "ScrollFrame", "AuDHDGuidePickerScroll", win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -30)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    win.content = ns.newFrame("Guide", "Frame", nil, scroll)
    win.content:SetSize(340, 10)
    scroll:SetScrollChild(win.content)
    tinsert(UISpecialFrames, "AuDHDGuidePicker")
  end
  win:SetScript("OnHide", onClose)
  fill()
  win:Show()
end
function P.toggle()
  if win and win:IsShown() then win:Hide() else P.show() end
end
ns.picker = P

-- ------------------------------------------------------------------ quests in your log the route ahead doesn't use
-- The route ahead: the guide you follow (all of it) and every guide after it, not those before. Where the next guide is
-- a choice you haven't made, every option for you. A pick-up, objective or hand-in of a quest there counts (not a step
-- to abandon it), as do your extra quests and, while a class guide you swapped to is followed, the route it goes back to
local function routeQuests()
  local E, Guides, A = engine()
  local cur = E and E.GetGuide()
  if not (cur and Guides and A and A.Compat) then return nil end
  local p = A.Compat.GetPlayerInfo() or {}
  local chosen = A.CharState and A.CharState().routes or {}
  local quests, seen, queue = {}, {}, { cur.id }
  local cq = ns.classQuest and ns.classQuest.state and ns.classQuest.state()
  local back = cq and cq.back
  if back and back.from == cur.id and back.to then queue[#queue + 1] = back.to end
  local i = 1
  while queue[i] do
    local id = queue[i]
    i = i + 1
    local g = not seen[id] and Guides.Get(id)
    if g then
      seen[id] = true
      pcall(function()
        for _, step in ipairs(g.steps or {}) do
          if Guides.Matches(step.only, p) then
            for _, goal in ipairs(step.goals or {}) do
              if type(goal.quest) == "number" and goal.t ~= "abandon" and Guides.Matches(goal.only, p) then
                quests[goal.quest] = true
              end
            end
          end
        end
      end)
      local nexts = g.nextChoices or { g.next }
      if g.nextChoices then
        for _, n in ipairs(g.nextChoices) do if n == chosen[g.id] then nexts = { n } end end
      end
      for _, n in ipairs(nexts) do
        local t = Guides.Get(n)
        if t and Guides.GuideMatches(t, p) then queue[#queue + 1] = n end
      end
    end
  end
  -- the steps read in go again, but for the guides a tab shows (as the engine does on a tab change)
  if Guides.ReleaseExcept and E.TabIds then pcall(Guides.ReleaseExcept, E.TabIds()) end
  for q in pairs(ns.extra and ns.extra.list() or {}) do quests[q] = true end
  return quests
end
-- the quests in your log not in `quests`: { { title, level, zone (the log's header over it) } }, in the log's order
local function offRoute(quests)
  local out, zone = {}, nil
  local ok, count = pcall(C_QuestLog.GetNumQuestLogEntries)
  for li = 1, (ok and count or 0) do
    local info = C_QuestLog.GetInfo(li)
    if info and info.isHeader then zone = info.title
    elseif info and info.questID and not quests[info.questID] then
      out[#out + 1] = { q = info.questID, title = info.title or questName(info.questID), level = info.level, zone = zone }
    end
  end
  return out
end
G.routeQuests, G.offRoute = routeQuests, offRoute   -- (the smoke test)

local OR = {}
local orWin, orLines, orQuests = nil, {}, nil
local function orFill()
  local list = orQuests and offRoute(orQuests)
  local texts = {}
  if not orQuests then
    texts[1] = { "Follow a guide first: there's no route to check against", "GameFontHighlightSmall" }
  elseif #list == 0 then
    texts[1] = { "Every quest in your log is on the route ahead", "GameFontHighlightSmall" }
  else
    local zone
    for _, e in ipairs(list) do
      if e.zone ~= zone then
        zone = e.zone
        texts[#texts + 1] = { zone or "", "GameFontNormal" }
      end
      texts[#texts + 1] = { ("  [%s] %s"):format(e.level or "?", e.title), "GameFontHighlightSmall" }
    end
  end
  local y = -2
  for n, t in ipairs(texts) do
    local fs = orLines[n]
    if not fs then
      fs = orWin.content:CreateFontString(nil, "OVERLAY")
      fs:SetJustifyH("LEFT")
      fs:SetWidth(300)
      orLines[n] = fs
    end
    fs:SetFontObject(t[2])
    fs:SetText(t[1])
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", 4, y)
    fs:Show()
    y = y - 16
  end
  for n = #texts + 1, #orLines do orLines[n]:Hide() end
  orWin.content:SetHeight(-y + 4)
  orWin.count:SetText(orQuests and #list > 0 and ("%d not on the route ahead"):format(#list) or "")
end
OR.fill = orFill
function OR.show()
  if not orWin then
    orWin = ns.newFrame("Guide", "Frame", "AuDHDOffRoute", UIParent, "BasicFrameTemplateWithInset")
    orWin:SetSize(340, 320)
    orWin:SetPoint("CENTER")
    orWin:SetFrameStrata("DIALOG")
    orWin:SetMovable(true)
    orWin:EnableMouse(true)
    orWin:RegisterForDrag("LeftButton")
    orWin:SetScript("OnDragStart", orWin.StartMoving)
    orWin:SetScript("OnDragStop", orWin.StopMovingOrSizing)
    local title = orWin:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -6)
    title:SetText("Quests off the route")
    orWin.count = orWin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    orWin.count:SetPoint("BOTTOMLEFT", 12, 10)
    local scroll = ns.newFrame("Guide", "ScrollFrame", "AuDHDOffRouteScroll", orWin, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -30)
    scroll:SetPoint("BOTTOMRIGHT", -30, 28)
    orWin.content = ns.newFrame("Guide", "Frame", nil, scroll)
    orWin.content:SetSize(300, 10)
    scroll:SetScrollChild(orWin.content)
    -- the list follows the log while it's open (a quest abandoned or taken); the route's quests are read once per opening
    orWin:RegisterEvent("QUEST_LOG_UPDATE")
    orWin:SetScript("OnEvent", function() if orWin:IsShown() then orFill() end end)
    tinsert(UISpecialFrames, "AuDHDOffRoute")
  end
  orQuests = routeQuests()
  orFill()
  orWin:Show()
end
function OR.toggle()
  if orWin and orWin:IsShown() then orWin:Hide() else OR.show() end
end
ns.offRoute = OR

-- ------------------------------------------------------------------ what Auto.lua may accept for you
-- the live step's quests and your extra quests. A timed quest only when the live step names it: never on the way somewhere.
function G.wants(q)
  local E = engine()
  if not (E and E.GetGuide()) then return not (ns.track and ns.track.isTimed(q)) end
  if E.WantsQuest("accept", q) then return true end
  if ns.track and ns.track.isTimed(q) then return false end
  return ns.extra and ns.extra.list()[q] and true or false
end

-- ------------------------------------------------------------------ following a guide
-- The engine keeps up to MAX_TABS guides open (unseen here: the window shows the one followed) and opens no more once
-- full. Then the oldest one not followed closes for the new one
function G.follow(id)
  local E = engine()
  if E then
    local tabs, active = E.GetTabs()
    local open = false
    for _, t in ipairs(tabs or {}) do if t.guideId == id then open = true end end
    if not open and #(tabs or {}) >= (E.MAX_TABS or 6) then
      for i = 1, #tabs do
        if i ~= active then E.CloseTab(i) break end
      end
    end
    E.OpenTab(id, true)
  end
  changed()
end
function G.start()
  local E, _, A = engine()
  if not E then return end
  ns.core.setProvider(provider)
  A.On("STEP_CHANGED", changed)
  A.On("STEP_UPDATED", changed)
  A.On("WAYPOINT_CHANGED", changed)
  A.On("GUIDE_CHANGED", changed)
  A.On("QUESTDB_LOADED", changed)   -- (the use button's quest items come from it)
  -- on a hearth step, its line's minutes ("ready in 37 min") count down, and the engine hears when the cooldown ends
  C_Timer.NewTicker(30, function()
    if not (last and last.hearth) then return end
    ns.core.hearthChanged()
    last = nil
    if ns.ui then ns.ui.refresh() end
  end)
  A.On("GUIDES_REGISTERED", function() if not E.GetGuide() then E.StartGuide() end changed() end)
  if not E.GetGuide() then E.StartGuide() end
  changed()
  if ns.route then ns.route.start() end
end
