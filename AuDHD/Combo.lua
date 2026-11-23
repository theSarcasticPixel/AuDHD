-- Combo points on the target's nameplate: a pip under it for each point you have on it, in the game's own combo point
-- art; all of them glow when you're full. Rogues, and druids in Cat Form (or with points still on the target). Our own
-- frame on the plate: nothing protected (a forbidden nameplate is left alone); no nameplate, no pips (the game's own
-- display still shows them). Settings, User Interface; /audhd combo on|off
local _, ns = ...
local C = {}
ns.combo = C

local isSecret = issecretvalue or function() return false end
local TEX = "Interface\\ComboFrame\\ComboPoint"
local CAT_FORM = 1
local STEP = 13   -- a pip's width and its gap

local function on() return not (AuDHDDB and AuDHDDB.comboOff) end

local function power(fn, ...)
  if not (fn and Enum and Enum.PowerType and Enum.PowerType.ComboPoints) then return nil end
  local ok, v = pcall(fn, ...)
  if ok and type(v) == "number" and not isSecret(v) then return v end
end
-- your points on the target and how many there can be; nil when the game doesn't say (or keeps it secret)
function C.points()
  local n
  if GetComboPoints then
    local ok, v = pcall(GetComboPoints, "player", "target")
    if ok and type(v) == "number" and not isSecret(v) then n = v end
  end
  n = n or power(UnitPower, "player", Enum and Enum.PowerType and Enum.PowerType.ComboPoints)
  if not n then return nil end
  local max = power(UnitPowerMax, "player", Enum and Enum.PowerType and Enum.PowerType.ComboPoints)
  return n, (max and max > 0) and max or 5
end

-- whether you use them now: a rogue, or a druid in Cat Form or with points on the target
function C.applies(n)
  local _, class = UnitClass("player")
  if class == "ROGUE" then return true end
  if class ~= "DRUID" then return false end
  if (n or 0) > 0 then return true end
  return GetShapeshiftFormID and GetShapeshiftFormID() == CAT_FORM or false
end

local function plateFor(unit)
  if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
  local ok, p = pcall(C_NamePlate.GetNamePlateForUnit, unit)
  if not ok or not p or isSecret(p) or (p.IsForbidden and p:IsForbidden()) then return nil end
  return p
end

local bar
local function pip(i)
  local p = bar.pips[i]
  if p then return p end
  p = {}
  p.bg = bar:CreateTexture(nil, "BACKGROUND")
  p.bg:SetTexture(TEX)
  p.bg:SetTexCoord(0, 0.375, 0, 1)
  p.bg:SetSize(12, 16)
  p.bg:SetPoint("LEFT", (i - 1) * STEP, 0)
  p.lit = bar:CreateTexture(nil, "ARTWORK")
  p.lit:SetTexture(TEX)
  p.lit:SetTexCoord(0.375, 0.5625, 0, 1)
  p.lit:SetSize(8, 16)
  p.lit:SetPoint("TOPLEFT", p.bg, "TOPLEFT", 2, 0)
  -- (full: the same art again, added on top)
  p.glow = bar:CreateTexture(nil, "OVERLAY")
  p.glow:SetTexture(TEX)
  p.glow:SetTexCoord(0.375, 0.5625, 0, 1)
  p.glow:SetAllPoints(p.lit)
  p.glow:SetBlendMode("ADD")
  bar.pips[i] = p
  return p
end

function C.update()
  local n, max
  if on() then n, max = C.points() end
  local plate = n and C.applies(n) and UnitExists("target") and UnitCanAttack("player", "target") and plateFor("target")
  if not plate then
    if bar then bar:Hide() end
    return
  end
  if not bar then
    bar = ns.newFrame("Combo", "Frame", "AuDHDComboPoints", UIParent)
    bar:SetHeight(16)
    bar.pips = {}
  end
  if bar.plate ~= plate then
    bar.plate = plate
    bar:SetParent(plate)
    bar:ClearAllPoints()
    bar:SetPoint("TOP", plate, "BOTTOM", 0, 4)
  end
  bar:SetWidth(max * STEP)
  for i = 1, math.max(max, #bar.pips) do
    local p = pip(i)
    local here = i <= max
    p.bg:SetShown(here)
    p.lit:SetShown(here and i <= n)
    p.glow:SetShown(here and i <= n and n >= max)
  end
  bar:Show()
end
C.bar = function() return bar end   -- (the smoke test)

-- /audhd combo on | off
function C.command(rest)
  if rest == "off" then AuDHDDB.comboOff = true elseif rest == "on" then AuDHDDB.comboOff = nil end
  pcall(C.update)
  return "combo points on the target's nameplate: " .. (AuDHDDB.comboOff and "off (/audhd combo on)" or "on (/audhd combo off)")
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_TARGET_CHANGED", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "PLAYER_COMBO_POINTS",
    "UPDATE_SHAPESHIFT_FORM", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, unit)
  if (event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT") and unit ~= "player" then return end
  pcall(C.update)
end)
