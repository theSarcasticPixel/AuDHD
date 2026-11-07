-- The way to the step you're on, from the engine's travel planner: walking on its terrain maps (buildings, floors and
-- doors included), flights you know, boats, zeppelins, the tram, portals and the Hearthstone. The arrow, the map lines and
-- the window read it through Walk.lua; Walk.lua's own graph is what's left when the planner has no answer. Our target goes
-- to the engine's Nav, so a timed quest, an extra quest or an ammo vendor gets the same treatment as a guide step.
local _, ns = ...
local R = {}
ns.route = R

local SAMPLE_EVERY, TICK = 0.1, 0.2   -- seconds: the planner's reading of where you are; keeping it fed while no arrow shows
local BETWEEN_MAX = 1500              -- yards: further apart, the line between two later steps stays Walk.lua's, which flies
local BETWEEN_KEEP = 64               -- later-step lines kept
local SAME_SPOT = 0.03                -- of a map's 100: the same place

local function nav()
  local A = AuDHDEngine
  local N = A and A.Nav
  if not (N and N.Path and A.Get("nav.navRouting") and AuDHDDB.pathStyle ~= "straight") then return nil end
  return N, A
end

local function same(m1, x1, y1, m2, x2, y2)
  return m1 and m1 == m2 and math.abs(x1 - x2) < SAME_SPOT and math.abs(y1 - y2) < SAME_SPOT
end

-- ------------------------------------------------------------------ the target
local syncM, syncX, syncY   -- where the planner is headed, when that's where we are
local setAt, setKey = 0, nil
local function sync()
  local N = nav()
  syncM, syncX, syncY = nil, nil, nil
  if not N or not ns.core then return end
  local want = ns.core.override or ns.core.target
  if not (want and want.m and want.x and want.y) then
    N.ReleaseTarget()
    return
  end
  local function onIt()
    local m, x, y = ns.geo.live(N.GetTarget())
    return same(m, x, y, want.m, want.x, want.y)
  end
  -- the guide's own waypoint knows the height of what stands there: only something else takes its place
  if not onIt() and N.IsOverride() then N.ReleaseTarget() end
  if not onIt() then
    local key = ("%d:%.2f:%.2f"):format(want.m, want.x, want.y)
    local now = GetTime()
    if key == setKey and now - setAt < 1 then return end
    setKey, setAt = key, now
    N.SetTarget(want.m, want.x, want.y, ns.core.text and ns.core.text(want))
    if not onIt() then return end
  end
  syncM, syncX, syncY = want.m, want.x, want.y
end
local function ready(step)
  return step and same(syncM, syncX, syncY, step.m, step.x, step.y)
end

-- ------------------------------------------------------------------ where you are on it
local at = {}
local function sample(N)
  local now = GetTime()
  if at.time and now - at.time < SAMPLE_EVERY then return at end
  at.time = now
  at.state, at.dist, at.turn, at.dn, at.dw, at.measured = N.Sample()
  at.c, at.X, at.Y = ns.walk.player()
  return at
end
local function planned(N)
  local T = N.travel
  return T and T.Active and T.Active()
end
-- what to do, for under the arrow
local FLOOR = { up = "go up", down = "go down" }
local function label(N)
  local floor = FLOOR[N.FloorHint() or ""]
  if floor then return floor end
  local t = planned(N) and N.travel.CurrentLabel()
  return t and (t:gsub("\n", ", ")) or nil
end

-- Walk.aim's answer: true when the planner has one, then the spot to point at (world X, Y), yards left, what to do
function R.aim(step)
  local N = nav()
  if not (N and ready(step)) then return false end
  local s = sample(N)
  if not s.c then return false end
  if s.state == "travel" then
    -- still searching: Walk.lua's line for now, not a straight one
    if not (s.measured or planned(N)) then return false end
    return true, s.X + s.dn, s.Y + s.dw, s.dist, label(N)
  elseif s.state == "instruction" then
    if s.dn then return true, s.X + s.dn, s.Y + s.dw, s.dist, label(N) end
    return true, nil, nil, nil, label(N)
  elseif s.state == "arrived" or s.state == "search" then
    return true, s.X + s.dn, s.Y + s.dw, s.dist, label(N)
  elseif s.state == "far" then
    return true, nil, nil, nil, label(N)
  end
  return false
