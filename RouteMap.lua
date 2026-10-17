-- The route ahead on the maps, so you know which way you're heading while you work:
-- * World map: the next steps as numbered pins (1 = the step you're on), joined by the walking way in route order (each
--   stretch in the colour of the step it leads to), with the way from you to step 1. Steps on another map show when the map you're looking at contains them.
-- * Minimap: the next few steps as numbered dots; one beyond the minimap's edge sits on the rim in its direction.
-- Our own frames only (pins on the map canvas, one line frame, dots on the minimap): nothing protected.
-- The minimap's size in yards per zoom level is the same table ForeverDB's addon uses.
local _, ns = ...
local R = {}
ns.routemap = R

local WORLD_STEPS, MINIMAP_STEPS = 10, 5
local MINIMAP_YARDS = { outdoor = { [0] = 466.6667, 400, 333.3333, 266.6667, 200, 133.3333 },
                        indoor = { [0] = 300, 240, 180, 120, 80, 50 } }
local COLOURS = { accept = { 1, 0.82, 0 }, turnin = { 0.25, 0.9, 0.25 }, ["do"] = { 1, 0.45, 0.2 } }
local OTHER = { 0.45, 0.7, 1 }
-- a path takes the colour of the step it leads to (the user, 2026-10-16: "so it matches the colour of the step its
-- going to")
local function colourOf(step) return step and COLOURS[step.k] or OTHER end
local isSecret = issecretvalue or function() return false end

-- one colour per objective of the step you're on (the window writes each objective in its colour: the legend)
ns.PALETTE = { { 0.2, 0.85, 1 }, { 1, 0.35, 0.85 }, { 0.6, 1, 0.2 }, { 1, 0.6, 0.15 }, { 0.75, 0.55, 1 }, { 1, 1, 0.35 } }
local function members(step)
  if not step or step.k ~= "do" then return {} end
  return step.mem or {}
end

-- the steps ahead with a place: { step, n } where n = 1 for the step you're on
local function ahead(count)
  local out, k = {}, 0
  while #out < count and k < count + 10 do
    local step = (k == 0) and ns.core.current() or ns.core.peek(k)
    if not step then break end
    if step.m and step.x and step.y then out[#out + 1] = { step = step, n = #out + 1 } end
    k = k + 1
  end
  return out
end

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

local function newPin(parent, size)
  local f = ns.newFrame("RouteMap", "Frame", nil, parent)
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
  -- hover: the steps behind the numbers (the user, 2026-10-16: "show the names of the quests the numbers refer to on
  -- hover"); clicks go through to the map
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
-- opens, and the path drawn just above the canvas went under them a split second later (the user, 2026-10-16)
local ours = {}
local function above(cv)
  local top = cv:GetFrameLevel()
  for _, c in ipairs({ cv:GetChildren() }) do
    if not ours[c] then
      local l = c:GetFrameLevel()
      if l and l > top then top = l end
    end
  end
  return math.min(top, 9000)
end
function R.drawWorld()
  for _, p in ipairs(worldPins) do p:Hide() end
  for _, l in ipairs(lines) do l:Hide() end
  if not (WorldMapFrame and WorldMapFrame:IsShown()) or AuDHDDB.mapHidden then return end
  local cv = canvas()
  local mapID = WorldMapFrame:GetMapID()
  if not (cv and mapID) then return end
  local w, h = cv:GetWidth(), cv:GetHeight()
  if not w or w <= 0 then return end
  local scale = cv:GetScale() or 1
  if not lineFrame then lineFrame = ns.newFrame("RouteMap", "Frame", nil, cv); ours[lineFrame] = true end
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
  -- a walking path (Walk.lua: world yards) on this map, from point k on; false if this map has no transform
  local function pathLine(pts, k, r, g, b, a)
    if not (ns.walk and ns.walk.toMap(mapID, 0, 0)) then return false end
    local px, py
    for i = k or 1, #pts - 1, 2 do
      if pts[i] then
        local x, y = ns.walk.toMap(mapID, pts[i], pts[i + 1])
        if px and not ((px < -0.05 or px > 1.05 or py < -0.05 or py > 1.05) and (x < -0.05 or x > 1.05 or y < -0.05 or y > 1.05)) then
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
    local x, y = onMap(e.step, mapID)
    local before = list[i - 1]
    if i > 1 and not (x and placed[#placed] and placed[#placed].n == e.n - 1) then
      -- one end is off this map: the walking way between them still crosses it (no straight line: we don't know where)
      local p = ns.walk and ns.walk.path(before.step.m, before.step.x, before.step.y, e.step.m, e.step.x, e.step.y)
      local c = colourOf(e.step)
      if p then pathLine(p.pts, 1, c[1], c[2], c[3], 0.85) end
    end
    if x then
      local g = stack(groups, e, x * w, y * h, size)
      local prev = placed[#placed]
      if prev and prev.n == e.n - 1 and prev.g ~= g then
        -- the walking way between the two steps, else a straight line
        local p = ns.walk and ns.walk.path(prev.step.m, prev.step.x, prev.step.y, e.step.m, e.step.x, e.step.y)
        local c = colourOf(e.step)
        if not (p and pathLine(p.pts, 1, c[1], c[2], c[3], 0.85)) then line(prev.x, prev.y, g.px / w, g.py / h, c[1], c[2], c[3], 0.85) end
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
  -- Darnassus, the user 2026-10-16)
  local first = placed[1]
  local target = ns.core.override or ns.core.target or (first and first.n == 1 and first.step)
  local m = C_Map.GetBestMapForUnit("player")
  local pos = target and m and not isSecret(m) and C_Map.GetPlayerMapPosition(m, "player")
  if pos then
    local px, py = pos:GetXY()
    local sx, sy = onMap({ m = m, x = px * 100, y = py * 100 }, mapID)
    -- the walking way from you (the part of it ahead of you), else a straight line
    local p = ns.walk and ns.walk.toStep(target)
    local tc = colourOf(target)
    local drawn = false
    if p and sx then
      local k = p.at or 1
      if not p.pts[k] then k = k + 2 end
      local x, y = ns.walk.toMap(mapID, p.pts[k], p.pts[k + 1])
      -- you to the path's start: in the air, a faint line to where your flight lands
      if x then line(sx, sy, x, y, tc[1], tc[2], tc[3], ns.walk.flying and ns.walk.flying() and 0.35 or 0.9) end
      drawn = pathLine(p.pts, k, tc[1], tc[2], tc[3], 0.9)
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
  if not spawnFrame then spawnFrame = ns.newFrame("RouteMap", "Frame", nil, cv); ours[spawnFrame] = true end
  spawnFrame:SetParent(cv)
  spawnFrame:SetAllPoints(cv)
  spawnFrame:SetFrameLevel(above(cv) + 25)
  spawnFrame:Show()
  local size = 9 / scale
  for mi, mem in ipairs(members(ns.core.current())) do
    local c = ns.PALETTE[(mi - 1) % #ns.PALETTE + 1]
    for _, group in ipairs(mem.sp or {}) do
      if group.m == mapID then
        local p = group.p
        local sz = group.o and size * 0.65 or size   -- objects you pick up: smaller dots
        for k = 1, #p - 1, 2 do
          nSpawn = nSpawn + 1
          local t = spawnDot(spawnFrame, nSpawn)
          t:SetSize(sz, sz)
          t:SetVertexColor(c[1], c[2], c[3], 0.95)
          t:ClearAllPoints()
          t:SetPoint("CENTER", cv, "TOPLEFT", p[k] / 100 * w, -p[k + 1] / 100 * h)
          t:Show()
        end
      end
    end
  end
end

-- ------------------------------------------------------------------ rares' spawn points
-- (the user, 2026-10-16: "add rarespawn locations to the map"): a skull at each spawn point of every rare on the map
-- you're looking at (RareData.lua, from Questie); a red one for a rare the route still needs. Hover: who, what level.
local rarePins = {}
local function rareTip(self)
  local r = self.rare and ns.rareData[self.rare]
  if not r then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(r.n, 1, 0.82, 0)
  local lv = r.lv and (r.lv[1] == r.lv[2] and tostring(r.lv[1]) or (r.lv[1] .. "-" .. r.lv[2])) or "?"
  GameTooltip:AddLine(("Rare%s, level %s"):format(r.e and " elite" or "", lv), 1, 1, 1)
  local route = ns.core.route()
  local w = route and route.rares and route.rares[self.rare]
  if w and not C_QuestLog.IsQuestFlaggedCompleted(w.q) then
    GameTooltip:AddLine("Needed for " .. (C_QuestLog.GetTitleForQuestID(w.q) or ("quest " .. w.q)), 1, 0.3, 0.2)
  end
  GameTooltip:AddLine("A spawn point: it may not be up", 0.6, 0.6, 0.6)
  GameTooltip:Show()
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
  local route = ns.core.route()
  local level = (spawnFrame and spawnFrame:GetFrameLevel() or above(cv)) - 2
  local n = 0
  for npc, r in pairs(ns.rareData) do
    local w8 = route and route.rares and route.rares[npc]
    local needed = w8 and not C_QuestLog.IsQuestFlaggedCompleted(w8.q)
    if needed or AuDHDDB.rares ~= "route" then
      for _, g in ipairs(r.sp) do
        if g.m == mapID then
          for k = 1, #g.p - 1, 2 do
            n = n + 1
            local pin = rarePins[n]
            if not pin then
              pin = ns.newFrame("RouteMap", "Frame", nil, cv)
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
            pin:SetPoint("CENTER", cv, "TOPLEFT", g.p[k] / 100 * w, -g.p[k + 1] / 100 * h)
            pin:Show()
          end
        end
      end
    end
  end
end

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
-- showed for a split second and never again, the user 2026-10-16)
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
  safe(R.drawWorld, "drawWorld")
  safe(R.drawSpawnsWorld, "drawSpawnsWorld")
  safe(R.drawRaresWorld, "drawRaresWorld")
  safe(R.drawMinimap, "drawMinimap")
  safe(R.drawSpawnsMinimap, "drawSpawnsMinimap")
end

function R.enable()
  if WorldMapFrame then
    WorldMapFrame:HookScript("OnShow", function() safe(R.drawWorld, "drawWorld"); safe(R.drawSpawnsWorld, "drawSpawnsWorld"); safe(R.drawRaresWorld, "drawRaresWorld") end)
    if WorldMapFrame.OnMapChanged then
      hooksecurefunc(WorldMapFrame, "OnMapChanged", function() safe(R.drawWorld, "drawWorld"); safe(R.drawSpawnsWorld, "drawSpawnsWorld"); safe(R.drawRaresWorld, "drawRaresWorld") end)
    end
  end
  -- the minimap follows you; the world map follows your position (the line from you) and its zoom
  C_Timer.NewTicker(0.2, function() safe(R.drawMinimap, "drawMinimap"); safe(R.drawSpawnsMinimap, "drawSpawnsMinimap") end)
  C_Timer.NewTicker(0.5, function()
    if WorldMapFrame and WorldMapFrame:IsShown() then safe(R.drawWorld, "drawWorld"); safe(R.drawSpawnsWorld, "drawSpawnsWorld"); safe(R.drawRaresWorld, "drawRaresWorld") end
  end)
end
