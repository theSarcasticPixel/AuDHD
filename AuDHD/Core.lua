-- The core: where the arrow points and how far it is, the hearthstone, caves, the game events and the slash commands.
-- It holds no route of its own: a guide engine plugs in through C.provider (the functions below hand on to it) and with
-- none plugged in there's simply no step, and the rest of the addon works without one.
local _, ns = ...
local C = {}
ns.core = C

local log = function(e, f) if ns.log then ns.log.add(e, f) end end
local isSecret = issecretvalue or function() return false end

-- UnitRace's second value is the game's file name for the race: Undead is "Scourge"
local TOKEN = { Scourge = "Undead" }
function ns.raceToken(race) return TOKEN[race] or race end
function ns.raceFits(rrace, race)
  if not rrace or not race then return true end
  race = ns.raceToken(race)
  for x in rrace:gmatch("[^/]+") do if x:lower() == race:lower() then return true end end
  return false
end

-- ------------------------------------------------------------------ the guide engine's slot
-- provider: current() -> step, i, pos, total, via; peek(k) -> step, i; ahead(limit) -> steps; info() -> { title, ends,
-- rares }; isDone(step, i); memLeft(m); markDone(reason); back(); later(); jump(n); advance(reason) -> true when the
-- step changed; plannedReward(questID); hasWork(questID). A step: k kind, t text, q quest, m uiMap, x, y (0..100), and
-- whatever else the engine carries.
C.provider = nil
local function ask(name, ...)
  local p = C.provider
  local f = p and p[name]
  if f then return f(...) end
end
function C.current() return ask("current") end
function C.peek(k) if k == 0 then return ask("current") end return ask("peek", k) end
function C.ahead(limit) return ask("ahead", limit) or {} end
function C.route() return ask("info") end
function C.isDone(step, i) return ask("isDone", step, i) end
function C.memLeft(m) return ask("memLeft", m) end
function C.back() return ask("back") end
function C.later() return ask("later") end
function C.jump(n) return ask("jump", n) end
function C.markDone(reason) return ask("markDone", reason) end
function C.plannedReward(questID) return ask("plannedReward", questID) end
-- the engine says its step changed (or plugged in): the arrow, the window, the map and the item button look again
function C.onStepChanged()
  local step, i, pos = C.current()
  C.setWaypoint(step)
  if step then log("STEP", { n = i, pos = pos, k = step.k, q = step.q, text = step.t }) end
  if ns.ui then ns.ui.refresh() end
  if ns.routemap then ns.routemap.refresh() end
  if ns.useItem then ns.useItem.refresh() end
end
function C.advance(reason)
  if ask("advance", reason) then C.onStepChanged() end
end
function C.setProvider(p)
  C.provider = p
  C.onStepChanged()
end

-- ------------------------------------------------------------------ quest helpers
local turnedIn = {}   -- this session: the game's completed flag can lag a moment behind QUEST_TURNED_IN
local function completed(q) return turnedIn[q] or C_QuestLog.IsQuestFlaggedCompleted(q) end
local function inLog(q) return C_QuestLog.GetLogIndexForQuestID(q) ~= nil end

-- the game's text for an objective (e.g. "Young Nightsaber slain: 3/7"), found by its name; nil if not in the log
function C.objectiveText(q, on)
  if not (q and on) then return nil end
  local ok, objs = pcall(C_QuestLog.GetQuestObjectives, q)
  if not ok or type(objs) ~= "table" then return nil end
  local want = on:lower()
  for _, o in ipairs(objs) do
    local text = o.text
    if text and not isSecret(text) and text:lower():find(want, 1, true) then return text, o.finished end
  end
end

-- "Tame a <beast>": a Taming Rod quest's objective doesn't report itself finished in Forever, so the pet you have out
-- counts: it carries the beast's name
local tameLogged = {}
local function tamed(on)
  if not (on and UnitExists("pet")) then return false end
  local name = UnitName("pet")
  return name and not isSecret(name) and name:lower() == on:lower() or false
end

-- the arrow's target: our own arrow (UI.lua) points at it. Blizzard's waypoint and super-tracking (SetSuperTracked*)
-- are Blizzard-only in Forever, so they're never called.
-- a weapon to buy that you can't pay for yet (money + the junk in your bags): the copper it costs and what you have
function C.weaponShort(step)
  if not step or step.k ~= "buyweapon" or not step.pc then return nil end
  local have = GetMoney() + (ns.auto and ns.auto.junkValue and ns.auto.junkValue() or 0)
  if have < step.pc then return step.pc, have end
end

C.target = nil
-- an arrows step: the ammo vendor nearest you now, not only the one the planner had in mind
function C.ammoStep(step)
  if not step or step.k ~= "buyammo" or not ns.ammo or not ns.ammo.nearestVendor then return step end
  local v = ns.ammo.nearestVendor()
  if not v then return step end
  return { k = step.k, m = v.m, x = v.x, y = v.y, lv = step.lv, t = ("Buy arrows from %s (to about %d)"):format(v.n, ns.ammo and ns.ammo.target() or 1000) }
end
-- the first place to go after the step on screen, in the (after + 1)th step ahead or later: the place (a map stop, with
-- ahead = which step ahead and from = that step), or nil
function C.nextStop(after)
  for k = (after or 0) + 1, (after or 0) + 10 do
    local s = C.peek(k)
    if not s then return nil end
    local p = s.stops and s.stops[1] or (s.m and s)
    if p then return setmetatable({ ahead = k, from = s }, { __index = p }) end
  end