end

-- ------------------------------------------------------------------ its line
-- as Walk.lua's paths: { c, pts = { X1, Y1, X2, Y2, ... }, at, len }, a false pair where a ride has no line
local built, builtC, flat
local function flatten(g, c)
  local pts = {}
  local function gap() if #pts > 0 and pts[#pts] then pts[#pts + 1], pts[#pts + 2] = false, false end end
  for _, leg in ipairs(g.legs or {}) do
    if leg.kind == "walk" then
      for _, p in ipairs(leg.pts or {}) do
        if p[1] == c then pts[#pts + 1], pts[#pts + 2] = p[2], p[3] else gap() end
      end
    else
      gap()
    end
  end
  while #pts > 0 and not pts[#pts] do pts[#pts], pts[#pts - 1] = nil, nil end
  if #pts < 2 then return nil end
  local len, px, py = 0, nil, nil
  for k = 1, #pts - 1, 2 do
    if pts[k] then
      if px then len = len + math.sqrt((pts[k] - px) ^ 2 + (pts[k + 1] - py) ^ 2) end
      px, py = pts[k], pts[k + 1]
    else
      px, py = nil, nil
    end
  end
  return { c = c, pts = pts, len = len, at = 1 }
end
function R.toStep(step)
  local N = nav()
  if not (N and ready(step)) then return nil end
  local s = sample(N)
  if not s.c or s.state == "taxi" or not (s.measured or planned(N)) then return nil end
  local g = N.GetRouteGeometry()
  if not g then return nil end
  if g ~= built or builtC ~= s.c then built, builtC, flat = g, s.c, flatten(g, s.c) end
  if flat then flat.at = ns.walk.place(flat, s.X, s.Y) or 1 end
  return flat
end

-- ------------------------------------------------------------------ the lines between later steps
-- searched one at a time when a map wants them; Walk.lua's line until the search is in or if it finds nothing
local kept, keptN, searching = {}, 0, false
local function faction()
  local C = AuDHDEngine.Compat
  return C and C.GetPlayerFaction and C.GetPlayerFaction() or nil
end
function R.between(m1, x1, y1, m2, x2, y2)
  local W = ns.walk
  local N, A = nav()
  local function old() return W.path(m1, x1, y1, m2, x2, y2) end
  if not N then return old() end
  local c1, X1, Y1 = W.toWorld(m1, x1, y1)
  local c2, X2, Y2 = W.toWorld(m2, x2, y2)
  -- (only the continent you're on: the engine keeps one continent's maps in memory)
  if not c1 or c1 ~= c2 or c1 ~= W.player() or not N.Path.Available(c1) then return old() end
  if math.sqrt((X2 - X1) ^ 2 + (Y2 - Y1) ^ 2) > BETWEEN_MAX then return old() end
  local key = ("%d:%d:%d:%d:%d"):format(c1, math.floor(X1 / 8), math.floor(Y1 / 8), math.floor(X2 / 8), math.floor(Y2 / 8))
  local p = kept[key]
  if p then return p end
  if p == nil and not searching then
    searching = true
    local ok = pcall(N.Path.Find, c1, { x = X1, y = Y1 }, { x = X2, y = Y2 }, function(points)
      searching = false
      if keptN >= BETWEEN_KEEP then kept, keptN = {}, 0 end
      keptN = keptN + 1
      kept[key] = false
      if not points then return end
      local pts = {}
      for _, q in ipairs(points) do pts[#pts + 1], pts[#pts + 2] = q.x, q.y end
      local line = { legs = { { kind = "walk", pts = {} } } }
      for k = 1, #pts - 1, 2 do line.legs[1].pts[#line.legs[1].pts + 1] = { c1, pts[k], pts[k + 1] } end
      kept[key] = flatten(line, c1) or false
    end, { profile = faction(), style = A.Get("nav.routeStyle") })
    if not ok then searching = false kept[key] = false end
  end
  return old()
end

-- ------------------------------------------------------------------ what Walk.lua knows and the planner doesn't
-- the flight paths you start with or told us about by talking to a flight master
function R.syncTaxis()
  local A = AuDHDEngine
  local N = A and A.Nav
  if not (N and A.CharState and ns.walk) then return end
  local flags = A.CharState().flags
  if type(flags.taxi) ~= "table" then flags.taxi = {} end
  local nodes = N.GetTravelData().taxiById
  local added = false
  for id in pairs(ns.walk.knownTaxis()) do
    if nodes[id] and not flags.taxi[id] then flags.taxi[id] = true added = true end
  end
  if added and N.travel and N.travel.Replan then N.travel.Replan() end
end
-- the rides only your race has, as the planner's walk-in portals
local function raceRides(N)
  local portals = {}
  local function ending(name, c, X, Y)
    local bestM, bestX, bestY, bestSize
    for m, t in pairs(ns.walkMaps or {}) do
      if t.c == c then
        local x, y = ns.walk.toMap(m, X, Y)
        local size = t.w * t.h
        if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 and (not bestSize or size < bestSize) then
          bestM, bestX, bestY, bestSize = m, x * 100, y * 100, size
        end
      end
    end
    return { name, c, X, Y, bestM, bestX, bestY, "l" }
  end
  for i, L in ipairs(ns.walk.raceRides()) do
    portals[#portals + 1] = { id = "portal-race-" .. i, name = L.name, faction = L.side == "H" and 2 or 1, seconds = 5,
      a = ending(L.name, L.c, L.aX, L.aY), b = ending(L.name, L.c, L.bX, L.bY) }
  end
  if #portals > 0 then N.RegisterTravelData({ portals = portals, build = N.travel.build }) end
end

-- places only a ride reaches: a walk into or out of one costs too much to choose, so the planner takes the ride.
-- Rut'theran Village is at the foot of Teldrassil, a fatal drop below Dolanaar, but on Teldrassil's map, and the
-- planner priced a straight walk down to its portal. Boxes in world yards; Rut'theran's: Teldrassil's map below 86 (the
-- top ends near 80), 45 to 70 across, down to the dock.
local RIDE_ONLY = {
  { name = "Rut'theran Village", c = 1, x1 = 8300, x2 = 8920, y1 = 250, y2 = 1523 },
}
local function rideOnly(c, x, y)
  for _, b in ipairs(RIDE_ONLY) do
    if c == b.c and x and y and x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then return b end
  end
end
R.rideOnly = rideOnly
local function walkHook(w, cost)
  if rideOnly(w.from.c, w.from.wx, w.from.wy) ~= rideOnly(w.to.c, w.to.wx, w.to.wy) then return 1e7 end
end

local hooked = false
function R.start()
  local A = AuDHDEngine
  local N = A and A.Nav
  if not (N and ns.walk) then return end
  -- (the engine's chime has no place here: the arrow says "Arrived")
  if A.Get("nav.arrivalSound") then A.Set("nav.arrivalSound", false) end
  if not hooked and N.travel and N.travel.WalkCostHook then
    hooked = true
    N.travel.WalkCostHook(walkHook)
  end
  raceRides(N)
  R.syncTaxis()
  local learn, read = ns.walk.learnHere, ns.walk.readTaxiMap
  ns.walk.learnHere = function(...)
    local id = learn(...)
    R.syncTaxis()
    return id
  end
  ns.walk.readTaxiMap = function(...)
    local all, added = read(...)
    R.syncTaxis()
    return all, added
  end
  local function tick()
    sync()
    local on = nav()
    if on then sample(on) end
  end
  C_Timer.NewTicker(TICK, function() ns.routemap.safe(tick, "route") end)
  ns.routemap.safe(tick, "route")
end
