-- The range guide: how far your target is (yards) and whether you can shoot it (or, for a class without a bow, reach
-- it with your main spell: Lightning Bolt, Shadow Bolt, Smite...; R.main). The number turns green inside
-- Auto Shot range (the game's own check, so Hawk Eye and anything else that adds range counts), orange when it's too
-- close to shoot (the dead zone), red beyond. The game gives addons no distance to a mob, only "in range of this
-- spell / item / interaction or not", so the yards are the band between the nearest check that says out of range
-- and the closest that says in range. Item and interact checks are restricted on enemies in combat, so they're only
-- used out of combat (when you pull); in combat it's the spell checks. Anything the game hides is left out.
-- It sits on the target's nameplate (enemy nameplates on, V); without one it stays where you put it.
-- Our own frame only: nothing protected. /wfn range lock | unlock | scale <n> | reset | hide | show | test
local _, ns = ...
local R = {}
ns.range = R

local isSecret = issecretvalue or function() return false end
local AUTO_SHOT, HUNTERS_MARK = 75, 1130
-- what you pull with, by class: the first one you know (ranged weapon spells only with a ranged weapon on). A class
-- without a bow gets its main spell's reach, not the bow's (the user, 2026-10-17)
local RANGED = { 2764, 2480, 7918, 7919 }   -- Throw, Shoot Bow, Shoot Gun, Shoot Crossbow
local MAIN = {
  HUNTER = { AUTO_SHOT },
  WARRIOR = { "ranged", 100 },              -- a ranged weapon, else Charge
  ROGUE = { "ranged", 1752 },               -- a ranged weapon, else Sinister Strike
  MAGE = { 133, 116 },                      -- Fireball, Frostbolt
  WARLOCK = { 686 },                        -- Shadow Bolt
  PRIEST = { 585, 589 },                    -- Smite, Shadow Word: Pain
  SHAMAN = { 403, 8042 },                   -- Lightning Bolt, Earth Shock
  DRUID = { 5176, 8921 },                   -- Wrath, Moonfire
  PALADIN = { 20271 },                      -- Judgement
}
local MELEE_BY_CLASS = {
  HUNTER = { 2973, 2974, 1495 },            -- Raptor Strike, Wing Clip, Mongoose Bite: melee range
  WARRIOR = { 78 }, ROGUE = { 1752 },       -- Heroic Strike, Sinister Strike
}
local MELEE_SPELLS = {}
-- items whose use range is known (LibRangeCheck's list); the ones this client doesn't have just answer nothing
local ITEMS = {
  { 5, 37727 }, { 5, 8149 }, { 8, 34368 }, { 10, 32321 }, { 15, 33069 }, { 20, 10645 }, { 25, 24268 }, { 25, 41509 },
  { 30, 835 }, { 35, 24269 }, { 35, 18904 }, { 40, 28767 }, { 45, 23836 }, { 60, 32825 }, { 80, 35278 }, { 100, 33119 },
}
-- CheckInteractDistance: 3 duel (~10 yd), 2 trade (~11 yd), 4 follow (~28 yd)
local INTERACT = { { 10, 3 }, { 11, 2 }, { 28, 4 } }

local frame, yardsText, infoText
local hawkEye, hawkEyeMax = 0, 0
local wasNear = false   -- last look: in melee range or just outside it (to tell the dead zone from far away)

local function settings()
  AuDHDDB.range = AuDHDDB.range or { scale = 1, locked = false }
  return AuDHDDB.range
end

local function bool(v)
  if v == nil or isSecret(v) then return nil end
  if v == true or v == 1 then return true end
  if v == false or v == 0 then return false end
  return nil
end

local function spellName(id)
  local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
  if not n and GetSpellInfo then n = GetSpellInfo(id) end
  return n
end

local function known(id)
  if IsPlayerSpell then local ok, k = pcall(IsPlayerSpell, id); if ok and k ~= nil and not isSecret(k) then return k end end
  if IsSpellKnown then local ok, k = pcall(IsSpellKnown, id); if ok and k ~= nil and not isSecret(k) then return k end end
  return true
end

-- in range of a spell (by its name, so any rank counts): true / false, nil when the game won't say
local function spellInRange(id)
  local name = spellName(id)
  if not name or not known(id) then return nil end
  if C_Spell and C_Spell.IsSpellInRange then
    local ok, r = pcall(C_Spell.IsSpellInRange, name, "target")
    if ok then return bool(r) end
  end
  if IsSpellInRange then
    local ok, r = pcall(IsSpellInRange, name, "target")
    if ok then return bool(r) end
  end
end

local function spellRange(id)
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, id)
    if ok and type(info) == "table" then return info.minRange, info.maxRange end
  end
  if GetSpellInfo then
    local _, _, _, _, minR, maxR = GetSpellInfo(id)
    return minR, maxR
  end
end

local function itemInRange(item)
  local f = (C_Item and C_Item.IsItemInRange) or IsItemInRange
  if not f then return nil end
  local ok, r = pcall(f, item, "target")
  if ok then return bool(r) end
end

local function interactInRange(index)
  if not CheckInteractDistance then return nil end
  local ok, r = pcall(CheckInteractDistance, "target", index)
  if ok then return bool(r) end
end

-- Hawk Eye: 2 yards more range per rank, read from your talents
local function readTalents()
  hawkEye, hawkEyeMax = 0, 0
  if not GetNumTalentTabs or not GetTalentInfo then return end
  local ok = pcall(function()
    for tab = 1, GetNumTalentTabs() do
      for i = 1, (GetNumTalents(tab) or 0) do
        local name, _, _, _, rank, maxRank = GetTalentInfo(tab, i)
        if name == "Hawk Eye" then hawkEye, hawkEyeMax = rank or 0, maxRank or 3 end
      end
    end
  end)
  if not ok then hawkEye, hawkEyeMax = 0, 0 end
end

local function playerClass()
  local _, c = UnitClass("player")
  return c
end

-- the spell you pull with: id, its label, and whether it's Auto Shot. Cached until your spells, gear or level change
local main
function R.main()
  if main then return main end
  local class = playerClass()
  MELEE_SPELLS = MELEE_BY_CLASS[class] or {}
  local hasRanged = GetInventoryItemID and GetInventoryItemID("player", 18)
  local function try(id)
    if id == "ranged" then
      if not hasRanged then return end
      for _, r in ipairs(RANGED) do local m = try(r) if m then return m end end
      return
    end
    local name = spellName(id)
    if name and known(id) then return { id = id, label = id == AUTO_SHOT and "bow" or name } end
  end
  for _, id in ipairs(MAIN[class] or {}) do main = try(id) if main then break end end
  main = main or { label = "melee" }
  return main
end

-- your pulling reach: the spell's own numbers (Auto Shot: 8-35, plus Hawk Eye if the spell doesn't count it already)
function R.shootRange()
  local m = R.main()
  if not m.id then return 0, 5 end
  local minR, maxR = spellRange(m.id)
  local shot = m.id == AUTO_SHOT
  minR = (minR and not isSecret(minR) and minR > 0) and minR or (shot and 8 or 0)
  local base = (maxR and not isSecret(maxR) and maxR > 0) and maxR or (shot and 35 or 30)
  if shot and base <= 35 then base = base + 2 * hawkEye end
  return minR, base
