-- The joined-up world map: every zone's painted map stitched into one, inside the game's own world map window (its
-- quest log, controls and icons stay as they are). It's a layer on the map's canvas just above the game's own art:
-- zoom runs from the whole world down to the minimap's pictures, panning runs past a map's edge into its neighbours,
-- and once the view is still the map underneath quietly becomes the zone you're looking at, so the quests, the zone
-- name and everything else the game draws match what's on screen.
-- How the zones blend (AtlasData.lua and Atlas\*.tga, made by tools/make_map_art.mjs from the game's own files):
--   * each zone's painting through its own masks: its territory (its land and a little past it, toward its
--     neighbours), then every zone's core over the neighbours' edges; its border colour-matched to the others
--   * where no zone paints, the continents' art turns to plain parchment (land) and the sea texture
--   * the fades are smooth curves over the zoom, each layer coming in over a range of it
--   * further in, the minimap's pictures mix in (partly greyed, warmed to the parchment with a hint of the zone's
--     colour, on land only), shrunk copies of them in the middle zooms, and a paper grain and a soft blur close up
-- The method (a stitched layer in the game's map, zoom levels and scroll extents of its own, the map underneath
-- following the view) follows OpenMap's (MIT licence), built here on the game's own art.
-- Off until switched on (/wfn atlas on, or the settings' Maps tab): the game can't be tried before launch.
local ADDON, ns = ...
local A = ns.atlasData
local M = {}
ns.atlas = M

local DIR = "Interface\\AddOns\\" .. ADDON .. "\\Atlas\\"
local SEA = "Interface\\AddOns\\" .. ADDON .. "\\Sea"
local TILE = 1600 / 3            -- yards across a minimap picture
local ZOOM_STEP = 1.25           -- each wheel notch
local ENTER, LEAVE = 0.9, 0.7    -- the map underneath becomes a zone at this share of its fit zoom; back out below that
local SWITCH_AFTER = 0.6         -- seconds the view is still before the map underneath follows it
local MAXZ = 50                  -- zones (frame levels for each pass)
local RANGE = 4 + 2 * MAXZ + 8   -- frame levels the art needs
local GRAIN_TILE = 14            -- world units a grain tile spans
local UNDER = { [1455] = true, [1458] = true }   -- underground cities: over the minimap's pictures (they show the ground)

local P = A and A.P
local WORLD = A and A.world
local W, H                       -- the world in world units (the world map's art size)
local map, sc, fl
local root, layer = nil, {}
local artLevel
local active, switching, userMoved = false, false, false
local wheelMode, scalingMode
local ourWheel = false           -- the game's map lets its own wheel zoom be turned off (ours is then the wheel's)
local reopen = false             -- the map was closed: its next showing comes back to the view you left
local live                       -- the last view: { u, v, zoom, width, height }
local zones = {}                 -- masked zones, biggest first (each one's rank: its frame level within a pass)
local rank = {}
local built = {}                 -- zone id -> { T = frame, C = frame, B = blur frame, pieces = { key -> textures } }
local cities = {}                -- city id -> frame
local tiles, spare = {}, {}      -- the minimap's pictures on screen, by c * 4096 + col * 64 + row
local tintOf = {}
local explored = {}              -- zone id -> { "x:y" = true }
local errs = {}
local gradeOf = setmetatable({}, { __mode = "k" })    -- texture -> its colour match (the border's copies)
local maskOf = setmetatable({}, { __mode = "k" })     -- a minimap picture's texture -> the land mask on it

local function isOn() return AuDHDDB and AuDHDDB.atlas end
-- work in progress: never tried in game yet, so it says so on the map, when turned on and at its first error
local WIP = "|cffff9933Work in progress:|r the joined-up map hasn't been tested in game yet and may show errors. /wfn atlas off turns it off."
local warned = false
local function report(where, err)
  if errs[where] then return end
  errs[where] = tostring(err)
  if ns.log then pcall(ns.log, "atlas " .. where .. ": " .. tostring(err)) end
  if not warned then
    warned = true
    print("AuDHD: the joined-up map (work in progress) hit an error. /wfn atlas shows it, /wfn atlas off turns the map off.")
  end
end
local function safe(where, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then report(where, err) end
  return ok
end
local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
local function smooth(r, x)
  local t = clamp((x - r[1]) / (r[2] - r[1]), 0, 1)
  return t * t * (3 - 2 * t)
end

-- ------------------------------------------------------------------ geometry: "zoom" 1 = the whole world fits
local function rectOf(id)
  local m = A.maps[id]
  local r = m and m.rect
  if r then return r[1], r[2], r[3], r[4] end
end
local function stitchable(id)
  if not id then return false end
  if id == WORLD then return true end
  local m = A.maps[id]
  return m and m.rect and m.art and (m.type == 2 or m.type == 3) and (m.cont == 0 or m.cont == 1) and true or false
end
local function fitPx() return math.min(sc:GetWidth() / W, sc:GetHeight() / H) end
local function K(id)                          -- the map's canvas units per world unit
  local l, _, r = rectOf(id)
  return A.maps[id].art[1] / ((r - l) * W)
end
local function zoomFor(id, scale) return scale * K(id) / fitPx() end
local function scaleFor(id, zoom) return zoom * fitPx() / K(id) end
local function fitZoom(id)
  local l, t, r, b = rectOf(id)
  return math.min(sc:GetWidth() / ((r - l) * W), sc:GetHeight() / ((b - t) * H)) / fitPx()
end
local function toWorld(id, x, y)
  local l, t, r, b = rectOf(id)
  return l + x * (r - l), t + y * (b - t)
end
local function fromWorld(id, u, v)
  local l, t, r, b = rectOf(id)
  return (u - l) / (r - l), (v - t) / (b - t)
end
local function view()
  local id = map:GetMapID()
  local u, v = toWorld(id, sc:GetCurrentScrollX() or 0.5, sc:GetCurrentScrollY() or 0.5)
  return u, v, zoomFor(id, sc:GetCanvasScale())
end
local function perPx(zoom)
  local px = fitPx() * zoom
  return 1 / (W * px), 1 / (H * px)
end
-- the fades go by how much of the world is in view (its area), so a tall or very wide window fades as a 3:2 one
local function detailK()
  local w, h = sc:GetWidth(), sc:GetHeight()
  if w <= 0 or h <= 0 then return 1 end
  return math.min(w / W, h / H) / math.sqrt(w * h / (W * H))
end
-- a minimap square (col, row as fractions) on continent c to the world
local function gridToWorld(c, col, row)
  local C = A.conts[c]
  local maxY, maxX, minY, minX = C.yards[1], C.yards[2], C.yards[3], C.yards[4]
  local Y, X = (32 - col) * TILE, (32 - row) * TILE
  return C.rect[1] + (maxY - Y) / (maxY - minY) * (C.rect[3] - C.rect[1]), C.rect[2] + (maxX - X) / (maxX - minX) * (C.rect[4] - C.rect[2])
end
local function worldToGrid(c, u, v)
  local C = A.conts[c]
  local maxY, maxX, minY, minX = C.yards[1], C.yards[2], C.yards[3], C.yards[4]
  local Y = maxY - (u - C.rect[1]) / (C.rect[3] - C.rect[1]) * (maxY - minY)
  local X = maxX - (v - C.rect[2]) / (C.rect[4] - C.rect[2]) * (maxX - minX)
  return 32 - Y / TILE, 32 - X / TILE
end
local CONT_MAP = { [0] = 1415, [1] = 1414 }

-- the maps at a world point: the world, its continent, the zone (or city) there
local function chainAt(u, v)
  local chain = { WORLD }
  local ok, info = pcall(C_Map.GetMapInfoAtPosition, WORLD, u, v)
  local cont = ok and info and info.mapID
  if not stitchable(cont) or A.maps[cont].type ~= 2 then return chain end
  chain[#chain + 1] = cont
  local x, y = fromWorld(cont, u, v)
  local ok2, z = pcall(C_Map.GetMapInfoAtPosition, cont, x, y)
  if ok2 and z and z.mapID ~= cont and stitchable(z.mapID) then chain[#chain + 1] = z.mapID end
  return chain
end

-- ------------------------------------------------------------------ placing art in world units
local function place(r, x, y, w, h)
  r:ClearAllPoints()
  r:SetPoint("TOPLEFT", root, "TOPLEFT", x, -y)
  r:SetSize(w, h)
end
local function placeRect(r, l, t, rr, b) place(r, l * W, t * H, (rr - l) * W, (b - t) * H) end
local function newLayer(level)
  local f = CreateFrame("Frame", nil, root)
  f:SetAllPoints(root)
  f:SetFrameLevel(artLevel + level)
  return f
end
local function mask(f, file, l, t, r, b)
  local mk = f:CreateMaskTexture()
  mk:SetTexture(DIR .. file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  placeRect(mk, l, t, r, b)
  return mk
end
local function pow2(n) local p = 1 while p < n do p = p * 2 end return p end

-- a map's art (its tiles, and with `pieces` its exploration pieces over them) into frame f, through masks; each
-- piece's textures kept by its place ("x:y") in `byPiece` to dim the unexplored ones
local function addArt(f, id, masks, pieces, byPiece, sub)
  local m = A.maps[id]
  local l, t, r, b = rectOf(id)
  local aw, ah, tw, th = m.art[1], m.art[2], m.art[3], m.art[4]
  local sx, sy = (r - l) * W / aw, (b - t) * H / ah
  local cols = math.ceil(aw / tw)
  local all = {}
  local function tex(file, x0, y0, w, h, tcw, tch, key)
    local tx = f:CreateTexture(nil, "ARTWORK", nil, sub or 0)
    tx:SetTexture(file, "CLAMP", "CLAMP", "LINEAR")
    tx:SetTexCoord(0, w / tcw, 0, h / tch)
    place(tx, l * W + x0 * sx, t * H + y0 * sy, w * sx, h * sy)
    for _, mk in ipairs(masks) do tx:AddMaskTexture(mk) end
    all[#all + 1] = tx
    if key and byPiece then
      byPiece[key] = byPiece[key] or {}
      table.insert(byPiece[key], tx)
    end
    return tx
  end
  for i = 5, #m.art do
    local k = i - 5
    local x0, y0 = (k % cols) * tw, math.floor(k / cols) * th
    local w, h = math.min(tw, aw - x0), math.min(th, ah - y0)
    if w > 0 and h > 0 then tex(m.art[i], x0, y0, w, h, tw, th) end
  end
  if pieces and m.pieces then
    for _, p in ipairs(m.pieces) do
      local pw, ph, px, py, pc = p[1], p[2], p[3], p[4], p[5]
      local key = px .. ":" .. py
      for i = 6, #p do
        local k = i - 6
        local cx, cy = k % pc, math.floor(k / pc)
        local w, h = math.min(256, pw - cx * 256), math.min(256, ph - cy * 256)
        if w > 0 and h > 0 then tex(p[i], px + cx * 256, py + cy * 256, w, h, pow2(w), pow2(h), key) end
      end
    end
  end
  return all
end

-- ------------------------------------------------------------------ the layers
local function buildBase()
  -- the world's art; the continents' over it, faded well inside their frames
  addArt(layer.world, WORLD, {})
  for c, id in pairs(CONT_MAP) do
    local f = newLayer(1)
    local l, t, r, b = rectOf(id)
    addArt(f, id, { mask(f, "C" .. id, l, t, r, b) })
    layer["cont" .. c] = f
  end
  -- where no zone paints: the sea texture everywhere, the continents' land as plain parchment (land where both the
  -- continent's art and the minimap's pictures say so)
  local mute = newLayer(2)
  local sea = mute:CreateTexture(nil, "BACKGROUND")
  sea:SetTexture(SEA, "REPEAT", "REPEAT")
  placeRect(sea, -0.3, -0.3, 1.3, 1.3)
  sea:SetTexCoord(0, 1.6 * W / P.seaTile, 0, 1.6 * H / P.seaTile)
  for c, id in pairs(CONT_MAP) do
    local l, t, r, b = rectOf(id)
    local paper = mute:CreateTexture(nil, "ARTWORK")
    paper:SetColorTexture(P.paperFill[1], P.paperFill[2], P.paperFill[3])
    placeRect(paper, l, t, r, b)
    paper:AddMaskTexture(mask(mute, "C" .. id .. "L", l, t, r, b))
    local gl, gt = gridToWorld(c, 0, 0)
    local gr, gb = gridToWorld(c, 64, 64)
    paper:AddMaskTexture(mask(mute, "L" .. c, gl, gt, gr, gb))
  end
  layer.mute = mute
  -- the shrunk minimap pictures, on land, under the zones (filling the gaps between them in the middle zooms)
  local lod = newLayer(3)
  local top = math.max(P.defaultTone[1], P.defaultTone[2], P.defaultTone[3])
  for c in pairs(CONT_MAP) do
    local gl, gt = gridToWorld(c, 0, 0)
    local gr, gb = gridToWorld(c, 64, 64)
    local lm = mask(lod, "L" .. c, gl, gt, gr, gb)
    for j = 0, 1 do for i = 0, 1 do
      local tx = lod:CreateTexture(nil, "ARTWORK")
      tx:SetTexture(DIR .. "M" .. c .. "_" .. (j * 2 + i), "CLAMP", "CLAMP", "LINEAR")
      local l, t = gridToWorld(c, i * 32, j * 32)
      local r, b = gridToWorld(c, (i + 1) * 32, (j + 1) * 32)
      placeRect(tx, l, t, r, b)
      tx:AddMaskTexture(lm)
      if tx.SetDesaturation then tx:SetDesaturation(P.miniDesat) end
      local k = {}
      for n = 1, 3 do k[n] = P.paper[n] + (P.defaultTone[n] / top - P.paper[n]) * P.toneShare end
      tx:SetVertexColor(k[1], k[2], k[3])
    end end
  end
  layer.lod = lod
  -- the minimap's pictures (filled in as they come into view), on land
  layer.mini = newLayer(4 + 2 * MAXZ + 2)
  layer.miniMask = {}
  for c in pairs(CONT_MAP) do
    local gl, gt = gridToWorld(c, 0, 0)
    local gr, gb = gridToWorld(c, 64, 64)
    layer.miniMask[c] = mask(layer.mini, "L" .. c, gl, gt, gr, gb)
  end
  layer.cities = newLayer(4 + 2 * MAXZ + 1)
  layer.under = newLayer(4 + 2 * MAXZ + 3)
  -- paper grain, over everything
  local grain = newLayer(4 + 2 * MAXZ + 4)
  local g = grain:CreateTexture(nil, "OVERLAY")
  g:SetTexture(DIR .. "Grain", "REPEAT", "REPEAT")
  placeRect(g, -0.3, -0.3, 1.3, 1.3)
  g:SetTexCoord(0, 1.6 * W / GRAIN_TILE, 0, 1.6 * H / GRAIN_TILE)
  layer.grain = grain
end

-- a zone's two passes (territory, core: each its painting and, through its border band, the colour-matched copy)
-- and the soft copies of its core, made when it first comes into view
local function buildZone(id)
  local z = { pieces = {} }
  local m = A.maps[id]
  local l, t, r, b = rectOf(id)
  local g = m.grade or { 1, 1, 1 }
  for pass, level in pairs({ T = 5 + rank[id], C = 5 + MAXZ + rank[id] }) do
    local f = newLayer(level)
    local mk, band = mask(f, "Z" .. id .. pass, l, t, r, b), mask(f, "Z" .. id .. "B", l, t, r, b)
    addArt(f, id, { mk }, true, z.pieces, 0)
    local twin = {}
    for _, tx in ipairs(addArt(f, id, { mk, band }, true, twin, 1)) do tx:SetVertexColor(g[1], g[2], g[3]) gradeOf[tx] = g end
    for key, list in pairs(twin) do
      for _, tx in ipairs(list) do table.insert(z.pieces[key], tx) end
    end
    z[pass] = f
  end
  built[id] = z
  M.dimUnexplored(id)
  return z
end
local function buildBlur(id, z)
  local l, t, r, b = rectOf(id)
  local f = newLayer(4 + 2 * MAXZ)
  local d = 0.6 * (r - l) / A.maps[id].art[1]   -- 0.6 art px, in world (0..1) across
  for _, o in ipairs({ { d, d }, { -d, -d } }) do
    local sub = CreateFrame("Frame", nil, f)
    sub:SetAllPoints(root)
    sub:SetFrameLevel(f:GetFrameLevel())
    local ox, oy = o[1], o[2]
    addArt(sub, id, { mask(sub, "Z" .. id .. "C", l, t, r, b) }, true, nil, 0)
    sub:SetAlpha(0.5)
    -- (each region, the mask too, placed from root: shifted by the copy's offset)
    for _, rg in ipairs({ sub:GetRegions() }) do
      local p, rel, rp, x, y = rg:GetPoint(1)
      if p and rel == root then rg:SetPoint(p, rel, rp, x + ox * W, y - oy * H) end
    end
  end
  z.blur = f
end

-- the unexplored pieces of a zone: this much of their colour (the game's own map leaves them out; here they show,
-- dimmed, so the map is whole)
function M.dimUnexplored(id)
  local z = built[id]
  if not z then return end
  local seen = explored[id]
  if not seen and C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures then
    seen = {}
    local ok, list = pcall(C_MapExplorationInfo.GetExploredMapTextures, id)
    if ok and list then for _, info in ipairs(list) do seen[(info.offsetX or 0) .. ":" .. (info.offsetY or 0)] = true end end
    explored[id] = seen
  end
  for key, list in pairs(z.pieces) do
    local k = (seen and not seen[key]) and P.unexplored or { 1, 1, 1 }
    for _, tx in ipairs(list) do
      local g = gradeOf[tx] or { 1, 1, 1 }
      tx:SetVertexColor(g[1] * k[1], g[2] * k[2], g[3] * k[3])
    end
  end
end

local function buildCity(id)
  local f = UNDER[id] and layer.under or layer.cities
  local sub = CreateFrame("Frame", nil, f)
  sub:SetAllPoints(root)
  sub:SetFrameLevel(f:GetFrameLevel())
  local l, t, r, b = rectOf(id)
  addArt(sub, id, { mask(sub, "City", l, t, r, b) })
  cities[id] = sub
  return sub
end

-- the minimap's pictures in view: each partly greyed, warmed to the parchment with a quarter of its zone's colour
local function tileTint(c, col, row)
  local key = c * 4096 + col * 64 + row
  if tintOf[key] then return tintOf[key] end
  local u, v = gridToWorld(c, col + 0.5, row + 0.5)
  local chain = chainAt(u, v)
  local zm = A.maps[chain[#chain]]
  local tone = zm and zm.tone or P.defaultTone
  local top = math.max(tone[1], tone[2], tone[3], 1e-3)
  local k = {}
  for n = 1, 3 do k[n] = P.paper[n] + (tone[n] / top - P.paper[n]) * P.toneShare end
  tintOf[key] = k
  return k
end
local function showTiles(u0, v0, u1, v1, on)
  local keep = {}
  if on and ns.tiles then
    for c in pairs(CONT_MAP) do
      local list = ns.tiles[c]
      local ca, ra = worldToGrid(c, u0, v0)
      local cb, rb = worldToGrid(c, u1, v1)
      local c0, c1 = math.max(0, math.floor(math.min(ca, cb))), math.min(63, math.floor(math.max(ca, cb)))
      local r0, r1 = math.max(0, math.floor(math.min(ra, rb))), math.min(63, math.floor(math.max(ra, rb)))
      if list and (c1 - c0 + 1) * (r1 - r0 + 1) <= 400 then
        for col = c0, c1 do for row = r0, r1 do
          local file = list[col * 64 + row]
          if file then
            local key = c * 4096 + col * 64 + row
            local tx = tiles[key]
            if not tx then
              tx = table.remove(spare) or layer.mini:CreateTexture(nil, "ARTWORK")
              tx:SetTexture(file, "CLAMP", "CLAMP", "LINEAR")
              local l, t = gridToWorld(c, col, row)
              local r, b = gridToWorld(c, col + 1, row + 1)
              placeRect(tx, l, t, r, b)
              if maskOf[tx] ~= layer.miniMask[c] then
                if maskOf[tx] then tx:RemoveMaskTexture(maskOf[tx]) end
                tx:AddMaskTexture(layer.miniMask[c])
                maskOf[tx] = layer.miniMask[c]
              end
              if tx.SetDesaturation then tx:SetDesaturation(P.miniDesat) end
              local k = tileTint(c, col, row)
              tx:SetVertexColor(k[1], k[2], k[3])
              tx:Show()
              tiles[key] = tx
            end
            keep[key] = true
          end
        end end
      end
    end
  end
  for key, tx in pairs(tiles) do
    if not keep[key] then tx:Hide() tiles[key] = nil spare[#spare + 1] = tx end
  end
end

-- ------------------------------------------------------------------ the view: every layer's strength and what's built
local function inView(id, u0, v0, u1, v1)
  local l, t, r, b = rectOf(id)
  return l and r > u0 and l < u1 and b > v0 and t < v1
end
local function update()
  if not active or not root then return end
  local u, v, zoom = view()
  local hu, hv = perPx(zoom)
  hu, hv = hu * sc:GetWidth() / 2, hv * sc:GetHeight() / 2
  local u0, v0, u1, v1 = u - hu, v - hv, u + hu, v + hv
  live = { u, v, zoom, sc:GetWidth(), sc:GetHeight() }
  local z = zoom * detailK()
  local ca = smooth(P.contIn, z)
  layer.cont0:SetAlpha(ca)
  layer.cont1:SetAlpha(ca)
  layer.mute:SetAlpha(smooth(P.mute, z))
  local la = P.lodIn[3] * smooth(P.lodIn, z)
  layer.lod:SetAlpha(la)
  layer.lod:SetShown(la > 0)
  local za = math.max(smooth(P.zoneIn, z), smooth(P.zoneHint, z) * P.zoneHint[3])
  local blurA = smooth(P.soft, z)
  for _, id in ipairs(zones) do
    local on = za > 0 and inView(id, u0, v0, u1, v1)
    local zb = built[id]
    if on and not zb then zb = buildZone(id) end
    if zb then
      zb.T:SetShown(on) zb.C:SetShown(on)
      zb.T:SetAlpha(za) zb.C:SetAlpha(za)
      local soft = on and blurA > 0
      if soft and not zb.blur then buildBlur(id, zb) end
      if zb.blur then zb.blur:SetShown(soft) zb.blur:SetAlpha(blurA * 0.8 * za) end
    end
  end
  for id, m in pairs(A.maps) do
    if m.type == 3 and not m.mask and m.art and m.rect and (m.cont == 0 or m.cont == 1) then
      local l, t, r, b = rectOf(id)
      local share = math.max((r - l) / (u1 - u0), (b - t) / (v1 - v0))
      local a = smooth(P.cityIn, share) * za
      local on = a > 0 and inView(id, u0, v0, u1, v1)
      local f = cities[id]
      if on and not f then f = buildCity(id) end
      if f then f:SetShown(on) f:SetAlpha(a) end
    end
  end
  local ma = P.miniMix[3] * smooth(P.miniMix, z) + (1 - P.miniMix[3]) * smooth(P.miniOver, z)
  layer.mini:SetAlpha(ma)
  showTiles(u0, v0, u1, v1, ma > 0)
  layer.grain:SetAlpha(smooth(P.soft, z) * P.grainAlpha)
end
local pending = CreateFrame("Frame")
pending:Hide()
pending:SetScript("OnUpdate", function(self) self:Hide() safe("view", update) end)
local function later() if active then pending:Show() end end

-- ------------------------------------------------------------------ the game's map: setting the view
local function setView(scale, x, y)
  sc.currentScale, sc.targetScale, sc.zoomTarget = scale, scale, scale
  sc.Child:SetScale(scale)
  sc:CalculateScrollExtents()
  x = clamp(x, sc.scrollXExtentsMin, sc.scrollXExtentsMax)
  y = clamp(y, sc.scrollYExtentsMin, sc.scrollYExtentsMax)
  sc.targetScrollX, sc.targetScrollY, sc.currentScrollX, sc.currentScrollY = x, y, x, y
  sc:SetNormalizedHorizontalScroll(x)
  sc:SetNormalizedVerticalScroll(y)
  map:OnCanvasScaleChanged()
  if sc.MarkAreaTriggersDirty then sc:MarkAreaTriggersDirty() end
  if sc.MarkViewRectDirty then sc:MarkViewRectDirty() end
end
local function showWorld(u, v, zoom)
  local id = map:GetMapID()
  local x, y = fromWorld(id, u, v)
  setView(scaleFor(id, zoom), x, y)
end

-- the game's own art for the map underneath (its tiles and explored pieces): hidden while ours shows
local function blizzardArt()
  local show = not active
  if map.detailLayerPool then
    for l in map.detailLayerPool:EnumerateActive() do l:SetShown(show) end
  end
  if map.EnumeratePinsByTemplate then
    for pin in map:EnumeratePinsByTemplate("MapExplorationPinTemplate") do pin:SetShown(show) end
  end
end

local function layout(id)
  local l, t, r = rectOf(id)
  local k = A.maps[id].art[1] / ((r - l) * W)
  root:SetScale(k)
  root:ClearAllPoints()
  root:SetPoint("TOPLEFT", root:GetParent(), "TOPLEFT", -l * W, t * H)
end

local ticker = CreateFrame("Frame")
ticker:Hide()
local badge   -- the "work in progress" note in the map's corner (on the scroll frame, so it doesn't zoom)
local function attach(id)
  active = isOn() and stitchable(id) and root ~= nil or false
  if root then root:SetShown(active) end
  if badge then badge:SetShown(active) end
  blizzardArt()
  if active then
    layout(id)
    ourWheel = MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_NONE ~= nil and sc.SetMouseWheelZoomMode ~= nil
    if ourWheel then sc:SetMouseWheelZoomMode(MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_NONE) end
    if sc.SetScalingMode then sc:SetScalingMode("SCALING_MODE_LINEAR") end
    if map:IsShown() then ticker:Show() end
    later()
  else
    if ourWheel and wheelMode then sc:SetMouseWheelZoomMode(wheelMode) end
    ourWheel = false
    if scalingMode and sc.SetScalingMode then sc:SetScalingMode(scalingMode) end
    ticker:Hide()
  end
end

local function build()
  if root then return end
  root = CreateFrame("Frame", nil, map:GetCanvas())
  root:SetSize(1, 1)
  root:SetFrameLevel(artLevel)
  layer.world = newLayer(0)
  for id, m in pairs(A.maps) do
    if m.type == 3 and m.mask and m.rect and (m.cont == 0 or m.cont == 1) then zones[#zones + 1] = id end
  end
  local function area(id) local l, t, r, b = rectOf(id) return (r - l) * (b - t) end
  table.sort(zones, function(a, b) return area(a) > area(b) end)
  while #zones > MAXZ do table.remove(zones) end
  for i, id in ipairs(zones) do rank[id] = i - 1 end
  buildBase()
end

-- zoom levels from the whole world to the deepest, in this map's scale
local function onZoomLevels(self)
  if isOn() and not root then build() end
  local id = self.mapID or map:GetMapID()
  attach(id)
  if not active then return end
  local levels, zoom = {}, 1
  while zoom < P.maxZoom * ZOOM_STEP do
    levels[#levels + 1] = { scale = scaleFor(id, math.min(zoom, P.maxZoom)), layerIndex = 1 }
    zoom = zoom * ZOOM_STEP
  end
  self.zoomLevels = levels
  self.baseScale = levels[1].scale
end

-- each time the game puts a map up: on opening, the view you left; another map put up while it's open (the quest
-- log's, the dropdown's) shows whole, as the game's does
local function resetView(self)
  userMoved = false
  local id = self.mapID or map:GetMapID()
  local back = reopen
  reopen = false
  if back and live and math.abs(sc:GetWidth() - live[4]) < 1 then
    showWorld(live[1], live[2], clamp(live[3], 1, P.maxZoom))
    userMoved = true
    return
  end
  local aw, ah = A.maps[id].art[1], A.maps[id].art[2]
  setView(math.min(self:GetWidth() / aw, self:GetHeight() / ah), 0.5, 0.5)
end

-- panning anywhere on the world (and a little past it), not just on the map underneath
local function extents(orig)
  return function(self, scale)
    if not active then return orig(self, scale) end
    local id = map:GetMapID()
    local hw = self:NormalizeHorizontalSize(self:GetWidth() * 0.5 / scale)
    local hh = self:NormalizeVerticalSize(self:GetHeight() * 0.5 / scale)
    local x0, y0 = fromWorld(id, 0, 0)
    local x1, y1 = fromWorld(id, 1, 1)
    local t = clamp((zoomFor(id, scale) - 1) / 0.6, 0, 1)
    local function range(a0, a1, half, slack)
      local lo, hi = a0 + half, a1 - half
      local pl, ph = lo, hi
      if lo > hi then pl, ph = (a0 + a1) / 2, (a0 + a1) / 2 end
      local fl0, fh0 = math.min(lo, hi) - slack, math.max(lo, hi) + slack
      return pl + (fl0 - pl) * t, ph + (fh0 - ph) * t
    end
    local minX, maxX = range(x0, x1, hw, (x1 - x0) * 0.2)
    local minY, maxY = range(y0, y1, hh, (y1 - y0) * 0.2)
    return minX, maxX, minY, maxY
  end
end

-- the wheel: a step about the point under the cursor
local function cursorOffset()
  local x, y = GetCursorPosition()
  local es = sc:GetEffectiveScale()
  return x / es - (sc:GetLeft() + sc:GetWidth() / 2), (sc:GetTop() - sc:GetHeight() / 2) - y / es
end
local function onWheel(_, delta)
  if not (active and ourWheel) then return end
  local u, v, zoom = view()
  local sx, sy = cursorOffset()
  local pu, pv = perPx(zoom)
  local cu, cv = u + sx * pu, v + sy * pv
  local to = clamp(zoom * (delta > 0 and ZOOM_STEP or 1 / ZOOM_STEP), 1, P.maxZoom)
  pu, pv = perPx(to)
  userMoved = true
  showWorld(cu - sx * pu, cv - sy * pv, to)
end

-- clicks: left zooms to the next map down under the cursor, right out to the one above
local function onClick(_, button)
  if not active then return false end
  local u, v, zoom = view()
  local sx, sy = cursorOffset()
  local pu, pv = perPx(zoom)
  local chain = chainAt(u + sx * pu, v + sy * pv)
  local target
  if button == "LeftButton" then
    for _, id in ipairs(chain) do
      if id ~= WORLD and fitZoom(id) > zoom * 1.05 then target = id break end
    end
  elseif button == "RightButton" then
    target = WORLD
    for _, id in ipairs(chain) do
      if id ~= WORLD and fitZoom(id) < zoom * 0.95 then target = id end
    end
  end
  if target then
    local l, t, r, b = rectOf(target)
    userMoved = true
    showWorld((l + r) / 2, (t + b) / 2, clamp(fitZoom(target), 1, P.maxZoom))
  end
  return true
end

-- once the view is still: the map underneath becomes the one you're looking at
local function pick(u, v, zoom, current)
  local best = WORLD
  for _, id in ipairs(chainAt(u, v)) do
    local need = (id == current) and LEAVE or ENTER
    if id ~= WORLD and zoom >= fitZoom(id) * need then best = id end
  end
  return best
end
local function settled()
  local lb = sc.mouseButtonInfo and sc.mouseButtonInfo.LeftButton
  return not (lb and lb.down)
    and (sc.currentScale or sc.targetScale) == sc.targetScale
    and (sc.currentScrollX or sc.targetScrollX) == sc.targetScrollX
    and (sc.currentScrollY or sc.targetScrollY) == sc.targetScrollY
end
local function switch(target)
  local u, v, zoom = view()
  switching = true
  local ok, err = pcall(map.SetMapID, map, target)
  switching = false
  if not ok then report("switch", err) return end
  if active then showWorld(u, v, zoom) end
end
local still, tick = 0, 0
ticker:SetScript("OnUpdate", function(_, elapsed)
  tick = tick + elapsed
  if tick < 0.1 then return end
  tick = 0
  if not active then return end
  still = settled() and still + 0.1 or 0
  if userMoved and still >= SWITCH_AFTER and not InCombatLockdown() then
    local id = map:GetMapID()
    local u, v, zoom = view()
    local target = pick(u, v, zoom, id)
    if target ~= id then safe("switch", switch, target) end
  end
end)

-- ------------------------------------------------------------------ hooks into the game's map
local hooked = false
local function setup()
  if hooked then return true end
  map = _G.WorldMapFrame
  sc = map and map.ScrollContainer
  if not (A and P and sc and sc.CreateZoomLevels and sc.CalculateScrollExtentsAtScale and map.GetPinFrameLevelsManager
      and map:GetPinFrameLevelsManager() and map.AddDataProvider and MapCanvasDataProviderMixin and C_Map) then
    return false
  end
  W, H = A.maps[WORLD].art[1], A.maps[WORLD].art[2]
  fl = map:GetPinFrameLevelsManager()
  fl:InsertFrameLevelAbove("PIN_FRAME_LEVEL_AUDHD_ATLAS", "PIN_FRAME_LEVEL_MAP_EXPLORATION", RANGE)
  artLevel = fl:GetValidFrameLevel("PIN_FRAME_LEVEL_AUDHD_ATLAS")
  wheelMode = sc.mouseWheelZoomMode or MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_FULL
  scalingMode = sc.scalingMode or "SCALING_MODE_TRANSLATE_FASTER_THAN_SCALE"
  hooked = true
  hooksecurefunc(sc, "CreateZoomLevels", function(self) safe("zoom levels", onZoomLevels, self) end)
  local blizzardReset = sc.ResetZoom
  sc.ResetZoom = function(self, ...)
    if active and not switching then
      if safe("reset", resetView, self) then return end
    end
    return blizzardReset(self, ...)
  end
  sc.CalculateScrollExtentsAtScale = extents(sc.CalculateScrollExtentsAtScale)
  if map.RefreshDetailLayers then hooksecurefunc(map, "RefreshDetailLayers", function() safe("art", blizzardArt) end) end
  sc:HookScript("OnMouseWheel", function(_, d) safe("wheel", onWheel, _, d) end)
  sc:HookScript("OnMouseDown", function() if active then userMoved = true end end)
  map:AddCanvasClickHandler(function(...)
    local ok, r = pcall(onClick, ...)
    if not ok then report("click", r) return false end
    return r
  end, 1000)
  local dp = CreateFromMixins(MapCanvasDataProviderMixin)
  dp.OnCanvasScaleChanged = later
  dp.OnCanvasPanChanged = later
  dp.OnMapChanged = later
  dp.OnShow = function()
    explored = {}
    for id in pairs(built) do safe("explored", M.dimUnexplored, id) end
    if active then ticker:Show() later() end
  end
  dp.OnHide = function() ticker:Hide() reopen = true end
  map:AddDataProvider(dp)
  safe("badge", function()
    badge = CreateFrame("Frame", nil, sc)
    badge:SetFrameLevel(sc:GetFrameLevel() + 2000)
    badge:SetPoint("BOTTOMLEFT", sc, "BOTTOMLEFT", 6, 6)
    badge:SetSize(250, 34)
    local bg = badge:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)
    local fs = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", 6, -4)
    fs:SetPoint("BOTTOMRIGHT", -6, 4)
    fs:SetJustifyH("LEFT")
    fs:SetText("|cffff9933WORK IN PROGRESS|r  joined-up map, untested\n|cffccccccErrors? /wfn atlas off|r")
    badge:SetShown(active)
  end)
  return true
end

-- ------------------------------------------------------------------ settings
-- the top of our art's frame levels (the route's lines and pins go above it: RouteMap.lua)
function M.top() return root and artLevel and artLevel + RANGE or 0 end
function M.isOn() return isOn() and true or false end
-- the view on a world point (0..1 across and down the world map) at a zoom (1: the whole world), and laid out again
function M.show(u, v, zoom)
  if not active then return end
  userMoved = true
  safe("show", showWorld, u, v, clamp(zoom or 1, 1, P.maxZoom))
  safe("view", update)
end
function M.refresh() if active then safe("view", update) end end
-- what went wrong (each place once), and what's built and showing: for /wfn atlas and the tests
function M.errors()
  local out = {}
  for where, e in pairs(errs) do out[#out + 1] = where .. ": " .. e end
  table.sort(out)
  return out
end
function M.stats()
  local z, shown, c, t = 0, 0, 0, 0
  for _, b in pairs(built) do z = z + 1 if b.T:IsShown() then shown = shown + 1 end end
  for _ in pairs(cities) do c = c + 1 end
  for _ in pairs(tiles) do t = t + 1 end
  return { zones = z, zonesShown = shown, cities = c, tiles = t, map = map and map:GetMapID(), zoom = active and select(3, view()) }
end
function M.shown() return active end
-- for what's drawn on top (RouteMap.lua): a place in world yards (X north, Y west) on continent c, as 0..1 of the
-- map underneath (past 0..1 when it's in a neighbour, which the joined-up map shows too); nil when not showing
function M.yardsToHost(c, X, Y)
  local C = active and A.conts[c]
  if not (C and X and Y) then return nil end
  local maxY, maxX, minY, minX = C.yards[1], C.yards[2], C.yards[3], C.yards[4]
  local u = C.rect[1] + (maxY - Y) / (maxY - minY) * (C.rect[3] - C.rect[1])
  local v = C.rect[2] + (maxX - X) / (maxX - minX) * (C.rect[4] - C.rect[2])
  return fromWorld(map:GetMapID(), u, v)
end
-- the part of the world in view, as 0..1 of the map underneath (x0, y0, x1, y1), widened by margin (a share of it)
function M.viewOnHost(margin)
  if not active then return nil end
  local ok, a, b, c, d = pcall(function()
    local u, v, zoom = view()
    local du, dv = perPx(zoom)
    local hw, hh = sc:GetWidth() / 2 * du * (1 + (margin or 0)), sc:GetHeight() / 2 * dv * (1 + (margin or 0))
    local id = map:GetMapID()
    local x0, y0 = fromWorld(id, u - hw, v - hh)
    local x1, y1 = fromWorld(id, u + hw, v + hh)
    return x0, y0, x1, y1
  end)
  if ok then return a, b, c, d end
  report("view", a)
end
function M.set(on)
  AuDHDDB.atlas = on or nil
  if on and not hooked then
    local ok, r = pcall(setup)
    if not ok then report("setup", r) end
    if not (ok and r) then return "the joined-up map can't attach to this world map" end
  end
  if not hooked then return end
  if map:IsShown() then
    safe("relayout", function() sc:CreateZoomLevels() sc:ResetZoom() end)
  else
    safe("relayout", attach, map:GetMapID())
  end
end
function M.command(arg)
  arg = (arg or ""):lower()
  if arg == "on" or arg == "off" then
    local r = M.set(arg == "on")
    return r or ("joined-up world map " .. (arg == "on" and ("on (open the world map: M). " .. WIP) or "off"))
  end
  local e = M.errors()
  return "joined-up world map (work in progress, untested): " .. (isOn() and "on" or "off") .. (active and ", showing" or "") .. " (/wfn atlas on|off)"
    .. (#e > 0 and ("; problems: " .. table.concat(e, "; ")) or "")
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("MAP_EXPLORATION_UPDATED")
ev:SetScript("OnEvent", function(_, e)
  if e == "PLAYER_LOGIN" then
    if isOn() then
      safe("setup", setup)
      print("AuDHD: " .. WIP)
    end
  else
    explored = {}
    for id in pairs(built) do safe("explored", M.dimUnexplored, id) end
  end
end)
