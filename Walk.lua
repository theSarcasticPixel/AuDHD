-- The walking way, GPS-style: the path over the ground from you to the step (around the tree trunks, down the ramps,
-- along the roads), found on the walk graph in WalkData.lua (built from the Forever client's terrain by ForeverDB;
-- tools/export_walk_lua.mjs). RouteMap.lua draws it, Arrow.lua points along it.
-- A continent's graph is decoded the first time a path on it is wanted. A* with a binary heap.
local _, ns = ...
local W = {}
ns.walk = W

local A64 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"
local D = {}
for i = 1, 64 do D[A64:byte(i)] = i - 1 end
local byte, floor, sqrt = string.byte, math.floor, math.sqrt
local function n3(s, p) local a, b, c = byte(s, p, p + 2); return (D[a] * 64 + D[b]) * 64 + D[c] end
local function hasBit(v, b) return floor(v / b) % 2 == 1 end
local E_WATER, E_ONEWAY, E_STEEP, E_DEEP = 1, 2, 8, 32
local CELL = 128
local function cellKey(X, Y) return floor((X + 32768) / CELL) * 4096 + floor((Y + 32768) / CELL) end

-- map <-> world: X grows north, Y grows west (the same as C_Map.GetWorldPosFromMapPos)
function W.toWorld(m, x, y)   -- x, y in 0..100
  local t = ns.walkMaps and ns.walkMaps[m]
  if t then return t.c, t.t - y / 100 * t.h, t.l - x / 100 * t.w end
  local ok, c, pos = pcall(C_Map.GetWorldPosFromMapPos, m, CreateVector2D(x / 100, y / 100))
  if ok and pos then local X, Y = pos:GetXY() return c, X, Y end
end
function W.toMap(m, X, Y)     -- 0..1 on map m, or nil
  local t = ns.walkMaps and ns.walkMaps[m]
  if not t then return nil end
  return (t.l - Y) / t.w, (t.t - X) / t.h
end
function W.mapCont(m) local t = ns.walkMaps and ns.walkMaps[m]; return t and t.c end