end

-- what the game says right now: the band the target is in (lo..hi yards), and shoot = in / out / nil
-- checks caught saying "in range" while Auto Shot says the target is beyond its minimum range: a check that does it
-- LIES times is left out for the session (it said "too close to shoot" all the time, the user 2026-10-16: Raptor
-- Strike's check, most likely)
local LIES = 3
local caught, distrust = {}, {}
function R.trustAll() caught, distrust = {}, {} end
function R.measure()
  local minR, maxR = R.shootRange()
  local m = R.main()
  local shoot = m.id and spellInRange(m.id)
  local lo, hi = 0, math.huge
  local function note(yd, r, key)
    if r == nil or distrust[key] then return end
    if r == true and shoot == true and yd < minR then
      -- can't be: Auto Shot reaches it, so it's at least minR away
      caught[key] = (caught[key] or 0) + 1
      if caught[key] >= LIES then
        distrust[key] = true
        if ns.log then ns.log.add("RANGE_DISTRUST", { check = key, yd = yd, minR = minR }) end
      end
      return
    end
    if r == true and yd < hi then hi = yd end
    if r == false and yd > lo then lo = yd end
  end
  local melee
  for _, id in ipairs(MELEE_SPELLS) do
    local key = "spell" .. id
    local r
    if not distrust[key] then r = spellInRange(id) end
    if r ~= nil then
      note(5, r, key)
      if not (r == true and shoot == true) then melee = r end
      break
    end
  end
  note(100, spellInRange(HUNTERS_MARK), "spell" .. HUNTERS_MARK)
  if not InCombatLockdown() then
    for _, it in ipairs(ITEMS) do note(it[1], itemInRange(it[2]), "item" .. it[2]) end
    for _, c in ipairs(INTERACT) do note(c[1], interactInRange(c[2]), "interact" .. c[2]) end
  end
  if shoot == true then
    if maxR < hi then hi = maxR end
    if minR > lo then lo = minR end
  elseif shoot == false and minR <= 0 then
    if maxR > lo then lo = maxR end
  elseif shoot == false and melee ~= true and hi > minR then
    -- neither melee nor shooting: the dead zone (a check says it's inside the bow's reach, or you were near a moment
    -- ago) or beyond the bow
    if hi <= maxR or wasNear then
      if minR < hi then hi = minR end
      if melee == false and 5 > lo then lo = 5 end
    elseif maxR > lo then lo = maxR end
  end
  if lo > hi then lo = hi end
  return lo, hi, shoot, melee, minR, maxR
end

local function attackable()
  if not UnitExists("target") then return false end
  local ok, can = pcall(UnitCanAttack, "player", "target")
  if not ok or isSecret(can) or not can then return false end
  local okd, dead = pcall(UnitIsDead, "target")
  return not (okd and not isSecret(dead) and dead)
end

local function band(lo, hi)
  if hi == math.huge then return lo > 0 and (">%d yd"):format(lo) or "? yd" end
  if lo <= 0 then return ("<%d yd"):format(hi) end
  if lo == hi then return ("%d yd"):format(hi) end
  return ("%d-%d yd"):format(lo, hi)
end

-- pinned just above the target's nameplate; the saved spot when there's none (nameplates off, too far to show one)
local pinnedTo = false
local PLATE_GAP = -14   -- the plate's top is well above its name: the text just clears it (user, 2026-10-17)
local function home()
  local s = settings()
  frame:ClearAllPoints()
  if s.p then frame:SetPoint(s.p, UIParent, s.rp, s.x, s.y) else frame:SetPoint("CENTER", UIParent, "CENTER", 0, -140) end
end
local function anchor()
  local plate
  if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
    local ok, p = pcall(C_NamePlate.GetNamePlateForUnit, "target")
    if ok and p and not isSecret(p) and not (p.IsForbidden and p:IsForbidden()) then plate = p end
  end
  if plate == pinnedTo then return end
  pinnedTo = plate
  if plate then
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOM", plate, "TOP", 0, settings().gap or PLATE_GAP)
  else
    home()
  end
end

-- how high over the nameplate (the settings window's slider; nil: PLATE_GAP)
function R.setGap(v)
  settings().gap = v
  pinnedTo = false   -- re-pin now
  if frame and frame:IsShown() then anchor() end
end
R.PLATE_GAP = PLATE_GAP

function R.update()
  if not frame then return end
  if settings().hidden or not attackable() then frame:Hide(); return end
  anchor()
  frame:Show()
  local lo, hi, shoot, melee, minR, maxR = R.measure()
  local tooClose = minR > 0 and (melee == true or (shoot ~= true and hi <= minR))
  wasNear = melee == true or hi <= minR + 2
  local canShoot = shoot == true or (shoot == nil and lo >= minR and hi <= maxR and hi ~= math.huge)
  yardsText:SetText(band(lo, hi))
  if canShoot then yardsText:SetTextColor(0.25, 1, 0.25)
  elseif tooClose then yardsText:SetTextColor(1, 0.6, 0.1)
  else yardsText:SetTextColor(1, 0.25, 0.25) end
  local hawk = hawkEyeMax > 0 and (" (Hawk Eye %d/%d)"):format(hawkEye, hawkEyeMax) or ""
  -- and the threat on it, you and your pet (Threat.lua)
  local threat = ns.threat and ns.threat.line("target")
  local label = R.main().label
  local reach = minR > 0 and ("%s: %d-%d yd%s"):format(label, minR, maxR, hawk) or ("%s: %d yd"):format(label, maxR)
  infoText:SetText((tooClose and (label == "bow" and "too close to shoot  " or "too close  ") or "") .. reach .. (threat and ("\n" .. threat) or ""))
end

-- which checks this client answers (logged once a session, out of combat, so the band can be tuned)
local probed = false
local function probe()
  if probed or InCombatLockdown() or not attackable() then return end
  probed = true
  local items, interact, spells = {}, {}, {}
  for _, it in ipairs(ITEMS) do if itemInRange(it[2]) ~= nil then items[#items + 1] = it[2] end end
  for _, c in ipairs(INTERACT) do if interactInRange(c[2]) ~= nil then interact[#interact + 1] = c[2] end end
  local ids = { R.main().id or AUTO_SHOT, HUNTERS_MARK }
  for _, id in ipairs(MELEE_SPELLS) do ids[#ids + 1] = id end
  for _, id in ipairs(ids) do
    if spellInRange(id) ~= nil then spells[#spells + 1] = id end
  end
  local minR, maxR = R.shootRange()
  if ns.log then ns.log.add("RANGE_PROBE", { items = items, interact = interact, spells = spells, minR = minR, maxR = maxR, hawkEye = hawkEye }) end
end

function R.create()
  if frame then return end
  local s = settings()
  frame = ns.newFrame("Range", "Frame", "AuDHDRange", UIParent)
  frame:SetSize(160, 58)
  frame:SetScale(s.scale or 1)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(not s.locked)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) if not settings().locked and not pinnedTo then self:StartMoving() end end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    local st = settings()
    st.p, st.rp, st.x, st.y = p, rp, x, y
  end)
  home()

  infoText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  infoText:SetPoint("BOTTOM")   -- grows upwards: a threat line never runs into the nameplate
  yardsText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  yardsText:SetPoint("BOTTOM", infoText, "TOP", 0, 2)

  readTalents()
  local elapsed = 0
  local ticker = ns.newFrame("Range", "Frame")
  ticker:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.1 then return end
    elapsed = 0
    R.update()
  end)
  ticker:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_TARGET_CHANGED" then probe(); R.update() else main = nil; readTalents() end
  end)
  for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "SPELLS_CHANGED",
    "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP" }) do
    pcall(ticker.RegisterEvent, ticker, e)
  end
  frame:Hide()
