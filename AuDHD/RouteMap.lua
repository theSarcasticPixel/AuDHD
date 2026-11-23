-- The route ahead on the maps, so you know which way you're heading while you work:
-- * World map: the next steps as numbered pins (1 = the step you're on), joined by the walking way in route order (each
--   stretch in the colour of the step it leads to), with the way from you to step 1. Steps on another map show when the map you're looking at contains them.
-- * Minimap: the next few steps as numbered dots; one beyond the minimap's edge sits on the rim in its direction.
-- * A route another addon sends (SideRoute.lua), on both maps the same way, in its own colour, under ours.
-- Our own frames only (pins on the map canvas, one line frame, dots on the minimap): nothing protected.
local _, ns = ...
local R = {}
ns.routemap = R

local WORLD_STEPS, MINIMAP_STEPS = 10, 5
local MINIMAP_YARDS = { outdoor = { [0] = 466.6667, 400, 333.3333, 266.6667, 200, 133.3333 },
                        indoor = { [0] = 300, 240, 180, 120, 80, 50 } }
local COLOURS = { accept = { 1, 0.82, 0 }, turnin = { 0.25, 0.9, 0.25 }, ["do"] = { 1, 0.45, 0.2 } }
local OTHER = { 0.45, 0.7, 1 }
-- a path takes the colour of the step it leads to
local function colourOf(step) return step and COLOURS[step.k] or OTHER end
local isSecret = issecretvalue or function() return false end

-- one colour per objective of the step you're on (the window writes each objective in its colour: the legend)
ns.PALETTE = { { 0.2, 0.85, 1 }, { 1, 0.35, 0.85 }, { 0.6, 1, 0.2 }, { 1, 0.6, 0.15 }, { 0.75, 0.55, 1 }, { 1, 1, 0.35 } }
-- A guide step's rings: each of its rows in the window's order (so the colours match), a "do" row with its goal's
-- places. Camps: the guide's own spawn spots, a ring per group of spawns, or every spawn when the guide has none. Or,
-- Settings > Maps, a dot for every spawn of the goal's mobs or objects (SpawnData.lua), the camps when that has none. Every open objective's, wherever the arrow
-- leads first. Worked out once a step and setting: { { sp = { { m, p = { x, y, ... } (0-100), o = an object } } } }
-- Settings > Maps, one of three: "camps" (the default), "each" (every spawn) or "off"
function R.spawnMode() return AuDHDDB.spawnRings or "camps" end
function R.setSpawnMode(mode)
  AuDHDDB.spawnRings = (mode == "each" or mode == "off") and mode or nil
  AuDHDDB.spawnRingsOff, AuDHDDB.spawnEach = nil, nil   -- (the two tick boxes before it, never released)
  pcall(R.refresh)
