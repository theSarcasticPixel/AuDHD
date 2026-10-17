-- The route engine: which step you're on (worked out from your quest log, so it survives reloads and playing out of
-- order), the waypoint arrow, the stretch pop-up, and the slash commands. UI.lua draws it; Log.lua records it all.
local _, ns = ...
-- routes that aren't published (a test route) come from a local addon of their own, AuDHD_Private, which loads after
-- this one and adds them here
ns.routes = ns.routes or {}
AuDHDRoutes = ns.routes
local C = {}
ns.core = C

local DEFAULT_ROUTE = "nelf_hunter_start"
local log = function(e, f) if ns.log then ns.log.add(e, f) end end
local isSecret = issecretvalue or function() return false end

local function db() return AuDHDDB end
-- a route's signature: when the planner's output changes, saved positions no longer line up, so the state starts
-- again (the steps you've already done are skipped again from your quest log)
local function signature(r)
  local first, last = r.steps[1], r.steps[#r.steps]
  return ("%d|%s|%s"):format(#r.steps, first and first.t or "", last and last.t or "")
end
-- the pet quests: the route's own list from the planner (a Hunter's Taming / Training the Beast, a Warlock's voidwalker
-- chain), else the Hunter titles, by the accept steps only: a "Together here" step names the quest too but carries
-- another quest's id
function ns.petQuests(r)
  local qs = {}
  if r.pet then
    for _, id in ipairs(r.pet) do qs[id] = true end
    return qs
  end
  for _, s in ipairs(r.steps) do
    if s.k == "accept" and s.q and s.t and (s.t:find("Taming the Beast", 1, true) or s.t:find("Training the Beast", 1, true)) then qs[s.q] = true end
  end
  return qs
end
-- a "Together here" step that mixes a pet quest with others becomes two steps, the pet part first, so the pet rule
-- below can move the pet part up on its own (and the rest, e.g. buying a vial, stays where the planner put it)
-- a route for any class: its "Train at" steps carry the nearest trainer of every class (tr[CLASS] = { name, map, x, y });
-- yours is the one shown and walked to
local function yourTrainers(r)
  local _, class = UnitClass("player")
  for _, s in ipairs(r.steps) do
    local t = s.tr and class and s.tr[class]
    if t then s.t = (s.hs and "Hearth, then: " or "") .. "Train at " .. t[1]; s.m, s.x, s.y = t[2], t[3], t[4] end
  end
end
local function splitPetGroups(r)
  if not r or r.splitDone then return r end
  r.splitDone = true
  yourTrainers(r)
  local qs, out = ns.petQuests(r), {}
  for _, s in ipairs(r.steps) do
    local pet, other = {}, {}
    if s.k == "do" and s.mem then
      for _, m in ipairs(s.mem) do if qs[m.q] then pet[#pet + 1] = m else other[#other + 1] = m end end
    end
    if #pet > 0 and #other > 0 then
      -- the group's text has one part per member, in the same order
      local parts, index = {}, {}
      local body = s.t and s.t:match("^Together here: (.*)$")
      if body then for p in (body .. "; "):gmatch("(.-); ") do parts[#parts + 1] = p end end
      for i, m in ipairs(s.mem) do index[m] = i end
      for _, list in ipairs({ pet, other }) do
        local c = {}
        for k, v in pairs(s) do c[k] = v end
        c.mem, c.q, c.o, c.on = list, list[1].q, nil, nil
        if #parts == #s.mem then
          local texts = {}
          for _, m in ipairs(list) do texts[#texts + 1] = parts[index[m]] end
          c.t = #list == 1 and texts[1] or "Together here: " .. table.concat(texts, "; ")
        end
        -- one member at one place (a vendor): go there, not to the group's spot
        local sp = #list == 1 and list[1].sp
        if sp and #sp == 1 and #sp[1].p == 2 then c.m, c.x, c.y = sp[1].m, sp[1].p[1], sp[1].p[2] end
        out[#out + 1] = c
      end
    else
      out[#out + 1] = s
    end
  end
  r.steps = out
  return r
end
local function rdb()
  local d = db()
  d.state = d.state or {}
  local r = splitPetGroups(ns.routes[d.route])
  local sig = r and signature(r)
  -- per character: each character follows the route from its own place in it
  local key = d.route .. "@" .. (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
  local st = d.state[key]
  if not st or st.sig ~= sig then
    st = { pos = 1, manual = {}, asked = {}, sig = sig }
    d.state[key] = st
  end
  return st
end
C.state = rdb   -- this character's place in the route (tests)
function C.route() return splitPetGroups(ns.routes[db().route]) end

-- the order you follow the steps in (a skipped stretch quest moves its steps later)
local function order()
  local r, st = C.route(), rdb()
  if not st.order or #st.order == 0 then
    st.order = {}
    for i = 1, #r.steps do st.order[i] = i end
  end
  return st.order
end
-- the step to do now: the GPS pick (below), else where you are in the route. The 5th value: a nearby step taken
-- out of the route's order
C.cur = nil
function C.current()
  local o, st = order(), rdb()
  if C.cur then return C.cur.step, C.cur.i, st.pos, #o, C.cur.via end
  local i = o[st.pos]
  return i and C.route().steps[i], i, st.pos, #o
end
-- the k-th step after the current one, in route order (done ones and the current one left out)
function C.peek(k)
  if k == 0 then return C.current() end
  local o, st = order(), rdb()
  local cur = C.cur and C.cur.i or o[st.pos]
  local n = 0
  for p = st.pos, #o do
    local i = o[p]
    if i ~= cur and not C.isDone(C.route().steps[i], i) then
      n = n + 1
      if n == k then return C.route().steps[i], i end
    end
  end
end

-- ------------------------------------------------------------------ is a step done?
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

-- "Tame a <beast>": a Taming Rod quest's objective doesn't report itself finished in Forever (the user's Strigid
-- Screecher, 2026-10-16), so the pet you have out counts: it carries the beast's name
local tameLogged = {}
local function tamed(on)
  if not (on and UnitExists("pet")) then return false end
  local name = UnitName("pet")
  return name and not isSecret(name) and name:lower() == on:lower() or false
end

local function objectiveDone(step)
  local ok, objs = pcall(C_QuestLog.GetQuestObjectives, step.q)
  if not ok or type(objs) ~= "table" then return false end
  if C_QuestLog.IsComplete(step.q) then return true end
  if step.on then
    local want = step.on:lower()
    for _, o in ipairs(objs) do
      local text = o.text
      if text and not isSecret(text) and text:lower():find(want, 1, true) then
        if not o.finished and text:find("^Tame ") and tamed(step.on) then
          if not tameLogged[step.q] then
            tameLogged[step.q] = true
            log("TAME_BY_PET", { q = step.q, on = step.on, have = o.numFulfilled, need = o.numRequired, type = o.type })
          end
          return true
        end
        return o.finished and true or false
      end
    end
  end
  -- no objective by that name (an item the quest hands you, or a name the game words differently): the quest itself
  return C_QuestLog.IsComplete(step.q) and true or false
end

-- a weapon you're wearing or carrying, by name
local function hasItem(name)
  for _, slot in ipairs({ 16, 17, 18 }) do
    local link = GetInventoryItemLink("player", slot)
    if link and C_Item.GetItemInfo(link) == name then return true end
  end
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.hyperlink and C_Item.GetItemInfo(info.hyperlink) == name then return true end
    end
  end
  return false
end

-- a member of a "do" step still to do: its quest in your log, not handed in, its objective not finished
function C.memLeft(m)
  return not (m.q and (completed(m.q) or not inLog(m.q))) and not objectiveDone(m)
end
function C.isDone(step, i)
  local st = rdb()
  if st.manual[i] then return true end
  local q = step.q
  -- a breadcrumb isn't offered once you have the quest it leads to (Tears of the Moon taken first: no Temple of the
  -- Moon at Sister Aquinne, the user 2026-10-16): its steps are done unless you have it
  if step.bc and q and not inLog(q) and (inLog(step.bc) or completed(step.bc)) then return true end
  if step.k == "accept" then return q and (inLog(q) or completed(q)) end
  if step.k == "turnin" then return q and completed(q) end
  if step.k == "do" and step.mem then
    for _, m in ipairs(step.mem) do
      if not completed(m.q) then
        if not inLog(m.q) or not objectiveDone(m) then return false end
      end
    end
    return true
  end
  if step.k == "do" then
    if not q then return false end
    if completed(q) then return true end
    if not inLog(q) then return false end
    return objectiveDone(step)
  end
  if (step.k == "buyweapon" or step.k == "craft") and step.wp and hasItem(step.wp) then return true end
  if step.k == "discover" and step.taxi and ns.walk and ns.walk.knownTaxis()[step.taxi] then return true end
  return false   -- train, bind, discover, buy, craft, run, grind: done by an event below or by you (Done)
end

-- a step the quest log can't tell is done (arrows, a trainer, a vendor): you're past it once the next quest step is
-- done (after a /reload with a new route, or you skipped it)
local function passed(i)
  local o, st = order(), rdb()
  for p = st.pos + 1, #o do
    local s = C.route().steps[o[p]]
    if s.q and (s.k == "accept" or s.k == "turnin" or s.k == "do") then return C.isDone(s, o[p]) end
  end
  return false
end

-- ------------------------------------------------------------------ moving along
-- the user's rule: a Hunter does the pet quests (Taming the Beast .. Training the Beast), and a Warlock the voidwalker
-- (The Binding), as soon as level 10, wherever the route is; their steps are moved up to where you are, in the route's
-- own order
local petQuests = ns.petQuests
local PET_CLASS = { HUNTER = true, WARLOCK = true }
local function isPetStep(s, qs)
  if s.q and qs[s.q] then return true end
  for _, m in ipairs(s.mem or {}) do if qs[m.q] then return true end end
  return false
end
local function petFirst()
  C.petPending = false
  if not PET_CLASS[select(2, UnitClass("player"))] or (UnitLevel("player") or 0) < 10 then return end
  local st, o, steps = rdb(), order(), C.route().steps
  local qs = petQuests(C.route())
  -- done pet steps move up with the rest (they're skipped at once), so the order stays put from one look to the next
  local pet, rest, open = {}, {}, false
  for p = st.pos, #o do
    local s = steps[o[p]]
    if isPetStep(s, qs) then
      pet[#pet + 1] = o[p]
      open = open or not C.isDone(s, o[p])
    else
      rest[#rest + 1] = o[p]
    end
  end
  if not open then return end
  C.petPending = true
  local p, moved = st.pos, false
  for _, list in ipairs({ pet, rest }) do
    for _, i in ipairs(list) do
      if o[p] ~= i then o[p] = i; moved = true end
      p = p + 1
    end
  end
  if moved then log("PET_FIRST", { n = pet[1], steps = #pet }) end
end

-- a pick-up whose quest needs another handed in first, while that hand-in is still ahead in the order: its quest's
-- steps go right after that hand-in (however the order came to be: a skipped stretch, Later, the pet quests)
local function prereqsMet(s)
  for _, x in ipairs(s.pre or {}) do if not completed(x) then return false end end
  if s.pre1 and #s.pre1 > 0 then
    for _, x in ipairs(s.pre1) do if completed(x) then return true end end
    return false
  end
  return true
end
local function unblock()
  local st, o, steps = rdb(), order(), C.route().steps
  for _ = 1, 20 do
    local moved = false
    for p = st.pos, #o do
      local s = steps[o[p]]
      if s.k == "accept" and s.q and not C.isDone(s, o[p]) and not prereqsMet(s) then
        local need = {}
        for _, x in ipairs(s.pre or {}) do need[x] = true end
        for _, x in ipairs(s.pre1 or {}) do need[x] = true end
        local last
        for p2 = p + 1, #o do
          local t = steps[o[p2]]
          if t.k == "turnin" and need[t.q] and not C.isDone(t, o[p2]) then last = p2 end
        end
        if last then
          -- this quest's steps between here and that hand-in move to just after it, in their order
          local q, moving, keep = s.q, {}, {}
          for p2 = p, last do
            if steps[o[p2]].q == q then moving[#moving + 1] = o[p2] else keep[#keep + 1] = o[p2] end
          end
          for _, i in ipairs(moving) do keep[#keep + 1] = i end
          for k, i in ipairs(keep) do o[p + k - 1] = i end
          log("UNBLOCK", { q = q, after = steps[o[p + #keep - #moving - 1]].q })
          moved = true
          break
        end
      end
    end
    if not moved then return end
  end
end

-- steps you can no longer do go: a pick-up that needs a quest you'll never hand in (skipped, and not in your log), and
-- the work and hand-in of a quest you don't have whose pick-up is gone (Planting the Heart once The Moss-twined Heart
-- was skipped: Blackmoss wasn't up, the user 2026-10-16)
local function prune()
  -- only once the game has your quest log (just after login it can read as empty: everything would look gone)
  local n = C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries()
  if not n or n == 0 then return end
  local st, o, steps = rdb(), order(), C.route().steps
  -- what was found gone is looked at again each time, not kept for good: a pick-up held back for a prerequisite that
  -- turns out not to be needed comes back (Call of Fire at Braldir, the user 2026-10-17: "it should be telling me to go
  -- there before sending me north to collect Fire Tar"). Once, for marks from before this: the work and hand-in marked
  -- for a quest whose pick-up is still to do (not done, not skipped) were gone with it, not skipped by you
  local prev = st.gone or {}
  if not st.goneKept2 then
    st.goneKept2 = true
    local open = {}
    for i, s in ipairs(steps) do if s.k == "accept" and s.q and not C.isDone(s, i) then open[s.q] = true end end
    for i in pairs(st.manual) do
      local s = steps[i]
      if s and s.q and s.k ~= "accept" and open[s.q] and not completed(s.q) and not inLog(s.q) then prev[i] = true end
    end
  end
  for i in pairs(prev) do st.manual[i] = nil end
  st.gone = {}
  -- looked at from the first quest step behind you that isn't done: one that was gone and isn't now is behind where
  -- you'd got to (the user, 2026-10-17: Call of Fire back, but the route still said Miners' Gear)
  local from = st.pos
  for p = 1, st.pos - 1 do
    local s = steps[o[p]]
    if s.q and (s.k == "accept" or s.k == "turnin" or s.k == "do") and not C.isDone(s, o[p]) then from = p break end
  end
  for _ = 1, 10 do
    local changed = false
    local willTurnIn, willAccept = {}, {}
    for p = from, #o do
      local s = steps[o[p]]
      if s.q and not C.isDone(s, o[p]) then
        if s.k == "turnin" then willTurnIn[s.q] = true elseif s.k == "accept" then willAccept[s.q] = true end
      end
    end
    for p = from, #o do
      local i = o[p]
      local s = steps[i]
      if s.q and not C.isDone(s, i) then
        local gone = false
        if s.k == "accept" and not prereqsMet(s) then
          gone = true
          for _, list in ipairs({ s.pre or {}, s.pre1 or {} }) do
            for _, x in ipairs(list) do if willTurnIn[x] or inLog(x) then gone = false end end
          end
        elseif s.k ~= "accept" and not inLog(s.q) and not completed(s.q) and not willAccept[s.q] then
          gone = true
        end
        if gone then
          st.manual[i] = true
          st.gone[i] = true
          if not prev[i] then log("STEP_GONE", { n = i, k = s.k, q = s.q }) end
          changed = true
        end
      end
    end
    if not changed then break end
  end
  -- back to the first of them still to do
  for p = from, st.pos - 1 do
    local s = steps[o[p]]
    if s.q and not C.isDone(s, o[p]) then
      st.pos = p
      log("STEP_BACK", { n = o[p], k = s.k, q = s.q, reason = "not gone" })
      break
    end
  end
end

local stepStarted = GetTime()
function C.advance(reason)
  petFirst()
  unblock()
  if reason ~= "init" then prune() end
  local st, o = rdb(), order()
  local moved = false
  while st.pos <= #o do
    local step, i = C.route().steps[o[st.pos]], o[st.pos]
    -- "passed" only on a fresh start: during play the GPS may have you do later quest steps first, which mustn't
    -- skip a trainer or vendor still ahead of you
    if not C.isDone(step, i) and (step.q or not (reason == "init" or reason == "route") or not passed(i)) then break end
    log("STEP_DONE", { n = i, k = step.k, q = step.q, reason = reason, secs = math.floor(GetTime() - stepStarted) })
    st.pos = st.pos + 1
    stepStarted = GetTime()
    moved = true
  end
  C.repick(moved or reason == "init" or reason == "route", reason)
end

function C.markDone(reason)
  local step, i = C.current()
  if not step then return end
  rdb().manual[i] = true
  C.advance(reason or "manual")
end
function C.back()
  local st = rdb()
  if st.pos <= 1 then return end
  st.pos = st.pos - 1
  local o = order()
  st.manual[o[st.pos]] = nil
  log("STEP_BACK", { n = o[st.pos] })
  stepStarted = GetTime()
  C.holdRoute()
end
function C.jump(n)
  local o, st = order(), rdb()
  for p, i in ipairs(o) do if i == n then st.pos = p break end end
  log("STEP_GOTO", { n = n })
  stepStarted = GetTime()
  C.holdRoute()
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
function C.setWaypoint(step)
  step = C.ammoStep(step)
  -- not off to the vendor before you can pay: you kill things where you are until then
  C.target = (step and step.m and step.x and step.y and not C.weaponShort(step)) and step or nil
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
-- a step's text as shown: a "Hearth, then:" step while the hearthstone is still cooling down says to walk instead
-- (the user, 2026-10-16: "its saying hearth but i have 38 mins left")
-- a "Hearth, then:" step you're already near walks instead: the planner hearthed from where it thought you'd be (the
-- user, 2026-10-16: "its now telling me to hearth to hand in a quest that is ~120 yards away")
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
-- would still be cooling down). The user, 2026-10-17, 1500 yd from Kharanos with the hearthstone bound there: "i feel
-- like now would be the time for me to use it but it's saying to run the 1500 yards"
local HEARTH_WORTH, HEARTH_LANDS, HEARTH_KEEP = 800, 300, 25
function C.hearthNow(step)
  if not (step and step.m and step.x and step.y) or step.hs or step.ds then return false end
  if C.hearthLeft() ~= 0 then return false end
  local b = C.bindSpot()
  if not b then return false end
  local cb, bx, by = worldPos(b.m, b.x / 100, b.y / 100)
  local cs, sx, sy = worldPos(step.m, step.x / 100, step.y / 100)
  if not cb or cb ~= cs or math.sqrt((bx - sx) ^ 2 + (by - sy) ^ 2) > HEARTH_LANDS then return false end
  local d = C.bearing(step)
  if d and d < HEARTH_WORTH then return false end
  -- and what comes after it is nearer the inn than where you are now: not a hearth there and a walk all the way back
  -- (the user, 2026-10-17: "i just hearthed and then it tells me to run back 1700 yards")
  for k = 1, 3 do
    local s = C.peek(k)
    if s and s ~= step and s.m and s.x and s.y then
      local c2, x2, y2 = worldPos(s.m, s.x / 100, s.y / 100)
      local after = C.bearing(s)
      if c2 == cb and after and math.sqrt((bx - x2) ^ 2 + (by - y2) ^ 2) > after then return false end
      break
    end
  end
  for k = 1, HEARTH_KEEP do
    local s = C.peek(k)
    if not s then break end
    if s.hs then return false end
  end
  return true
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

-- ------------------------------------------------------------------ GPS: what to do now
-- The user: "the addon should be adjusting what to do based on where you are, not so stringent. it should act like a
-- GPS". The route's next step stays the plan, but anything you can do right now that is close by or nearly on the way
-- there comes first: a pick-up whose quest you can take, a hand-in of a finished quest (also one the route doesn't
-- plan, e.g. one you took on your own), or the objectives of a quest you have that you're standing among.
local NEAR, NEAR_DO, DETOUR, STICK = 250, 90, 120, 40   -- yards
local WORK_KEEP = 150   -- yards: this near a kill / collect step's spawns, you stay on it
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
local function spot(t)   -- a step's or member's own place, in world coordinates (worked out once)
  if t.w == nil then
    local c, x, y
    if t.m and t.x and t.y then c, x, y = worldPos(t.m, t.x / 100, t.y / 100) end
    t.w = c and { c = c, x = x, y = y } or false
  end
  return t.w or nil
end
-- caves: the map is flat, so a spot above a cave looks the same as one in it (box: x1, x2, y1, y2 on the zone's map)
local CAVES = {
  ["Grizzled Den"] = { m = 1426, door = { 42, 54 }, box = { 39.5, 44.5, 44.5, 56.5 } },
  -- the Fire Tar for Call of Fire, the user 2026-10-17: "the entrance to the cave for the Fire Tar is 35.5,18.8"
  ["Silver Stream Mine"] = { m = 1432, door = { 35.5, 18.8 }, box = { 33.5, 38.5, 19.3, 29 } },
}
local function caveAt(m, x, y)
  for name, cv in pairs(CAVES) do
    local b = cv.box
    if cv.m == m and x >= b[1] and x <= b[2] and y >= b[3] and y <= b[4] then return name, cv end
  end
end
local function spawnSpots(mem)   -- a member's spawn points, in world coordinates (worked out once)
  if not mem.ws then
    mem.ws = {}
    for _, g in ipairs(mem.sp or {}) do
      for k = 1, #g.p - 1, 2 do
        local c, x, y = worldPos(g.m, g.p[k] / 100, g.p[k + 1] / 100)
        -- over: an outdoor spot (no ly) over a cave, which the arrow would lead you into the cave for (Shimmerweed on
        -- the hill over the Grizzled Den, the user 2026-10-17: "it is still sending me through the cave")
        if c then
          mem.ws[#mem.ws + 1] = { c = c, x = x, y = y, m = g.m, mx = g.p[k], my = g.p[k + 1], ly = mem.ly,
            over = not mem.ly and caveAt(g.m, g.p[k], g.p[k + 1]) and true or nil }
        end
      end
    end
  end
  return mem.ws
end
-- the spots not over a cave, or all of them when that's all there is
local function landSpots(list)   -- worked out once per list (asked many times a second: no new table each time)
  if list.land == nil then
    local out = {}
    for _, w in ipairs(list) do if not w.over then out[#out + 1] = w end end
    list.land = #out > 0 and out or false
  end
  return list.land or list
end
local function dist(a, b) local dx, dy = a.x - b.x, a.y - b.y return math.sqrt(dx * dx + dy * dy) end
C.worldPos, C.playerWorld = worldPos, playerWorld   -- Rare.lua: the spawn points near you

-- a kill / collect step hops between the spawn points of what you still need: the nearest one you haven't been to,
-- then the next nearest from there, and round again once you've seen them all (the ones seen last stay off the list,
-- so it doesn't send you straight back). The user, 2026-10-17: sent to "a spot with a single boar spawn" for bear furs
-- and boar ribs, "once you reach one, it takes you to the next closest one and does it in a loop"
-- yards: a spawn point this close counts as reached, the arrow moves on (the user, 2026-10-17: "within 50 yards ... so
-- you don't have to be exactly on it"); points this far from the step's spot
-- and the route's way on: a spot counts its distance from you plus ROAM_ON x its distance to the route's next step, so
-- you work towards where you go next instead of away from it (the user, 2026-10-17: "feels like im being lead far away")
local ROAM_SEEN, ROAM_AREA, ROAM_ON = 50, 350, 0.7
-- spots you've been to are kept by place (m:x:y) for ROAM_KEEP seconds, whatever step you were on: two steps for the
-- same mobs share them, and switching steps doesn't send you back (the user, 2026-10-17: "jumping back and forth")
local ROAM_KEEP = 900
local roam = { step = nil, seen = {}, order = {}, goal = nil, pt = nil, nextW = nil }
local function pkey(w) return w.m .. ":" .. w.mx .. ":" .. w.my end
local function isSeen(w) local t = roam.seen[pkey(w)] return t and GetTime() - t < ROAM_KEEP end
local function markSeen(w) local k = pkey(w) if not isSeen(w) then roam.order[#roam.order + 1] = k end roam.seen[k] = GetTime() end
-- where the route goes after this step: the first of the next few steps with a place
local function roamNext()
  for k = 1, 4 do
    local s = C.peek(k)
    if not s then return nil end
    -- one you hearth to: no way towards it (the Stonesplinter Scouts, the user 2026-10-17)
    if s.hs and (C.hearthLeft() or 0) == 0 and not C.hearthNear(s) or C.hearthNow(s) then return nil end
    if s.m and s.x and s.y then
      local c, x, y = worldPos(s.m, s.x / 100, s.y / 100)
      if c then return { c = c, x = x, y = y } end
    end
  end
end
-- a step done on the way to the route's step (via): only the spots on the way there from where you are, so it leads
-- you towards it instead of all over (the user, 2026-10-17: "it should be sending me in the direction of the
-- shimmerweed via points that have the thick bear fur so its not going everywhere"; "this kind of logic should be used
-- always")
local ROAM_DETOUR = 180   -- yards: a spot's detour (you -> spot -> route's step, against straight there)
local function onTheWay(w, pw, aim)
  return w.c == pw.c and aim.c == pw.c and dist(pw, w) + dist(w, aim) - dist(pw, aim) <= ROAM_DETOUR
end
local function roamPoints(step, pw)
  local all, near = {}, {}
  local home = step.x and spot(step)
  for _, mem in ipairs(step.mem) do
    -- only what is left: not a quest handed in or not in your log (the user, 2026-10-17: sent to kill Rockjaw
    -- Skullthumpers for Those Blasted Troggs!, handed in an hour before, as the Bonesnappers were still to do)
    if C.memLeft(mem) then
      for _, w in ipairs(landSpots(spawnSpots(mem))) do
        all[#all + 1] = w
        if home and w.c == home.c and dist(w, home) <= ROAM_AREA then near[#near + 1] = w end
      end
    end
  end
  if roam.via and roam.nextW and pw then
    local way = {}
    for _, w in ipairs(all) do if onTheWay(w, pw, roam.nextW) then way[#way + 1] = w end end
    return way
  end
  return #near > 0 and near or all
end
local function roamPick(pw)
  local pts = roamPoints(roam.step, pw)
  if #pts == 0 then return nil end
  local on = roam.via and 1 or ROAM_ON
  local function nearestFree()
    local best, bd
    for _, w in ipairs(pts) do
      if not isSeen(w) and w.c == pw.c then
        local d = dist(w, pw) + ((roam.nextW and roam.nextW.c == w.c) and on * dist(w, roam.nextW) or 0)
        if not bd or d < bd then best, bd = w, d end
      end
    end
    return best
  end
  local best = nearestFree()
  if not best and roam.via then return nil end   -- on the way: none left, on to the route's step
  if not best then
    -- all seen: round again, keeping the most recent half of this step's spots off the list
    local mine = {}
    for _, w in ipairs(pts) do mine[pkey(w)] = true end
    local recent = {}
    for i = #roam.order, 1, -1 do local k = roam.order[i] if mine[k] and roam.seen[k] then recent[#recent + 1] = k end end
    local keepN = math.min(math.ceil(#recent / 2), #recent - 1)
    for i = keepN + 1, #recent do roam.seen[recent[i]] = nil end
    for i = 1, keepN do mine[recent[i]] = nil end
    local order = {}
    for _, k in ipairs(roam.order) do if roam.seen[k] then order[#order + 1] = k end end
    roam.order = order
    best = nearestFree()
    if not best then for k in pairs(mine) do roam.seen[k] = nil end best = nearestFree() end
  end
  return best
end
local function roamable(step)
  if not step or step.k ~= "do" or not step.mem then return false end
  for _, mem in ipairs(step.mem) do if mem.sp and #mem.sp > 0 then return true end end
  return false
end
-- once a second: mark the spawn points you're at as seen, and move the arrow on when its point is
function C.roamTick()
  if not roam.step or C.goalTarget ~= roam.goal or C.onTaxi() then return end
  local pw = playerWorld()
  if not pw then return end
  if roam.via then roam.nextW = C.routeAim or roam.nextW end
  for _, w in ipairs(roamPoints(roam.step, pw)) do
    if w.c == pw.c and dist(w, pw) <= ROAM_SEEN then markSeen(w) end
  end
  local stillWanted = false
  if roam.pt then for _, w in ipairs(roamPoints(roam.step, pw)) do if pkey(w) == pkey(roam.pt) then stillWanted = true end end end
  if roam.pt and not isSeen(roam.pt) and stillWanted then return end
  local nxt = roamPick(pw)
  if nxt and (not roam.pt or pkey(nxt) ~= pkey(roam.pt)) then
    roam.pt = nxt
    roam.goal.m, roam.goal.x, roam.goal.y, roam.goal.ly = nxt.m, nxt.mx, nxt.my, nxt.ly or false
    C.caveTick()
    if ns.arrow and ns.arrow.update then ns.arrow.update() end
  end
end
local plainWaypoint = C.setWaypoint
function C.setWaypoint(step)
  plainWaypoint(step)
  C.goalTarget = C.target
  if not (C.target and C.target == step and roamable(step)) then roam.step, roam.goal = nil, nil C.caveTick() return end
  if roam.step ~= step then
    local was = roam.pt
    roam.step, roam.pt = step, nil
    -- a step on the way to the route's (via): towards that step's place; else towards the next steps
    roam.via = C.cur and C.cur.step == step and C.cur.via and C.routeAim and true or nil
    roam.nextW = roam.via and C.routeAim or roamNext()
    -- the step's own fields (text, quest), with the spawn point to head for
    roam.goal = setmetatable({ m = step.m, x = step.x, y = step.y }, { __index = step })
    if was then
      for _, w in ipairs(roamPoints(step)) do
        if pkey(w) == pkey(was) then roam.pt = w; roam.goal.m, roam.goal.x, roam.goal.y, roam.goal.ly = w.m, w.mx, w.my, w.ly or false end
      end
    end
  end
  C.target = roam.goal
  C.goalTarget = roam.goal
  C.roamTick()
  C.caveTick()
end

-- caves: the map is flat, so a spot above a cave looks the same as one in it. Inside a cave and going somewhere outside
-- it, or outside and going to something in it (a member's ly), the arrow goes to the entrance first (IsIndoors says
-- which side you're on). The user, 2026-10-17: sent to the Shimmerweed on the hill from inside the Grizzled Den
local DOOR_NEAR = 15   -- yards: at the entrance, go on in
local function targetCave(t)
  local ly = t.ly
  if ly == nil and t.mem then
    for _, mem in ipairs(t.mem) do if mem.ly then ly = mem.ly end end
  end
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
        if not d or d > DOOR_NEAR then
          want = setmetatable({ m = cv.m, x = cv.door[1], y = cv.door[2], ly = false,
            t = ("Into the %s: %s"):format(tc, C.text(goal)) }, { __index = goal })
        end
      end
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
C.roamState = roam   -- the smoke test

local function readyToHandIn(q)
  if not inLog(q) then return false end
  if C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(q) then return true end
  if C_QuestLog.IsComplete(q) then return true end
  -- every objective finished, a "Tame a ..." counting when that beast is your pet (Forever flags neither the objective
  -- nor the quest as done after a Taming Rod)
  local ok, objs = pcall(C_QuestLog.GetQuestObjectives, q)
  if not ok or type(objs) ~= "table" or #objs == 0 then return false end
  for _, o in ipairs(objs) do
    local text = o.text
    if not o.finished then
      if not (text and not isSecret(text) and text:find("^Tame ") and tamed(text:match("^Tame an? (.+)$"))) then return false end
    end
  end
  return true
end
-- can you do this step right now?
local function doable(s)
  local q = s.q
  if s.k == "accept" then
    if not q or inLog(q) or completed(q) then return false end
    if s.ml and (UnitLevel("player") or 0) < s.ml then return false end
    for _, p in ipairs(s.pre or {}) do if not completed(p) then return false end end
    if s.pre1 then
      local any = false
      for _, p in ipairs(s.pre1) do if completed(p) then any = true end end
      if not any then return false end
    end
    return true
  end
  if s.k == "turnin" then return q and readyToHandIn(q) or false end
  if s.k == "do" then
    for _, m in ipairs(s.mem or { { q = q, on = s.on } }) do
      if m.q and inLog(m.q) and not completed(m.q) and not objectiveDone(m) then return true end
    end
    return false
  end
  return true   -- a trainer, vendor, hearth ...: in the route's order
end
-- where to go for a step from P: a "do" step's nearest spawn point of what's left to do, else its own place
-- aim: on the way there (the route's step), the spot of those you haven't just been to that is most on the way (the
-- detour counting double); nil when none is
local function placeFor(s, P, aim)
  if s.k == "do" and s.mem then
    local best, bd
    local direct = aim and aim.c == P.c and dist(P, aim)
    for _, m in ipairs(s.mem) do
      if m.q and inLog(m.q) and not objectiveDone(m) then
        for _, w in ipairs(landSpots(spawnSpots(m))) do
          if w.c == P.c and not (direct and isSeen(w)) then
            local d = dist(P, w)
            if direct then d = d + 2 * (d + dist(w, aim) - direct) end
            if not bd or d < bd then best, bd = w, d end
          end
        end
      end
    end
    if best then return best end
    if direct then return nil end
  end
  return spot(s)
end

-- escorts: once you start one you can't do anything else, so an escort's pick-up waits while its area still has
-- quests to do there (the user, 2026-10-16: "not starting them in an area that still has quests to do unless all
-- quests ahead of it can be done on the escort"; Sleeping Druid and Druid of the Claw before Lynessa's escort).
-- The route file lists each escort's area quests (tools/export_route_lua.mjs). What holds it: a quest to hand in there,
-- objectives of yours there that need more than killing on the way out (chests, or a quest handed in there), and a
-- quest to pick up there that the route plans or that follows one of the area's quests. Returns the steps to do first
-- (made up from the area list), or nil when the escort can go.
local waitSteps = {}
local function waitStep(id, t)
  local w = waitSteps[id]
  t.held = true
  if not w then w = t; waitSteps[id] = w else for k, v in pairs(t) do w[k] = v end; w.w = nil end
  return w
end
local function available(a)
  if a.bc and (inLog(a.bc) or completed(a.bc)) then return false end
  if a.ml and (UnitLevel("player") or 0) < a.ml then return false end
  for _, p in ipairs(a.pre or {}) do if not completed(p) then return false end end
  if a.pre1 then
    for _, p in ipairs(a.pre1) do if completed(p) then return true end end
    return false
  end
  return true
end
function C.escortWait(s)
  local area = s and s.k == "accept" and s.q and C.route().escorts and C.route().escorts[s.q]
  if not area or inLog(s.q) or completed(s.q) then return nil end
  local planned, inArea = {}, {}
  for _, r in ipairs(C.route().steps) do if r.q then planned[r.q] = true end end
  for _, a in ipairs(area) do inArea[a.q] = true end
  local out, manual = {}, rdb().manual
  local function add(id, t) if not manual[id] then out[#out + 1] = waitStep(id, t) end end   -- Skip / Done lets it go
  for _, a in ipairs(area) do
    local q = a.q
    if not completed(q) then
      if inLog(q) then
        if readyToHandIn(q) then
          if a.e then add("wt" .. q, { k = "turnin", q = q, m = a.e.m, x = a.e.x, y = a.e.y, t = ("Turn in %s to %s"):format(a.t, a.e.n) }) end
        else
          local left, chest = {}, false
          for _, m in ipairs(a.mem or {}) do
            if not objectiveDone(m) then left[#left + 1] = m; chest = chest or m.ob == 1 end
          end
          if #left > 0 and (a.e or chest) then
            local g = left[1].sp and left[1].sp[1]
            add("wd" .. q, { k = "do", q = q, mem = left, m = g and g.m, x = g and g.p[1], y = g and g.p[2], t = ("Do %s"):format(a.t) })
          end
        end
      elseif a.s and available(a) then
        local follows = planned[q]
        for _, p in ipairs(a.pre1 or {}) do if inArea[p] then follows = true end end
        for _, p in ipairs(a.pre or {}) do if inArea[p] then follows = true end end
        if follows then add("wa" .. q, { k = "accept", q = q, m = a.s.m, x = a.s.x, y = a.s.y, t = ("Accept %s from %s"):format(a.t, a.s.n) }) end
      end
    end
  end
  return #out > 0 and out or nil
end
local function waitId(w) for id, v in pairs(waitSteps) do if v == w then return id end end end

local offSteps = {}   -- made-up "do" steps for quests the route doesn't plan, by quest

local holdUntil = 0
function C.holdRoute()   -- Back / goto: show that route step for a while, whatever is near
  holdUntil = GetTime() + 120
  C.cur = nil
  C.repick(true, "hold")
end

-- the step to do now: { step, i, via } (via: a nearby step out of the route's order)
-- skip for now (the user, 2026-10-16: "skip and 'skip for now' in case you do want to do it later"; "should not bring it
-- up again unless you get 500+ yards away from it then come back within 200 yards again"): the step is put aside; once
-- you've been LATER_AWAY yards from it, it comes back when you're within LATER_BACK of it - never as the step the arrow
-- sends you back for
local LATER_AWAY, LATER_BACK = 500, 200
function C.later()
  local step, i = C.current()
  if not step then return end
  local st = rdb()
  st.later = st.later or {}
  local P = playerWorld()
  local w = P and placeFor(step, P) or P
  st.later[i] = { c = w and w.c, x = w and w.x, y = w and w.y }
  log("STEP_LATER", { n = i, k = step.k, q = step.q })
  C.advance("later")
end

-- on a flight path: where you are says nothing about what's on your way (the user, 2026-10-17: "while you're
-- mid-flight it should not be updating the quest route as though you're walking")
local function onTaxi() return UnitOnTaxi and UnitOnTaxi("player") and true or false end
C.onTaxi = onTaxi
-- yards: a flight master this near you, or this little out of the way to the route's step
local FP_NEAR, FP_DETOUR = 600, 400
C.fpSteps = {}
-- only flight masters with a flight from them (the data has some with none, like Teldrassil's "Fishing Village": not
-- in the game), and not a class's own (Nighthaven: druids)
local FP_CLASS = { [62] = "DRUID" }
local fpReal = {}
local function realFlights(c, d)
  if not fpReal[c] then
    fpReal[c] = {}
    for a in (d.flights or ""):gmatch("(%d+)>%d+>%d+") do fpReal[c][tonumber(a)] = true end
  end
  return fpReal[c]
end
function C.flightToLearn(P, R)
  if not (ns.walk and ns.walk.knownTaxis and ns.walkData) then return nil end
  local d = ns.walkData[P.c]
  if not (d and d.taxis) then return nil end
  local K, st = ns.walk.knownTaxis(), rdb()
  local real = realFlights(P.c, d)
  local _, class = UnitClass("player")
  local rw = R and placeFor(R, P)
  rw = rw and rw.c == P.c and rw or nil
  local best, bd
  for _, t in ipairs(d.taxis) do
    local id = "f" .. t.id
    if not K[t.id] and not st.manual[id] and real[t.id] and (not FP_CLASS[t.id] or FP_CLASS[t.id] == class) then
      C.fpSteps[t.id] = C.fpSteps[t.id] or { k = "discover", taxi = t.id, m = t.m, x = t.x, y = t.y,
                                             t = ("Learn the flight path at %s (talk to the flight master)"):format(t.n) }
      local s = C.fpSteps[t.id]
      local w = spot(s)
      if w and w.c == P.c then
        local dd = dist(P, w)
        local onWay = rw and dd < dist(P, rw) and dd + dist(w, rw) - dist(P, rw) <= FP_DETOUR
        if (dd <= FP_NEAR or onWay) and (not bd or dd < bd) then best, bd = { step = s, i = id, via = true }, dd end
      end
    end
  end
  return best
end
local function pick()
  local st, o, steps = rdb(), order(), C.route().steps
  -- an escort under way: that's all you can do (follow them; no detours)
  for i, s in ipairs(steps) do
    if s.esc and s.q and inLog(s.q) and not readyToHandIn(s.q) and not C.isDone(s, i) then return { step = s, i = i } end
  end
  -- a timed quest in your log (tm from the route, or a timer the game shows): its own steps, straight there, nothing
  -- on the way (Scalding Mornbrew, the user 2026-10-17: sent to kill 12 boars first, handed in with 25 s left)
  local timers = ns.questTimers or {}
  for i, s in ipairs(steps) do
    if s.q and (s.tm or timers[s.q]) and s.k ~= "accept" and inLog(s.q) and not C.isDone(s, i) and doable(s)
        and (s.k == "do" or readyToHandIn(s.q)) then
      return { step = s, i = i, via = true }
    end
  end
  -- the route's next step: the first from where you are in the route that you can do now (an accept whose quest you
  -- can't take yet waits)
  -- a step left behind: you've done LEFT_DONE or more of the steps after it and it's over LEFT_FAR yards away. It
  -- isn't the route's step (it'd send you back across the zone); it's done when you pass near it again (the user,
  -- 2026-10-17: sent 3200 yd back to Kharanos for Camping 101's hand-in, route step 2, with steps 3-30 done, "that is
  -- fucking insane"). The last steps of the route, nothing after them: it's their turn
  local LEFT_DONE, LEFT_FAR = 3, 500
  local Pnow = GetTime() >= holdUntil and not onTaxi() and playerWorld()
  -- each step's done-ness asked once per pick (not 40 times over: lag, the user 2026-10-17)
  local doneAt = {}
  local function isDoneAt(q)
    local v = doneAt[q]
    if v == nil then v = C.isDone(steps[o[q]], o[q]) and true or false doneAt[q] = v end
    return v
  end
  local function leftBehind(p, s)
    if not Pnow then return false end
    local done = 0
    for q = p + 1, math.min(#o, p + 40) do
      if isDoneAt(q) then done = done + 1 if done >= LEFT_DONE then break end end
    end
    if done < LEFT_DONE then return false end
    local w = placeFor(s, Pnow)
    return w and w.c == Pnow.c and dist(Pnow, w) > LEFT_FAR or false
  end
  local rp, held, firstUp
  for p = st.pos, math.min(#o, st.pos + 40) do
    local s, i = steps[o[p]], o[p]
    local up = not isDoneAt(p) and doable(s) and not (st.later and st.later[i])
    if up then firstUp = firstUp or p end
    if up and not leftBehind(p, s) then
      -- an escort whose area has quests left: those first
      held = C.escortWait(s)
      rp = p
      break
    end
  end
  rp = rp or firstUp or st.pos
  local R, Ri = steps[o[rp]], o[rp]
  C.routeStep = Ri   -- the route's own step under any GPS pick (tests, /wfn why)
  if not R then return nil end
  local P = GetTime() >= holdUntil and not onTaxi() and playerWorld()
  -- steps put aside for later: armed once you've been LATER_AWAY from them
  for _, lt in pairs(st.later or {}) do
    if P and not lt.away and (not lt.x or lt.c ~= P.c or dist(P, lt) > LATER_AWAY) then lt.away = true end
  end
  if held then
    local best, bd
    for _, w in ipairs(held) do
      local ww = P and placeFor(w, P)
      local d = ww and ww.c == P.c and dist(P, ww) or 0
      if not bd or d < bd then best, bd = w, d end
    end
    return { step = best, i = waitId(best), via = "escort" }
  end
  if not P then return { step = R, i = Ri } end
  -- a flight master you haven't learned, near you or on your way: always there first (the user, 2026-10-17: "when going
  -- near a flight path you dont have it should always direct you there", sent on to Westfall past Stormwind's)
  local fp = C.flightToLearn(P, R)
  if fp then return fp end
  -- working a kill / collect step (among its spawns): stay on it until it's done, instead of flipping to another one
  -- nearby (the user, 2026-10-17: Stocking Jetsteam's two steps by turns, "jumping back and forth between two spots")
  local cs = C.cur and C.cur.step
  if cs and cs.k == "do" and type(C.cur.i) == "number" and not C.isDone(cs, C.cur.i) and doable(cs) then
    local w = placeFor(cs, P)
    local aim = C.cur.via and C.routeAim
    if aim and C.cur.step ~= R then w = placeFor(cs, P, aim) w = w and onTheWay(w, P, aim) and w end
    if w and w.c == P.c and dist(P, w) <= WORK_KEEP then return C.cur end
  end
  local rw = placeFor(R, P)
  rw = rw and rw.c == P.c and rw or nil
  C.routeAim = rw
  local rd = rw and dist(P, rw)
  local prev = C.cur and C.cur.via and C.cur.i
  -- walking to the route's step (not hearthing there): what's on the way counts however far it is (the user, walking
  -- from Darnassus to Dolanaar past the Barrow Den, 2026-10-16: "why is it telling me to go back to dolanaar and not to
  -- do the barrow den quests on the way?")
  local walking = rd and not (R.hs and (C.hearthLeft() or 0) == 0 and not C.hearthNear(R)) and not C.hearthNow(R)
  -- hearthing there: no way to be on (the user, 2026-10-17, Stonesplinter Scouts in Loch Modan with the route's step a
  -- hearth back to Dun Morogh: sent north to the scouts "on the way" west, not to those all round you to the south)
  if not walking then C.routeAim = nil end
  local best, bestScore
  -- allow: more detour that's still worth it (a quest the route doesn't plan: less than coming back for it later)
  local function consider(s, i, allow)
    local lt = st.later and st.later[i]
    if lt and not lt.away then return end
    -- a kill / collect step: its spot most on the way (the user, 2026-10-17: "via points that have the thick bear fur")
    local w = placeFor(s, P, walking and s.k == "do" and rw or nil)
    if not w or w.c ~= P.c then return end
    local d = dist(P, w)
    if lt and d > LATER_BACK then return end
    local sticky = (i == prev) and 1.5 or 1
    -- the detour: there and on to the route's step, against going straight there
    local detour = rw and (d + dist(w, rw) - rd) or d
    local limit = math.max(DETOUR, allow or 0)
    local onTheWay = walking and d < rd and detour <= limit
    if allow and not onTheWay and d > NEAR_DO then return end
    if d > ((s.k == "do") and NEAR_DO or NEAR) * sticky and not onTheWay then return end
    if detour > limit * sticky and d > 40 then return end
    -- in the order you pass them: the nearest first, a detour counting double (the destination itself has none)
    local score = d + 2 * detour + ((s.k == "do") and 30 or 0) - ((i == prev) and STICK or 0)
    if not bestScore or score < bestScore then best, bestScore = { step = s, i = i, d = d }, score end
  end
  local handedIn = {}
  for p = st.pos, #o do
    local s, i = steps[o[p]], o[p]
    if s.k == "turnin" and s.q then handedIn[s.q] = true end
    -- while the pet quests are open (level 10 Hunter), only hand-ins on the way: nothing else comes before the pet
    local kinds = C.petPending and s.k == "turnin" or not C.petPending and (s.k == "accept" or s.k == "turnin" or s.k == "do")
    -- a timed quest is taken only in the route's order: its clock starts at the pick-up
    if s.tm and s.k == "accept" then kinds = false end
    if p ~= rp and s.q and kinds and not C.isDone(s, i) and doable(s) then
      local held = C.escortWait(s)
      if held then
        -- an escort nearby that has to wait: what holds it, instead
        for _, w in ipairs(held) do consider(w, waitId(w)) end
      else
        consider(s, i)
      end
    end
  end
  -- finished quests in your log the rest of the route doesn't hand in
  local ends = C.route().ends or {}
  local ok, n = pcall(C_QuestLog.GetNumQuestLogEntries)
  for li = 1, (ok and n or 0) do
    local info = C_QuestLog.GetInfo(li)
    local q = info and not info.isHeader and info.questID
    local e = q and ends[q]
    if e and not handedIn[q] and readyToHandIn(q) and not rdb().manual["e" .. q] then
      C.extra = C.extra or {}
      C.extra[q] = C.extra[q] or { k = "turnin", q = q, m = e.m, x = e.x, y = e.y, t = ("Turn in %s to %s"):format(e.t, e.n) }
      consider(C.extra[q], "e" .. q)
    end
  end
  -- pick-ups the route doesn't plan, handed in near one of its hand-ins and with any work near where it goes (The Glowing
  -- Fruit on the way to Ursal, the user 2026-10-16: "if you're running near something it may as well be added"); offered
  -- like any pick-up on your way, their work afterwards as an off-route quest in your log (objs)
  for q, pk in pairs(C.route().picks or {}) do
    if not rdb().manual["p" .. q] then
      local taken = false
      for _, x in ipairs(pk.ex or {}) do if inLog(x) or completed(x) then taken = true end end
      if pk.bc and (inLog(pk.bc) or completed(pk.bc)) then taken = true end
      C.picks = C.picks or {}
      C.picks[q] = C.picks[q] or { k = "accept", q = q, m = pk.m, x = pk.x, y = pk.y, ml = pk.ml, pre = pk.pa, pre1 = pk.po,
                                   t = ("Accept %s from %s (%s)"):format(pk.t, pk.n, pk.w and "extra XP: its work and hand-in are near your route" or "free: handed in near your route") }
      if not taken and doable(C.picks[q]) then consider(C.picks[q], "p" .. q) end
    end
  end
  -- the objectives of quests in your log that the route doesn't plan (taken on your own): when you pass them, if going
  -- now costs less than coming back from where it's handed in (Twisted Hatred's Lord Melenas in Fel Rock, the user
  -- 2026-10-16: "it's not telling me to go in and do it")
  local objs = C.route().objs or {}
  for li = 1, (ok and n or 0) do
    local info = C_QuestLog.GetInfo(li)
    local q = info and not info.isHeader and info.questID
    local o = q and objs[q]
    if o and not handedIn[q] and not readyToHandIn(q) and not rdb().manual["o" .. q] then
      local left = {}
      for _, m in ipairs(o.mem) do if not objectiveDone(m) then left[#left + 1] = m end end
      if #left > 0 then
        offSteps[q] = offSteps[q] or { k = "do", q = q, t = ("Do %s"):format(o.t) }
        local st = offSteps[q]
        st.mem = left
        local e, w = ends[q], placeFor(st, P)
        local back = 0
        if e and w then
          local ew = spot(e)
          if ew and ew.c == w.c then back = dist(w, ew) * 2 * 0.75 end
        end
        local g = left[1].sp and left[1].sp[1]
        st.m, st.x, st.y, st.w = g and g.m, g and g.p[1], g and g.p[2], nil
        consider(st, "o" .. q, back)
      end
    end
  end
  -- the route's own step when it's as close
  if best and not (rd and rd <= best.d) then
    local s = best.step
    local w = s.k == "do" and placeFor(s, P)
    if w and w.mx then   -- the arrow to the nearest spawn of what's left, not the planner's camp
      local c = {}
      for k, v in pairs(s) do c[k] = v end
      c.m, c.x, c.y, c.w = w.m, w.mx, w.my, nil
      s = c
    end
    return { step = s, i = best.i, via = s.held and "escort" or true }
  end
  return { step = R, i = Ri }
end

-- look again: a new pick is logged and shown (force: show it anyway)
function C.repick(force, reason)
  local old = C.cur
  if old and old.via and C.isDone(old.step, old.i) then
    log("STEP_DONE", { n = old.i, k = old.step.k, q = old.step.q, reason = reason, via = true, secs = math.floor(GetTime() - stepStarted) })
    stepStarted = GetTime()
  end
  -- flying: the arrow stays on what it showed at take-off until that's done
  if onTaxi() and old and old.step and not C.isDone(old.step, old.i) and not force then return end
  local new = pick()
  C.cur = new
  if force or (old and old.i) ~= (new and new.i) then C.onStepChanged() end
end

-- ------------------------------------------------------------------ a quest you took that the route doesn't plan
-- auto-accept takes plenty of quests the route doesn't need: each one asks once whether to do it, with what it adds
-- (the user, 2026-10-17: "showing how much extra time it will add and for how much exp, showing xp/hr with it vs
-- without it"). Until you say "Do it", the GPS doesn't send you to its work.
local RUN = 7   -- yards a second, on foot
local offQueue, offShowing = {}, false
local function thousands(n)
  local s = tostring(math.floor(n + 0.5))
  return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
local function onRouteQ(q)
  for _, s in ipairs(C.route().steps) do
    if s.q == q then return true end
    for _, m in ipairs(s.mem or {}) do if m.q == q then return true end end
  end
  return false
end
-- seconds it adds: its work, plus the walk there, round its objectives, to its hand-in and back to the route's step
function C.offRouteCost(q)
  local r = C.route()
  local e, o = (r.ends or {})[q], (r.objs or {})[q]
  local P = playerWorld()
  if not P then return nil end
  local here, walk, far = P, 0, false
  for _, m in ipairs(o and o.mem or {}) do
    if not objectiveDone(m) then
      local best, bd
      for _, w in ipairs(spawnSpots(m)) do
        if w.c == here.c and (not bd or dist(here, w) < bd) then best, bd = w, dist(here, w) end
      end
      if best then walk, here = walk + bd, best elseif #spawnSpots(m) > 0 then far = true end
    end
  end
  local ew = e and spot(e)
  if ew then
    if ew.c == here.c then walk, here = walk + dist(here, ew), ew else far = true end
  end
  local R = C.routeStep and r.steps[C.routeStep]
  local rw = R and spot(R)
  if rw and rw.c == here.c and rw.c == P.c then walk = walk + dist(here, rw) - dist(P, rw) end
  return math.max(0, walk) / RUN + (e and e.ws or 0), e and e.xp, far
end
local function offShowNext()
  if offShowing and StaticPopup_Visible and StaticPopup_Visible("AUDHD_OFFROUTE") then return end
  local q = table.remove(offQueue, 1)
  if not q then return end
  local r = C.route()
  local name = ((r.ends or {})[q] or (r.objs or {})[q] or {}).t or (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(q)) or ("quest " .. q)
  local secs, xp, far = C.offRouteCost(q)
  local lines = { ("You took |cffffd200%s|r. It isn't on your route."):format(name) }
  if far then
    lines[#lines + 1] = "Part of it is on another continent: a long trip."
  elseif secs then
    lines[#lines + 1] = ("About |cffffffff+%d min|r for |cffffffff%s XP|r."):format(math.max(1, math.floor(secs / 60 + 0.5)), xp and thousands(xp) or "? ")
    local o, st = order(), rdb()
    if r.xph and r.minutes and xp and #o > 0 then
      local left = r.minutes * 60 * math.max(1, #o - st.pos + 1) / #o
      local with = (r.xph * left / 3600 + xp) / (left + secs) * 3600
      lines[#lines + 1] = ("XP/h: |cffffffff%s|r without it, |cff%s%s|r with it."):format(thousands(r.xph), with >= r.xph and "40ff40" or "ff6060", thousands(with))
    end
  else
    lines[#lines + 1] = "AuDHD can't tell how long it takes."
  end
  lines[#lines + 1] = "Do it?"
  offShowing = true
  local dlg = StaticPopup_Show("AUDHD_OFFROUTE", table.concat(lines, "\n"))
  if dlg then dlg.data = { q = q } else offShowing = false end
  log("OFFROUTE_ASK", { q = q, secs = secs and math.floor(secs), xp = xp, far = far or nil })
end
StaticPopupDialogs["AUDHD_OFFROUTE"] = {
  text = "%s",
  button1 = "Do it",
  button2 = "Skip & abandon",
  OnAccept = function(_, data) C.offRouteChoice(data, true) end,
  OnCancel = function(_, data, reason) if reason == "clicked" then C.offRouteChoice(data, false) end end,
  OnHide = function() offShowing = false; C_Timer.After(0.2, offShowNext) end,
  timeout = 0, whileDead = true, hideOnEscape = false, preferredIndex = 3,
}
-- abandon a quest in your log: true when the game took it
function C.abandon(q)
  if C_QuestLog.SetSelectedQuest and C_QuestLog.SetAbandonQuest and C_QuestLog.AbandonQuest then
    if not C_QuestLog.GetLogIndexForQuestID(q) then return false end
    C_QuestLog.SetSelectedQuest(q)
    C_QuestLog.SetAbandonQuest()
    C_QuestLog.AbandonQuest()
    return true
  end
  local idx = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(q)
  if idx and SelectQuestLogEntry and SetAbandonQuest and AbandonQuest then
    SelectQuestLogEntry(idx)
    SetAbandonQuest()
    AbandonQuest()
    return true
  end
  return false
end
function C.offRouteChoice(data, doIt)
  if not data then return end
  local st = rdb()
  st.offAsked = st.offAsked or {}
  st.offAsked[data.q] = doIt and "do" or "skip"
  st.manual["o" .. data.q] = not doIt or nil   -- skipped: the GPS doesn't send you to its work
  -- and out of your log (the user, 2026-10-17: "when you click 'skip it' ... it should also abandon the quest")
  local abandoned = not doIt and C.abandon(data.q)
  log("OFFROUTE_CHOICE", { q = data.q, doIt = doIt, abandoned = abandoned or nil })
  C.repick(true, "off-route choice")
end
function C.offRouteAsk(q)
  q = tonumber(q)
  if not q or q <= 0 or not C.route() then return end
  local st = rdb()
  if (st.offAsked or {})[q] or onRouteQ(q) or (C.route().picks or {})[q] then return end   -- a pick-up the GPS offered: you chose it
  st.manual["o" .. q] = true   -- not offered until you answer
  offQueue[#offQueue + 1] = q
  C_Timer.After(0.5, offShowNext)   -- after auto-accept has closed the quest window
end

-- ------------------------------------------------------------------ the stretch pop-up
StaticPopupDialogs["AUDHD_STRETCH"] = {
  text = "%s",
  button1 = "Attempt",
  button2 = "Skip for now",
  OnAccept = function(_, data) C.stretchChoice(data, true) end,
  OnCancel = function(_, data, reason) if reason == "clicked" then C.stretchChoice(data, false) end end,
  timeout = 0, whileDead = true, hideOnEscape = false, preferredIndex = 3,
}
function C.stretchChoice(data, attempt)
  local st, o = rdb(), order()
  st.asked[data.i] = true
  log("STRETCH_CHOICE", { n = data.i, q = data.q, attempt = attempt })
  if attempt then return end
  -- skip: this quest's remaining steps go before the step the planner found (or out of the route)
  -- with it the quests that need it handed in first (Planting the Heart after The Moss-twined Heart: left behind, it
  -- sent you to Denalan for a quest you couldn't take, the user 2026-10-16)
  local qs, steps = { [data.q] = true }, C.route().steps
  local grew = true
  while grew do
    grew = false
    for p = st.pos, #o do
      local s = steps[o[p]]
      if s.k == "accept" and s.q and not qs[s.q] then
        for _, list in ipairs({ s.pre or {}, s.pre1 or {} }) do
          for _, x in ipairs(list) do if qs[x] then qs[s.q], grew = true, true end end
        end
      end
    end
  end
  local moving, keep = {}, {}
  for p, i in ipairs(o) do
    local s = steps[i]
    if p >= st.pos and s.q and qs[s.q] then moving[#moving + 1] = i else keep[#keep + 1] = i end
  end
  if data.before then
    local at = #keep + 1
    for p, i in ipairs(keep) do if i == data.before then at = p break end end
    for k, i in ipairs(moving) do table.insert(keep, at + k - 1, i) end
  end
  st.order = keep
  stepStarted = GetTime()
  C.advance("stretch-skip")
  C.onStepChanged()
end

local ammoCheck, moneyCheck   -- below, with the events that finish steps
function C.onStepChanged()
  local step, i, pos, total, via = C.current()
  if step then
    C.setWaypoint(step)
    log("STEP", { n = i, pos = pos, k = step.k, q = step.q, text = step.t, via = via })
    if step.k == "buyammo" then C_Timer.After(0.5, ammoCheck) end
    if step.pop and not rdb().asked[i] then
      local dlg = StaticPopup_Show("AUDHD_STRETCH", step.pop.q .. "\n\n" .. (step.pop.skip or ""))
      if dlg then dlg.data = { i = i, q = step.q, before = step.pop.before } end
    end
  end
  if ns.ui then ns.ui.refresh() end
  if ns.routemap then ns.routemap.refresh() end
  if ns.useItem then ns.useItem.refresh() end
end

-- the reward the route plans to take from a quest (Auto.lua picks it at the turn-in)
function C.plannedReward(questID)
  local r = C.route()
  if not r then return nil end
  for _, s in ipairs(r.steps) do
    if s.k == "turnin" and s.q == questID and s.wp then return s.wp end
  end
end

-- ------------------------------------------------------------------ events that finish steps
local frame = ns.newFrame("Core", "Frame")
local pending = false
local function soon(reason)
  if pending then return end
  pending = true
  C_Timer.After(0.4, function() pending = false; C.advance(reason) end)
end
local function currentKind() local s = C.current(); return s and s.k, s end
-- an ammo step is done once you carry (nearly) the amount it buys up to: bought just now, or already
function ammoCheck()
  if currentKind() ~= "buyammo" or not ns.ammo then return end
  local n = ns.ammo.count()
  if n and n >= 0.9 * (ns.ammo and ns.ammo.target() or 1000) then C.markDone("ammo stocked") end
end

-- saving up for a weapon: the arrow comes back (to the vendor) once money + junk covers it
function moneyCheck()
  local k, step = currentKind()
  if k ~= "buyweapon" or not step.pc then return end
  local short = C.weaponShort(step) ~= nil
  if short == (C.target == nil) then return end
  C.setWaypoint(step)
  if ns.ui then ns.ui.refresh() end
end

local events = {
  QUEST_ACCEPTED = function(a, b) soon("quest accepted"); C.offRouteAsk(b or a) end,
  PLAYER_CONTROL_GAINED = function() soon("landed") end,   -- off the flight path: look again where you are
  QUEST_TURNED_IN = function(q) turnedIn[q] = true; soon("quest turned in") end,
  QUEST_REMOVED = function() soon("quest removed") end,
  QUEST_LOG_UPDATE = function()
    soon("quest log")
    if ns.ui then C_Timer.After(0.5, ns.ui.refresh) end   -- the live objective counts
  end,
  PLAYER_LEVEL_UP = function() soon("level up") end,
  BAG_UPDATE_DELAYED = function() ammoCheck(); moneyCheck() end,
  PLAYER_MONEY = function() moneyCheck() end,
  MERCHANT_CLOSED = function()
    ammoCheck()
    if currentKind() == "visit" then C.markDone("vendor visited") end
  end,
  TRAINER_CLOSED = function()
    local k = currentKind()
    if k == "train" or k == "learn" or k == "learnweapon" or k == "visit" then C.markDone("trainer visited") end
  end,
  TAXIMAP_OPENED = function()
    if currentKind() == "discover" then C.markDone("flight master") end
    -- the flight paths you know: the arrow flies you when it's quicker (Walk.lua), the planner starts from them
    if ns.walk then
      local all, added = ns.walk.readTaxiMap()
      if #added > 0 then log("TAXI_KNOWN", { ids = all }) end
    end
  end,
  HEARTHSTONE_BOUND = function()
    if currentKind() == "bind" then C.markDone("hearthstone bound") end
    C_Timer.After(1, learnBind)
  end,
  -- where a hearth lands: the inn's spot (once the new zone has loaded)
  UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID)
    if unit == "player" and spellID == HEARTHSTONE_SPELL then C_Timer.After(4, learnBind) end
  end,
  PLAYER_EQUIPMENT_CHANGED = function(slot)
    local k, step = currentKind()
    if (k == "buyweapon" or k == "craft") and step.wp and (slot == 16 or slot == 18) then
      local link = GetInventoryItemLink("player", slot)
      local name = link and C_Item.GetItemInfo(link)
      if name == step.wp then C.markDone("weapon equipped") end
    end
  end,
}
-- each character follows its own route (AuDHDDB.route is the one in use now): at login, the route this
-- character last followed; a character without one keeps the route in use if it's for its race and class and still
-- ahead of it, else gets the best fit: for its race and class (a route for its class before one for any class), one
-- that starts at or below its level, fastest first (a new Dwarf gets the Dun Morogh start, not the Night Elf one)
local function charKey() return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?") end
-- a route's race can name several ("Dwarf/Gnome": they share Coldridge Valley)
function ns.raceFits(rrace, race)
  if not rrace or not race then return true end
  for x in rrace:gmatch("[^/]+") do if x:lower() == race:lower() then return true end end
  return false
end
local function fits(r, race, class, level)
  return r and ns.raceFits(r.race, race) and (not r.class or r.class:upper() == (class or ""):upper())
    and (r.target or 0) > level
end
function C.pickCharRoute()
  local d = AuDHDDB
  d.charRoute = d.charRoute or {}
  local key = charKey()
  local _, race = UnitRace("player")
  local _, class = UnitClass("player")
  local level = UnitLevel("player") or 1
  local mine = d.charRoute[key]
  if not (mine and ns.routes[mine]) then
    mine = nil
    if fits(ns.routes[d.route], race, class, level) and (ns.routes[d.route].start or 1) <= level then mine = d.route end
    if not mine then
      local best, bestRank
      for k, r in pairs(ns.routes) do
        if fits(r, race, class, level) then
          local rank = ((r.start or 1) <= level and 0 or 2e6) + (r.class and 0 or 1e6) + (r.minutes or 1e5)
          if not bestRank or rank < bestRank or (rank == bestRank and k < best) then best, bestRank = k, rank end
        end
      end
      mine = best or d.route
    end
    d.charRoute[key] = mine
  end
  if mine ~= d.route then log("ROUTE", { route = mine, why = "character" }) end
  d.route = mine
end
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= "AuDHD" then return end
    AuDHDDB = AuDHDDB or {}
    AuDHDDB.route = AuDHDDB.route or DEFAULT_ROUTE
    if not ns.routes[AuDHDDB.route] then AuDHDDB.route = DEFAULT_ROUTE end
    AuDHDDB.auto = AuDHDDB.auto or {}
    return
  end
  if event == "PLAYER_LOGIN" then
    C.pickCharRoute()
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
    for e in pairs(events) do pcall(frame.RegisterEvent, frame, e) end
    -- the quest log isn't ready at login: look a moment later
    C_Timer.After(3, function() C.advance("init") end)
    -- every 2 s: the GPS looks at where you are now, and objectives that finish without a quest log update (taming
    -- with a Taming Rod) are seen
    C_Timer.NewTicker(2, function() C.advance("gps") end)
    C_Timer.NewTicker(1, function() C.roamTick() C.caveTick() end)   -- the arrow hops between spawn points on a kill / collect step
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

-- ------------------------------------------------------------------ /wfn
local function say(msg) print("|cff66ccffAuDHD|r: " .. msg) end
-- follow another route (/wfn route, the route picker): from its first step you haven't done
function C.setRoute(key)
  if not ns.routes[key] then return end
  AuDHDDB.route = key
  AuDHDDB.charRoute = AuDHDDB.charRoute or {}
  AuDHDDB.charRoute[charKey()] = key
  C.cur = nil
  log("ROUTE", { route = key })
  C.advance("route")
  C.onStepChanged()
  if ns.ui then ns.ui.refresh() end
  say("route: " .. (ns.routes[key].title or key))
end
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
  elseif cmd == "routes" and ns.picker then
    ns.picker.show()
  elseif cmd == "settings" and ns.settings then
    ns.settings.show()
  elseif cmd == "minimap" and ns.minimap then
    AuDHDDB.minimap = AuDHDDB.minimap or { angle = 200 }
    AuDHDDB.minimap.hide = (rest == "off") or nil
    ns.minimap.apply()
    say("minimap button: " .. (AuDHDDB.minimap.hide and "off" or "on") .. " (/wfn minimap on|off)")
  elseif cmd == "route" then
    if ns.routes[rest] then
      C.setRoute(rest)
    else
      local names = {}
      for k in pairs(ns.routes) do names[#names + 1] = k end
      say("routes: " .. table.concat(names, ", ") .. " (now: " .. AuDHDDB.route .. ")")
    end
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
      say("auto: " .. table.concat(parts, ", ") .. "  (/wfn auto accept|complete|junk|repair on|off, /wfn auto reward value|manual; hold Shift to pause)")
    end
  elseif cmd == "ammo" then
    if rest == "off" then say(ns.ammo.goVendor(true))
    elseif tonumber(rest) then AuDHDDB.ammoTarget = tonumber(rest); say("buying ammo up to " .. rest)
    else say(ns.ammo.goVendor()) end
  elseif cmd == "map" then
    AuDHDDB.mapHidden = (rest == "off") or nil
    if ns.routemap then ns.routemap.refresh() end
    say("route on the maps: " .. (AuDHDDB.mapHidden and "off" or "on") .. " (/wfn map on|off)")
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
    say(("rewards are scored for %s (specs: %s; /wfn spec <name>)"):format(sp and sp.name or "?", table.concat(names, ", ")))
  elseif cmd == "announce" and ns.questDone then
    say(ns.questDone.command(rest))
  elseif cmd == "askbuffs" and ns.buffAsk then
    say(ns.buffAsk.command(rest))
  elseif cmd == "imbue" and ns.imbue then
    say(ns.imbue.command(rest))
  elseif cmd == "heal" and ns.heal then
    say(ns.heal.command(rest))
  elseif cmd == "shards" and ns.shards then
    say(ns.shards.command(rest))
  elseif (cmd == "buffs" or cmd == "aspect") and ns.imbue then
    say(ns.imbue.command(rest, "buffs"))
  elseif cmd == "blocked" and ns.walk then
    local n, ax, ay, bx, by = ns.walk.block()
    if n > 0 then
      say(("that way's out (%.1f,%.1f to %.1f,%.1f): finding another (/wfn unblock puts them all back)"):format(ax or 0, ay or 0, bx or 0, by or 0))
      if ns.arrow and ns.arrow.update then ns.arrow.update() end
    else
      say("no walking way to block here")
    end
  elseif cmd == "unblock" and ns.walk then
    say(("%d blocked stretches put back"):format(ns.walk.unblock()))
  elseif cmd == "log" then
    local n, s = ns.log.count()
    say(("%d entries this session, %d sessions saved (written on /reload or logout)"):format(n, s))
  elseif cmd == "reset" then
    AuDHDDB.state[AuDHDDB.route] = nil
    log("ROUTE_RESET", { route = AuDHDDB.route })
    C.advance("route")
    say("route reset to step 1 (steps you've done are skipped again)")
  else
    say("/wfn (show/hide), /wfn note <text>, /wfn done, /wfn later, /wfn back, /wfn goto <n>, /wfn route [name], /wfn routes, /wfn settings, /wfn minimap on|off, /wfn auto, /wfn ammo [off|<count>], /wfn arrow, /wfn map on|off, /wfn threat on|off, /wfn rares all|route|off, /wfn perf, /wfn spec [name], /wfn imbue [off|on], /wfn shards [off|on|max <n>|low <n>|lock|unlock|reset], /wfn heal [on|off|setup], /wfn buffs [off|on], /wfn announce [off|on], /wfn askbuffs [off|on], /wfn blocked, /wfn unblock, /wfn log, /wfn reset")
  end
end
