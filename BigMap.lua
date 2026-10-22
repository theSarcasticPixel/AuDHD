-- The detailed map: the open world drawn from the game's own minimap pictures (TileData.lua: which picture is which
-- square of the world), in a window you drag to pan and scroll to zoom, with you, the way to your step and the next
-- steps on it. Kalimdor and the Eastern Kingdoms side by side, as on the game's world map (the user, 2026-10-22: "combine
-- both sides of the map into one"). Off until switched on in the settings (Windows); /wfn bigmap or a key (Key Bindings, AuDHD) opens it.
-- Open world only: in a dungeon the game doesn't say where you are.
local ADDON, ns = ...
local B = {}
ns.bigmap = B
BINDING_NAME_AUDHD_BIGMAP = "Detailed map"

local TILE = 1600 / 3          -- yards across a tile
local W, H = 760, 520          -- the window
local ZMIN, ZMAX = 8, 1024     -- a tile's size on screen, zoomed out (the whole world) and in
local frame, view, arrow, label, sea
local tex = {}                 -- the tile textures, by continent * 4096 + col * 64 + row, while on screen
local spare = {}
local missing = {}             -- pictures this client hasn't got
local lines, dots = {}, {}
-- where each continent's 64 x 64 grid sits on the one map: Kalimdor on the left, the Eastern Kingdoms (its tiles
-- start at column 17) two tiles to the right of Kalimdor's last (56)
local OFF = { [1] = { 0, 0 }, [0] = { 42, 0 } }
local st = { cx = 50, cy = 32, size = 256, follow = true }

local function isOn() return AuDHDDB.bigMap end

-- world (X north, Y west) on continent c to the one map's grid (col, row as fractions)
local function grid(c, X, Y) return 32 - Y / TILE + OFF[c][1], 32 - X / TILE + OFF[c][2] end
-- the grid to the view's pixels
local function px(col, row)
  return (col - st.cx) * st.size + W / 2, (row - st.cy) * st.size + (H - 30) / 2
end