end

function R.command(rest)
  local s = settings()
  local cmd, val = (rest or ""):match("^(%S*)%s*(%S*)")
  if cmd == "lock" then s.locked = true; frame:EnableMouse(false)
  elseif cmd == "unlock" then s.locked = false; frame:EnableMouse(true)
  elseif cmd == "scale" and tonumber(val) then s.scale = math.max(0.4, math.min(3, tonumber(val))); frame:SetScale(s.scale)
  elseif cmd == "reset" then
    s.p, s.rp, s.x, s.y, s.scale = nil, nil, nil, nil, 1
    frame:SetScale(1); pinnedTo = false; home()
  elseif cmd == "hide" then s.hidden = true; frame:Hide()
  elseif cmd == "show" then s.hidden = nil; R.update()
  elseif cmd == "test" then
    if not attackable() then return "range: target an enemy first" end
    probed = false; probe()
    local lo, hi, shoot, melee, minR, maxR = R.measure()
    local label = R.main().label
    return ("range: %s, %s %s, melee %s, reach %d-%d yd, Hawk Eye %d/%d%s"):format(band(lo, hi), label, tostring(shoot),
      tostring(melee), minR, maxR, hawkEye, hawkEyeMax, InCombatLockdown() and " (in combat: spell checks only)" or "")
  else
    return ("range guide: %s, scale %.1f%s (/wfn range lock | unlock | scale <0.4-3> | reset | hide | show | test)")
      :format(s.locked and "locked" or "unlocked (drag to move)", s.scale or 1, s.hidden and ", hidden" or "")
  end
  return ("range guide: %s"):format(cmd)
end
