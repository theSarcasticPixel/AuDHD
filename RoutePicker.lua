-- The route picker (the user, 2026-10-16: "there should be a button to pick the next route we want to take, with time
-- estimates next to them so we know how long it will be to complete the next level range"): the routes for your race
-- and class that still take you somewhere (their target is above your level), fastest first, each with the planner's
-- time to its target level and where that time goes. Click one to follow it. Opens by itself when a route is finished;
-- the window's Routes button and /wfn routes open it too. The routes are planned on the PC (tools/plan_route.mjs) from
-- your log: the times are the planner's estimates from where you were then.
local _, ns = ...
local P = {}
ns.picker = P

local frame, rows = nil, {}
local ROW_H, WIDTH = 62, 480

local function duration(min)
  min = math.floor((min or 0) + 0.5)
  if min < 60 then return ("%d min"):format(min) end
  return ("%d h %02d min"):format(math.floor(min / 60), min % 60)
end
local function short(min)
  min = math.floor((min or 0) + 0.5)
  if min < 60 then return ("%dm"):format(min) end
  return ("%dh%02d"):format(math.floor(min / 60), min % 60)
end

-- the routes worth offering: { key, r }, fastest first
function P.choices()
  local _, race = UnitRace("player")
  local _, class = UnitClass("player")
  local level = UnitLevel("player") or 1
  local out = {}
  for key, r in pairs(ns.routes or {}) do
    local sameChar = ns.raceFits(r.race, race) and (not r.class or not class or r.class:upper() == class:upper())
    if sameChar and (r.target or 0) > level then out[#out + 1] = { key = key, r = r } end
  end
  table.sort(out, function(a, b) return (a.r.minutes or 1e9) < (b.r.minutes or 1e9) end)
  return out
end

-- a route's lines under its name: how long and how fast, and where the time goes (the three zones that take longest)
function P.parts(r)
  local zones = {}
  for _, z in ipairs(r.zones or {}) do zones[#zones + 1] = z end
  table.sort(zones, function(a, b) return a.min > b.min end)
  local where = {}
  for i = 1, math.min(3, #zones) do where[#where + 1] = ("%s %s"):format(zones[i].z, short(zones[i].min)) end
  if #zones > 3 then where[#where + 1] = ("+%d more"):format(#zones - 3) end
  local time = ("|cffffffff%s|r to level %d"):format(duration(r.minutes), r.target or 0)
  if r.xph then time = time .. ("   |cff88ccff%dk XP/h|r"):format(math.floor(r.xph / 1000 + 0.5)) end
  return time, table.concat(where, ", ")
end
function P.describe(r)
  local time, where = P.parts(r)
  return time .. (where ~= "" and ("  |cffaaaaaa%s|r"):format(where) or "")
end

-- the name without its level range (the time line says where it goes)
-- (a Hunter route in two styles says which: pet first, or the fastest overall)
local STYLE = { pet = " (pet first)", fast = " (fastest)" }
local function name(r) return ((r.title or "?"):gsub(":%s*level %d+ to %d+$", "")) .. (STYLE[r.style] or "") end

local function create()
  frame = ns.newFrame("RoutePicker", "Frame", "AuDHDRoutePicker", UIParent, "BackdropTemplate")
  frame:SetSize(WIDTH, 120)
  frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                      tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  frame:SetBackdropColor(0, 0, 0, 0.92)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
  frame:SetFrameStrata("DIALOG")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.title:SetPoint("TOPLEFT", 12, -10)
  frame.title:SetText("Choose your next route")
  frame.sub = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.sub:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -3)
  frame.sub:SetPoint("RIGHT", -12, 0)
  frame.sub:SetJustifyH("LEFT")
  local close = ns.newFrame("RoutePicker", "Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function() frame:Hide() end)
  -- closed: back to the window it was opened from (the settings hide while it's up)
  frame:SetScript("OnHide", function()
    local back = frame.back
    frame.back = nil
    if back then back() end
  end)
  frame:Hide()
end

local function row(i)
  local b = rows[i]
  if b then return b end
  b = ns.newFrame("RoutePicker", "Button", nil, frame, "BackdropTemplate")
  b:SetSize(WIDTH - 20, ROW_H - 4)
  b:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                  tile = true, tileSize = 16, edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
  b:SetBackdropColor(0.1, 0.1, 0.15, 0.9)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetPoint("TOPLEFT", 2, -2)
  hl:SetPoint("BOTTOMRIGHT", -2, 2)
  hl:SetColorTexture(1, 0.8, 0.3, 0.15)
  -- three lines that never wrap: name (tags on the right), time and XP/h, the main zones
  local function text(font)
    local f = b:CreateFontString(nil, "OVERLAY", font)
    f:SetJustifyH("LEFT")
    f:SetWordWrap(false)
    return f
  end
  b.tag = text("GameFontNormalSmall")
  b.tag:SetPoint("TOPRIGHT", -10, -8)
  b.tag:SetJustifyH("RIGHT")
  b.name = text("GameFontNormal")
  b.name:SetPoint("TOPLEFT", 10, -7)
  b.name:SetPoint("RIGHT", b.tag, "LEFT", -8, 0)
  b.info = text("GameFontHighlightSmall")
  b.info:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -5)
  b.info:SetPoint("RIGHT", -10, 0)
  b.where = text("GameFontDisableSmall")
  b.where:SetPoint("TOPLEFT", b.info, "BOTTOMLEFT", 0, -4)
  b.where:SetPoint("RIGHT", -10, 0)
  b:SetScript("OnClick", function(self)
    PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
    ns.core.setRoute(self.key)
    frame:Hide()
  end)
  rows[i] = b
  return b
end

function P.show(back)
  if not frame then create() end
  frame.back = back
  local list = P.choices()
  for _, b in ipairs(rows) do b:Hide() end
  local current = AuDHDDB.route
  for i, c in ipairs(list) do
    local b = row(i)
    b.key = c.key
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -44 - (i - 1) * ROW_H)
    local tags = {}
    if i == 1 and #list > 1 then tags[#tags + 1] = "|cff40ff40fastest|r" end
    if c.key == current then tags[#tags + 1] = "|cffaaaaaafollowing now|r" end
    if c.r.start and c.r.start > (UnitLevel("player") or 1) + 1 then tags[#tags + 1] = ("|cffff6040planned from level %d|r"):format(c.r.start) end
    if c.r.reached == false then tags[#tags + 1] = ("|cffff6040doesn't reach %d|r"):format(c.r.target or 0) end
    b.tag:SetText(table.concat(tags, "  "))
    b.name:SetText(name(c.r))
    local time, where = P.parts(c.r)
    b.info:SetText(time)
    b.where:SetText(where)
    b:Show()
  end
  frame.sub:SetText(#list > 0 and "Click a route to follow it. Times are the planner's estimates."
    or "No planned routes go beyond your level yet: ask for the next ones to be planned (from your log).")
  frame:SetHeight(50 + math.max(1, #list) * ROW_H + 6)
  frame:Show()
end

function P.toggle()
  if frame and frame:IsShown() then frame:Hide() else P.show() end
end