end
function C.setWaypoint(step)
  step = C.ammoStep(step)
  -- a finished step on screen has no place of its own: the arrow leads on to the next place, as the map's numbers do
  if step and step.finished and not step.m then step = C.nextStop(0) end
  -- not off to the vendor before you can pay: you kill things where you are until then
  C.target = (step and step.m and step.x and step.y and not C.weaponShort(step)) and step or nil
  C.goalTarget = C.target
  C.caveTick()
end

-- distance (yards) and the angle to turn an up-pointing arrow by (radians, counter-clockwise), or nil
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local function worldPos(m, x, y)
  local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, m, CreateVector2D(x, y))
  if not ok or not pos then return nil end
  local wx, wy = pos:GetXY()
  return cont, wx, wy
end
function C.bearing(step)
  if not step then return nil end
  local m = C_Map.GetBestMapForUnit("player")
  if not m or isSecret(m) then return nil end
  local p = C_Map.GetPlayerMapPosition(m, "player")
  if not p then return nil end
  local px, py = p:GetXY()
  if isSecret(px) then return nil end
  local ca, ax, ay = worldPos(m, px, py)
  local cb, bx, by = worldPos(step.m, step.x / 100, step.y / 100)
  if not ca or ca ~= cb then return nil end
  -- world coordinates: X grows north, Y grows west; facing is radians from north, counter-clockwise
  local dx, dy = bx - ax, by - ay
  local dist = math.sqrt(dx * dx + dy * dy)
  local facing = GetPlayerFacing and GetPlayerFacing()
  if not facing or isSecret(facing) then return dist, nil end
  return dist, atan2(dy, dx) - facing
end

-- the hearthstone: seconds until it's ready (0 = ready), or nil when the game won't say
local HEARTHSTONE_ITEM, HEARTHSTONE_SPELL = 6948, 8690
function C.hearthLeft()
  local start, dur
  if C_Container and C_Container.GetItemCooldown then start, dur = C_Container.GetItemCooldown(HEARTHSTONE_ITEM) end
  if not start and C_Spell and C_Spell.GetSpellCooldown then
    local cd = C_Spell.GetSpellCooldown(HEARTHSTONE_SPELL)
    if type(cd) == "table" then start, dur = cd.startTime, cd.duration end
  end
  if not start or isSecret(start) or isSecret(dur) then return nil end
  if start == 0 or dur <= 1.5 then return 0 end   -- 1.5 s: only the global cooldown
  return math.max(0, start + dur - GetTime())
end
-- the engine's hearth goals ask Polestar's QoL for the Hearthstone (QoL.GetHearth), which isn't brought across:
-- answered here, or a guide's own "Hearth to Darkshire" on cooldown reads as ready and never says to walk to the inn
local hearthInfo = { item = HEARTHSTONE_ITEM }
function C.hearthInfo()
  local left = C.hearthLeft()
  if left == nil then return nil end
  local n = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(HEARTHSTONE_ITEM)
  hearthInfo.have = n == nil or isSecret(n) or n > 0
  hearthInfo.remaining = left
  hearthInfo.ready = hearthInfo.have and left == 0
  local bind = GetBindLocation and GetBindLocation()
  hearthInfo.bind = bind and not isSecret(bind) and bind ~= "" and bind or nil
  return hearthInfo
end
if AuDHDEngine then
  AuDHDEngine.QoL = AuDHDEngine.QoL or {}
  AuDHDEngine.QoL.GetHearth = AuDHDEngine.QoL.GetHearth or C.hearthInfo
end
-- the way to a hearth goal's inn without the Hearthstone ("the trip takes 12 min"): the engine plans the whole journey
-- each time a step with a hearth goal is looked at, kept only 5 s or 25 yd, and the arrow looks at the steps ahead all
-- the time. Worked out at most once a minute per inn, sooner once you've moved 300 yd. Only that line asks (Engine.lua
-- hearthTrip, the one call with noHearth)
local INN_EVERY, INN_MOVED = 60, 300
local innTrips = {}
function C.innTrip(estimate, to)   -- the planner's search itself (timed by /audhd perf)
  local ok, s = pcall(estimate, nil, to, nil, true)
  if ok and type(s) == "number" then return s end
  return nil
end
local function keepInnTrips()
  local N = AuDHDEngine and AuDHDEngine.Nav
  if not (N and type(N.EstimateTravel) == "function") or C.innTripsKept then return end
  C.innTripsKept = true
  local estimate = N.EstimateTravel
  N.EstimateTravel = function(from, to, budgeted, noHearth)
    if not (noHearth and from == nil and type(to) == "table") then return estimate(from, to, budgeted, noHearth) end
    local P = AuDHDEngine.Compat
    local c, X, Y
    if P and P.GetPlayerWorldPosition then c, X, Y = P.GetPlayerWorldPosition() end
    local key = ("%s:%.2f:%.2f"):format(tostring(to.map), to.x or 0, to.y or 0)
    local k, now = innTrips[key], GetTime()
    if k and now - k.at < INN_EVERY and k.c == c
      and (not (X and k.X) or (X - k.X) ^ 2 + (Y - k.Y) ^ 2 < INN_MOVED * INN_MOVED) then
      return k.s
    end
    local s = C.innTrip(estimate, to)
    innTrips[key] = { at = now, c = c, X = X, Y = Y, s = s }
    return s
  end
