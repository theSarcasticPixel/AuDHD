-- The route ahead on the maps, so you know which way you're heading while you work:
-- * World map: the next steps as numbered pins (1 = the step you're on), joined by the walking way in route order (each
--   stretch in the colour of the step it leads to), with the way from you to step 1. Steps on another map show when the map you're looking at contains them.
-- * Minimap: the next few steps as numbered dots; one beyond the minimap's edge sits on the rim in its direction.
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
-- places. Camps: the guide's own spawn spots, a ring per group of spawns. Or, Settings > Maps, a dot for every spawn of
-- the goal's mobs or objects (SpawnData.lua), the camps when that has none. Every open objective's, wherever the arrow
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
    out[i] = { sp = goal and ((each and everySpawn(goal)) or camps(goal)) or nil }
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
-- steps at (nearly) the same spot share one pin: a pill wide enough for all their numbers, coloured by the first
local function style(pin, group, size)
  local c = COLOURS[group.step.k] or OTHER
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
  -- (the joined-up map's art is a frame on the canvas with its layers above it: Atlas.lua)
  if ns.atlas and ns.atlas.top() > top then top = ns.atlas.top() end
  return math.min(top, 9000)
end
-- where things go: 0..1 of the map underneath. With the joined-up map showing, everything in view counts, the parts
-- in its neighbours too (Atlas.lua: the map underneath is only the zone in the middle); else what's on the map itself.
-- at(m, x, y[, any]): a map spot (0..100), nil when out of view (any: anywhere); yards(c, X, Y): world yards;
-- inView(x, y)
local function placer(mapID)
  local P = {}
  local x0, y0, x1, y1
  if ns.atlas and ns.atlas.shown() then x0, y0, x1, y1 = ns.atlas.viewOnHost(0.1) end
  if x0 then
    P.wide = true
    function P.inView(x, y) return x and y and x >= x0 and x <= x1 and y >= y0 and y <= y1 or false end
    function P.yards(c, X, Y) return ns.atlas.yardsToHost(c, X, Y) end
    function P.at(m, x, y, any)
      if not (ns.walk and m and x and y) then return nil end
      local c, X, Y = ns.walk.toWorld(m, x, y)
      local fx, fy = ns.atlas.yardsToHost(c, X, Y)
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
  local placed, nLines = {}, 0
  local function line(x1, y1, x2, y2, r, g, b, a)
    nLines = nLines + 1
    local l = lines[nLines]
    if not l then l = lineFrame:CreateLine(nil, "ARTWORK"); lines[nLines] = l end
    l:SetColorTexture(r, g, b, a)
    l:SetThickness(3 / scale)
    l:SetStartPoint("TOPLEFT", cv, x1 * w, -y1 * h)
    l:SetEndPoint("TOPLEFT", cv, x2 * w, -y2 * h)
    l:Show()
  end
  -- a walking path (Walk.lua: { c, pts } in world yards) on this map, from point k on; false if it can't be placed
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

-- ------------------------------------------------------------------ the rest, as on the detailed map
-- (BigMap.lua): the route's later pick-ups and hand-ins as the game's ! and ? (small, past the numbered steps), the
-- hand-ins of finished quests in your log the route doesn't hand in itself, and the place a guard told you the way to.
-- With the joined-up map also your party or raid where the game's own dots don't reach: it draws them on the map
-- underneath only, so a friend in the next zone over would be missing.
local marks, mates, flag, extraFrame = {}, {}, {}, nil
local aheadAt, later = -10, {}
local shown = { marks = 0, log = 0, mates = 0, flag = 0 }
local edgeOf = setmetatable({}, { __mode = "k" })   -- a party dot -> its black edge
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
-- the unit's map is the one underneath or inside it: the game draws its own dot there
local function under(m, host)
  for _ = 1, 5 do
    if not m then return false end
    if m == host then return true end
    local mi = C_Map.GetMapInfo and C_Map.GetMapInfo(m)
    m = mi and mi.parentMapID
  end
  return false
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
  -- party or raid beyond the map underneath (joined-up map only): a class-coloured dot each, hover for who
  if P.wide then
    local raid = IsInRaid and IsInRaid()
    local count = GetNumGroupMembers and GetNumGroupMembers() or 0
    for i = 1, raid and count or count - 1 do
      local u = (raid and "raid" or "party") .. i
      if UnitExists(u) and not (UnitIsUnit and UnitIsUnit(u, "player")) and not (UnitIsConnected and not UnitIsConnected(u)) then
        local um = C_Map.GetBestMapForUnit(u)
        local pos = um and not isSecret(um) and not under(um, mapID) and C_Map.GetPlayerMapPosition(um, u)
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
            edge:SetVertexColor(0, 0, 0, 0.9)
          end
          edge:SetSize(20 / scale, 20 / scale)
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
function R.drawMinimap()
  for _, p in ipairs(miniPins) do p:Hide() end
  for _, t in ipairs(miniTrail) do t:Hide() end
  if not Minimap or AuDHDDB.mapHidden then return end
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
  local groups = {}
  for _, e in ipairs(ahead(MINIMAP_STEPS)) do
    local ok, c2, wpos = pcall(C_Map.GetWorldPosFromMapPos, e.step.m, CreateVector2D(e.step.x / 100, e.step.y / 100))
    if ok and wpos and c2 == cont then
      local bx, by = wpos:GetXY()
      -- world X grows north, Y grows west: east = -(dY), north = dX
      local east, north = -(by - ay), bx - ax
      local x, y = east, north
      if rotates and facing then
        local c, s = math.cos(facing), math.sin(facing)
        x, y = x * c + y * s, -x * s + y * c
      end
      local d = math.sqrt(x * x + y * y)
      local k = radiusPx / radiusYards
      local px, py = x * k, y * k
      local edge = false
      if d > radiusYards * 0.92 then            -- beyond the edge: on the rim, in its direction
        local f = (radiusPx - 7) / math.sqrt(px * px + py * py)
        px, py, edge = px * f, py * f, true
      end
      local g = stack(groups, e, px, py, 12)
      g.edge = edge
    end
  end
  -- the walking way from you to the step: dots every STEP yards, inside the rim (lines can't be cut to a round minimap)
  local nTrail = 0
  local target = ns.core.override or ns.core.target
  local p = target and ns.walk and ns.walk.toStep(target)
  if p then
    local _, PX, PY = ns.walk.player()
    local k = radiusPx / radiusYards
    local function place(X, Y)
      local east, north = -(Y - PY), X - PX
      local x, y = east, north
      if rotates and facing then
        local c, s = math.cos(facing), math.sin(facing)
        x, y = x * c + y * s, -x * s + y * c
      end
      if x * x + y * y > (radiusYards * 0.9) ^ 2 then return false end
      nTrail = nTrail + 1
      local t = miniTrail[nTrail]
      if not t then
        t = Minimap:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\AddOns\\AuDHD\\Media\\dot")
        t:SetSize(5, 5)
        miniTrail[nTrail] = t
      end
      local tc = colourOf(target)
      t:SetVertexColor(tc[1], tc[2], tc[3], 0.95)
      t:ClearAllPoints()
      t:SetPoint("CENTER", Minimap, "CENTER", x * k, y * k)
      t:Show()
      return true
    end
    local pts, j = p.pts, p.at or 1
    if PX and pts[j] then
      local fx, fy, carry = PX, PY, TRAIL_STEP
      while pts[j] and nTrail < 80 do
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
  end
  for i = nTrail + 1, #miniTrail do miniTrail[i]:Hide() end
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
      local p = group.p
      for j = 1, #p - 1, 2 do
        local ok, c2, wpos = pcall(C_Map.GetWorldPosFromMapPos, group.m, CreateVector2D(p[j] / 100, p[j + 1] / 100))
        if ok and wpos and c2 == cont then
          local bx, by = wpos:GetXY()
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
  safe(R.drawRaresWorld, "drawRaresWorld"); safe(R.drawExtrasWorld, "drawExtrasWorld")
  safe(R.drawMinimap, "drawMinimap")
  safe(R.drawSpawnsMinimap, "drawSpawnsMinimap")
end

-- a tick box in the world map's bottom left corner: the route's numbers and lines on that map, on or off, apart from
-- the Settings switch for both maps. Hidden while that switch has the route off on both maps.
local routeBox
local function showRouteBox()
  local wm = WorldMapFrame
  local sc = wm and wm.ScrollContainer
  if not sc then return end
  if not sc.GetFrameLevel then sc = wm end   -- (as Fishing.lua: the map picture's frame, else the map)
  if not routeBox then
    routeBox = ns.newFrame("RouteMap", "CheckButton", "AuDHDWorldRouteBox", sc, "UICheckButtonTemplate")
    routeBox:SetSize(24, 24)
    routeBox:SetPoint("BOTTOMLEFT", sc, "BOTTOMLEFT", 6, 6)
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

function R.enable()
  if WorldMapFrame then
    WorldMapFrame:HookScript("OnShow", function() safe(showRouteBox, "routeBox") end)
    WorldMapFrame:HookScript("OnShow", function() safe(R.drawWorld, "drawWorld"); safe(R.drawSpawnsWorld, "drawSpawnsWorld"); safe(R.drawRaresWorld, "drawRaresWorld"); safe(R.drawExtrasWorld, "drawExtrasWorld") end)
    if WorldMapFrame.OnMapChanged then
      hooksecurefunc(WorldMapFrame, "OnMapChanged", function() safe(R.drawWorld, "drawWorld"); safe(R.drawSpawnsWorld, "drawSpawnsWorld"); safe(R.drawRaresWorld, "drawRaresWorld"); safe(R.drawExtrasWorld, "drawExtrasWorld") end)
    end
  end
  -- the minimap follows you; the world map follows your position (the line from you) and its zoom
  C_Timer.NewTicker(0.2, function() safe(R.drawMinimap, "drawMinimap"); safe(R.drawSpawnsMinimap, "drawSpawnsMinimap") end)
  C_Timer.NewTicker(0.5, function()
    if WorldMapFrame and WorldMapFrame:IsShown() then safe(R.drawWorld, "drawWorld"); safe(R.drawSpawnsWorld, "drawSpawnsWorld"); safe(R.drawRaresWorld, "drawRaresWorld"); safe(R.drawExtrasWorld, "drawExtrasWorld") end
  end)
end