-- ------------------------------------------------------------------ the graph
local graphs = {}
local joinCities   -- below, with the cities
local function graph(cont)
  if graphs[cont] ~= nil then return graphs[cont] or nil end
  local d = ns.walkData and ns.walkData[cont]
  if not d then graphs[cont] = false return nil end
  local G = { X = {}, Y = {}, adj = {}, cost = {}, grid = {}, ledge = {} }
  local nodes, n = d.nodes, floor(#d.nodes / 7)
  for i = 1, n do
    local p = (i - 1) * 7 + 1
    local X, Y = n3(nodes, p) / 2 - 32768, n3(nodes, p + 3) / 2 - 32768
    G.X[i], G.Y[i], G.adj[i], G.cost[i] = X, Y, {}, {}
    if hasBit(D[byte(nodes, p + 6)], 16) then G.ledge[i] = true end
    local k = cellKey(X, Y)
    local cell = G.grid[k]
    if not cell then cell = {}; G.grid[k] = cell end
    cell[#cell + 1] = i
  end
  local function link(i, j, c)
    local a = G.adj[i]
    a[#a + 1] = j
    G.cost[i][#a] = c
  end
  local edges = d.edges
  for k = 1, floor(#edges / 7) do
    local p = (k - 1) * 7 + 1
    local i, j, fl = n3(edges, p) + 1, n3(edges, p + 3) + 1, D[byte(edges, p + 6)]
    local len = sqrt((G.X[i] - G.X[j]) ^ 2 + (G.Y[i] - G.Y[j]) ^ 2)
    -- swimming is slower, deep water and steep slopes are kept for when there's no other way
    local f = hasBit(fl, E_DEEP) and 3 or hasBit(fl, E_WATER) and 1.6 or hasBit(fl, E_STEEP) and 1.5 or 1
    link(i, j, len * f)
    if not hasBit(fl, E_ONEWAY) then link(j, i, len * f) end
  end
  G.ride, G.rideCost = {}, {}
  for _, L in ipairs(d.links or {}) do
    link(L.a + 1, L.b + 1, L.cost)
    G.ride[(L.a + 1) * 65536 + L.b + 1], G.rideCost[(L.a + 1) * 65536 + L.b + 1] = L.name, L.cost
    if L.both then
      link(L.b + 1, L.a + 1, L.cost)
      G.ride[(L.b + 1) * 65536 + L.a + 1], G.rideCost[(L.b + 1) * 65536 + L.a + 1] = L.name, L.cost
    end
  end
  G.n = n
  joinCities(G, link)
  graphs[cont] = G
  W.applyBlocks(G, cont)
  return G
end

-- ways you can't walk (a cliff the graph runs up or down): you say so with /wfn blocked, and the stretch of the way the
-- arrow is leading you along, AHEAD_BLOCK yards from where you are, is taken out of the graph (kept in AuDHDDB, by
-- the world spots of its ends; logged as WALK_BLOCKED to go into the data). The user, 2026-10-17: "its currently trying
-- to make me walk up a path that cant be walked"
local AHEAD_BLOCK = 70
local function blocks()
  AuDHDDB.walkBlocked = AuDHDDB.walkBlocked or {}
  return AuDHDDB.walkBlocked
end
local function cut(G, i, j)
  for _, e in ipairs({ { i, j }, { j, i } }) do
    local a, c = G.adj[e[1]], G.cost[e[1]]
    for k = #a, 1, -1 do
      if a[k] == e[2] then table.remove(a, k) table.remove(c, k) end
    end
  end
end
local function nodeAt(G, X, Y)
  local cx, cy = floor((X + 32768) / CELL), floor((Y + 32768) / CELL)
  for dx = -1, 1 do
    for dy = -1, 1 do
      for _, i in ipairs(G.grid[(cx + dx) * 4096 + cy + dy] or {}) do
        if math.abs(G.X[i] - X) < 0.6 and math.abs(G.Y[i] - Y) < 0.6 then return i end
      end
    end
  end
end
function W.applyBlocks(G, cont)
  for _, b in ipairs(AuDHDDB and AuDHDDB.walkBlocked or {}) do
    if b.c == cont then
      local i, j = nodeAt(G, b[1], b[2]), nodeAt(G, b[3], b[4])
      if i and j then cut(G, i, j) end
    end
  end
end

-- the node nearest X, Y within r yards
local function nearest(G, X, Y, r)
  local best, bd = nil, r * r
  local cx, cy = floor((X + 32768) / CELL), floor((Y + 32768) / CELL)
  local span = math.ceil(r / CELL)
  for dx = -span, span do
    for dy = -span, span do
      local cell = G.grid[(cx + dx) * 4096 + cy + dy]
      if cell then
        for _, i in ipairs(cell) do
          local d = (G.X[i] - X) ^ 2 + (G.Y[i] - Y) ^ 2
          if d < bd then best, bd = i, d end
        end
      end
    end
  end
  return best, best and sqrt(bd)
end

-- the nodes within r yards of X, Y with their distances ({ [node] = yards }), else the nearest within far yards: the
-- one nearest node can be the wrong side of a wall or a stream (it made 400 yd of difference in Darnassus)
local function around(G, X, Y, r, far)
  local out, any = {}, false
  local cx, cy = floor((X + 32768) / CELL), floor((Y + 32768) / CELL)
  local span = math.ceil(r / CELL)
  for dx = -span, span do
    for dy = -span, span do
      local cell = G.grid[(cx + dx) * 4096 + cy + dy]
      if cell then
        for _, i in ipairs(cell) do
          local d = sqrt((G.X[i] - X) ^ 2 + (G.Y[i] - Y) ^ 2)
          if d <= r then out[i], any = d, true end
        end
      end
    end
  end
  if any then return out end
  local i, d = nearest(G, X, Y, far)
  if i then out[i] = d return out end
end

-- A* from any of the starts to any of the goals ({ [node] = yards to walk straight from/to the spot }), aiming at the
-- spot gx, gy: the node list, or nil
local function astar(G, starts, goals, gx, gy)
  local X, Y, adj, cost = G.X, G.Y, G.adj, G.cost
  local dist, prev, closed = {}, {}, {}
  local heap, hf, size = {}, {}, 0
  local function push(v, f)
    size = size + 1
    local k = size
    heap[k], hf[k] = v, f
    while k > 1 do
      local p = floor(k / 2)
      if hf[p] <= hf[k] then break end
      heap[p], heap[k], hf[p], hf[k] = heap[k], heap[p], hf[k], hf[p]
      k = p
    end
  end
  local function pop()
    local v = heap[1]
    heap[1], hf[1] = heap[size], hf[size]
    heap[size], hf[size] = nil, nil
    size = size - 1
    local k = 1
    while true do
      local l, r, m = 2 * k, 2 * k + 1, k
      if l <= size and hf[l] < hf[m] then m = l end
      if r <= size and hf[r] < hf[m] then m = r end
      if m == k then break end
      heap[m], heap[k], hf[m], hf[k] = heap[k], heap[m], hf[k], hf[m]
      k = m
    end
    return v
  end
  for i, d in pairs(starts) do
    dist[i] = d
    push(i, d + sqrt((X[i] - gx) ^ 2 + (Y[i] - gy) ^ 2))
  end
  local expanded, best, bestCost = 0, nil, math.huge
  while size > 0 do
    if hf[1] >= bestCost then break end
    local u = pop()
    if goals[u] and dist[u] + goals[u] < bestCost then best, bestCost = u, dist[u] + goals[u] end
    if not closed[u] then
      closed[u] = true
      expanded = expanded + 1
      if expanded > 20000 then break end
      local a, c, du = adj[u], cost[u], dist[u]
      for k = 1, #a do
        local v = a[k]
        local nd = du + c[k]
        if not dist[v] or nd < dist[v] then
          dist[v], prev[v] = nd, u
          push(v, nd + sqrt((X[v] - gx) ^ 2 + (Y[v] - gy) ^ 2))
        end
      end
    end
  end
  if not best then return nil end
  local path, u = {}, best
  while u do table.insert(path, 1, u); u = prev[u] end
  return path
end

-- ------------------------------------------------------------------ paths
-- the walking way between two map spots: { c = continent, pts = { X1, Y1, X2, Y2, ... } (world yards, from start to
-- goal, the exact spots at both ends), len = yards, ride = "Portal ..." when it takes one }, or nil (another continent,
-- no data, or no way found: draw a straight line then)
local cache, cacheN = {}, 0
local CITY = { [1457] = true, [1453] = true, [1455] = true }   -- Darnassus, Stormwind, Ironforge
-- the city's own ground on its map (0..100): Darnassus ends at its east gate, x 88.5 (where you cross into Teldrassil)
local CITY_EDGE = { [1457] = { x2 = 88.7 } }
local function inCity(m, X, Y)
  if not (CITY[m] and X) then return false end
  local x, y = W.toMap(m, X, Y)
  if not x then return false end
  local e = CITY_EDGE[m] or {}
  return x >= (e.x1 or 0) / 100 and x <= (e.x2 or 100) / 100 and y >= (e.y1 or 0) / 100 and y <= (e.y2 or 100) / 100
end
-- a city's nodes, all joined up: the city is walked straight (cityStraight), but its few nodes don't join up by
-- themselves (the tram's end in Ironforge and in Stormwind joined to nothing: the user, 2026-10-17, "it should be taking
-- me to the tram"). Nodes of the same city within JOIN yards get a straight edge, a little dearer than a real one
local JOIN = 400
joinCities = function(G, link)
  local byCity = {}
  for i = 1, #G.X do
    for m in pairs(CITY) do
      if inCity(m, G.X[i], G.Y[i]) then byCity[m] = byCity[m] or {}; table.insert(byCity[m], i) break end
    end
  end
  for _, list in pairs(byCity) do
    for a = 1, #list do
      for b = a + 1, #list do
        local i, j = list[a], list[b]
        local d = sqrt((G.X[i] - G.X[j]) ^ 2 + (G.Y[i] - G.Y[j]) ^ 2)
        if d <= JOIN then link(i, j, d * 1.2) link(j, i, d * 1.2) end
      end
    end
  end
end
-- a path's corners in the city at either end: one straight line instead, from the start to the last corner in the city
-- before the way leaves it (or a ride), and from the first corner in the city after the last ride to the goal
local function cityStraight(pts, m1, m2)
  local n = #pts
  local firstRide, lastRide = nil, nil
  for k = 1, n - 1, 2 do
    if not pts[k] then firstRide = firstRide or k; lastRide = k end
  end
  local head, tail = 1, n - 1   -- corners kept: from head to tail
  if CITY[m1] then
    for k = 1, (firstRide or n + 1) - 2, 2 do
      if inCity(m1, pts[k], pts[k + 1]) then head = k end
    end
  end
  if CITY[m2] then
    for k = n - 1, (lastRide or -1) + 2, -2 do
      if inCity(m2, pts[k], pts[k + 1]) then tail = k end
    end
  end
  if tail < head then return pts, nil end
  local out = {}
  if head > 1 then out[1], out[2] = pts[1], pts[2] end
  for k = head, tail + 1 do out[#out + 1] = pts[k] end
  if tail < n - 1 then out[#out + 1], out[#out + 2] = pts[n - 1], pts[n] end
  local len, px, py = 0, nil, nil
  for k = 1, #out - 1, 2 do
    if out[k] then
      if px then len = len + sqrt((out[k] - px) ^ 2 + (out[k + 1] - py) ^ 2) end
      px, py = out[k], out[k + 1]
    else
      px, py = nil, nil
    end
  end
  return out, len
end
-- ------------------------------------------------------------------ flights
-- the flight paths you know, per character (read from the flight map each time it opens: W.readTaxiMap). A long trip
-- flies when that's quicker than walking or the boat (the user at Rut'theran, 2026-10-16: "its telling me to take a
-- boat from teldrassil to darkshore which doesn't make sense as i have the fp to darkshore")
-- the flight paths every character of a race starts with (the user, 2026-10-16: night elves Rut'theran and Auberdine,
-- dwarves and gnomes Ironforge, humans Stormwind): client TaxiNodes ids
local RACE_TAXIS = { NightElf = { 27, 26 }, Human = { 2 }, Dwarf = { 6 }, Gnome = { 6 } }
function W.knownTaxis()
  AuDHDDB.taxi = AuDHDDB.taxi or {}
  local k = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
  if not AuDHDDB.taxiV2 then AuDHDDB.taxi, AuDHDDB.taxiV2 = {}, true end   -- open a flight map to learn yours again
  local K = AuDHDDB.taxi[k]
  if not K then
    K = {}
    local _, race = UnitRace("player")
    for _, id in ipairs(RACE_TAXIS[race] or {}) do K[id] = true end
    AuDHDDB.taxi[k] = K
  end
  return K
end
local direct = {}   -- [continent] = { [from id] = { [to id] = seconds } }
local function flights(c)
  if direct[c] then return direct[c] end
  local t = {}
  local d = ns.walkData and ns.walkData[c]
  for a, b, s in ((d and d.flights) or ""):gmatch("(%d+)>(%d+)>(%d+)") do
    a, b = tonumber(a), tonumber(b)
    t[a] = t[a] or {}
    t[a][b] = tonumber(s)
  end
  direct[c] = t
  return t
end
-- the quickest flight from a to b through flight masters you know (the game flies on through them), in seconds
local function flyTime(c, a, b, K)
  local T, dist, done = flights(c), { [a] = 0 }, {}
  while true do
    local u, du
    for n, dn in pairs(dist) do if not done[n] and (not du or dn < du) then u, du = n, dn end end
    if not u then return nil end
    if u == b then return du end
    done[u] = true
    for v, s in pairs(T[u] or {}) do
      if K[v] and (not dist[v] or du + s < dist[v]) then dist[v] = du + s end
    end
  end
end
local FLY_MIN, RUN = 500, 7   -- yards: shorter trips walk; run speed, yd/s (a flight's seconds as yards of walking)
local flyPath   -- below W.path, which it uses for the walks to and from the flight masters

function W.path(m1, x1, y1, m2, x2, y2, noFly)
  local c1, X1, Y1 = W.toWorld(m1, x1, y1)
  local c2, X2, Y2 = W.toWorld(m2, x2, y2)
  if not c1 or c1 ~= c2 then return nil end
  local key = ("%d:%d:%d:%d:%d%s"):format(c1, floor(X1 / 8), floor(Y1 / 8), floor(X2 / 8), floor(Y2 / 8), noFly and "n" or "")
  if cache[key] ~= nil then return cache[key] or nil end
  -- within a city: a straight line. The graph's few nodes there zig-zag round the lakes and terraces however we weigh
  -- them (the user in Darnassus, 2026-10-16: "paths are still fucked"), and the city is open enough to walk straight
  if CITY[m1] and m1 == m2 then cache[key] = false return nil end
  local G = graph(c1)
  local res = false
  if G then
    -- in a city the graph has few nodes (none in Ironforge's Tinker Town, so no way from Jemma Quikswitch to the tram:
    -- the user, 2026-10-17, and its nodes there don't join up): start from any node within reach, the city is walked
    -- straight to it anyway (cityStraight)
    local r1, r2 = CITY[m1] and 600 or 150, CITY[m2] and 600 or 200
    local s, ds = nearest(G, X1, Y1, r1)
    local g, dg = nearest(G, X2, Y2, r2)
    local starts, goals = around(G, X1, Y1, 60, r1), around(G, X2, Y2, 60, r2)
    -- a ledge a player told us the way up to (the top of a walkWays way): near it, that way only, never the other
    -- nodes round it at the foot of the cliff (Braldir Ashmantle, the user 2026-10-17)
    local ledge = false
    local function ledgeOnly(set)
      local only
      for i, d in pairs(set or {}) do if G.ledge[i] then only = only or {} only[i] = d ledge = true end end
      return only or set
    end
    starts, goals = ledgeOnly(starts), ledgeOnly(goals)
    -- indoors (a temple, an inn) the graph has no nodes: when you're nearer the goal than either end is to the graph,
    -- going by it would walk round the building (the user at Priestess A'moora, 2026-10-16): a straight line then
    local straight = sqrt((X2 - X1) ^ 2 + (Y2 - Y1) ^ 2)
    local nodes = s and g and straight > 40 and straight > ds + dg and astar(G, starts, goals, X2, Y2)
    if not nodes and s and g and straight > 40 and (CITY[m1] or CITY[m2]) then
      -- none from the nodes next to you: any of the city's within reach
      local ok = straight > ds + dg
      local cs = CITY[m1] and around(G, X1, Y1, r1, r1) or starts
      local cg = CITY[m2] and around(G, X2, Y2, r2, r2) or goals
      nodes = ok and astar(G, ledgeOnly(cs), ledgeOnly(cg), X2, Y2)
    end
    if nodes then
      local pts, len, ride, rideCost = { X1, Y1 }, 0, nil, 0
      local px, py = X1, Y1
      for k, i in ipairs(nodes) do
        if k > 1 and G.ride[nodes[k - 1] * 65536 + i] then
          -- a boat or portal: no line across the water, the path starts again where you land
          ride = G.ride[nodes[k - 1] * 65536 + i]
          rideCost = rideCost + G.rideCost[nodes[k - 1] * 65536 + i]
          pts[#pts + 1], pts[#pts + 2] = false, false
        else
          len = len + sqrt((G.X[i] - px) ^ 2 + (G.Y[i] - py) ^ 2)
        end
        pts[#pts + 1], pts[#pts + 2] = G.X[i], G.Y[i]
        px, py = G.X[i], G.Y[i]
      end
      len = len + sqrt((X2 - px) ^ 2 + (Y2 - py) ^ 2)
      pts[#pts + 1], pts[#pts + 2] = X2, Y2
      -- into or out of a city: straight across the city to where the way crosses its edge (the gate, a portal), the
      -- graph only outside (the user, 2026-10-16: "the fastest way is directly east through the warriors terrace and
      -- out the gate")
      if (CITY[m1] or CITY[m2]) and m1 ~= m2 then
        local p2, l2 = cityStraight(pts, m1, m2)
        if l2 then pts, len = p2, l2 end
      end
      -- a way far longer than the straight line is the graph's gaps, not a wall: in the cities it barely has nodes (none
      -- in the buildings: 390 yd round the north of Darnassus to Fandral, 80 yd away, the user 2026-10-16); outside
      -- them a short hop can still go round a cliff
      -- (to or from a ledge, the long way round is the way: the cliff is the wall)
      local most = ledge and math.huge or (CITY[m1] or CITY[m2]) and 1.6 * straight + 30 or straight < 200 and 3 * straight + 60 or math.huge
      if ride or len <= most then res = { c = c1, pts = pts, len = len, ride = ride, cost = len + rideCost } end
    end
  end
  if not noFly then res = flyPath(c1, X1, Y1, X2, Y2, m1, x1, y1, m2, x2, y2, res and res.cost or math.huge) or res end
  cacheN = cacheN + 1
  if cacheN > 400 then cache, cacheN = {}, 0 end
  cache[key] = res
  return res or nil
end

-- walk to a flight master you know, fly, walk from where you land: when that beats the ground way (cost: yards, a
-- flight's seconds at run speed) by a tenth. Its path: the first walk, a break (the flight), the second walk.
flyPath = function(c, X1, Y1, X2, Y2, m1, x1, y1, m2, x2, y2, groundCost)
  local d = ns.walkData and ns.walkData[c]
  if not (d and d.taxis) or sqrt((X2 - X1) ^ 2 + (Y2 - Y1) ^ 2) < FLY_MIN then return nil end
  local K = W.knownTaxis()
  local best, bestCost
  for _, a in ipairs(d.taxis) do
    local da = K[a.id] and sqrt((a.X - X1) ^ 2 + (a.Y - Y1) ^ 2) * 1.3
    if da and da < groundCost then
      for _, b in ipairs(d.taxis) do
        local db = b ~= a and K[b.id] and sqrt((b.X - X2) ^ 2 + (b.Y - Y2) ^ 2) * 1.3
        local secs = db and da + db < groundCost and flyTime(c, a.id, b.id, K)
        if secs and (not bestCost or da + db + secs * RUN < bestCost) then best, bestCost = { a, b }, da + db + secs * RUN end
      end
    end
  end
  if not best or bestCost > groundCost * 0.9 then return nil end
  local a, b = best[1], best[2]
  local w1 = W.path(m1, x1, y1, a.m, a.x, a.y, true)
  local w2 = W.path(b.m, b.x, b.y, m2, x2, y2, true)
  local p1 = w1 and w1.pts or { X1, Y1, a.X, a.Y }
  local p2 = w2 and w2.pts or { b.X, b.Y, X2, Y2 }
  local pts = {}
  for k = 1, #p1 do pts[k] = p1[k] end
  pts[#pts + 1], pts[#pts + 2] = false, false
  for k = 1, #p2 do pts[#pts + 1] = p2[k] end
  local len = (w1 and w1.len or sqrt((a.X - X1) ^ 2 + (a.Y - Y1) ^ 2)) + (w2 and w2.len or sqrt((X2 - b.X) ^ 2 + (Y2 - b.Y) ^ 2))
  return { c = c, pts = pts, len = len, ride = "Fly to " .. b.n, cost = bestCost, fly = { from = a.id, to = b.id } }
end

function W.resetPaths() cache, cacheN = {}, 0; W.newPaths() end
-- the flight map is open: the flight paths it shows you know (by the game's node id where it says, else by name)
-- a flight path learned by talking to its flight master: on Forever they open a chat window first, and you have the
-- path from then on, flight map opened or not (the user, 2026-10-18: Stormwind's "didn't update to being learned until
-- i clicked the travel part"). The one you don't know yet within 40 yd of you; its id, or nil
function W.learnHere()
  local m = C_Map.GetBestMapForUnit("player")
  local p = m and C_Map.GetPlayerMapPosition(m, "player")
  if not p then return nil end
  local px, py = p:GetXY()
  if not px or (issecretvalue and issecretvalue(px)) then return nil end
  local c, X, Y = W.toWorld(m, px * 100, py * 100)
  local K, best, bd = W.knownTaxis(), nil, 40
  for _, d in pairs(ns.walkData or {}) do
    for _, t in ipairs(d.taxis or {}) do
      if not K[t.id] and t.m then
        local tc, tX, tY = W.toWorld(t.m, t.x, t.y)
        local dd = tc == c and X and tX and math.sqrt((tX - X) ^ 2 + (tY - Y) ^ 2)
        if dd and dd < bd then best, bd = t.id, dd end
      end
    end
  end
  if best then K[best] = true; W.resetPaths() end
  return best
end

function W.readTaxiMap()
  local K, added, changed = W.knownTaxis(), {}, false
  -- every flight master the map draws says whether you know it: unknown ones it draws too, greyed (the user,
  -- 2026-10-17: "its telling me to go to a flight path to turn in Stormpike's Order, which requires stormwind, i dont
  -- have stormwind, it should be taking me to the tram")
  local function setKnown(id, yes)
    if yes and not K[id] then K[id] = true; added[#added + 1] = id; changed = true
    elseif not yes and K[id] then K[id] = nil; changed = true end
  end
  local byName = {}
  for _, d in pairs(ns.walkData or {}) do
    for _, t in ipairs(d.taxis or {}) do byName[t.n:lower()] = t.id end
  end
  if NumTaxiNodes and TaxiNodeName and TaxiNodeGetType then
    for i = 1, NumTaxiNodes() do
      local ty = TaxiNodeGetType(i)
      local name = (TaxiNodeName(i) or ""):match("^([^,]+)")
      local id = name and byName[name:lower()]
      if id then setKnown(id, ty == "CURRENT" or ty == "REACHABLE") end
    end
  end
  if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and GetTaxiMapID then
    local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, GetTaxiMapID())
    for _, n in ipairs(ok and nodes or {}) do
      -- state: 0 you're here, 1 you can fly there, 2 you can't (not learned)
      if n.nodeID and n.state ~= nil then setKnown(n.nodeID, n.state == 0 or n.state == 1) end
    end
  end
  if changed then W.resetPaths() end
  local all = {}
  for id in pairs(K) do all[#all + 1] = id end
  table.sort(all)
  return all, added
end

-- you, in world yards: continent, X, Y (nil when the game won't say)
local isSecret = issecretvalue or function() return false end
function W.player()
  local m = C_Map.GetBestMapForUnit("player")
  if not m or isSecret(m) then return nil end
  local p = C_Map.GetPlayerMapPosition(m, "player")
  if not p then return nil end
  local x, y = p:GetXY()
  if isSecret(x) then return nil end
  local c, X, Y = W.toWorld(m, x * 100, y * 100)
  return c, X, Y, m, x * 100, y * 100
end

-- the way to the step you're on, kept (W.toStep, below); worked out again after a new flight path or a flight
local live = { key = nil, path = nil, at = 0, fresh = 0 }
function W.newPaths() live.key, live.path = nil, nil end

-- ------------------------------------------------------------------ on a flight
-- where the flight you took lands: while you fly, the way to the step starts there, not where you are in the air (the
-- user, 2026-10-16: "make the paths show where you are going to on the flight path, rather than lag behind/treat it
-- like youre walking there"). Known from the node you clicked on the flight map (TakeTaxiNode, hooked: nothing is
-- called), else the flight the path planned.
local flight
local function taxiWhere(name, id)
  name = name and name:match("^([^,]+)")
  for c, d in pairs(ns.walkData or {}) do
    for _, t in ipairs(d.taxis or {}) do
      if t.id == id or (name and t.n:lower() == name:lower()) then return { t = t, c = c } end
    end
  end
end
function W.tookTaxi(i)
  flight = taxiWhere(TaxiNodeName and TaxiNodeName(i))
  W.newPaths()
end
if hooksecurefunc and TakeTaxiNode then hooksecurefunc("TakeTaxiNode", W.tookTaxi) end
-- the flight master you're flying to, while you fly (nil on the ground)
function W.flying()
  if not (UnitOnTaxi and UnitOnTaxi("player")) then
    if flight then flight = nil; W.newPaths() end
    return nil
  end
  if not flight and live.path and live.path.fly then
    flight = taxiWhere(nil, live.path.fly.to)
    if flight then W.newPaths() end
  end
  return flight and flight.t
end
-- where the way to the step starts: you, or where your flight lands
function W.origin()
  local t = W.flying()
  if t then return flight.c, t.X, t.Y, t.m, t.x, t.y end
  return W.player()
end

-- the way from you to a step, kept while you stay on it: you're placed on the nearest stretch of it (not just the
-- nearest corner: the graph's stretches can be 100 yd long). Worked out again when the step changes, when you're more
-- than OFF yards off it, and every FRESH seconds anyway, taking the new way when it's shorter than what's left of the
-- old one (you walked the avenue, the old way zig-zagged beside it: the user in Darnassus, 2026-10-16)
local OFF, AHEAD, FRESH = 35, 30, 2
-- the stretch of p nearest X, Y: the index of the corner after it, and the distance to it
local function place(p, X, Y)
  local pts, best, bi = p.pts, nil, nil
  for k = 1, #pts - 3, 2 do
    local ax, ay, bx, by = pts[k], pts[k + 1], pts[k + 2], pts[k + 3]
    if ax and bx then
      local dx, dy = bx - ax, by - ay
      local l2 = dx * dx + dy * dy
      local f = l2 > 0 and math.max(0, math.min(1, ((X - ax) * dx + (Y - ay) * dy) / l2)) or 0
      local qx, qy = ax + dx * f, ay + dy * f
      local d = (qx - X) ^ 2 + (qy - Y) ^ 2
      if not best or d < best then best, bi = d, k + 2 end
    end
  end
  return bi, best and sqrt(best)
end
-- yards to walk from X, Y: to corner k, then along the path (a ride costs nothing here)
local function remaining(p, k, X, Y)
  local pts = p.pts
  local left = sqrt((pts[k] - X) ^ 2 + (pts[k + 1] - Y) ^ 2)
  for i = k, #pts - 3, 2 do
    if pts[i] and pts[i + 2] then left = left + sqrt((pts[i + 2] - pts[i]) ^ 2 + (pts[i + 3] - pts[i + 1]) ^ 2) end
  end
  return left
end
local function fresh(m, x, y, step)
  local p = W.path(m, x, y, step.m, step.x, step.y)
  if not p then return nil end
  -- a copy: the cached one is shared
  local q = { c = p.c, len = p.len, ride = p.ride, fly = p.fly, pts = {}, at = 3 }
  for k, v in ipairs(p.pts) do q.pts[k] = v end
  return q
end
function W.toStep(step)
  if not (step and step.m and step.x and step.y) then live.key, live.path = nil, nil return nil end
  local c, X, Y, m, x, y = W.origin()
  if not c then return live.path end
  local key = ("%d:%.1f:%.1f"):format(step.m, step.x, step.y)
  local p = live.key == key and live.path
  local now = GetTime()
  if p then
    local k, off = place(p, X, Y)
    if k and off <= OFF then
      p.at = k
      if now - live.fresh < FRESH then return p end
      live.fresh = now
      local q = fresh(m, x, y, step)
      if q and q.len + 20 < remaining(p, k, X, Y) then live.path = q; return q end
      return p
    end
  end
  -- at most twice a second (the arrow asks 30 times a second)
  if now - live.at < 0.5 and live.key == key then return live.path end
  live.at, live.fresh = now, now
  live.key, live.path = key, fresh(m, x, y, step)
  return live.path
end
-- where the arrow should point: a spot AHEAD yards along the path from where you are on it (world X, Y), and the
-- yards left to walk; nil when there's no path
function W.aim(step)
  local p = W.toStep(step)
  if not p then return nil end
  -- in the air: nothing to steer; how far it is from where you land
  local t = W.flying()
  if t then return nil, nil, p.len, "flying to " .. t.n end
  local c, X, Y = W.player()
  if not c or c ~= p.c then return nil end
  local pts = p.pts
  local j = math.min(p.at or 3, #pts - 1)
  if not pts[j] then j = j + 2 end
  -- from you to the corner ahead, then along the path
  local aimX, aimY, walked = nil, nil, 0
  local fx, fy = X, Y
  while true do
    local seg = sqrt((pts[j] - fx) ^ 2 + (pts[j + 1] - fy) ^ 2)
    if not aimX and walked + seg >= AHEAD then
      local f = seg > 0 and (AHEAD - walked) / seg or 0
      aimX, aimY = fx + (pts[j] - fx) * f, fy + (pts[j + 1] - fy) * f
    end
    walked = walked + seg
    if j + 2 > #pts - 1 or not pts[j + 2] then break end   -- the end, or a ride: aim at where you board
    fx, fy = pts[j], pts[j + 1]
    j = j + 2
  end
  if not aimX then aimX, aimY = pts[j], pts[j + 1] end
  -- the rest after a ride
  local rest = 0
  for i = j + 2, #pts - 3, 2 do
    if pts[i] and pts[i + 2] then rest = rest + sqrt((pts[i + 2] - pts[i]) ^ 2 + (pts[i + 3] - pts[i + 1]) ^ 2) end
  end
  return aimX, aimY, walked + rest, p.ride
end
-- /wfn blocked: the stretches of the way ahead of you, up to AHEAD_BLOCK yards, out of the graph; the way is found again.
-- Returns how many stretches, and the map spots of the first and last corner (for the log)
function W.block()
  local p = live.path
  local c, X, Y = W.player()
  if not (p and c and c == p.c) then return 0 end
  local G = graph(c)
  if not G then return 0 end
  local pts = p.pts
  local k = place(p, X, Y) or 3
  local n, walked, first, last = 0, 0, nil, nil
  for j = math.max(1, k - 2), #pts - 3, 2 do
    if not (pts[j] and pts[j + 2]) then break end   -- a ride: not a walk
    local i1, i2 = nodeAt(G, pts[j], pts[j + 1]), nodeAt(G, pts[j + 2], pts[j + 3])
    if i1 and i2 then
      cut(G, i1, i2)
      local b = blocks()
      b[#b + 1] = { c = c, pts[j], pts[j + 1], pts[j + 2], pts[j + 3] }
      n = n + 1
      first = first or { pts[j], pts[j + 1] }
      last = { pts[j + 2], pts[j + 3] }
    end
    walked = walked + sqrt((pts[j + 2] - pts[j]) ^ 2 + (pts[j + 3] - pts[j + 1]) ^ 2)
    if walked >= AHEAD_BLOCK and n > 0 then break end
  end
  if n > 0 then
    W.resetPaths()
    local m = C_Map.GetBestMapForUnit("player")
    local function mp(w) local x, y = W.toMap(m, w[1], w[2]) return x and math.floor(x * 1000 + 0.5) / 10, y and math.floor(y * 1000 + 0.5) / 10 end
    local ax, ay = mp(first)
    local bx, by = mp(last)
    if ns.log then ns.log.add("WALK_BLOCKED", { c = c, n = n, fm = m, fx = ax, fy = ay, tx = bx, ty = by,
      e = (function() local o = {} local b = blocks() for q = #b - n + 1, #b do o[#o + 1] = ("%.1f,%.1f,%.1f,%.1f"):format(b[q][1], b[q][2], b[q][3], b[q][4]) end return table.concat(o, " ") end)() }) end
    return n, ax, ay, bx, by
  end
  return 0
end
function W.unblock()
  local n = #blocks()
  AuDHDDB.walkBlocked = {}
  graphs = {}
  W.resetPaths()
  return n
end

-- distance and turn (radians, counter-clockwise, for an up-pointing arrow) from you to world X, Y; like Core's bearing
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
function W.bearing(X, Y)
  local c, PX, PY = W.player()
  if not c then return nil end
  local dx, dy = X - PX, Y - PY
  local facing = GetPlayerFacing and GetPlayerFacing()
  if not facing or isSecret(facing) then return sqrt(dx * dx + dy * dy), nil end
  return sqrt(dx * dx + dy * dy), atan2(dy, dx) - facing
end
