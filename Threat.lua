-- Threat on the nameplates (the user, 2026-10-16: "can we have the threat show on the nameplates along with the range
-- indicator"): on each enemy nameplate in a fight with you or your pet, who has it and your share:
--   YOU (red)      you have aggro: back off, or Feign Death
--   PET (green)    your pet holds it
--   62% (yellow..) your threat against whoever holds it, coloured as the game colours threat (grey < 80% < yellow
--                  < orange < red: about to pull it)
-- The range guide (Range.lua) shows the same for your target, with your pet's share. The game's threat API only;
-- our own frames on the nameplates: nothing protected (a forbidden nameplate is left alone).
local _, ns = ...
local T = {}
ns.threat = T

local isSecret = issecretvalue or function() return false end

-- one unit's threat on mob: isTanking, status (0..3), scaled % (100 = pulls it), or nil
local function situation(who, mob)
  if not UnitDetailedThreatSituation or (who == "pet" and not UnitExists("pet")) then return nil end
  local ok, tanking, status, pct = pcall(UnitDetailedThreatSituation, who, mob)
  if not ok or status == nil or isSecret(status) or isSecret(pct) then return nil end
  return tanking, status, pct or 0
end

local function colour(status)
  if GetThreatStatusColor then
    local ok, r, g, b = pcall(GetThreatStatusColor, status)
    if ok and r then return r, g, b end
  end
  if status == 3 then return 1, 0, 0 elseif status == 2 then return 1, 0.6, 0 elseif status == 1 then return 1, 1, 0.47 end
  return 0.69, 0.69, 0.69
end
local function hex(r, g, b) return ("|cff%02x%02x%02x"):format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)) end

-- the short label for mob: "YOU", "PET", "62%", or nil (no fight with you or your pet)
function T.short(mob)
  local me, myStatus, myPct = situation("player", mob)
  local pet, petStatus = situation("pet", mob)
  if me == nil and pet == nil then return nil end
  if me then return hex(1, 0.15, 0.15) .. "YOU|r" end
  if pet then return hex(0.3, 1, 0.3) .. "PET|r" end
  return hex(colour(myStatus or 0)) .. ("%d%%"):format(math.floor(myPct or 0)) .. "|r"
end

-- the long line for the range guide: "threat: PET has it, you 45%" or nil
function T.line(mob)
  local me, myStatus, myPct = situation("player", mob)
  local pet, _, petPct = situation("pet", mob)
  if me == nil and pet == nil then return nil end
  local mine = me and (hex(1, 0.15, 0.15) .. "YOU have it|r")
    or me ~= nil and (hex(colour(myStatus or 0)) .. ("you %d%%"):format(math.floor(myPct or 0)) .. "|r") or nil
  if pet then return hex(0.3, 1, 0.3) .. "PET has it|r" .. (mine and (", " .. mine) or "") end
  if petPct then return (mine and (mine .. ", ") or "") .. ("pet %d%%"):format(math.floor(petPct)) end
  return mine
end

-- ------------------------------------------------------------------ the nameplate labels
local labels = {}   -- by nameplate unit token ("nameplate3")
local function plateFor(unit)
  if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
  local ok, p = pcall(C_NamePlate.GetNamePlateForUnit, unit)
  if not ok or not p or isSecret(p) or (p.IsForbidden and p:IsForbidden()) then return nil end
  return p
end
local function label(unit)
  local l = labels[unit]
  local plate = plateFor(unit)
  if not plate then if l then l:Hide() end return nil end
  if not l then
    l = ns.newFrame("Threat", "Frame", nil, UIParent)
    l:SetSize(40, 14)
    l.text = l:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l.text:SetPoint("CENTER")
    labels[unit] = l
  end
  if l.plate ~= plate then
    l.plate = plate
    l:SetParent(plate)
    l:ClearAllPoints()
    l:SetPoint("LEFT", plate, "RIGHT", -6, 0)
  end
  return l
end
local function show(unit)
  if AuDHDDB and AuDHDDB.threatHidden then return end
  local enemy = UnitCanAttack and UnitCanAttack("player", unit)
  local text = enemy and T.short(unit)
  local l = text and label(unit) or labels[unit]
  if not l then return end
  if text then l.text:SetText(text); l:Show() else l:Hide() end
end
function T.update()
  if AuDHDDB and AuDHDDB.threatHidden then
    for _, l in pairs(labels) do l:Hide() end
    return
  end
  for unit, l in pairs(labels) do
    if UnitExists(unit) then show(unit) else l:Hide() end
  end
end

function T.enable()
  local f = ns.newFrame("Threat", "Frame")
  for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_REGEN_ENABLED" }) do
    pcall(f.RegisterEvent, f, e)
  end
  f:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then pcall(show, unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then if labels[unit] then labels[unit]:Hide() end
    else pcall(T.update) end
  end)
  -- threat moves without an event for every change: look again a few times a second
  local acc = 0
  f:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.25 then return end
    acc = 0
    if C_NamePlate and C_NamePlate.GetNamePlates then
      local ok, plates = pcall(C_NamePlate.GetNamePlates)
      for _, p in ipairs(ok and plates or {}) do
        local unit = p.namePlateUnitToken or (p.UnitFrame and p.UnitFrame.unit)
        if unit and not isSecret(unit) then pcall(show, unit) end
      end
    end
    pcall(T.update)
  end)
end

-- /wfn threat on | off
function T.command(rest)
  if rest == "off" then AuDHDDB.threatHidden = true elseif rest == "on" then AuDHDDB.threatHidden = nil end
  pcall(T.update)
  return "threat on nameplates: " .. (AuDHDDB.threatHidden and "off (/wfn threat on)" or "on (/wfn threat off)")
end