end
keepInnTrips()
-- the engine's words that send players to Polestar's command: ours instead
if AuDHDEngine and type(AuDHDEngine.L) == "table" then
  rawset(AuDHDEngine.L, "Not offered by %s? Report it with /polestar", "Not offered by %s? Report it with /audhd report")
end
-- and tells it when the cooldown starts or ends, or the bind moves, as QoL did: it looks at its hearth goals again
local hearthWas
function C.hearthChanged(force)
  local left = C.hearthLeft()
  local now = left and left > 0
  if now == hearthWas and not force then return end
  hearthWas = now
  if AuDHDEngine and AuDHDEngine.Fire then AuDHDEngine.Fire("QOL_HEARTH_CHANGED", C.hearthInfo()) end
end
-- a step with a hearth of the guide's own in it ("Hearth to Darkshire"), or one the old planner reached by hearthstone
function C.hearthStep(step)
  return step ~= nil and (step.hs or step.hearth or step.k == "hearth") and true or false
end
-- a step's text as shown: a "Hearth, then:" step while the hearthstone is still cooling down says to walk instead
-- a "Hearth, then:" step you're already near walks instead: the planner hearthed from where it thought you'd be
local HEARTH_NEAR = 600   -- yards: about a minute and a half on foot, less than a hearth costs you (its cooldown)
function C.hearthNear(step)
  local d = step and step.hs and step.x and C.bearing(step)
  return d ~= nil and d < HEARTH_NEAR
end
-- where your hearthstone takes you: the inn you bound at, by its name (GetBindLocation). Learned where you stand when
-- you bind and where you land after a hearth (any inn), else these
local BINDS = {
  ["Thunderbrew Distillery"] = { m = 1426, x = 47.4, y = 52.5 }, ["Stoutlager Inn"] = { m = 1432, x = 35.5, y = 48.4 },
  ["Stonefire Tavern"] = { m = 1455, x = 18.2, y = 51.5 }, ["Lion's Pride Inn"] = { m = 1429, x = 43.8, y = 65.8 },
  ["Sentinel Hill"] = { m = 1436, x = 52.9, y = 53.7 }, ["Dolanaar"] = { m = 1438, x = 55.6, y = 59.8 },
  ["Auberdine"] = { m = 1439, x = 37.0, y = 44.1 }, ["Craftsmen's Terrace"] = { m = 1457, x = 67.4, y = 15.6 },
}
function C.bindSpot()
  local name = GetBindLocation and GetBindLocation()
  if not name or isSecret(name) then return nil end
  local b = (AuDHDDB.binds or {})[name] or BINDS[name]
  return b and { m = b.m, x = b.x, y = b.y, n = name }
end
local function learnBind()
  local name = GetBindLocation and GetBindLocation()
  local m = C_Map.GetBestMapForUnit("player")
  local p = m and not isSecret(m) and C_Map.GetPlayerMapPosition(m, "player")
  if not (name and p) or isSecret(name) then return end
  local x, y = p:GetXY()
  if isSecret(x) then return end
  AuDHDDB.binds = AuDHDDB.binds or {}
  AuDHDDB.binds[name] = { m = m, x = math.floor(x * 1000 + 0.5) / 10, y = math.floor(y * 1000 + 0.5) / 10 }
  log("BIND_SPOT", { n = name, bm = m, bx = AuDHDDB.binds[name].x, by = AuDHDDB.binds[name].y })
end
C.learnBind = learnBind
-- hearth now, though the route walks: the hearthstone is ready, the step is by the inn it takes you to (HEARTH_LANDS
-- yards) and HEARTH_WORTH or more away from you, and no hearth the route plans comes in the next HEARTH_KEEP steps (it
-- would still be cooling down)
local HEARTH_WORTH, HEARTH_LANDS, HEARTH_KEEP = 800, 300, 25
-- whether a hearth of the route's own comes in the next HEARTH_KEEP steps: the arrow asks every frame, so the answer is
-- kept HEARTH_LOOK seconds for the same step
local HEARTH_LOOK = 5
local keptAhead = {}
local function hearthAhead(step)
  local key = ("%s:%s:%s"):format(tostring(step.i), tostring(step.k), tostring(step.q))
  local now = GetTime()
  if keptAhead.key == key and now - keptAhead.at < HEARTH_LOOK then return keptAhead.found end
  local found = false
  for k = 1, HEARTH_KEEP do
    local s = C.peek(k)
    if not s then break end
    if C.hearthStep(s) then found = true break end
  end
  keptAhead.key, keptAhead.at, keptAhead.found = key, now, found
  return found
end
function C.hearthNow(step)
  if not (step and step.m and step.x and step.y) or C.hearthStep(step) or step.ds then return false end
  if C.hearthLeft() ~= 0 then return false end
  local b = C.bindSpot()
  if not b then return false end
  local cb, bx, by = worldPos(b.m, b.x / 100, b.y / 100)
  local cs, sx, sy = worldPos(step.m, step.x / 100, step.y / 100)
  if not cb or cb ~= cs or math.sqrt((bx - sx) ^ 2 + (by - sy) ^ 2) > HEARTH_LANDS then return false end
  local d = C.bearing(step)
  if d and d < HEARTH_WORTH then return false end
  -- and what comes after it is nearer the inn than where you are now: not a hearth there and a walk all the way back
  for k = 1, 3 do
    local s = C.peek(k)
    if s and s ~= step and s.m and s.x and s.y then
      local c2, x2, y2 = worldPos(s.m, s.x / 100, s.y / 100)
      local after = C.bearing(s)
      if c2 == cb and after and math.sqrt((bx - x2) ^ 2 + (by - y2) ^ 2) > after then return false end
      break
    end
  end
  return not hearthAhead(step)