end
function R.spawnsOn() return R.spawnMode() ~= "off" end
function R.eachSpawn() return R.spawnMode() == "each" end
local function isObject(goal) return goal.object ~= nil or goal.fromKind == "object" end
local unpacked = setmetatable({}, { __mode = "v" })
local function spawnsOf(kind, id)
  local s = ns.spawnData and ns.spawnData[kind] and ns.spawnData[kind][id]
  if not s then return nil end
  local key = kind .. id
  if unpacked[key] then return unpacked[key] end
  local groups = {}
  for part in s:gmatch("[^|]+") do
    local m, rest = part:match("^(%d+):(.*)$")
    local p = {}
    for x, y in (rest or ""):gmatch("([%d.]+),([%d.]+)") do p[#p + 1] = tonumber(x) p[#p + 1] = tonumber(y) end
    if m and #p > 0 then groups[#groups + 1] = { m = tonumber(m), p = p, o = kind == "object" } end
  end
  unpacked[key] = groups
  return groups
end
local function everySpawn(goal)
  local out, seen = {}, {}
  local function add(kind, id)
    id = tonumber(id)
    if not id or seen[kind .. id] then return end
    seen[kind .. id] = true
    for _, g in ipairs(spawnsOf(kind, id) or {}) do out[#out + 1] = g end
  end
  local fromKind = goal.fromKind == "object" and "object" or "npc"
  if goal.npc then add("npc", goal.npc) end
  if goal.object then add("object", goal.object) end
  if goal.fromId then add(fromKind, goal.fromId) end
  if goal.fromAlsoId then add(fromKind, goal.fromAlsoId) end
  for _, f in ipairs(type(goal.fromNpcs) == "table" and goal.fromNpcs or {}) do add("npc", f.npc) end
  return #out > 0 and out or nil
end
local function camps(goal)
  local spots = goal.spots
  if type(spots) ~= "table" or not goal.map then return nil end
  local p = {}
  for _, s in ipairs(spots) do
    local _, x, y = ns.geo.live({ map = goal.map, x = s.x, y = s.y, f = goal.f })
    if x and y then p[#p + 1] = x p[#p + 1] = y end
  end
  return #p > 0 and { { m = goal.map, p = p, o = isObject(goal) } } or nil
end
local ringKey, ringMem
local function guideMembers(step)
  if not R.spawnsOn() then return {} end
  local E = AuDHDEngine and AuDHDEngine.Engine
  local guide = E and E.GetGuide and E.GetGuide()
  local goals = guide and guide.steps and guide.steps[step.i] and guide.steps[step.i].goals
  if not goals then return {} end
  local each = R.eachSpawn()
  local parts = { tostring(goals), step.i, each and "each" or "camps" }
  for _, r in ipairs(step.rows) do parts[#parts + 1] = r.k == "do" and tostring(r.g) or "-" end
  local key = table.concat(parts, ",")
  if key == ringKey then return ringMem end
  local out = {}
  for i, r in ipairs(step.rows) do
    local goal = r.k == "do" and r.g and goals[r.g]
    out[i] = { sp = goal and ((each and everySpawn(goal)) or camps(goal) or everySpawn(goal)) or nil }
  end
  ringKey, ringMem = key, out
  return out
end
local function members(step)
  if not step then return {} end
  if step.rows and step.i then return guideMembers(step) end
  if step.k ~= "do" then return {} end
  return step.mem or {}
end
R.members = members   -- (the smoke test)

-- the places ahead: { step, n, of } where n = 1 for the first place of the step you're on; step is that place (a guide
-- step's stop, else the step itself), of the step it's part of
local function ahead(count)
  local out, k = {}, 0
  while #out < count and k < count + 10 do
    local step = (k == 0) and ns.core.current() or ns.core.peek(k)
    if not step then break end
    if step.stops then   -- a guide step: one number per place it sends you (Guide.lua), so the hand-in between two kills shows
      for _, s in ipairs(step.stops) do if #out < count then out[#out + 1] = { step = s, n = #out + 1, of = step } end end
    elseif step.m and step.x and step.y then out[#out + 1] = { step = step, n = #out + 1, of = step } end
    k = k + 1
  end
  return out
end

R.ahead = ahead   -- (the smoke test)

-- a step's position on another map (0..1), or nil when that map doesn't contain it
local function onMap(step, mapID)
  if step.m == mapID then return step.x / 100, step.y / 100 end
  local ok, cont, world = pcall(C_Map.GetWorldPosFromMapPos, step.m, CreateVector2D(step.x / 100, step.y / 100))
  if not ok or not world then return nil end
  local ok2, m2, pos = pcall(C_Map.GetMapPosFromWorldPos, cont, world, mapID)
  if not ok2 or not pos or m2 ~= mapID then return nil end
  local x, y = pos:GetXY()
  if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
  return x, y
end

-- a frame for a map: made without a parent, then put there (the gamepad UI's navigation watches frames made inside an
-- open window, and one made there from our code blocks its next close)
local function onFrame(parent)
  local f = ns.newFrame("RouteMap", "Frame")
  f:SetParent(parent)
  return f
end
local function newPin(parent, size)
  local f = onFrame(parent)
  f:SetSize(size, size)
  f.dot = f:CreateTexture(nil, "ARTWORK")
  f.dot:SetAllPoints()
  f.dot:SetTexture("Interface\\AddOns\\AuDHD\\Media\\dot")
  f.ring = f:CreateTexture(nil, "BORDER")
  f.ring:SetPoint("CENTER")
  f.ring:SetSize(size + 4, size + 4)
  f.ring:SetTexture("Interface\\AddOns\\AuDHD\\Media\\dot")
  f.ring:SetVertexColor(0, 0, 0, 0.85)
  f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.text:SetPoint("CENTER", 0, 0)
  f.text:SetTextColor(0, 0, 0)
  -- hover: the steps behind the numbers; clicks go through to the map
  f:EnableMouse(true)
  if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
  f:SetScript("OnEnter", function(self)
    local g = self.group
    if not g then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("AuDHD route", 0.4, 0.8, 1)
    for _, it in ipairs(g.steps or {}) do
      local c = colourOf(it.step)
      local text = ns.ui and ns.ui.line and ns.ui.line(it.step) or ns.core.text(it.step)
      GameTooltip:AddLine(("%d. %s"):format(it.n, (text:gsub("%*%*", ""))), c[1], c[2], c[3], true)
    end
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return f
end
-- "2-4,7": the step numbers sharing a pin, consecutive runs joined
local function numbers(ns)
  local parts, i = {}, 1
  while i <= #ns do
    local j = i
    while ns[j + 1] == ns[j] + 1 do j = j + 1 end
    parts[#parts + 1] = (j > i) and (ns[i] .. "-" .. ns[j]) or tostring(ns[i])
    i = j + 1
  end
  return table.concat(parts, ",")
end
-- steps at (nearly) the same spot share one pin: a pill wide enough for all their numbers, coloured by the first (or
-- colour)
local function style(pin, group, size, colour)
  local c = colour or COLOURS[group.step.k] or OTHER
  pin.dot:SetVertexColor(c[1], c[2], c[3])
  pin.text:SetText(numbers(group.ns))
  pin.group = group
  local tw = (pin.text:GetStringWidth() or 0) * (pin.text:GetScale() or 1)
  local wdt = math.max(size, tw + size * 0.6)
  pin:SetSize(wdt, size)
  pin.ring:SetSize(wdt + size * 0.22, size * 1.22)
end
-- add a step at (px, py) to the group it sits on (within dist), else a new group
local function stack(groups, e, px, py, dist)
  for _, g in ipairs(groups) do
    if (g.px - px) ^ 2 + (g.py - py) ^ 2 < dist * dist then
      g.ns[#g.ns + 1] = e.n
      g.steps[#g.steps + 1] = { n = e.n, step = e.step }
      return g
    end
  end
  local g = { px = px, py = py, ns = { e.n }, step = e.step, steps = { { n = e.n, step = e.step } } }
  groups[#groups + 1] = g
  return g
end

-- ------------------------------------------------------------------ world map
local worldPins, lines, lineFrame, playerLine = {}, {}, nil, nil
local function canvas()
  return WorldMapFrame and WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
end
-- above everything the map has on its canvas: the map raises its own layers (the tiles, other addons' pins) after it
-- opens, and the path drawn just above the canvas went under them a split second later
local ours = {}
local function above(cv)
  local top = cv:GetFrameLevel()
  for _, c in ipairs({ cv:GetChildren() }) do
    if not ours[c] then
      local l = c:GetFrameLevel()
      if l and l > top then top = l end
    end
  end
  -- (the joined-up map's art is a frame on the canvas with its layers above it: Atlas.lua, or OpenMap's, which says
  -- how high its art reaches)
  if ns.atlas and ns.atlas.top() > top then top = ns.atlas.top() end
  local api = _G.OpenMapAPI
  local art = api and api.ArtTopLevel and api.ArtTopLevel()
  if type(art) == "number" and art > top then top = art end
  return math.min(top, 9000)
end
R.above = above   -- (the smoke test)
-- OpenMap's joined-up world map (the addon OpenMap, through its OpenMapAPI) while it's showing on a zone or a map
-- inside one: its API, else nil. Zoomed out to a continent or the world, everything stays on the map underneath, as
-- without it
local function openMap(mapID)
  local api = _G.OpenMapAPI
  if not (api and api.IsStitched and api.CanvasFromWorldPos and api.IsStitched()) then return nil end
  local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
  if not (info and info.mapType and info.mapType >= 3) then return nil end
  return api
end
-- the part of the map's canvas in the window, as 0..1 of the map underneath (x0, y0, x1, y1), widened by margin (a
-- share of it); nil when the frames can't say
local function canvasView(margin)
  local sc = WorldMapFrame.ScrollContainer
  local cv = canvas()
  if not (sc and cv and sc.GetLeft and sc.GetEffectiveScale) then return nil end
  local cl, ct, cw, ch = cv:GetLeft(), cv:GetTop(), cv:GetWidth(), cv:GetHeight()
  local l, r, t, b = sc:GetLeft(), sc:GetRight(), sc:GetTop(), sc:GetBottom()
  local es, ec = sc:GetEffectiveScale(), cv:GetEffectiveScale()
  if not (cl and ct and cw and ch and l and r and t and b and es and ec and cw > 0 and ch > 0) then return nil end
  local x0, x1 = (l * es - cl * ec) / (cw * ec), (r * es - cl * ec) / (cw * ec)
  local y0, y1 = (ct * ec - t * es) / (ch * ec), (ct * ec - b * es) / (ch * ec)
  local mx, my = (x1 - x0) * margin, (y1 - y0) * margin
  return x0 - mx, y0 - my, x1 + mx, y1 + my
end
-- where things go: 0..1 of the map underneath. With a joined-up map showing (OpenMap's, or Atlas.lua's), everything in
-- view counts, the parts in its neighbours too (the map underneath is only the zone in the middle); else what's on the
-- map itself.
-- at(m, x, y[, any]): a map spot (0..100), nil when out of view (any: anywhere); yards(c, X, Y): world yards;
-- inView(x, y)
local function placer(mapID)
  local P = {}
  local x0, y0, x1, y1, toHost
  local api = openMap(mapID)
  if api then
    toHost = api.CanvasFromWorldPos
    x0, y0, x1, y1 = canvasView(0.1)
    if not x0 then x0, y0, x1, y1 = -math.huge, -math.huge, math.huge, math.huge end
  elseif ns.atlas and ns.atlas.shown() then
    toHost = ns.atlas.yardsToHost
    x0, y0, x1, y1 = ns.atlas.viewOnHost(0.1)
  end
  if x0 then
    P.wide = true
    function P.inView(x, y) return x and y and x >= x0 and x <= x1 and y >= y0 and y <= y1 or false end
    function P.yards(c, X, Y) if c and X and Y then return toHost(c, X, Y) end end
    function P.at(m, x, y, any)
      if not (ns.walk and m and x and y) then return nil end
      local c, X, Y = ns.walk.toWorld(m, x, y)
      if not (c and X and Y) then return nil end
      local fx, fy = toHost(c, X, Y)
      if fx and (any or P.inView(fx, fy)) then return fx, fy end
    end
  else
    function P.inView(x, y) return x and y and x >= -0.05 and x <= 1.05 and y >= -0.05 and y <= 1.05 or false end
    function P.yards(_, X, Y) if ns.walk and ns.walk.toMap(mapID, 0, 0) then return ns.walk.toMap(mapID, X, Y) end end
    function P.at(m, x, y) if m and x and y then return onMap({ m = m, x = x, y = y }, mapID) end end
  end
  return P
end
R.placer = placer
-- straight lines and walking paths on the canvas, from a pool of lines on frame: line(x1, y1, x2, y2, r, g, b, a) in
-- 0..1 of the canvas; pathLine(p, k, r, g, b, a) a walking path (Walk.lua: { c, pts } in world yards) from point k on,
-- false if it can't be placed. used() is how many lines are out
local function liner(frame, pool, cv, w, h, scale, P)
  local n = 0
  local function line(x1, y1, x2, y2, r, g, b, a)
    n = n + 1
    local l = pool[n]
    if not l then l = frame:CreateLine(nil, "ARTWORK"); pool[n] = l end
    l:SetColorTexture(r, g, b, a)
    l:SetThickness(3 / scale)
    l:SetStartPoint("TOPLEFT", cv, x1 * w, -y1 * h)
    l:SetEndPoint("TOPLEFT", cv, x2 * w, -y2 * h)
    l:Show()
  end
  local function pathLine(p, k, r, g, b, a)
    local pts = p.pts
    if not P.yards(p.c, pts[k or 1] or pts[(k or 1) + 2], pts[(k or 1) + 1] or pts[(k or 1) + 3]) then return false end
    local px, py
    for i = k or 1, #pts - 1, 2 do
      if pts[i] then
        local x, y = P.yards(p.c, pts[i], pts[i + 1])
        if px and x and (P.inView(px, py) or P.inView(x, y)) then
          line(px, py, x, y, r, g, b, a)
        end
        px, py = x, y
      else
        px, py = nil, nil   -- a boat or portal: no line across
      end
    end
    return true
  end
  return line, pathLine, function() return n end
end
function R.drawWorld()
  for _, p in ipairs(worldPins) do p:Hide() end
  for _, l in ipairs(lines) do l:Hide() end
  -- the tick box on the world map: the numbers and their lines only, the rest stays (AuDHDDB.worldRouteOff)
  if not (WorldMapFrame and WorldMapFrame:IsShown()) or AuDHDDB.mapHidden or AuDHDDB.worldRouteOff then return end
  local cv = canvas()
  local mapID = WorldMapFrame:GetMapID()
  if not (cv and mapID) then return end
  local w, h = cv:GetWidth(), cv:GetHeight()
  if not w or w <= 0 then return end
  local scale = cv:GetScale() or 1
  if not lineFrame then lineFrame = onFrame(cv); ours[lineFrame] = true end
  local P = placer(mapID)
  local base = above(cv)
  lineFrame:SetParent(cv)
  lineFrame:SetAllPoints(cv)
  lineFrame:SetFrameLevel(base + 20)
  lineFrame:Show()
  local size = 18 / scale
  local placed = {}
  local line, pathLine = liner(lineFrame, lines, cv, w, h, scale, P)
  local groups = {}
  local list = ahead(WORLD_STEPS)
  for i, e in ipairs(list) do
    local x, y = P.at(e.step.m, e.step.x, e.step.y)
    local before = list[i - 1]
    if i > 1 and not (x and placed[#placed] and placed[#placed].n == e.n - 1) then
      -- one end is off this map: the walking way between them still crosses it (no straight line: we don't know where)
      local p = ns.route and ns.route.between(before.step.m, before.step.x, before.step.y, e.step.m, e.step.x, e.step.y)
      local c = colourOf(e.step)
      if p then pathLine(p, 1, c[1], c[2], c[3], 0.85) end
    end
    if x then
      local g = stack(groups, e, x * w, y * h, size)
      local prev = placed[#placed]
      if prev and prev.n == e.n - 1 and prev.g ~= g then
        -- the walking way between the two steps, else a straight line
        local p = ns.route and ns.route.between(prev.step.m, prev.step.x, prev.step.y, e.step.m, e.step.x, e.step.y)
        local c = colourOf(e.step)
        if not (p and pathLine(p, 1, c[1], c[2], c[3], 0.85)) then line(prev.x, prev.y, g.px / w, g.py / h, c[1], c[2], c[3], 0.85) end
      end
      placed[#placed + 1] = { n = e.n, x = g.px / w, y = g.py / h, g = g, step = e.step }
    end
  end
  for i, g in ipairs(groups) do
    local pin = worldPins[i]
    if not pin then pin = newPin(cv, size); worldPins[i] = pin; ours[pin] = true end
    pin:SetParent(cv)
    pin:SetFrameLevel(base + 30)
    pin.text:SetScale(1 / scale)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", cv, "TOPLEFT", g.px, -g.py)
    style(pin, g, size)
    pin:Show()
  end
  -- you -> step 1, also when step 1 is off this map (you're in Darnassus, it's in Dolanaar: the map you open on is
  -- Darnassus)
  local first = placed[1]
  local target = ns.core.override or ns.core.target or (first and first.n == 1 and first.step)
  local m = C_Map.GetBestMapForUnit("player")
  local pos = target and m and not isSecret(m) and C_Map.GetPlayerMapPosition(m, "player")
  if pos then
    local px, py = pos:GetXY()
    local sx, sy = P.at(m, px * 100, py * 100, true)
    -- the walking way from you (the part of it ahead of you), else a straight line
    local p = ns.walk and ns.walk.toStep(target)
    local tc = colourOf(target)
    local drawn = false
    if p and sx then
      local k = p.at or 1
      if not p.pts[k] then k = k + 2 end
      local x, y = P.yards(p.c, p.pts[k], p.pts[k + 1])
      -- you to the path's start: in the air, a faint line to where your flight lands
      if x then line(sx, sy, x, y, tc[1], tc[2], tc[3], ns.walk.flying and ns.walk.flying() and 0.35 or 0.9) end
      drawn = pathLine(p, k, tc[1], tc[2], tc[3], 0.9)
    end
    if sx and not drawn and first and first.n == 1 then line(sx, sy, first.x, first.y, tc[1], tc[2], tc[3], 0.9) end
  end
end

-- ------------------------------------------------------------------ spawn points of the step you're on
local spawnFrame, spawnTex, nSpawn = nil, {}, 0
local function spawnDot(parent, i)
  local t = spawnTex[i]
  if not t then t = parent:CreateTexture(nil, "OVERLAY"); t:SetTexture("Interface\\AddOns\\AuDHD\\Media\\dot"); spawnTex[i] = t end
  return t
end
function R.drawSpawnsWorld()
  for i = 1, nSpawn do spawnTex[i]:Hide() end
  nSpawn = 0
  if not (WorldMapFrame and WorldMapFrame:IsShown()) or AuDHDDB.mapHidden then return end
  local cv = canvas()
  local mapID = WorldMapFrame:GetMapID()
  if not (cv and mapID) then return end
  local w, h = cv:GetWidth(), cv:GetHeight()
  if not w or w <= 0 then return end
  local scale = cv:GetScale() or 1
  if not spawnFrame then spawnFrame = onFrame(cv); ours[spawnFrame] = true end
  local P = placer(mapID)
  spawnFrame:SetParent(cv)
  spawnFrame:SetAllPoints(cv)
  spawnFrame:SetFrameLevel(above(cv) + 25)
  spawnFrame:Show()
  local size = 9 / scale
  for mi, mem in ipairs(members(ns.core.current())) do
    local c = ns.PALETTE[(mi - 1) % #ns.PALETTE + 1]
    for _, group in ipairs(mem.sp or {}) do
      if P.wide or group.m == mapID then
        local p = group.p
        local sz = group.o and size * 0.65 or size   -- objects you pick up: smaller dots
        for k = 1, #p - 1, 2 do
          local x, y = p[k] / 100, p[k + 1] / 100
          if P.wide then x, y = P.at(group.m, p[k], p[k + 1]) end
          if x then
          nSpawn = nSpawn + 1
          local t = spawnDot(spawnFrame, nSpawn)
          t:SetSize(sz, sz)
          t:SetVertexColor(c[1], c[2], c[3], 0.95)
          t:ClearAllPoints()
          t:SetPoint("CENTER", cv, "TOPLEFT", x * w, -y * h)
          t:Show()
          end
        end
      end
    end
  end
end

-- ------------------------------------------------------------------ rares' spawn points
-- : a skull at each spawn point of every rare on the map you're looking at (RareData.lua); a red one for a rare the
-- route still needs. Hover: who, what level, what it drops and how often (RareDrops.lua).
local rarePins = {}
local function rareTip(self)
  local r = self.rare and ns.rareData[self.rare]
  if not r then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(r.n, 1, 0.82, 0)
  local lv = r.lv and (r.lv[1] == r.lv[2] and tostring(r.lv[1]) or (r.lv[1] .. "-" .. r.lv[2])) or "?"
  GameTooltip:AddLine(("Rare%s, level %s"):format(r.e and " elite" or "", lv), 1, 1, 1)
  local w = ns.rare and ns.rare.wanted(self.rare)
  if w then
    GameTooltip:AddLine("Needed for " .. (C_QuestLog.GetTitleForQuestID(w.q) or ("quest " .. w.q)), 1, 0.3, 0.2)
  end
  local drops = ns.rareDrops and ns.rareDrops[self.rare]
  if drops then
    GameTooltip:AddLine("Drops:", 1, 0.82, 0)
    for _, d in ipairs(drops) do
      local id, name, quality, chance = d[1], d[2], d[3], d[4]
      -- (the game's own name and colour once it knows the item; asked for, so the next look has them)
      local own, _, q
      local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo   -- (newer clients have only C_Item's)
      if info then own, _, q = info(id) end
      if not own and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
      local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or quality]
      local pct = chance >= 10 and ("%d%%"):format(math.floor(chance + 0.5)) or ("%.1f%%"):format(chance)
      GameTooltip:AddDoubleLine("  " .. (own or name), pct, c and c.r or 1, c and c.g or 1, c and c.b or 1, 0.8, 0.8, 0.8)
    end
  end
  GameTooltip:AddLine("A spawn point: it may not be up", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end
R.rareTip = rareTip   -- (the smoke test)
-- (the joined-up map: every rare in the world is looked at, so each spawn point is turned into world yards once)
local rareYards = setmetatable({}, { __mode = "k" })
local function rareAt(P, g, k)
  local yd = rareYards[g]
  if not yd then
    yd = {}
    for i = 1, #g.p - 1, 2 do
      local c, X, Y = ns.walk.toWorld(g.m, g.p[i], g.p[i + 1])
      yd[i], yd[i + 1], yd.c = X or false, Y or false, yd.c or c
    end
    rareYards[g] = yd
  end
  if not (yd.c and yd[k]) then return nil end
  local x, y = P.yards(yd.c, yd[k], yd[k + 1])
  if P.inView(x, y) then return x, y end
end
function R.drawRaresWorld()
  for _, p in ipairs(rarePins) do p:Hide() end
  if not (WorldMapFrame and WorldMapFrame:IsShown()) or AuDHDDB.mapHidden or AuDHDDB.rares == "off" or not ns.rareData then return end
  local cv = canvas()
  local mapID = WorldMapFrame:GetMapID()
  if not (cv and mapID) then return end
  local w, h = cv:GetWidth(), cv:GetHeight()
  if not w or w <= 0 then return end
  local scale = cv:GetScale() or 1
  local level = (spawnFrame and spawnFrame:GetFrameLevel() or above(cv)) - 2
  local P = placer(mapID)
  local n = 0
  for npc, r in pairs(ns.rareData) do
    local needed = ns.rare and ns.rare.wanted(npc) ~= nil
    if needed or AuDHDDB.rares ~= "route" then
      for _, g in ipairs(r.sp) do
        if P.wide or g.m == mapID then
          for k = 1, #g.p - 1, 2 do
          local x, y = g.p[k] / 100, g.p[k + 1] / 100
          if P.wide then x, y = rareAt(P, g, k) end
          if x then
            n = n + 1
            local pin = rarePins[n]
            if not pin then
              pin = onFrame(cv)
              pin.tex = pin:CreateTexture(nil, "ARTWORK")
              pin.tex:SetAllPoints()
              pin.tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
              pin:EnableMouse(true)
              if pin.SetMouseClickEnabled then pin:SetMouseClickEnabled(false) end
              pin:SetScript("OnEnter", rareTip)
              pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
              rarePins[n] = pin
              ours[pin] = true
            end
            local size = (needed and 18 or 14) / scale
            pin:SetParent(cv)
            pin:SetFrameLevel(math.max(1, level))
            pin:SetSize(size, size)
            pin.tex:SetVertexColor(1, needed and 0.35 or 1, needed and 0.35 or 1)
            pin.rare = npc
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", cv, "TOPLEFT", x * w, -y * h)
            pin:Show()
          end
          end
        end
      end
    end
  end
end

-- ------------------------------------------------------------------ gathering (Gather.lua)
-- The herb and ore nodes the tracked list still needs, on a zone's map: the game's Find Herbs and Find Minerals icons,
-- grey where your skill is too low. Not on the joined-up views
local GATHER_ICON = { herb = "Interface\\Icons\\INV_Misc_Flower_02", mine = "Interface\\Icons\\Spell_Nature_Earthquake" }
local gatherPins = {}
local function gatherTip(self)
  local k = self.kind and ns.gatherKinds[self.kind]
  if not (k or self.name) then return end
  local p = k and k[4] or self.p
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(k and k[1] or self.name, 1, 1, 1)
  GameTooltip:AddLine(k and ("%s %d"):format(p == "herb" and "Herbalism" or "Mining", k[5]) or (p == "herb" and "Herbalism" or "Mining"), 0.7, 0.7, 0.7)
  if self.gathered then GameTooltip:AddLine("You gathered here", 0.6, 0.8, 1) end
  if not self.ok then GameTooltip:AddLine(k and "Your skill is too low for it" or "You don't have the skill", 1, 0.45, 0.45) end
  GameTooltip:Show()
end
-- a node's icon: herb or ore by our kind, else by the sort a gathered one was (p)
local function gatherIcon(tex, kind, ok, p)
  local k = ns.gatherKinds[kind]
  tex:SetTexture(GATHER_ICON[k and k[4] or p or "herb"])
  tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  if tex.SetDesaturated then tex:SetDesaturated(not ok) end
  tex:SetAlpha(ok and 1 or 0.6)
end
function R.drawGatherWorld()
  for _, p in ipairs(gatherPins) do p:Hide() end
  if not (ns.gather and WorldMapFrame and WorldMapFrame:IsShown()) or AuDHDDB.mapHidden then return end
  local cv = canvas()
  local mapID = WorldMapFrame:GetMapID()
  if not (cv and mapID) then return end
  local w, h = cv:GetWidth(), cv:GetHeight()
  if not w or w <= 0 then return end
  local P = placer(mapID)
  if P.wide then return end
  local nodes = ns.gather.nodes(mapID)
  if #nodes == 0 then return end
  local scale = cv:GetScale() or 1
  local level = (spawnFrame and spawnFrame:GetFrameLevel() or above(cv)) - 3
  for n, node in ipairs(nodes) do
    local pin = gatherPins[n]
    if not pin then
      pin = onFrame(cv)
      pin.tex = pin:CreateTexture(nil, "ARTWORK")
      pin.tex:SetAllPoints()
      pin:EnableMouse(true)
      if pin.SetMouseClickEnabled then pin:SetMouseClickEnabled(false) end
      pin:SetScript("OnEnter", gatherTip)
      pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
      gatherPins[n] = pin
      ours[pin] = true
    end
    local size = 14 / scale
    pin:SetParent(cv)
    pin:SetFrameLevel(math.max(1, level))
    pin:SetSize(size, size)
    pin.kind, pin.ok, pin.name, pin.p, pin.gathered = node[3], node[4], node.name, node.p, node.gathered
    gatherIcon(pin.tex, node[3], node[4], node.p)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", cv, "TOPLEFT", node[1] * w, -node[2] * h)
    pin:Show()
  end
end

-- ------------------------------------------------------------------ the rest, as on the detailed map
-- (BigMap.lua): the route's later pick-ups and hand-ins as the game's ! and ? (small, past the numbered steps), the
-- hand-ins of finished quests in your log the route doesn't hand in itself, and the place a guard told you the way to.
-- With the joined-up map also your party or raid, each in a ring: the game draws them on the map underneath only, so a
-- friend in the next zone over would be missing, and its dots don't say party from raid.
local marks, mates, flag, extraFrame = {}, {}, {}, nil
local aheadAt, later = -10, {}
local shown = { marks = 0, log = 0, mates = 0, flag = 0 }
local edgeOf = setmetatable({}, { __mode = "k" })   -- a party dot -> its ring
-- the ring round a group or guild member's dot: blue your party, orange your raid, green your guild
local RING = { party = { 0.3, 0.6, 1 }, raid = { 1, 0.55, 0.1 }, guild = { 0.25, 0.9, 0.3 } }
local function groupRing() return (IsInRaid and IsInRaid()) and RING.raid or RING.party end
R.RING = RING   -- (the smoke test)
local function hoverPin(list, i, parent)
  local f = list[i]
  if f then return f end
  f = onFrame(parent)
  f.icon = f:CreateTexture(nil, "OVERLAY")
  f.icon:SetAllPoints(f)
  -- hover only: clicks go through to the map (and no click script: the gamepad UI takes a frame with one for a button)
  f:EnableMouse(true)
  if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
  f:SetScript("OnEnter", function(self)
    if not (GameTooltip and (self.tip or self.unit)) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.unit then GameTooltip:SetUnit(self.unit) else GameTooltip:SetText(self.tip, 1, 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  list[i] = f
  ours[f] = true
  return f
end
function R.drawExtrasWorld()
  for _, f in ipairs(marks) do f:Hide() end
  for _, f in ipairs(mates) do f:Hide() end
  for _, f in ipairs(flag) do f:Hide() end
  shown.marks, shown.log, shown.mates, shown.flag = 0, 0, 0, 0
  if not (WorldMapFrame and WorldMapFrame:IsShown()) or AuDHDDB.mapHidden then return end
  local cv = canvas()
  local mapID = WorldMapFrame:GetMapID()
  if not (cv and mapID) then return end
  local w, h = cv:GetWidth(), cv:GetHeight()
  if not w or w <= 0 then return end
  local scale = cv:GetScale() or 1
  if not extraFrame then extraFrame = onFrame(cv); ours[extraFrame] = true end
  extraFrame:SetParent(cv)
  extraFrame:SetAllPoints(cv)
  extraFrame:SetFrameLevel(above(cv) + 22)   -- over the route's lines, under its numbered pins
  extraFrame:Show()
  local P = placer(mapID)
  local function put(list, i, x, y, size, level)
    local f = hoverPin(list, i, extraFrame)
    f:SetSize(size / scale, size / scale)
    f:SetFrameLevel(extraFrame:GetFrameLevel() + (level or 1))
    f:ClearAllPoints()
    f:SetPoint("CENTER", cv, "TOPLEFT", x * w, -y * h)
    f.tip, f.unit = nil, nil
    f:SetAlpha(1)
    f:Show()
    return f
  end
  local n = 0
  if ns.questIcon and ns.core.ahead then
    local numbered = {}
    for _, e in ipairs(ahead(WORLD_STEPS)) do numbered[e.of.i or e.of] = true end
    local now = GetTime()
    if now - aheadAt > 3 then aheadAt = now later = ns.core.ahead() or {} end
    local handed = {}
    for _, s in ipairs(later) do
      if s.k == "turnin" and s.q then handed[s.q] = true end
      if n < 200 and not numbered[s.i or s] and (s.k == "accept" or s.k == "turnin") then
        local x, y = P.at(s.m, s.x, s.y)
        if x then
          n = n + 1
          local f = put(marks, n, x, y, 14)
          f.tip = s.t
          ns.questIcon(f.icon, s)
          f:SetAlpha(0.85)
          shown.marks = shown.marks + 1
        end
      end
    end
    local ends = (ns.core.route() or {}).ends or {}
    local ok, count = pcall(C_QuestLog.GetNumQuestLogEntries)
    for li = 1, (ok and count or 0) do
      local info = C_QuestLog.GetInfo(li)
      local q = info and not info.isHeader and info.questID
      local e = q and ends[q]
      if e and e.m and n < 200 and not handed[q] and ns.core.readyToHandIn and ns.core.readyToHandIn(q) then
        local x, y = P.at(e.m, e.x, e.y)
        if x then
          n = n + 1
          local f = put(marks, n, x, y, 16, 2)
          f.tip = ("Turn in %s to %s"):format(e.t or "?", e.n or "?")
          ns.questIcon(f.icon, { k = "turnin", q = q })
          shown.log = shown.log + 1
        end
      end
    end
  end
  -- the guard's flag: the game's own icon (its minimap icon sheet), a gold square if this client can't say which
  local m, gx, gy, name, texIndex
  if ns.guardFlag then m, gx, gy, name, texIndex = ns.guardFlag() end
  local fx, fy = P.at(m, gx, gy)
  if fx then
    local f = put(flag, 1, fx, fy, 20, 3)
    f.tip = name
    local coords = texIndex and ((C_Minimap and C_Minimap.GetPOITextureCoords and { C_Minimap.GetPOITextureCoords(texIndex) })
      or (GetPOITextureCoords and { GetPOITextureCoords(texIndex) }))
    if coords and coords[4] then
      f.icon:SetTexture("Interface\\Minimap\\POIIcons")
      f.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
      f.icon:SetColorTexture(1, 0.82, 0, 1)
    end
    shown.flag = 1
  end
  -- party or raid (joined-up map only): a class-coloured dot each in its ring (black with the rings off), hover for who; on the map underneath
  -- too, over the game's own dot, so every one has the ring
  if P.wide then
    local ring = not AuDHDDB.mapRingsOff and groupRing()
    local raid = IsInRaid and IsInRaid()
    local count = GetNumGroupMembers and GetNumGroupMembers() or 0
    for i = 1, raid and count or count - 1 do
      local u = (raid and "raid" or "party") .. i
      if UnitExists(u) and not (UnitIsUnit and UnitIsUnit(u, "player")) and not (UnitIsConnected and not UnitIsConnected(u)) then
        local um = C_Map.GetBestMapForUnit(u)
        local pos = um and not isSecret(um) and C_Map.GetPlayerMapPosition(um, u)
        local ux, uy
        if pos then ux, uy = pos:GetXY() end
        local x, y
        if ux and not isSecret(ux) then x, y = P.at(um, ux * 100, uy * 100) end
        if x then
          shown.mates = shown.mates + 1
          local f = put(mates, shown.mates, x, y, 14, 4)
          local edge = edgeOf[f]
          if not edge then
            f.icon:SetTexture("Interface\\AddOns\\AuDHD\\SoftOval")
            edge = f:CreateTexture(nil, "BORDER")
            edgeOf[f] = edge
            edge:SetPoint("CENTER")
            edge:SetTexture("Interface\\AddOns\\AuDHD\\SoftOval")
          end
          if ring then edge:SetVertexColor(ring[1], ring[2], ring[3], 1) else edge:SetVertexColor(0, 0, 0, 0.9) end
          edge:SetSize(24 / scale, 24 / scale)
          local _, class = UnitClass(u)
          local col = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
          f.icon:SetVertexColor(col and col.r or 1, col and col.g or 1, col and col.b or 1, 1)
          f.unit = u
        end
      end
    end
  end
end
function R.extrasShown() return shown end

-- ------------------------------------------------------------------ minimap
local miniPins, miniTrail, TRAIL_STEP = {}, {}, 12
-- the minimap as it is now: where you are (world yards, continent), its radius in yards and pixels, how it's turned; nil
-- when it can't say
local function miniView()
  if not Minimap or AuDHDDB.mapHidden then return nil end
  local m = C_Map.GetBestMapForUnit("player")
  if not m or isSecret(m) then return nil end
  local pos = C_Map.GetPlayerMapPosition(m, "player")
  if not pos then return nil end
  local okW, cont, me = pcall(C_Map.GetWorldPosFromMapPos, m, pos)
  if not okW or not me then return nil end
  local v = { cont = cont }
  v.ax, v.ay = me:GetXY()
  local zoom = Minimap:GetZoom() or 0
  local t = (IsIndoors and IsIndoors()) and MINIMAP_YARDS.indoor or MINIMAP_YARDS.outdoor
  v.radiusYards = (t[zoom] or t[0]) / 2
  v.radiusPx = (Minimap:GetWidth() or 140) / 2
  v.facing = GetPlayerFacing and GetPlayerFacing()
  if v.facing and isSecret(v.facing) then v.facing = nil end
  v.rotates = GetCVar("rotateMinimap") == "1"
  return v
end
-- a map spot (0..100) on the minimap, in pixels from its centre, and whether it's beyond the edge (then on the rim, in
-- its direction); nil on another continent
local function miniSpot(v, m, x, y)
  local ok, c2, wpos = pcall(C_Map.GetWorldPosFromMapPos, m, CreateVector2D(x / 100, y / 100))
  if not (ok and wpos and c2 == v.cont) then return nil end
  local bx, by = wpos:GetXY()
  -- world X grows north, Y grows west: east = -(dY), north = dX
  local east, north = -(by - v.ay), bx - v.ax
  local px, py = east, north
  if v.rotates and v.facing then
    local c, s = math.cos(v.facing), math.sin(v.facing)
    px, py = px * c + py * s, -px * s + py * c
  end
  local d = math.sqrt(px * px + py * py)
  local k = v.radiusPx / v.radiusYards
  px, py = px * k, py * k
  if d > v.radiusYards * 0.92 then
    local f = (v.radiusPx - 7) / math.sqrt(px * px + py * py)
    return px * f, py * f, true
  end
  return px, py, false
end
-- a walking way p (Walk.lua) from you on the minimap v: dots every TRAIL_STEP yards from where you are on it, inside the
-- rim (lines can't be cut to a round minimap), from pool, in colour c. How many are out (the rest of pool is hidden)
local function trail(v, p, pool, c)
  local n = 0
  local _, PX, PY = ns.walk.player()
  local k = v.radiusPx / v.radiusYards
  local function place(X, Y)
    local east, north = -(Y - PY), X - PX
    local x, y = east, north
    if v.rotates and v.facing then
      local cs, sn = math.cos(v.facing), math.sin(v.facing)
      x, y = x * cs + y * sn, -x * sn + y * cs
    end
    if x * x + y * y > (v.radiusYards * 0.9) ^ 2 then return false end
    n = n + 1
    local t = pool[n]
    if not t then
      t = Minimap:CreateTexture(nil, "OVERLAY")
      t:SetTexture("Interface\\AddOns\\AuDHD\\Media\\dot")
      t:SetSize(5, 5)
      pool[n] = t
    end
    t:SetVertexColor(c[1], c[2], c[3], 0.95)
    t:ClearAllPoints()
    t:SetPoint("CENTER", Minimap, "CENTER", x * k, y * k)
    t:Show()
    return true
  end
  local pts, j = p.pts, p.at or 1
  if PX and pts[j] then
    local fx, fy, carry = PX, PY, TRAIL_STEP
    while pts[j] and n < 80 do
      local dx, dy = pts[j] - fx, pts[j + 1] - fy
      local seg = math.sqrt(dx * dx + dy * dy)
      local at, out = carry, false
      while at <= seg do
        if not place(fx + dx * at / seg, fy + dy * at / seg) then out = true break end
        at = at + TRAIL_STEP
      end
      if out then break end
      carry = at - seg
      fx, fy = pts[j], pts[j + 1]
      j = j + 2
    end
  end
  for i = n + 1, #pool do pool[i]:Hide() end
  return n
end
function R.drawMinimap()
  for _, p in ipairs(miniPins) do p:Hide() end
  for _, t in ipairs(miniTrail) do t:Hide() end
  local v = miniView()
  if not v then return end
  local groups = {}
  for _, e in ipairs(ahead(MINIMAP_STEPS)) do
    local px, py, edge = miniSpot(v, e.step.m, e.step.x, e.step.y)
    if px then
      local g = stack(groups, e, px, py, 12)
      g.edge = edge
    end
  end
  -- the walking way from you to the step
  local target = ns.core.override or ns.core.target
  local p = target and ns.walk and ns.walk.toStep(target)
  if p then trail(v, p, miniTrail, colourOf(target)) end
  for i, g in ipairs(groups) do
    local pin = miniPins[i]
    if not pin then pin = newPin(Minimap, 14); miniPins[i] = pin end
    pin:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", Minimap, "CENTER", g.px, g.py)
    style(pin, g, 14)
    pin:SetAlpha(g.edge and 0.7 or 1)
    pin:Show()
  end
end

-- a spawn group's points in world yards, worked out once and kept on the group (they never move): continent, x, y each.
-- The minimap redraws five times a second and asking the game for each point every time was most of the addon's time
local function worldOf(group)
  if group.w then return group.w end
  local w, n, p = {}, 0, group.p
  for j = 1, #p - 1, 2 do
    local ok, c2, wpos = pcall(C_Map.GetWorldPosFromMapPos, group.m, CreateVector2D(p[j] / 100, p[j + 1] / 100))
    if ok and wpos and c2 then
      local bx, by = wpos:GetXY()
      w[n + 1], w[n + 2], w[n + 3] = c2, bx, by
      n = n + 3
    end
  end
  group.w = w
  return w
end
R.worldOf = worldOf   -- (the smoke test)

local miniSpawnFrame, miniSpawnTex, nMiniSpawn = nil, {}, 0
function R.drawSpawnsMinimap()
  for i = 1, nMiniSpawn do miniSpawnTex[i]:Hide() end
  nMiniSpawn = 0
  if not Minimap or AuDHDDB.mapHidden then return end
  local mem = members(ns.core.current())
  if #mem == 0 then return end
  local m = C_Map.GetBestMapForUnit("player")
  if not m or isSecret(m) then return end
  local pos = C_Map.GetPlayerMapPosition(m, "player")
  if not pos then return end
  local okW, cont, me = pcall(C_Map.GetWorldPosFromMapPos, m, pos)
  if not okW or not me then return end
  local ax, ay = me:GetXY()
  local zoom = Minimap:GetZoom() or 0
  local t = (IsIndoors and IsIndoors()) and MINIMAP_YARDS.indoor or MINIMAP_YARDS.outdoor
  local radiusYards = (t[zoom] or t[0]) / 2
  local radiusPx = (Minimap:GetWidth() or 140) / 2
  local facing = GetPlayerFacing and GetPlayerFacing()
  if facing and isSecret(facing) then facing = nil end
  local rotates = GetCVar("rotateMinimap") == "1"
  if not miniSpawnFrame then miniSpawnFrame = ns.newFrame("RouteMap", "Frame", nil, Minimap); miniSpawnFrame:SetAllPoints(Minimap) end
  miniSpawnFrame:SetFrameLevel(Minimap:GetFrameLevel() + 3)
  local k = radiusPx / radiusYards
  for mi, mm in ipairs(mem) do
    local c = ns.PALETTE[(mi - 1) % #ns.PALETTE + 1]
    for _, group in ipairs(mm.sp or {}) do
      local w = worldOf(group)
      for j = 1, #w - 2, 3 do
        if w[j] == cont then
          local bx, by = w[j + 1], w[j + 2]
          local x, y = -(by - ay), bx - ax
          if x * x + y * y <= (radiusYards * 0.95) ^ 2 then
            if rotates and facing then
              local cs, sn = math.cos(facing), math.sin(facing)
              x, y = x * cs + y * sn, -x * sn + y * cs
            end
            nMiniSpawn = nMiniSpawn + 1
            local tex = miniSpawnTex[nMiniSpawn]
            -- a target: tiny centre, see-through fill, thin ring, in the objective's colour (objects a little smaller)
            if not tex then tex = miniSpawnFrame:CreateTexture(nil, "OVERLAY"); tex:SetTexture("Interface\\AddOns\\AuDHD\\Media\\target"); miniSpawnTex[nMiniSpawn] = tex end
            tex:SetSize(group.o and 10 or 12, group.o and 10 or 12)
            tex:SetVertexColor(c[1], c[2], c[3], 0.9)
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", Minimap, "CENTER", x * k, y * k)
            tex:Show()
          end
        end
      end
    end
  end
end

-- the gathering nodes near you on the minimap (Gather.lua), in your zone
local gatherMiniFrame, gatherMini, nGatherMini = nil, {}, 0
local gatherSpot = setmetatable({}, { __mode = "k" })   -- a node's point -> its world spot { c, x, y }
function R.drawGatherMinimap()
  for i = 1, nGatherMini do gatherMini[i]:Hide() end
  nGatherMini = 0
  if not (ns.gather and Minimap) or AuDHDDB.mapHidden then return end
  local m = C_Map.GetBestMapForUnit("player")
  if not m or isSecret(m) then return end
  local nodes = ns.gather.nodes(m)
  if #nodes == 0 then return end
  local pos = C_Map.GetPlayerMapPosition(m, "player")
  if not pos then return end
  local okW, cont, me = pcall(C_Map.GetWorldPosFromMapPos, m, pos)
  if not okW or not me then return end
  local ax, ay = me:GetXY()
  local zoom = Minimap:GetZoom() or 0
  local t = (IsIndoors and IsIndoors()) and MINIMAP_YARDS.indoor or MINIMAP_YARDS.outdoor
  local radiusYards = (t[zoom] or t[0]) / 2
  local k = ((Minimap:GetWidth() or 140) / 2) / radiusYards
  local facing = GetPlayerFacing and GetPlayerFacing()
  if facing and isSecret(facing) then facing = nil end
  local rotates = GetCVar("rotateMinimap") == "1"
  if not gatherMiniFrame then gatherMiniFrame = ns.newFrame("RouteMap", "Frame", nil, Minimap); gatherMiniFrame:SetAllPoints(Minimap) end
  gatherMiniFrame:SetFrameLevel(Minimap:GetFrameLevel() + 2)
  for _, node in ipairs(nodes) do
    -- its world spot, worked out once per point (as worldOf above; kept beside it, a gathered one being saved)
    local pt = node[5]
    local s = pt and gatherSpot[pt]
    if not s then
      s = { c = false }
      local ok, c2, wpos = pcall(C_Map.GetWorldPosFromMapPos, m, CreateVector2D(node[1], node[2]))
      if ok and wpos and c2 then s.c = c2; s.x, s.y = wpos:GetXY() end
      if pt then gatherSpot[pt] = s end
    end
    if s.c == cont then
      local bx, by = s.x, s.y
      local x, y = -(by - ay), bx - ax
      if x * x + y * y <= (radiusYards * 0.95) ^ 2 then
        if rotates and facing then
          local cs, sn = math.cos(facing), math.sin(facing)
          x, y = x * cs + y * sn, -x * sn + y * cs
        end
        nGatherMini = nGatherMini + 1
        local tex = gatherMini[nGatherMini]
        if not tex then tex = gatherMiniFrame:CreateTexture(nil, "OVERLAY"); tex:SetSize(12, 12); gatherMini[nGatherMini] = tex end
        gatherIcon(tex, node[3], node[4], node.p)
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", Minimap, "CENTER", x * k, y * k)
        tex:Show()
      end
    end
  end
end

-- ------------------------------------------------------------------ a route another addon sent (SideRoute.lua)
-- Its next stops numbered on the world map in their own colour, joined by the way there (walks and the flights you know:
-- Route.lua's between, far), under ours, and the way from
-- you to its first stop (kept apart from ours: Walk.lua's "side" slot); the next few on the minimap, with a trail to the
-- first. Our route, arrow and trail stay as they are
local SIDE = { 0.78, 0.5, 1 }
local SIDE_WORLD, SIDE_MINIMAP = 15, 5
local FAINT = 0.3   -- a straight line's alpha where no way is known
R.SIDE_WORLD = SIDE_WORLD
local sidePins, sideLines, sideFrame, sideMini, sideTrail = {}, {}, nil, {}, {}
local function sidePin(parent, size)
  local f = newPin(parent, size)
  f:SetScript("OnEnter", function(self)
    local g, r = self.group, ns.sideRoute and ns.sideRoute.current()
    if not (g and r) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(r.name, SIDE[1], SIDE[2], SIDE[3])
    for _, it in ipairs(g.steps) do
      GameTooltip:AddLine(("%d. %s"):format(it.n, it.step.title or "?"), 1, 1, 1, true)
      if it.step.tip then GameTooltip:AddLine(it.step.tip, 0.7, 0.7, 0.7, true) end
    end
    GameTooltip:Show()
  end)
  return f
end
function R.drawSideWorld()
  for _, p in ipairs(sidePins) do p:Hide() end
  for _, l in ipairs(sideLines) do l:Hide() end
  local r = ns.sideRoute and ns.sideRoute.current()
  if not r or not (WorldMapFrame and WorldMapFrame:IsShown()) or AuDHDDB.mapHidden then return end
  local cv = canvas()
  local mapID = WorldMapFrame:GetMapID()
  if not (cv and mapID) then return end
  local w, h = cv:GetWidth(), cv:GetHeight()
  if not w or w <= 0 then return end
  local scale = cv:GetScale() or 1
  if not sideFrame then sideFrame = onFrame(cv); ours[sideFrame] = true end
  local P = placer(mapID)
  local base = above(cv)
  sideFrame:SetParent(cv)
  sideFrame:SetAllPoints(cv)
  sideFrame:SetFrameLevel(base + 18)
  sideFrame:Show()
  local line, pathLine, used = liner(sideFrame, sideLines, cv, w, h, scale, P)
  local size = 16 / scale
  local groups, last, one = {}, nil, nil
  for i = 1, math.min(#r.stops, SIDE_WORLD) do
    local s, prev = r.stops[i], r.stops[i - 1]
    local x, y = P.at(s.m, s.x, s.y)
    if prev then
      -- the way between the two (the travel planner's, however far), else a faint straight line when both are
      -- on this map: the direction only, no way known (yet)
      local p = ns.route and ns.route.between(prev.m, prev.x, prev.y, s.m, s.x, s.y, true)
      if not (p and pathLine(p, 1, SIDE[1], SIDE[2], SIDE[3], 0.8)) and x and last and last.n == i - 1 then
        line(last.x, last.y, x, y, SIDE[1], SIDE[2], SIDE[3], FAINT)
      end
    end
    if x then
      local g = stack(groups, { n = i, step = s }, x * w, y * h, size)
      last = { n = i, x = g.px / w, y = g.py / h }
      if i == 1 then one = last end
    end
  end
  -- you -> its first stop: the walking way from you (the part of it ahead of you), else a faint straight line when that
  -- stop is on this map
  local m = C_Map.GetBestMapForUnit("player")
  local pos = m and not isSecret(m) and C_Map.GetPlayerMapPosition(m, "player")
  if pos then
    local px, py = pos:GetXY()
    local sx, sy = P.at(m, px * 100, py * 100, true)
    local p = ns.walk and ns.walk.toStep(r.stops[1], "side")
    local drawn = false
    if p and sx then
      local k = p.at or 1
      if not p.pts[k] then k = k + 2 end
      local x, y = P.yards(p.c, p.pts[k], p.pts[k + 1])
      if x then line(sx, sy, x, y, SIDE[1], SIDE[2], SIDE[3], 0.8) end
      drawn = pathLine(p, k, SIDE[1], SIDE[2], SIDE[3], 0.8)
    end
    if sx and not drawn and one then line(sx, sy, one.x, one.y, SIDE[1], SIDE[2], SIDE[3], FAINT) end
  end
  for i, g in ipairs(groups) do
    local pin = sidePins[i]
    if not pin then pin = sidePin(cv, size); sidePins[i] = pin; ours[pin] = true end
    pin:SetParent(cv)
    pin:SetFrameLevel(base + 28)
    pin.text:SetScale(1 / scale)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", cv, "TOPLEFT", g.px, -g.py)
    style(pin, g, size, SIDE)
    pin:Show()
  end
  return #groups, used()
end
function R.drawSideMinimap()
  for _, p in ipairs(sideMini) do p:Hide() end
  for _, t in ipairs(sideTrail) do t:Hide() end
  local r = ns.sideRoute and ns.sideRoute.current()
  local v = r and miniView()
  if not v then return end
  -- the walking way from you to its first stop
  local p = ns.walk and ns.walk.toStep(r.stops[1], "side")
  local dots = p and trail(v, p, sideTrail, SIDE) or 0
  local groups = {}
  for i = 1, math.min(#r.stops, SIDE_MINIMAP) do
    local s = r.stops[i]
    local px, py, edge = miniSpot(v, s.m, s.x, s.y)
    if px then
      local g = stack(groups, { n = i, step = s }, px, py, 12)
      g.edge = edge
    end
  end
  for i, g in ipairs(groups) do
    local pin = sideMini[i]
    if not pin then pin = sidePin(Minimap, 12); sideMini[i] = pin end
    pin:SetFrameLevel(Minimap:GetFrameLevel() + 4)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", Minimap, "CENTER", g.px, g.py)
    style(pin, g, 12, SIDE)
    pin:SetAlpha(g.edge and 0.6 or 0.9)
    pin:Show()
  end
  return #groups, dots
end

-- the drawing, protected: an error is logged once (MAP_ERROR, with where it happened) instead of vanishing (the path
-- showed for a split second and never again)
local logged = {}
local function safe(fn, name)
  local ok, err = xpcall(fn, function(e) return tostring(e) .. " | " .. (debugstack and debugstack(2, 6, 0) or "") end)
  if not ok then
    local key = name .. tostring(err):sub(1, 120)
    if not logged[key] and ns.log and ns.log.add then
      logged[key] = true
      ns.log.add("MAP_ERROR", { event = name, err = tostring(err):sub(1, 600) })
    end
  end
end
R.safe = safe

function R.refresh()
  if R.routeBox and R.routeBox() then safe(R.showRouteBox, "routeBox") end   -- (defined below)
  safe(R.drawWorld, "drawWorld")
  safe(R.drawSpawnsWorld, "drawSpawnsWorld")
  safe(R.drawRaresWorld, "drawRaresWorld"); safe(R.drawGatherWorld, "drawGatherWorld"); safe(R.drawExtrasWorld, "drawExtrasWorld"); safe(R.drawSideWorld, "drawSideWorld")
  safe(R.drawMinimap, "drawMinimap")
  safe(R.drawSpawnsMinimap, "drawSpawnsMinimap"); safe(R.drawGatherMinimap, "drawGatherMinimap")
  safe(R.drawSideMinimap, "drawSideMinimap")
end
-- a route another addon sent changed (SideRoute.lua)
function R.refreshSide()
  safe(R.drawSideWorld, "drawSideWorld")
  safe(R.drawSideMinimap, "drawSideMinimap")
end

-- a tick box in the world map's bottom left corner: the route's numbers and lines on that map, on or off, apart from
-- the Settings switch for both maps. Hidden while that switch has the route off on both maps. With OpenMap its button
-- (36 high, 14 up) takes that corner: the box goes above it
local routeBox
local function showRouteBox()
  local wm = WorldMapFrame
  local sc = wm and wm.ScrollContainer
  if not sc then return end
  if not sc.GetFrameLevel then sc = wm end   -- (as Fishing.lua: the map picture's frame, else the map)
  if not routeBox then
    routeBox = ns.newFrame("RouteMap", "CheckButton", "AuDHDWorldRouteBox", sc, "UICheckButtonTemplate")
    routeBox:SetSize(24, 24)
    routeBox:SetPoint("BOTTOMLEFT", sc, "BOTTOMLEFT", 6, _G.OpenMapAPI and 56 or 6)
    routeBox:SetFrameLevel((sc:GetFrameLevel() or 1) + 20)
    routeBox.label = routeBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    routeBox.label:SetPoint("LEFT", routeBox, "RIGHT", 2, 1)
    routeBox.label:SetText("Route")
    routeBox:SetScript("OnClick", function(self)
      AuDHDDB.worldRouteOff = not self:GetChecked() or nil
      safe(R.drawWorld, "drawWorld")
    end)
    routeBox:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText("AuDHD: route")
      GameTooltip:AddLine("The route's numbered steps and the lines between them on this map. The minimap keeps its own", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    routeBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- in the top right corner, under the fishing level (Fishing.lua), a button listing the quests in your log the route
    -- ahead doesn't use (Guide.lua)
    local off = ns.newFrame("RouteMap", "Button", "AuDHDWorldOffRoute", sc, "UIPanelButtonTemplate")
    off:SetSize(130, 22)
    off:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -10, -30)
    off:SetFrameLevel((sc:GetFrameLevel() or 1) + 20)
    off:SetText("Quests off route")
    off:SetScript("OnClick", function() if ns.offRoute then ns.offRoute.toggle() end end)
    off:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetText("AuDHD: quests off route")
      GameTooltip:AddLine("Lists the quests in your log that neither the guide you follow nor any guide after it uses", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    off:SetScript("OnLeave", function() GameTooltip:Hide() end)
    routeBox.off = off
  end
  routeBox:SetChecked(not AuDHDDB.worldRouteOff)
  routeBox:SetShown(not AuDHDDB.mapHidden)
  routeBox.off:SetShown(not AuDHDDB.mapHidden)
end
R.showRouteBox = showRouteBox
R.routeBox = function() return routeBox end   -- (the smoke test)

-- the ring on OpenMap's own dots (S: its map, the global OpenMap's MapStitch): its party and raid, and guild members
-- who share where they are (the dot's data says guild); a friend outside the guild has none. Its pins are pooled per
-- set, so a reused one loses a ring it no longer needs
function R.ringPin(S, set, pin, data)
  if not pin then return end
  local col
  if AuDHDDB.mapRingsOff then col = nil
  elseif set == S.GetPinSet("group") then col = groupRing()
  elseif set == S.GetPinSet("friends") and type(data) == "table" and type(data.p) == "table" and data.p.guild then
    col = RING.guild
  end
  local ring = pin.audhdRing
  if not col then
    if ring then ring:Hide() end
    return
  end
  if not ring then
    ring = pin:CreateTexture(nil, "BORDER")
    ring:SetPoint("CENTER")
    ring:SetTexture("Interface\\AddOns\\AuDHD\\SoftOval")
    pin.audhdRing = ring
  end
  local w = pin:GetWidth() or 12
  ring:SetSize(w + 10, w + 10)
  ring:SetVertexColor(col[1], col[2], col[3], 1)
  ring:Show()
end
-- OpenMap's AddPin wrapped: its pin as before, then the ring (an error logged once and the rings stop, OpenMap goes on)
function R.ringOpenMap()
  local S = _G.OpenMap and _G.OpenMap.MapStitch
  if not (type(S) == "table" and type(S.AddPin) == "function" and type(S.GetPinSet) == "function") or S.audhdRings then return end
  S.audhdRings = true
  local add = S.AddPin
  local failed
  S.AddPin = function(set, u, v, look, data, ...)
    local pin = add(set, u, v, look, data, ...)
    if not failed then
      local ok, err = pcall(R.ringPin, S, set, pin, data)
      if not ok then
        failed = true
        if ns.log and ns.log.add then ns.log.add("MAP_ERROR", { event = "openMapRing", err = tostring(err):sub(1, 600) }) end
      end
    end
    return pin
  end
end

-- redrawn as OpenMap's joined-up view moves (it says so a few times a second at most), not only every half second
local toldOpenMap = false
function R.hookOpenMap()
  local api = _G.OpenMapAPI
  if toldOpenMap or not (api and api.RegisterCallback) then return end
  toldOpenMap = true
  R.ringOpenMap()
  local function redraw()
    if WorldMapFrame and WorldMapFrame:IsShown() then safe(R.drawWorld, "drawWorld"); safe(R.drawSpawnsWorld, "drawSpawnsWorld"); safe(R.drawRaresWorld, "drawRaresWorld"); safe(R.drawGatherWorld, "drawGatherWorld"); safe(R.drawExtrasWorld, "drawExtrasWorld"); safe(R.drawSideWorld, "drawSideWorld") end
  end
  api.RegisterCallback("AuDHD", "OpenMap_ViewChanged", redraw)
  api.RegisterCallback("AuDHD", "OpenMap_StitchedChanged", redraw)
end
function R.enable()
  safe(R.hookOpenMap, "hookOpenMap")
  if WorldMapFrame then
    WorldMapFrame:HookScript("OnShow", function() safe(showRouteBox, "routeBox") end)
    WorldMapFrame:HookScript("OnShow", function() safe(R.drawWorld, "drawWorld"); safe(R.drawSpawnsWorld, "drawSpawnsWorld"); safe(R.drawRaresWorld, "drawRaresWorld"); safe(R.drawGatherWorld, "drawGatherWorld"); safe(R.drawExtrasWorld, "drawExtrasWorld"); safe(R.drawSideWorld, "drawSideWorld") end)
    if WorldMapFrame.OnMapChanged then
      hooksecurefunc(WorldMapFrame, "OnMapChanged", function() safe(R.drawWorld, "drawWorld"); safe(R.drawSpawnsWorld, "drawSpawnsWorld"); safe(R.drawRaresWorld, "drawRaresWorld"); safe(R.drawGatherWorld, "drawGatherWorld"); safe(R.drawExtrasWorld, "drawExtrasWorld"); safe(R.drawSideWorld, "drawSideWorld") end)
    end
  end
  -- the minimap follows you; the world map follows your position (the line from you) and its zoom
  C_Timer.NewTicker(0.2, function() safe(R.drawMinimap, "drawMinimap"); safe(R.drawSpawnsMinimap, "drawSpawnsMinimap"); safe(R.drawGatherMinimap, "drawGatherMinimap"); safe(R.drawSideMinimap, "drawSideMinimap") end)
  C_Timer.NewTicker(0.5, function()
    if WorldMapFrame and WorldMapFrame:IsShown() then safe(R.drawWorld, "drawWorld"); safe(R.drawSpawnsWorld, "drawSpawnsWorld"); safe(R.drawRaresWorld, "drawRaresWorld"); safe(R.drawGatherWorld, "drawGatherWorld"); safe(R.drawExtrasWorld, "drawExtrasWorld"); safe(R.drawSideWorld, "drawSideWorld") end
  end)
end