local function drawTiles()
  local want = {}
  local half = (W / 2) / st.size + 1
  local halfH = ((H - 30) / 2) / st.size + 1
  for c = 0, 1 do
    local tiles = ns.tiles and ns.tiles[c]
    local oc, or_ = OFF[c][1], OFF[c][2]
    if tiles then
      for col = math.max(0, math.floor(st.cx - half - oc)), math.min(63, math.floor(st.cx + half - oc)) do
        for row = math.max(0, math.floor(st.cy - halfH - or_)), math.min(63, math.floor(st.cy + halfH - or_)) do
          local id = tiles[col * 64 + row]
          if id then want[c * 4096 + col * 64 + row] = id end
        end
      end
    end
  end
  for k, t in pairs(tex) do
    if not want[k] then t:Hide() spare[#spare + 1] = t tex[k] = nil end
  end
  for k, id in pairs(want) do
    local t = tex[k]
    if not t then
      t = table.remove(spare) or view:CreateTexture(nil, "BACKGROUND")
      tex[k] = t
    end
    -- a picture this client hasn't got: left out (the game would draw it bright green)
    if t.id ~= id and t:SetTexture(id) == false then missing[id] = true end
    t.id = id
    if missing[id] then t:Hide() end
    local c, kk = math.floor(k / 4096), k % 4096
    local col, row = math.floor(kk / 64) + OFF[c][1], kk % 64 + OFF[c][2]
    -- both edges rounded the same way: neighbours meet exactly, no gap and no overlap (a pixel over showed as a grid
    -- of darker lines while the pictures fade, the user 2026-10-22)
    local x0, y0 = px(col, row)
    local x1, y1 = px(col + 1, row + 1)
    x0, y0, x1, y1 = math.floor(x0 + 0.5), math.floor(y0 + 0.5), math.floor(x1 + 0.5), math.floor(y1 + 0.5)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", view, "TOPLEFT", x0, -y0)
    t:SetSize(math.max(1, x1 - x0), math.max(1, y1 - y0))
    if not missing[id] then t:Show() end
  end
end

-- The game's own painted maps over the minimap pictures (setting "bigMapArtOff" turns them off): zoomed out, the
-- continent maps, fading into the minimap pictures as you zoom in; zoomed in, the city maps of the cities the minimap
-- pictures don't show (inside a mountain, underground, or drawn by the game apart from the ground). Each map is placed
-- by where the game says its corners are in the world (the user, 2026-10-22: "seamless transition from world map to
-- showing the minimap art as you zoom in, and seeing things like iron forge").
local CONTINENTS = { 1414, 1415 }            -- Kalimdor, the Eastern Kingdoms
local CITIES = { 1455, 1458, 1453, 1454 }    -- Ironforge, Undercity, Stormwind, Orgrimmar
local art = {}                               -- [map] = its picture and place, or false
local artTex = {}
local artCount = 0                           -- (the smoke test) pictures drawn last time

local function artOf(m)
  if art[m] ~= nil then return art[m] end
  art[m] = false
  if not (C_Map and ns.walk) then return false end
  local ok, layers = pcall(C_Map.GetMapArtLayers, m)
  local L = ok and type(layers) == "table" and layers[1]
  local ok2, files = pcall(C_Map.GetMapArtLayerTextures, m, 1)
  if not (L and L.layerWidth and L.tileWidth and ok2 and type(files) == "table" and #files > 0) then return false end
  local c0, X0, Y0 = ns.walk.toWorld(m, 0, 0)
  local c1, X1, Y1 = ns.walk.toWorld(m, 100, 100)
  if not (c0 and c0 == c1 and OFF[c0] and X0 and Y0 and X1 and Y1) then return false end
  local col0, row0 = grid(c0, X0, Y0)
  local col1, row1 = grid(c0, X1, Y1)
  art[m] = { c = c0, files = files, w = L.layerWidth, h = L.layerHeight, tw = L.tileWidth, th = L.tileHeight,
             cols = math.ceil(L.layerWidth / L.tileWidth), col0 = col0, row0 = row0,
             sx = (col1 - col0) / L.layerWidth, sy = (row1 - row0) / L.layerHeight }
  return art[m]
end

-- 0 at lo and below, 1 at hi and above (a tile's size on screen), even steps per mouse-wheel turn between
local function ramp(lo, hi)
  if st.size <= lo then return 0 elseif st.size >= hi then return 1 end
  return math.log(st.size / lo) / math.log(hi / lo)
end

-- the squares the minimap pictures cover on continent c, row by row: { row, first col, last col }. The continent's
-- painted map is drawn only there, so its sea and parchment don't cover the other continent (the user, 2026-10-22:
-- "trim around the lands a bit so it isn't overlapping")
local runs = {}
local function runsOf(c)
  if runs[c] then return runs[c] end
  local list, tiles = {}, ns.tiles and ns.tiles[c] or {}
  for row = 0, 63 do
    local from
    for col = 0, 64 do
      local on = col < 64 and tiles[col * 64 + row]
      if on and not from then from = col
      elseif not on and from then list[#list + 1] = { row, from, col - 1 } from = nil end
    end
  end
  runs[c] = list
  return list
end

-- a city's painted map fades out towards its edges (SoftOval.tga), not a box laid on top (the user: "more rounded
-- and not so copy-paste over the top, so it fades in gently")
-- A continent's goes through its land mask (LandMask0/1.tga, tools/make_land_masks.mjs: the squares with a minimap
-- picture, blurred), so its painted sea fades into ours along the coast (the user: "we want it to all look seamless
-- and not so blocky"). One mask per key, laid over the view's pixels x0, y0 to x1, y1.
local masks = {}
local function maskFor(key, file, x0, y0, x1, y1)
  if masks[key] == nil then
    masks[key] = false
    if view.CreateMaskTexture then
      local k = view:CreateMaskTexture()
      if k then
        k:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\" .. file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        masks[key] = k
      end
    end
  end
  local k = masks[key]
  if k then
    k:ClearAllPoints()
    k:SetPoint("TOPLEFT", view, "TOPLEFT", x0, -y0)
    k:SetSize(math.max(1, x1 - x0), math.max(1, y1 - y0))
  end
  return k or nil
end

local n   -- the art textures used in this pass
-- the part of map A's picture inside the grid box (g0x, g0y)-(g1x, g1y), cut along the picture's own tiles
local function drawPart(A, g0x, g0y, g1x, g1y, alpha, sub, mask)
  local ax0, ay0 = math.max(0, (g0x - A.col0) / A.sx), math.max(0, (g0y - A.row0) / A.sy)
  local ax1, ay1 = math.min(A.w, (g1x - A.col0) / A.sx), math.min(A.h, (g1y - A.row0) / A.sy)
  if ax1 <= ax0 or ay1 <= ay0 then return end
  local s0x, s0y = px(A.col0 + ax0 * A.sx, A.row0 + ay0 * A.sy)
  local s1x, s1y = px(A.col0 + ax1 * A.sx, A.row0 + ay1 * A.sy)
  if s1x <= 0 or s0x >= W or s1y <= 0 or s0y >= H - 30 then return end
  for tr = math.floor(ay0 / A.th), math.ceil(ay1 / A.th) - 1 do
    for tc = math.floor(ax0 / A.tw), math.ceil(ax1 / A.tw) - 1 do
      local id = A.files[tr * A.cols + tc + 1]
      if id and not missing[id] then
        local x0, y0 = math.max(ax0, tc * A.tw), math.max(ay0, tr * A.th)
        local x1, y1 = math.min(ax1, (tc + 1) * A.tw), math.min(ay1, (tr + 1) * A.th)
        local p0x, p0y = px(A.col0 + x0 * A.sx, A.row0 + y0 * A.sy)
        local p1x, p1y = px(A.col0 + x1 * A.sx, A.row0 + y1 * A.sy)
        -- both edges rounded the same way, so neighbouring parts meet without a seam or an overlap
        p0x, p0y, p1x, p1y = math.floor(p0x + 0.5), math.floor(p0y + 0.5), math.floor(p1x + 0.5), math.floor(p1y + 0.5)
        if p1x > 0 and p0x < W and p1y > 0 and p0y < H - 30 and p1x > p0x and p1y > p0y then
          n = n + 1
          local t = artTex[n]
          if not t then t = view:CreateTexture(nil, "BACKGROUND") artTex[n] = t end
          if t.id ~= id and t:SetTexture(id) == false then missing[id] = true end
          t.id = id
          t:SetDrawLayer("BACKGROUND", sub)
          t:SetTexCoord((x0 - tc * A.tw) / A.tw, (x1 - tc * A.tw) / A.tw, (y0 - tr * A.th) / A.th, (y1 - tr * A.th) / A.th)
          t:ClearAllPoints()
          t:SetPoint("TOPLEFT", view, "TOPLEFT", p0x, -p0y)
          t:SetSize(p1x - p0x, p1y - p0y)
          t:SetAlpha(alpha)
          if t.mask ~= mask then
            if t.mask and t.RemoveMaskTexture then t:RemoveMaskTexture(t.mask) end
            if mask and t.AddMaskTexture then t:AddMaskTexture(mask) end
            t.mask = mask
          end
          if missing[id] then t:Hide() else t:Show() end
        end
      end
    end
  end
end

local SEA = 24   -- grid squares per repeat of the sea texture

local function drawArt()
  n = 0
  local a = AuDHDDB.bigMapArtOff and 0 or 1 - ramp(24, 80)
  -- the minimap pictures fade out as the painted continents fade in (solid until halfway), so the ones the painted
  -- maps don't cover (Quel'Thalas, the edge below Kalimdor) don't stand out (only when both painted maps are there)
  local both = a > 0 and artOf(CONTINENTS[1]) and artOf(CONTINENTS[2])
  local fade = both and math.min(1, (1 - a) * 2) or 1
  -- the sea moves with the map; it turns black as the pictures (whose sea is black) fade in, so it doesn't flip
  -- between black where there's a picture and green where there isn't (the user, 2026-10-22)
  local seaAlpha = both and 1 - fade or a
  if sea then
    if seaAlpha > 0 then
      local u0, v0 = (st.cx - (W / 2) / st.size) / SEA, (st.cy - ((H - 30) / 2) / st.size) / SEA
      sea:SetTexCoord(u0, u0 + W / st.size / SEA, v0, v0 + (H - 30) / st.size / SEA)
      sea:SetAlpha(seaAlpha)
      sea:Show()
    else
      sea:Hide()
    end
  end
  if not AuDHDDB.bigMapArtOff then
    if a > 0 then
      for _, m in ipairs(CONTINENTS) do
        local A = artOf(m)
        if A then
          local o = OFF[A.c]
          local x0, y0 = px(o[1], o[2])
          local x1, y1 = px(o[1] + 64, o[2] + 64)
          local mask = maskFor("land" .. A.c, "LandMask" .. A.c, x0, y0, x1, y1)
          if mask then
            drawPart(A, A.col0, A.row0, A.col0 + A.w * A.sx, A.row0 + A.h * A.sy, a, 2, mask)
          else
            -- (no masks in this client: the squares with a picture, hard-edged)
            for _, r in ipairs(runsOf(A.c)) do
              drawPart(A, r[2] + o[1], r[1] + o[2], r[3] + 1 + o[1], r[1] + 1 + o[2], a, 2)
            end
          end
        end
      end
    end
    local b = ramp(40, 90)
    if b > 0 then
      for _, m in ipairs(CITIES) do
        local A = artOf(m)
        if A then
          local g1x, g1y = A.col0 + A.w * A.sx, A.row0 + A.h * A.sy
          local x0, y0 = px(A.col0, A.row0)
          local x1, y1 = px(g1x, g1y)
          if x1 > 0 and x0 < W and y1 > 0 and y0 < H - 30 then
            drawPart(A, A.col0, A.row0, g1x, g1y, b, 3, maskFor(m, "SoftOval", x0, y0, x1, y1))
          end
        end
      end
    end
  end
  for i = n + 1, #artTex do artTex[i]:Hide() end
  artCount = n
  for _, t in pairs(tex) do t:SetAlpha(fade) end
end

-- the way to your step (Walk.lua's path, world yards) and the next steps as numbered dots
local function drawRoute(c)   -- c: the continent you're on
  for _, l in ipairs(lines) do l:Hide() end
  for _, d in ipairs(dots) do d:Hide() end
  if not (ns.core and ns.walk) then return end
  local n = 0
  local function line(x1, y1, x2, y2, r, g, b)
    n = n + 1
    local l = lines[n]
    if not l then l = view:CreateLine(nil, "ARTWORK") lines[n] = l end
    l:SetColorTexture(r, g, b, 0.9)
    l:SetThickness(3)
    l:SetStartPoint("TOPLEFT", view, x1, -y1)
    l:SetEndPoint("TOPLEFT", view, x2, -y2)
    l:Show()
  end
  local step = ns.core.current()
  local p = step and ns.walk.toStep(step)
  if p and p.pts and c then
    -- from the corner you're heading for (p.at, an index into pts); a gap (nil) is a flight or a boat: no line
    local lx, ly
    for i = p.at or 1, #p.pts - 1, 2 do
      if p.pts[i] and p.pts[i + 1] then
        local x, y = px(grid(c, p.pts[i], p.pts[i + 1]))
        if lx then line(lx, ly, x, y, 1, 0.82, 0) end
        lx, ly = x, y
      else
        lx = nil
      end
    end
  end
  local k = 0
  for i = 0, 8 do
    local s = ns.core.peek(i)
    if not s then break end
    local sc, X, Y
    if s.m and s.x and s.y then sc, X, Y = ns.walk.toWorld(s.m, s.x, s.y) end
    if (sc == 0 or sc == 1) and X then
      k = k + 1
      local d = dots[k]
      if not d then
        d = ns.newFrame("BigMap", "Frame", nil, view)
        d:SetSize(18, 18)
        d.bg = d:CreateTexture(nil, "OVERLAY")
        d.bg:SetAllPoints(d)
        d.bg:SetColorTexture(0, 0, 0, 0.75)
        d.text = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        d.text:SetPoint("CENTER")
        dots[k] = d
      end
      local x, y = px(grid(sc, X, Y))
      d:ClearAllPoints()
      d:SetPoint("CENTER", view, "TOPLEFT", x, -y)
      d.text:SetText(i == 0 and "|cffffd100>|r" or tostring(i))
      d:SetFrameLevel(view:GetFrameLevel() + 5)
      d:Show()
    end
  end
end

local last = { at = 0 }
local function update(force)
  local c, X, Y
  if ns.walk then c, X, Y = ns.walk.player() end
  local here = (c == 0 or c == 1) and X and Y
  st.mine = here and c or nil
  if here then
    label:SetText("")
    local col, row = grid(c, X, Y)
    if st.follow then st.cx, st.cy = col, row end
    local x, y = px(col, row)
    arrow:ClearAllPoints()
    arrow:SetPoint("CENTER", view, "TOPLEFT", x, -y)
    if GetPlayerFacing then arrow:SetRotation(GetPlayerFacing() or 0) end
    arrow:Show()
  else
    -- in a dungeon or on a boat: the game doesn't say where
    label:SetText("Not on the open world map here")
    arrow:Hide()
  end
  if force or st.cx ~= last.cx or st.cy ~= last.cy or st.size ~= last.size then
    last.cx, last.cy, last.size = st.cx, st.cy, st.size
    drawTiles()
    drawArt()
    force = true
  end
  -- the route moves with the map, and is worked out again twice a second
  local now = GetTime()
  if force or now - last.at > 0.5 then last.at = now drawRoute(st.mine) end
end

local function create()
  frame = ns.newFrame("BigMap", "Frame", "AuDHDBigMap", UIParent, "BackdropTemplate")
  frame:SetSize(W + 16, H + 16)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("HIGH")
  frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                      tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  frame:SetBackdropColor(0, 0, 0, 0.95)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("Detailed map")
  local close = ns.newFrame("BigMap", "Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function() frame:Hide() end)
  local me = ns.newFrame("BigMap", "Button", nil, frame, "UIPanelButtonTemplate")
  me:SetSize(110, 20)
  me:SetPoint("RIGHT", close, "LEFT", -4, 0)
  me:SetText("Center on me")
  me:SetScript("OnClick", function() st.follow = true update(true) end)
  -- the game's own map (the world map key opens this one while it replaces it)
  local game = ns.newFrame("BigMap", "Button", nil, frame, "UIPanelButtonTemplate")
  game:SetSize(90, 20)
  game:SetPoint("RIGHT", me, "LEFT", -4, 0)
  game:SetText("Game map")
  game:SetScript("OnClick", function()
    frame:Hide()
    if ToggleWorldMap then ToggleWorldMap() elseif WorldMapFrame then WorldMapFrame:Show() end
  end)
  -- the map itself: drag to pan (the window moves by its title bar), scroll to zoom where the cursor is
  view = ns.newFrame("BigMap", "Frame", nil, frame)
  view:SetPoint("TOPLEFT", 8, -38)
  view:SetSize(W, H - 30)
  if view.SetClipsChildren then view:SetClipsChildren(true) end
  view:EnableMouse(true)
  view:EnableMouseWheel(true)
  local bg = view:CreateTexture(nil, "BACKGROUND", nil, -8)
  bg:SetAllPoints(view)
  bg:SetColorTexture(0, 0, 0, 1)   -- where there's no tile: the sea, black as the game's own tiles draw it
  -- zoomed out, with the painted maps: a mottled sea (Sea.tga) so the land sits in one map (the user, 2026-10-22: "a
  -- more neutral colour that makes it look more like it's all part of one map, rather than the black blocks")
  sea = view:CreateTexture(nil, "BACKGROUND", nil, -7)
  sea:SetAllPoints(view)
  sea:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Sea", "REPEAT", "REPEAT")
  sea:Hide()
  arrow = view:CreateTexture(nil, "OVERLAY")
  arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
  arrow:SetSize(28, 28)
  label = view:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("TOP", 0, -8)
  local drag
  view:SetScript("OnMouseDown", function(_, b)
    if b ~= "LeftButton" then return end
    local x, y = GetCursorPosition()
    drag = { x = x, y = y, cx = st.cx, cy = st.cy, s = view:GetEffectiveScale() }
  end)
  view:SetScript("OnMouseUp", function() drag = nil end)
  view:SetScript("OnMouseWheel", function(_, d)
    local old = st.size
    st.size = math.max(ZMIN, math.min(ZMAX, st.size * (d > 0 and 1.25 or 0.8)))
    -- the spot under the cursor stays under it (unless the map follows you)
    if not st.follow then
      local x, y = GetCursorPosition()
      local s = view:GetEffectiveScale()
      local l, t = view:GetLeft(), view:GetTop()
      if l and t then
        local mx, my = x / s - l - W / 2, t - y / s - (H - 30) / 2
        st.cx = st.cx + mx / old - mx / st.size
        st.cy = st.cy + my / old - my / st.size
      end
    end
    AuDHDDB.bigMapZoom = st.size
    update(true)
  end)
  local title2 = ns.newFrame("BigMap", "Frame", nil, frame)
  title2:SetPoint("TOPLEFT", 0, 0)
  title2:SetPoint("TOPRIGHT", -240, 0)
  title2:SetHeight(32)
  title2:EnableMouse(true)
  title2:RegisterForDrag("LeftButton")
  title2:SetScript("OnDragStart", function() frame:StartMoving() end)
  title2:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
  local wait = 0
  frame:SetScript("OnUpdate", function(_, dt)
    if drag then
      local x, y = GetCursorPosition()
      st.cx = drag.cx - (x - drag.x) / drag.s / st.size
      st.cy = drag.cy + (y - drag.y) / drag.s / st.size
      if math.abs(x - drag.x) + math.abs(y - drag.y) > 4 then st.follow = false end
    end
    wait = wait - dt
    if wait > 0 and not drag then return end
    wait = 0.05
    update()
  end)
  st.size = AuDHDDB.bigMapZoom or 256
  if UISpecialFrames then table.insert(UISpecialFrames, "AuDHDBigMap") end
  frame:Hide()
end

function B.show()
  if not isOn() then return false end
  if not frame then create() end
  frame:Show()
  update(true)
  return true
end
function B.toggle()
  if frame and frame:IsShown() then frame:Hide() return true end
  return B.show()
end
function AuDHD_ToggleBigMap() B.toggle() end
function B.isOn() return isOn() and true or false end
function B.set(on)
  AuDHDDB.bigMap = on or nil
  if not on and frame then frame:Hide() end
  if B.bindKeys then B.bindKeys() end
end
-- instead of the world map: your world map key (M) opens this one (setting "bigMapReplace"); the game's map is still
-- one click away (Game map) and opens as always from its other buttons. Key bindings can't change in combat: then
-- it waits for the fight to end.
local keys = ns.newFrame("BigMap", "Frame")
local keysTag
local function bindKeys()
  if InCombatLockdown() then keys.later = true return end
  keys.later = nil
  local list = {}
  if isOn() and AuDHDDB.bigMapReplace and GetBindingKey then list = { GetBindingKey("TOGGLEWORLDMAP") } end
  local tag = table.concat(list, ",")
  if tag == keysTag then return end   -- (setting them sends UPDATE_BINDINGS again)
  keysTag = tag
  ClearOverrideBindings(keys)
  for _, k in ipairs(list) do SetOverrideBinding(keys, false, k, "AUDHD_BIGMAP") end
end
B.bindKeys = bindKeys
for _, e in ipairs({ "PLAYER_LOGIN", "UPDATE_BINDINGS", "PLAYER_REGEN_ENABLED" }) do keys:RegisterEvent(e) end
keys:SetScript("OnEvent", function(_, e)
  if e == "PLAYER_REGEN_ENABLED" and not keys.later then return end
  bindKeys()
end)
function B.artOn() return not AuDHDDB.bigMapArtOff end
function B.setArt(on)
  AuDHDDB.bigMapArtOff = not on or nil
  if frame and frame:IsShown() then update(true) end
end
function B.replaces() return isOn() and AuDHDDB.bigMapReplace and true or false end
function B.setReplace(on)
  AuDHDDB.bigMapReplace = on or nil
  bindKeys()
end

-- (the smoke test) the tiles on screen now
function B.shown()
  local n = 0
  for _ in pairs(tex) do n = n + 1 end
  return n, st.mine, st.cx and math.floor(st.cx), st.cy and math.floor(st.cy)
end
function B.artShown() return artCount end

-- /wfn bigmap [on|off|replace on|off]
function B.command(arg)
  arg = (arg or ""):lower()
  local r = arg:match("^replace%s*(%a*)$")
  if r then
    if r == "on" or r == "off" then B.setReplace(r == "on") end
    return "the world map key opens the " .. (B.replaces() and "detailed map" or "game's map")
  end
  if arg == "on" or arg == "off" then B.set(arg == "on") return "detailed map: " .. arg end
  if not isOn() then return "the detailed map is off: switch it on in the settings (Windows) or /wfn bigmap on" end
  B.toggle()
end
