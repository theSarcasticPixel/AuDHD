-- Routes other addons send, drawn on the world map and minimap beside ours (RouteMap.lua): the book collecting route
-- of Books on map (Forever), for one. Such addons send their route to Shortest Path Forever through its public API
-- (ShortestPathForever.API, version 1: Navigate, NavigateRoute, CurrentStop, Cancel); while Shortest Path Forever isn't
-- loaded, AuDHD answers it instead (set up at login, when every addon has loaded). Only drawn: our arrow and route stay
-- on the guide. The engine's own hand-off (AuDHDEngine/Nav/Handoff.lua) passes over this stand-in (standIn), so it never
-- hands our route to it. A bar shows how far its ways are worked out (above the sender's own window when we know it)
local _, ns = ...
local S = {}
ns.sideRoute = S

local MAX_STOPS = 64
local journeys = {}   -- owner -> { { m, x, y (0..100), title, tip } }
local order = {}      -- the owners, the one that sent last at the end: its route is the one drawn

local since, readyAt   -- when the route (or your continent) last changed, for the bar; when its ways were all in
local function redraw() if ns.routemap and ns.routemap.refreshSide then ns.routemap.refreshSide() end end
local function drop(owner) for i = #order, 1, -1 do if order[i] == owner then table.remove(order, i) end end end

-- a stop as sent: a map, x and y in 0..1, a title and a tooltip line; nil when it isn't one
local function stopOf(map, x, y, title, tip)
  if type(map) ~= "number" or type(x) ~= "number" or type(y) ~= "number" or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
  return { m = map, x = x * 100, y = y * 100, title = type(title) == "string" and title or nil,
           tip = type(tip) == "string" and tip or nil }
end
local function set(owner, stops)
  if type(owner) ~= "string" or #stops == 0 then return false end
  journeys[owner] = stops
  drop(owner)
  order[#order + 1] = owner
  since, readyAt = GetTime(), nil
  redraw()
  return true
end

local API = { version = 1, standIn = "AuDHD" }
-- one place: a route of one stop
function API.Navigate(owner, map, x, y, title)
  local s = stopOf(map, x, y, title)
  return s and set(owner, { s }) or false
end
-- stops = { { map, x, y, title, tooltip, kind }, ... }: the first 64. Each sent again replaces the last
function API.NavigateRoute(owner, stops)
  if type(stops) ~= "table" then return false end
  local out = {}
  for i, st in ipairs(stops) do
    if i > MAX_STOPS then break end
    local s = type(st) == "table" and stopOf(st.map, st.x, st.y, st.title, st.tooltip)
    if not s then return false end
    out[#out + 1] = s
  end
  return set(owner, out)
end
-- the stop the route is on (the first), or nil when that addon has none here
function API.CurrentStop(owner)
  local s = journeys[owner] and journeys[owner][1]
  if s then return { map = s.m, x = s.x / 100, y = s.y / 100, title = s.title } end
end
function API.Cancel(owner)
  if not journeys[owner] then return false end
  journeys[owner] = nil
  drop(owner)
  redraw()
  return true
end
S.API = API

-- the route drawn: { owner, name (the addon's title, without colours), stops }, or nil
function S.current()
  local owner = order[#order]
  local stops = owner and journeys[owner]
  if not stops then return nil end
  local meta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  local ok, title = pcall(function() return meta and meta(owner, "Title") end)
  local name = ok and type(title) == "string" and title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") or owner
  return { owner = owner, name = name, stops = stops }
end

-- ------------------------------------------------------------------ how far its ways are worked out
-- done and total of the ways drawn (from you to its first stop, and between its next stops on your continent, as the
-- world map draws them), then "ready", "working" or "away" (its first stop is on another continent: the engine plans
-- only on yours); nil with no route, or with the travel planner off (Walk.lua's lines come at once). Asking is what
-- works them out, map open or not
function S.progress()
  local r, W, R = S.current(), ns.walk, ns.route
  if not (r and W and R and R.planning and R.planning()) then return nil end
  local here = W.player()
  if not here then return nil end
  local function cont(st) return (W.toWorld(st.m, st.x, st.y)) end
  if cont(r.stops[1]) ~= here then return 0, 0, "away" end
  local done, total = 0, 1
  if W.toStep(r.stops[1], "side") or W.slotNone("side") then done = 1 end
  for i = 2, math.min(#r.stops, ns.routemap and ns.routemap.SIDE_WORLD or 15) do
    local a, b = r.stops[i - 1], r.stops[i]
    if cont(a) == here and cont(b) == here then
      total = total + 1
      if R.between(a.m, a.x, a.y, b.m, b.x, b.y, true) ~= nil then done = done + 1 end
    end
  end
  return done, total, done >= total and "ready" or "working"
end

-- what the bar shows at now: { text, done, total }, or nil (hidden). From when a route comes in (or you reach another
-- continent) until its ways are in, then "ready" for READY_FOR seconds; "away" for AWAY_FOR. Not again while you walk it
local READY_FOR, AWAY_FOR = 3, 6
local lastC
function S.barModel(now)
  local r = S.current()
  if not (r and ns.walk) then return nil end
  local c = ns.walk.player()
  if c and c ~= lastC then lastC, since, readyAt = c, now, nil end
  if not since then return nil end
  local done, total, state = S.progress()
  if not state then return nil end
  if state == "away" then
    if now - since > AWAY_FOR then since = nil return nil end
    return { text = r.name .. ": next stop is on another continent", done = 0, total = 1 }
  elseif state == "ready" then
    readyAt = readyAt or now
    if now - readyAt > READY_FOR then since = nil return nil end
    return { text = r.name .. ": route ready", done = total, total = total }
  end
  readyAt = nil
  return { text = ("%s: finding the way %d/%d"):format(r.name, done, total), done = done, total = total }
end

-- the window each sender shows its route in: the bar goes above it while it's open, else near the top of the screen
local WINDOWS = { Books_on_map_Forever = "BooksOnMapForeverRoute" }
function S.window(owner)
  local w = WINDOWS[owner] and _G[WINDOWS[owner]]
  if w and w.IsShown and w:IsShown() then return w end
end
local bar
local function makeBar()
  bar = ns.newFrame("SideRoute", "StatusBar", "AuDHDSideRouteBar", UIParent, "BackdropTemplate")
  bar:SetSize(290, 18)
  bar:SetFrameStrata("MEDIUM")
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetStatusBarColor(0.78, 0.5, 1)
  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(bar)
  bg:SetColorTexture(0, 0, 0, 0.6)
  if bar.SetBackdrop then
    bar:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
                      insets = { left = 2, right = 2, top = 2, bottom = 2 } })
  end
  bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.text:SetPoint("LEFT", bar, "LEFT", 6, 0)
  bar.text:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
  bar.text:SetWordWrap(false)
  bar:Hide()
end
-- the bar as it is now; returns the model shown and what it's above (the window, or nil: the top of the screen)
function S.updateBar()
  local m = S.barModel(GetTime())
  if not m then
    if bar then bar:Hide() end
    return nil
  end
  if not bar then makeBar() end
  local w = S.window(S.current().owner)
  bar:ClearAllPoints()
  if w then
    bar:SetPoint("BOTTOM", w, "TOP", 0, 4)
    bar:SetWidth(math.max(w:GetWidth() or 290, 200))
  else
    bar:SetPoint("TOP", UIParent, "TOP", 0, -96)
    bar:SetWidth(290)
  end
  bar:SetMinMaxValues(0, math.max(m.total, 1))
  bar:SetValue(m.done)
  bar.text:SetText(m.text)
  bar:Show()
  return m, w
end

-- answers for Shortest Path Forever while it isn't loaded; true when it does
function S.install()
  if _G.ShortestPathForever ~= nil then return false end
  local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
  if loaded and loaded("ShortestPathForever") then return false end
  _G.ShortestPathForever = { API = API }
  return true
end

local frame = ns.newFrame("SideRoute", "Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
  pcall(S.install)
  C_Timer.NewTicker(0.2, function() pcall(S.updateBar) end)
end)
