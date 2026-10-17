-- /way: your own waypoint, with its own arrow (separate from the route's). The user, 2026-10-17: "add the ability to
-- go /way <coordinates> to set a waypoint on the map with a separate arrow".
--   /way 42 54            this zone, x 42 y 54 (also "42, 54" or "42,54")
--   /way 42 54 cave door  with a note
--   /way Loch Modan 35 47 another zone, by name
--   /way                  where it is;  /way clear  removes it
-- The game's own map pin too, where this client has one (C_Map.SetUserWaypoint). /way stays TomTom's when TomTom is
-- loaded; /wfnway always works. Our own frame only: nothing protected.
local _, ns = ...
local W = {}
ns.way = W

local SIZE, ARRIVED = 64, 10   -- arrow size; yards that count as there
local frame, tex, distText, labelText
local arrivedAt

local function db()
  AuDHDDB.way = AuDHDDB.way or {}
  return AuDHDDB.way
end
local function say(msg) print("|cff66ccffAuDHD|r: " .. msg) end

-- green on course -> yellow to the side -> red behind (as the route arrow)
local function colourFor(turn)
  local off = math.abs(turn)
  while off > math.pi do off = math.abs(off - 2 * math.pi) end
  local f = off / math.pi
  if f < 0.5 then return f * 2, 1, 0 end
  return 1, 1 - (f - 0.5) * 2, 0
end

-- a zone by (part of) its name: the zones of both continents, the cities too
local function zoneByName(name)
  name = name:lower():gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then return nil end
  local best
  for id = 1411, 1460 do
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(id)
    local n = info and info.name and info.name:lower()
    if n == name then return id, info.name end
    if n and not best and n:find(name, 1, true) == 1 then best = { id, info.name } end
  end
  if best then return best[1], best[2] end
end

local function mapName(m)
  local info = C_Map.GetMapInfo and C_Map.GetMapInfo(m)
  return info and info.name or ("map " .. m)
end

local function gamePin(w)
  if not (C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return end
  pcall(function()
    if w then
      if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(w.m) then return end
      C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(w.m, w.x / 100, w.y / 100))
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    elseif C_Map.ClearUserWaypoint then
      C_Map.ClearUserWaypoint()
    end
  end)
end

function W.get() return db().w end

function W.set(m, x, y, note)
  db().w = { m = m, x = x, y = y, note = note }
  arrivedAt = nil
  gamePin(db().w)
  if frame then frame:Show() end
  if ns.log then ns.log.add("WAYPOINT_SET", { wm = m, wx = x, wy = y, note = note }) end
  return db().w
end

function W.clear()
  db().w = nil
  arrivedAt = nil
  gamePin(nil)
  if frame then frame:Hide() end
end

-- "/way [zone] x y [note]" -> map, x, y, note (or nil, why)
function W.parse(text)
  text = (text or ""):gsub(",", " ")
  local before, x, y, note = text:match("^%s*(.-)%s*(%d+%.?%d*)%s+(%d+%.?%d*)%s*(.-)%s*$")
  x, y = tonumber(x), tonumber(y)
  if not x or not y then return nil, "give the coordinates: /way 42 54 (or /way Dun Morogh 42 54)" end
  if x > 100 or y > 100 then return nil, "coordinates are 0-100" end
  local m
  if before and before ~= "" then
    m = zoneByName(before)
    if not m then return nil, ("no zone called %q"):format(before) end
  else
    m = C_Map.GetBestMapForUnit("player")
    if not m then return nil, "can't tell which zone you're in: add its name (/way Dun Morogh 42 54)" end
  end
  return m, x, y, note ~= "" and note or nil
end

function W.command(text)
  local t = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if t == "clear" or t == "reset" or t == "off" then
    W.clear()
    return say("waypoint cleared")
  end
  if t == "" then
    local w = W.get()
    if not w then return say("no waypoint (/way 42 54, /way Dun Morogh 42 54, /way clear)") end
    local d = ns.core.bearing(w)
    return say(("waypoint: %s %.1f, %.1f%s%s"):format(mapName(w.m), w.x, w.y, w.note and (" (" .. w.note .. ")") or "",
      d and (", %d yd away"):format(math.floor(d)) or ""))
  end
  local m, x, y, note = W.parse(text)
  if not m then return say(x) end
  W.set(m, x, y, note)
  say(("waypoint set: %s %.1f, %.1f%s"):format(mapName(m), x, y, note and (" (" .. note .. ")") or ""))
end

function W.update()
  if not frame then return end
  local w = W.get()
  if not w then frame:Hide() return end
  labelText:SetText("|cff66ccff/way|r " .. (w.note or ("%s %.1f, %.1f"):format(mapName(w.m), w.x, w.y)))
  local d, turn = ns.core.bearing(w)
  if not d then
    tex:Hide()
    distText:SetText("|cffaaaaaaanother zone or continent|r")
    return
  end
  tex:Show()
  if d < ARRIVED then
    tex:SetRotation(0)
    tex:SetVertexColor(0.3, 1, 0.3)
    distText:SetText("|cff40ff40Arrived|r")
    -- there: cleared after a few seconds
    arrivedAt = arrivedAt or GetTime()
    if GetTime() - arrivedAt > 5 then
      say("waypoint reached")
      W.clear()
    end
    return
  end
  arrivedAt = nil
  distText:SetText(("%d yd"):format(math.floor(d)))
  if turn then
    tex:SetRotation(turn)
    tex:SetVertexColor(colourFor(turn))
  else
    tex:SetRotation(0)
    tex:SetVertexColor(0.8, 0.8, 0.8)
  end
end

function W.create()
  if frame then return end
  local s = db()
  frame = CreateFrame("Frame", "AuDHDWayArrow", UIParent)
  frame:SetSize(SIZE + 120, SIZE + 40)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    s.p, s.rp, s.x, s.y = p, rp, x, y
  end)
  if s.p then frame:SetPoint(s.p, UIParent, s.rp, s.x, s.y) else frame:SetPoint("TOP", UIParent, "TOP", 180, -140) end

  tex = frame:CreateTexture(nil, "ARTWORK")
  tex:SetSize(SIZE, SIZE)
  tex:SetPoint("TOP")
  tex:SetTexture("Interface\\AddOns\\AuDHD\\Media\\arrow")
  distText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  distText:SetPoint("TOP", tex, "BOTTOM", 0, -2)
  labelText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  labelText:SetPoint("TOP", distText, "BOTTOM", 0, -2)
  labelText:SetWidth(SIZE + 120)
  labelText:SetWordWrap(false)
  -- X: done with it (the user, 2026-10-17: "the ability to x/close the vendor arrows for when you decide to keep going")
  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetSize(22, 22)
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  close:SetScript("OnClick", function()
    if ns.log then local w = W.get() ns.log.add("WAYPOINT_CLOSED", { note = w and w.note }) end
    W.clear()
  end)
  frame.close = close

  local acc = 0
  frame:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.05 then return end
    acc = 0
    W.update()
  end)
  if s.w then gamePin(s.w) else frame:Hide() end
end

-- /wfnway always; /way unless TomTom (loaded before us, by name) has it
local tomtom = false
pcall(function()
  local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  tomtom = loaded and loaded("TomTom") and true or false
end)
SLASH_AUDHDWAY1 = "/wfnway"
if not tomtom then SLASH_AUDHDWAY2 = "/way" end
SlashCmdList.AUDHDWAY = function(msg) W.command(msg) end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function() W.create() end)