end
function C.text(step)
  local t = step and step.t or ""
  -- a "Together here" step: only the parts still to do (one part per member, in order)
  local body = step and step.mem and t:match("^Together here: (.*)$")
  if body then
    local parts = {}
    for p in (body .. "; "):gmatch("(.-); ") do parts[#parts + 1] = p end
    if #parts == #step.mem then
      local left = {}
      for k, m in ipairs(step.mem) do if C.memLeft(m) then left[#left + 1] = parts[k] end end
      if #left > 0 and #left < #parts then t = #left == 1 and left[1] or "Together here: " .. table.concat(left, "; ") end
    end
  end
  if C.hearthNow(step) then t = ("Hearth (to %s), then: "):format(C.bindSpot().n) .. t end
  if step and step.hs then
    local left = C.hearthLeft()
    if C.hearthNear(step) then
      t = t:gsub("^Hearth, then: ", "Walk, then: ")
    elseif left and left > 0 then
      t = t:gsub("^Hearth, then: ", ("Walk (hearth ready in %d min), then: "):format(math.ceil(left / 60)))
    end
  end
  -- a death skip you don't need: already close (a minute or so on foot), or already dead (you'll get there anyway)
  if step and step.ds then
    local d = step.x and C.bearing(step)
    if d and d < 400 then t = t:gsub("^Death skip: [^:]*, then: ", "")
    elseif UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then t = t:gsub("^Death skip: let a mob kill you, release, and ", "Release and ") end
  end
  return t
end

-- yards from you to the step (same continent only), or nil
function C.distance(step)
  local d = C.bearing(step)
  return d and math.floor(d) or nil
end

-- ------------------------------------------------------------------ where you are, and caves
local function playerWorld()
  local m = C_Map.GetBestMapForUnit("player")
  if not m or isSecret(m) then return nil end
  local p = C_Map.GetPlayerMapPosition(m, "player")
  if not p then return nil end
  local px, py = p:GetXY()
  if isSecret(px) then return nil end
  local c, x, y = worldPos(m, px, py)
  return c and { c = c, x = x, y = y }
end
-- caves: the map is flat, so a spot above a cave looks the same as one in it (box: x1, x2, y1, y2 on the zone's map)
local CAVES = {
  ["Grizzled Den"] = { m = 1426, door = { 42, 54 }, box = { 39.5, 44.5, 44.5, 56.5 } },
  -- the Fire Tar for Call of Fire
  ["Silver Stream Mine"] = { m = 1432, door = { 35.5, 18.8 }, box = { 33.5, 38.5, 19.3, 29 } },
  -- 20-30 (from the guide's way in, not yet seen in game: listed in the 20-30 doc to check)
  ["Rethban Caverns"] = { m = 1433, door = { 14.5, 32.0 }, box = { 11, 17, 20, 31.5 } },
  ["Whelgar's Excavation"] = { m = 1437, door = { 38.2, 50.9 }, box = { 37.5, 41, 51.2, 55 } },
  ["Vul'Gol Ogre Mound"] = { m = 1431, door = { 34.6, 77.6 }, box = { 34, 39, 77.5, 86 } },
  -- Horde (from the guide's way in and where the mobs inside spawn; not yet seen in game)
  ["Burning Blade Coven"] = { m = 1411, door = { 45.3, 56.3 }, box = { 42.2, 45.7, 51.9, 55.9 } },
  ["Dustwind Cave"] = { m = 1411, door = { 53.2, 29.1 }, box = { 51.5, 53.7, 24.2, 29.5 } },
  ["Skull Rock"] = { m = 1411, door = { 54.9, 9.6 }, box = { 51.2, 55.2, 7.4, 11.3 } },
  ["Palemane Rock"] = { m = 1412, door = { 35.4, 65.0 }, box = { 31.5, 35.3, 62.8, 66.5 } },
  ["Seer Wiserunner's cave"] = { m = 1412, door = { 34.9, 43.6 }, box = { 33.8, 34.7, 42.8, 43.8 } },
  ["Venture Co. Mine"] = { m = 1412, door = { 58.4, 52.6 }, box = { 57.5, 62.2, 44.0, 52.4 } },
  ["Night Web's Hollow"] = { m = 1420, door = { 26.8, 59.4 }, box = { 22.9, 26.65, 57.9, 61.0 } },
  ["Deep Elem Mine"] = { m = 1421, door = { 56.5, 45.9 }, box = { 56.7, 59.2, 44.2, 46.2 } },
  ["Dreadmist Den"] = { m = 1413, door = { 47.7, 19.2 }, box = { 47.85, 48.2, 18.85, 19.35 } },
  ["Chol'aruk's cave"] = { m = 1413, door = { 58.1, 25.3 }, box = { 57.4, 58.2, 25.9, 27.8 } },
  -- druid class quests (doors from the guide, boxes round the spots inside; not yet seen in game)
  ["Moonkin Stone cave"] = { m = 1439, door = { 43.1, 45.6 }, box = { 43.3, 43.8, 45.75, 46.25 } },
  ["Stormrage Barrow Dens"] = { m = 1450, door = { 72.15, 62.2 }, box = { 72.2, 75.7, 63.0, 67.8 } },
  ["Ur'endra's cave"] = { m = 2521, door = { 54.3, 65.8 }, box = { 52.8, 54.1, 64.4, 65.5 } },
  -- starting zones (doors and the way in from the guide; not yet seen in game)
  ["Coldridge troll cave"] = { m = 1426, door = { 26.85, 79.83 }, box = { 26.9, 31.0, 77.8, 83.6 } },
  -- the way in from the guides (Frostmane Hold: "Run up the side of the cave entrance"; the quarry: where
  -- "inside" begins; Cliffspring: "at the mouth of the cave"; Thistlefur Hold: "Enter Thistlefur Hold"; Fargodeep: "Go
  -- into the mine") or the wiki (Shadowthread Cave's entrance); not yet seen in game
  ["Frostmane Hold"] = { m = 1426, door = { 24.9, 50.5 }, box = { 21.0, 24.6, 49.8, 55.0 } },
  ["Gol'Bolar Quarry"] = { m = 1426, door = { 70.7, 56.3 }, box = { 70.2, 73.5, 49.8, 56.0 } },
  ["Cliffspring cave"] = { m = 1439, door = { 54.9, 33.2 }, box = { 55.1, 57.6, 33.5, 37.2 } },
  ["Thistlefur Hold"] = { m = 1440, door = { 38.4, 30.6 }, box = { 38.6, 42.5, 30.8, 35.2 } },
  ["Shadowthread Cave"] = { m = 1438, door = { 56.7, 32.0 }, box = { 55.5, 58.5, 25.5, 31.7 } },
  ["Fargodeep Mine"] = { m = 1429, door = { 40.5, 82.3 }, box = { 39.6, 42.2, 77.2, 82.0 } },
  -- entrances placed by hand; not yet seen in game
  ["Azurelode Mine"] = { m = 1424, door = { 27.2, 59 }, box = { 26.7, 32.7, 50.9, 59.8 } },  -- box drawn on the page
  ["Darrow Hill cave"] = { m = 1424, door = { 46, 32 }, box = { 41.8, 47.7, 24.7, 34.3 } },  -- box drawn on the page
  ["Growless Cave"] = { m = 1416, door = { 37.6, 67.8 }, box = { 37, 38.2, 65.6, 66.8 } },  -- box fitted round its spots
  ["Boulderslide Cavern"] = { m = 1442, door = { 57.9, 90.8 }, box = { 56.9, 63, 88.9, 94.1 } },  -- box drawn on the page
  ["Old Icebeard's cave"] = { m = 1426, door = { 37.9, 53.8 }, box = { 37.9, 39.1, 53.3, 54.5 } },  -- box fitted round its spots
  ["Jorel Windsinger's cave"] = { m = 2521, door = { 63.6, 37 }, box = { 63.9, 65.6, 34.1, 35.6 } },  -- box fitted round its spots
  ["Incinerator Gar'im's cave"] = { m = 1433, door = { 71.6, 84.6 }, box = { 66.5, 73.2, 79.1, 86.9 } },  -- box fitted round its spots
  ["Broodmother Valraxx's cave"] = { m = 1412, door = { 33.4, 7.5 }, box = { 33.1, 34, 6.5, 7.9 } },  -- box fitted round its spots
  ["Volcor's cave"] = { m = 1439, door = { 44.7, 85.2 }, box = { 44.8, 45.6, 84.9, 85.9 } },  -- box round Volcor, short of the mouth (44.6,85.0) where the escape completes
  ["Render's Rock"] = { m = 1433, door = { 28.1, 7.5 }, box = { 22.7, 23.9, 12, 13.2 } },  -- box fitted round its spots
  ["Echo Ridge Mine"] = { m = 1429, door = { 47.63, 32.07 }, box = { 47.0, 51.0, 25.0, 31.8 } },
  ["Jasperlode Mine"] = { m = 1429, door = { 61.65, 53.61 }, box = { 59.5, 62.2, 48.5, 53.4 } },
  -- entrances from the second guide set's "Enter the cave" points; not yet seen in game
  ["Fel Rock"] = { m = 1438, door = { 54.65, 52.45 }, box = { 50.5, 54.3, 48.8, 52.3 } },
  ["Splithoof Hold"] = { m = 1441, door = { 44.05, 37.34 }, box = { 41.3, 44.6, 30.8, 37.0 } },
  ["Grenka's cave"] = { m = 1441, door = { 27.27, 51.29 }, box = { 25.3, 27.4, 51.6, 56.3 } },
  -- the entrance, and where the path up to it starts
  ["Den Mother's cave"] = { m = 1439, door = { 51.6, 37.5 }, up = { 52.4, 36 }, box = { 51.0, 52.1, 37.7, 38.9 } },
  -- the Legacy of the Aspects; box fitted round the book, short of the entrance
  ["Dor'Danil Barrow Den"] = { m = 1440, door = { 75.74, 75.34 }, box = { 75.0, 76.2, 73.8, 75.1 } },
}
local function caveAt(m, x, y)
  for name, cv in pairs(CAVES) do
    local b = cv.box
    if cv.m == m and x >= b[1] and x <= b[2] and y >= b[3] and y <= b[4] then return name, cv end
  end
end
C.worldPos, C.playerWorld = worldPos, playerWorld   -- Rare.lua: the spawn points near you
-- caves: the map is flat, so a spot above a cave looks the same as one in it. Inside a cave and going somewhere outside
-- it, or outside and going to something in it (a member's ly), the arrow goes to the entrance first (IsIndoors says
-- which side you're on)
local DOOR_NEAR = 15   -- yards: at the entrance, go on in
local function targetCave(t)
  local ly = t.ly
  if ly == nil and t.mem then
    for _, mem in ipairs(t.mem) do if mem.ly then ly = mem.ly end end
  end
  if ly == "any" then ly = t.m and t.x and caveAt(t.m, t.x, t.y) end
  return ly or nil
end
C.caves = CAVES
function C.caveTick()
  local goal = C.goalTarget
  if not goal then return end
  local want = goal
  local m = C_Map.GetBestMapForUnit("player")
  local p = m and not isSecret(m) and C_Map.GetPlayerMapPosition(m, "player")
  if p then
    local px, py = p:GetXY()
    if not isSecret(px) then
      local indoors = IsIndoors and IsIndoors()
      local here, hcv = caveAt(m, px * 100, py * 100)
      local tc = targetCave(goal)
      if indoors and here and tc ~= here then
        want = setmetatable({ m = hcv.m, x = hcv.door[1], y = hcv.door[2], ly = false,
          t = ("Out of the %s, then: %s"):format(here, C.text(goal)) }, { __index = goal })
      elseif not indoors and tc and CAVES[tc] then
        local cv = CAVES[tc]
        local door = { m = cv.m, x = cv.door[1], y = cv.door[2] }
        local d = C.bearing(door)
        -- an entrance up a slope (cv.up, where the way up starts): there first, then the entrance
        local up = cv.up
        if up and C.caveUpDone ~= tc then
          local du = C.bearing({ m = cv.m, x = up[1], y = up[2] })
          if (d and d <= DOOR_NEAR) or (du and du <= DOOR_NEAR) then C.caveUpDone = tc else
            want = setmetatable({ m = cv.m, x = up[1], y = up[2], ly = false,
              t = ("Up to the %s: %s"):format(tc, C.text(goal)) }, { __index = goal })
          end
        end
        if want == goal and (not d or d > DOOR_NEAR) then
          want = setmetatable({ m = cv.m, x = cv.door[1], y = cv.door[2], ly = false,
            t = ("Into the %s: %s"):format(tc, C.text(goal)) }, { __index = goal })
        end
      end
      if C.caveUpDone and C.caveUpDone ~= tc then C.caveUpDone = nil end
    end
  end
  -- the same door as before: keep the same table (the walk path is keyed by place, the arrow by table)
  local cur = C.target
  if want ~= goal and cur and cur ~= goal and cur.m == want.m and cur.x == want.x and cur.y == want.y then return end
  if cur ~= want then
    C.target = want
    if ns.arrow and ns.arrow.update then ns.arrow.update() end
  end
end

local function readyToHandIn(q)
  if not inLog(q) then return false end
  if C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(q) then return true end
  if C_QuestLog.IsComplete(q) then return true end
  -- every objective finished, a "Tame a ..." counting when that beast is your pet (Forever flags neither the objective
  -- nor the quest as done after a Taming Rod)
  local ok, objs = pcall(C_QuestLog.GetQuestObjectives, q)
  if not ok or type(objs) ~= "table" then return false end
  -- no objectives: a "go and talk to" quest (Training the Beast, to Jocaste in Darnassus: Forever calls it neither
  -- ready nor complete, so the hand-in was never offered); not one the guide has work for (its objectives not loaded
  -- yet)
  if #objs == 0 then return not ask("hasWork", q) end
  for _, o in ipairs(objs) do
    local text = o.text
    if not o.finished then
      if not (text and not isSecret(text) and text:find("^Tame ") and tamed(text:match("^Tame an? (.+)$"))) then return false end
    end
  end
  return true
end
C.readyToHandIn = readyToHandIn

-- ------------------------------------------------------------------ events
local frame = ns.newFrame("Core", "Frame")
local pending = false
local function soon(reason)
  if pending then return end
  pending = true
  C_Timer.After(0.4, function() pending = false; C.advance(reason) end)
end
-- a flight master's chat window has a "show me where I can fly" line (the taxi icon); any other NPC's doesn't
local function flightGossip()
  local opts = C_GossipInfo and C_GossipInfo.GetOptions and C_GossipInfo.GetOptions() or {}
  for _, o in ipairs(opts) do
    if o.icon == 132057 or (o.type and tostring(o.type):lower() == "taxi") then return true end
  end
  return false
end
-- talking to a flight master learns its path (told = the game said "New flight path discovered")
function C.flightLearned(told)
  if not ns.walk or not ns.walk.learnHere or not (told or flightGossip()) then return end
  local id = ns.walk.learnHere()
  if id then log("TAXI_LEARNED", { id = id }) end
  if ns.ui then ns.ui.refresh() end
end

local events = {
  QUEST_ACCEPTED = function() soon("quest accepted") end,
  PLAYER_CONTROL_GAINED = function() soon("landed") end,   -- off the flight path: look again where you are
  QUEST_TURNED_IN = function(q) turnedIn[q] = true; soon("quest turned in") end,
  QUEST_REMOVED = function() soon("quest removed") end,
  QUEST_LOG_UPDATE = function()
    soon("quest log")
    if ns.ui then C_Timer.After(0.5, ns.ui.refresh) end   -- the live objective counts
  end,
  PLAYER_LEVEL_UP = function() soon("level up") end,
  PLAYER_DEAD = function() soon("died") end,
  PLAYER_ALIVE = function() soon("alive") end,
  PLAYER_UNGHOST = function() soon("resurrected") end,
  -- a flight master's chat window: the path is yours from now (Forever opens it before the flight map)
  GOSSIP_SHOW = function() C.flightLearned(false) end,
  UI_INFO_MESSAGE = function(_, msg) if msg and ERR_NEWTAXIPATH and msg == ERR_NEWTAXIPATH then C.flightLearned(true) end end,
  TAXIMAP_OPENED = function()
    -- the flight paths you know: the arrow flies you when it's quicker (Walk.lua)
    if ns.walk then
      local all, added = ns.walk.readTaxiMap()
      if #added > 0 then log("TAXI_KNOWN", { ids = all }) end
    end
  end,
  HEARTHSTONE_BOUND = function() C_Timer.After(1, learnBind) C.hearthChanged(true) end,
  BAG_UPDATE_COOLDOWN = function() C.hearthChanged() end,
  -- where a hearth lands: the inn's spot (once the new zone has loaded)
  UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID)
    if unit == "player" and spellID == HEARTHSTONE_SPELL then C_Timer.After(4, learnBind) end
  end,
}
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= "AuDHD" then return end
    AuDHDDB = AuDHDDB or {}
    AuDHDDB.auto = AuDHDDB.auto or {}
    return
  end
  if event == "PLAYER_LOGIN" then
    ns.log.start()
    ns.log.enable()
    ns.auto.enable()
    if ns.ui then ns.ui.create() end
    if ns.arrow then ns.arrow.create() end
    if ns.range then pcall(ns.range.create) end
    if ns.routemap then pcall(ns.routemap.enable) end
    if ns.ammo then pcall(ns.ammo.enable) end
    if ns.party then pcall(ns.party.enable) end
    if ns.threat then pcall(ns.threat.enable) end
    if ns.drops then pcall(ns.drops.enable) end
    if ns.rare then pcall(ns.rare.enable) end
    if ns.minimap then pcall(ns.minimap.create) end
    if ns.settings then pcall(ns.settings.register) end
    if ns.guide then pcall(ns.guide.start) end
    if ns.extra then pcall(ns.extra.enable) end
    if ns.track then pcall(ns.track.enable) end
    for e in pairs(events) do pcall(frame.RegisterEvent, frame, e) end
    -- the quest log isn't ready at login: look a moment later
    C_Timer.After(3, function() C.advance("init") end)
    C_Timer.NewTicker(2, function() C.advance("tick") end)
    C_Timer.NewTicker(1, function() C.caveTick() end)
    return
  end
  local h = events[event]
  if h then
    local ok, err = pcall(h, ...)
    if not ok then log("CORE_ERROR", { event = event, err = tostring(err) }) end
  end
end)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

-- ------------------------------------------------------------------ /audhd
local function say(msg) print("|cff66ccffAuDHD|r: " .. msg) end
SLASH_AUDHD1 = "/audhd"
SLASH_AUDHD2 = "/wfn"
SlashCmdList.AUDHD = function(input)
  local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if cmd == "" then
    if ns.ui then ns.ui.toggle() end
  elseif cmd == "note" and rest ~= "" then
    local step, i = C.current()
    log("NOTE", { text = rest, n = i, q = step and step.q })
    say("noted: " .. rest)
  elseif cmd == "done" then C.markDone("manual")
  elseif cmd == "later" then C.later()
  elseif cmd == "back" then C.back()
  elseif cmd == "goto" and tonumber(rest) then C.jump(tonumber(rest))
  elseif cmd == "settings" and ns.settings then
    ns.settings.show()
  elseif cmd == "minimap" and ns.minimap then
    AuDHDDB.minimap = AuDHDDB.minimap or { angle = 200 }
    AuDHDDB.minimap.hide = (rest == "off") or nil
    ns.minimap.apply()
    say("minimap button: " .. (AuDHDDB.minimap.hide and "off" or "on") .. " (/audhd minimap on|off)")
  elseif cmd == "auto" then
    local key, val = rest:match("^(%S+)%s*(%S*)$")
    if key and ns.auto.DEFAULTS[key] ~= nil then
      if key == "reward" then AuDHDDB.auto.reward = (val == "manual") and "manual" or "value"
      else AuDHDDB.auto[key] = (val ~= "off") end
      say(("auto %s: %s"):format(key, tostring(AuDHDDB.auto[key])))
    else
      local parts = {}
      for k, d in pairs(ns.auto.DEFAULTS) do
        local v = AuDHDDB.auto[k]
        if v == nil then v = d end
        parts[#parts + 1] = k .. "=" .. tostring(v)
      end
      say("auto: " .. table.concat(parts, ", ") .. "  (/audhd auto accept|complete|junk|repair on|off, /audhd auto reward value|manual; hold Shift to pause)")
    end
  elseif cmd == "ammo" then
    if rest == "off" then say(ns.ammo.goVendor(true))
    elseif tonumber(rest) then AuDHDDB.ammoTarget = tonumber(rest); say("buying ammo up to " .. rest)
    else say(ns.ammo.goVendor()) end
  elseif cmd == "map" then
    AuDHDDB.mapHidden = (rest == "off") or nil
    if ns.routemap then ns.routemap.refresh() end
    say("route on the maps: " .. (AuDHDDB.mapHidden and "off" or "on") .. " (/audhd map on|off)")
  elseif cmd == "arrow" then
    say(ns.arrow.command(rest))
  elseif cmd == "range" then
    say(ns.range.command(rest))
  elseif cmd == "threat" and ns.threat then
    say(ns.threat.command(rest))
  elseif cmd == "perf" and ns.perf then
    say(ns.perf.run(say))
  elseif cmd == "rares" and ns.rare then
    say(ns.rare.command(rest))
  elseif cmd == "spec" then
    local _, class = UnitClass("player")
    local names = {}
    for _, sp in ipairs(ns.weights and ns.weights[class] or {}) do names[#names + 1] = sp.name end
    if rest ~= "" then AuDHDDB.spec = rest end
    local sp = ns.auto.spec()
    say(("rewards are scored for %s (specs: %s; /audhd spec <name>)"):format(sp and sp.name or "?", table.concat(names, ", ")))
  elseif cmd == "announce" and ns.questDone then
    say(ns.questDone.command(rest))
  elseif cmd == "askbuffs" and ns.buffAsk then
    say(ns.buffAsk.command(rest))
  elseif cmd == "imbue" and ns.imbue then
    say(ns.imbue.command(rest))
  elseif cmd == "heal" and ns.heal then
    say(ns.heal.command(rest))
  elseif cmd == "fish" and ns.fishing then
    say(ns.fishing.command(rest))
  elseif cmd == "dungeons" and ns.dungeons then
    local r = ns.dungeons.command(rest)
    if r then say(r) end
  elseif cmd == "atlas" and ns.atlas then
    say(ns.atlas.command(rest))
  elseif cmd == "bigmap" and ns.bigmap then
    local r = ns.bigmap.command(rest)
    if r then say(r) end
  elseif cmd == "shards" and ns.shards then
    say(ns.shards.command(rest))
  elseif (cmd == "buffs" or cmd == "aspect") and ns.imbue then
    say(ns.imbue.command(rest, "buffs"))
  elseif cmd == "food" and ns.imbue then
    say(ns.imbue.command(rest, "food"))
  elseif cmd == "scrolls" and ns.imbue then
    say(ns.imbue.command(rest, "scrolls"))
  elseif cmd == "blocked" and ns.walk then
    local n, ax, ay, bx, by = ns.walk.block()
    if n > 0 then
      say(("that way's out (%.1f,%.1f to %.1f,%.1f): finding another (/audhd unblock puts them all back)"):format(ax or 0, ay or 0, bx or 0, by or 0))
      if ns.arrow and ns.arrow.update then ns.arrow.update() end
    else
      say("no walking way to block here")
    end
  elseif cmd == "unblock" and ns.walk then
    say(("%d blocked stretches put back"):format(ns.walk.unblock()))
  elseif cmd == "stats" and ns.stats then
    say("info bar: " .. ns.stats.command(rest))
  elseif cmd == "paths" and ns.walk then
    say("map paths: " .. ns.walk.setStyle(rest == "straight" and "straight" or rest == "detailed" and "detailed" or (AuDHDDB.pathStyle == "straight" and "detailed" or "straight")))
  elseif cmd == "bags" and ns.altItems then
    local msg = ns.altItems.bagsCommand(rest)
    if msg then say(msg) end
  elseif cmd == "find" and ns.altItems then
    ns.altItems.command(rest)
  elseif cmd == "ah" and ns.auction then
    local msg = ns.auction.command(rest)
    if msg then say(msg) end
  elseif cmd == "bankalt" and ns.services then
    ns.services.command(rest)
  elseif cmd == "where" and ns.track then
    say(ns.track.where())
  elseif cmd == "guides" and ns.picker then
    ns.picker.show()
  elseif cmd == "extra" and ns.extra then
    say(ns.extra.command(rest))
  elseif cmd == "share" and ns.share then
    say(ns.share.command(rest))
  elseif cmd == "report" and ns.share then
    ns.share.showReport()
  elseif cmd == "unskip" and ns.guide then
    say(ns.guide.unskip())
  elseif cmd == "log" then
    local n, s = ns.log.count()
    say(("%d entries this session, %d sessions saved (written on /reload or logout)"):format(n, s))
  else
    say("/audhd (show/hide), /audhd note <text>, /audhd done, /audhd later, /audhd unskip, /audhd back, /audhd goto <n>, /audhd settings, /audhd minimap on|off, /audhd auto, /audhd ammo [off|<count>], /audhd arrow, /audhd map on|off, /audhd threat on|off, /audhd rares all|route|off, /audhd perf, /audhd spec [name], /audhd imbue [off|on], /audhd shards [off|on|max <n>|low <n>|lock|unlock|reset], /audhd heal [on|off|setup], /audhd fish [on|off|right|middle|4|5|status|loud on|off|volume <10-100>|lure on|off|zone on|off|map on|off], /audhd bigmap [on|off|replace on|off], /audhd atlas on|off (work in progress), /audhd buffs [off|on], /audhd food [off|on], /audhd scrolls [off|on], /audhd announce [off|on], /audhd askbuffs [off|on], /audhd stats [show|hide|lock|unlock|reset|move|bags|repair|volume], /audhd paths [detailed|straight], /audhd bankalt [<name>|off|on|clear], /audhd find <item>, /audhd bags [all|close|<name>], /audhd ah [scan|on|off|price <item>], /audhd blocked, /audhd unblock, /audhd where, /audhd guides, /audhd dungeons [name], /audhd extra, /audhd share, /audhd report, /audhd log")
  end
end

