-- Click-cast healing (the user, 2026-10-17: "you can assign a spell+rank to any mouse button and it shows your party in a
-- horizontal line across the bottom-middle of your screen (about halfway between the bottom of the screen and the
-- middle)"). Off until you switch it on in the settings or with /wfn heal on.
--   Your party (you first) as health bars in a row, centred, a quarter of the screen up from the bottom. Click one with
--   a mouse button and it casts the spell (and rank) you set for that button on them. Nothing set for the left button:
--   it targets them.
--   The spells: the settings' "Click-cast spells" button (or /wfn heal setup), a row per mouse button. Click a row to
--   pick from your spellbook, or drag a spell from your spellbook onto it; right-click clears it.
-- Secure unit buttons: the game casts on your click, the addon only says which spell. Their spells, places and the
-- whole row can only change out of combat (done as the fight ends).
local _, ns = ...
local H = {}
ns.heal = H

local UNITS = { "player", "party1", "party2", "party3", "party4" }
local BUTTONS = {
  { "LeftButton", "Left click" }, { "RightButton", "Right click" }, { "MiddleButton", "Middle click" },
  { "Button4", "Mouse button 4" }, { "Button5", "Mouse button 5" },
}
-- { saved key's prefix, column title, the attribute's prefix }
local MODS = { { "", "Click", "*" }, { "shift-", "Shift + click", "shift-" }, { "ctrl-", "Ctrl + click", "ctrl-" } }
local W, HT, GAP = 110, 44, 6
local isSecret = issecretvalue or function() return false end

-- each character's own spells (a priest's Lesser Heal is no use to your druid: the user, 2026-10-18), and its own on
-- or off; the first ones saved were for the whole account, and are dropped
local function charKey()
  return (UnitName("player") or "?") .. "-" .. ((GetRealmName and GetRealmName()) or "?")
end
local function db()
  AuDHDDB.heal = AuDHDDB.heal or {}
  local all = AuDHDDB.heal
  if all.binds or all.on ~= nil then all.binds, all.on = nil, nil end
  all.chars = all.chars or {}
  local key = charKey()
  all.chars[key] = all.chars[key] or {}
  local d = all.chars[key]
  d.binds = d.binds or {}
  return d
end
local function log(e, t) if ns.log then ns.log.add(e, t) end end

local function spellInfo(id)
  if C_Spell and C_Spell.GetSpellInfo then
    local i = C_Spell.GetSpellInfo(id)
    if i then return i.name, i.iconID end
  end
  if GetSpellInfo then
    local n, _, icon = GetSpellInfo(id)
    return n, icon
  end
end
local function spellRank(id)
  local s = (C_Spell and C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id)) or (GetSpellSubtext and GetSpellSubtext(id))
  if s and s ~= "" then return s end
end
local function helpful(id)
  if C_Spell and C_Spell.IsSpellHelpful then return C_Spell.IsSpellHelpful(id) end
  if IsHelpfulSpell then local n = spellInfo(id) return n and IsHelpfulSpell(n) end
end
local function harmful(id)
  if C_Spell and C_Spell.IsSpellHarmful then return C_Spell.IsSpellHarmful(id) end
  if IsHarmfulSpell then local n = spellInfo(id) return n and IsHarmfulSpell(n) end
end
-- "Healing Wave (Rank 3)"
function H.label(bind)
  if not bind then return nil end
  return bind.rank and ("%s (%s)"):format(bind.name, bind.rank) or bind.name
end

-- your spellbook's spells, every rank it lists: the ones you can cast on someone else, or all of them when the game
-- can't say which those are; with `everything`, your other spells after them (enemy = true)
function H.bookSpells(everything)
  local all, seen = {}, {}
  local function add(id, name, rank, passive)
    if not id or not name or passive or seen[id] then return end
    seen[id] = true
    if not rank or rank == "" then rank = spellRank(id) end
    all[#all + 1] = { id = id, name = name, rank = rank ~= "" and rank or nil }
  end
  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and Enum and Enum.SpellBookSpellBank then
    for i = 1, C_SpellBook.GetNumSpellBookSkillLines() or 0 do
      local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
      if line and line.itemIndexOffset then
        for slot = line.itemIndexOffset + 1, line.itemIndexOffset + (line.numSpellBookItems or 0) do
          local it = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
          if it and it.spellID and (not (Enum.SpellBookItemType and it.itemType) or it.itemType == Enum.SpellBookItemType.Spell) then
            add(it.spellID, it.name, it.subName, it.isPassive)
          end
        end
      end
    end
  elseif GetNumSpellTabs then
    local book = BOOKTYPE_SPELL or "spell"
    for t = 1, GetNumSpellTabs() do
      local _, _, offset, n = GetSpellTabInfo(t)
      for slot = (offset or 0) + 1, (offset or 0) + (n or 0) do
        local name, rank, id = GetSpellBookItemName(slot, book)
        add(id, name, rank, IsPassiveSpell and IsPassiveSpell(slot, book))
      end
    end
  end
  local out, rest = {}, {}
  for _, s in ipairs(all) do if helpful(s.id) then out[#out + 1] = s else s.enemy = true rest[#rest + 1] = s end end
  if #out == 0 then out, rest = all, {} end
  local function rankN(s) return tonumber(s.rank and s.rank:match("%d+")) or 0 end
  local function byName(a, b) if a.name ~= b.name then return a.name < b.name end return rankN(a) > rankN(b) end
  table.sort(out, byName)
  -- everything: the rest after them, marked (Purge, the user 2026-10-18: "click casting cant select purge"; the game
  -- says who it works on when you click)
  if everything then
    table.sort(rest, byName)
    for _, s in ipairs(rest) do out[#out + 1] = s end
  end
  return out
end

-- what each mouse button does on the frames, plain and with Shift or Ctrl held (the user, 2026-10-18: "we need to add
-- shift and control modifiers"): { ["*1"] = { type, spell }, ["shift-1"] = ..., ["ctrl-1"] = ... }. A plain click's
-- spell ("*") is also what any other modifier does when that one has nothing set.
function H.plan()
  local d, out = db(), {}
  for i, mb in ipairs(BUTTONS) do
    for _, m in ipairs(MODS) do
      local bind = d.binds[m[1] .. mb[1]]
      -- a damaging spell goes to whoever they're targeting (the user, 2026-10-18: "damaging spells ... to the target of
      -- the target you press"): click the tank's box, hit what the tank is hitting
      if bind then out[m[3] .. i] = { "spell", bind.id, harmful(bind.id) and "target" or nil }
      elseif m[1] == "" and i == 1 then out[m[3] .. i] = { "target" }
      else out[m[3] .. i] = {} end
    end
  end
  return out
end

local container, units, ticker = nil, {}, nil
local pending = {}

local function applyBinds()
  if not container then return end
  if InCombatLockdown() then pending.binds = true return end
  pending.binds = nil
  local plan = H.plan()
  for _, b in ipairs(units) do
    for key, p in pairs(plan) do
      local prefix, i = key:match("^(.-)(%d)$")
      b:SetAttribute(prefix .. "type" .. i, p[1])
      b:SetAttribute(prefix .. "spell" .. i, p[2])
      b:SetAttribute(prefix .. "unit" .. i, p[3] and (b.unit .. p[3]) or nil)
    end
  end
end

-- a quarter of the screen up from the bottom: halfway between the bottom and the middle
local function place()
  if InCombatLockdown() then pending.place = true return end
  pending.place = nil
  container:ClearAllPoints()
  container:SetPoint("CENTER", UIParent, "BOTTOM", 0, (UIParent:GetHeight() or 800) / 4)
end

-- the members there are, side by side and centred (who's shown is the game's own unit watch, safe in a fight too)
function H.layout()
  if not container then return end
  if InCombatLockdown() then pending.layout = true return end
  pending.layout = nil
  local shown = {}
  for _, b in ipairs(units) do if UnitExists(b.unit) then shown[#shown + 1] = b end end
  local total = #shown * W + math.max(0, #shown - 1) * GAP
  local placed = {}
  for i, b in ipairs(shown) do
    b:ClearAllPoints()
    b:SetPoint("CENTER", container, "CENTER", -total / 2 + W / 2 + (i - 1) * (W + GAP), 0)
    placed[b] = true
  end
  for _, b in ipairs(units) do
    if not placed[b] then b:ClearAllPoints() b:SetPoint("CENTER", container, "CENTER", 0, 0) end
  end
  return #shown
end

-- their buffs, yours first (your heals over time, your Mark), then everyone else's (the user, 2026-10-18: "it should
-- show the hots and buffs on the horizontal bar of players"): { icon, count, dur, exp, mine }
local AURAS, AS, HOT = 6, 16, 14
-- whether you (or your pet) cast it. Other players' buffs come as the game's hidden ("secret") values, which may be shown
-- but not compared: comparing one is an error (it hid every buff on everyone else: the user, 2026-10-18, "cant see hots or
-- buffs on other players"). Not known: not yours.
local function castByMe(src, fromMe)
  local ok, r = pcall(function()
    if fromMe ~= nil and not isSecret(fromMe) then return fromMe and true or false end
    if src ~= nil and not isSecret(src) then return src == "player" or src == "pet" end
    return false
  end)
  return ok and r or false
end
function H.auras(u)
  local mine, other = {}, {}
  for i = 1, 40 do
    local a
    if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
      local d = C_UnitAuras.GetBuffDataByIndex(u, i)
      if not d then break end
      a = { icon = d.icon, count = d.applications, dur = d.duration, exp = d.expirationTime, id = d.auraInstanceID,
            mine = castByMe(d.sourceUnit, d.isFromPlayerOrPlayerPet) }
    elseif UnitBuff then
      local name, icon, count, _, dur, exp, src = UnitBuff(u, i)
      if not name then break end
      a = { icon = icon, count = count, dur = dur, exp = exp, mine = castByMe(src) }
    else
      break
    end
    table.insert(a.mine and mine or other, a)
  end
  for _, a in ipairs(other) do mine[#mine + 1] = a end
  return mine
end
local auraErr   -- logged once a session
local function showAuras(b)
  if b.container or not b.auras then return end   -- the game fills its own container
  local u = b.unit
  if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
    for _, f in ipairs(b.auras) do f:Hide() end
    return
  end
  local ok, list = pcall(H.auras, u)
  if not ok then
    if not auraErr then auraErr = true log("HEAL_AURA_ERR", { unit = u, err = tostring(list) }) end
    list = {}
  end
  local A = C_UnitAuras or {}
  for i, f in ipairs(b.auras) do
    local a = list[i]
    if a then
      f.icon:SetTexture(a.icon)
      -- stacks: the game's own display text where it has one (safe with hidden values)
      if not pcall(function()
        if a.id and A.GetAuraApplicationDisplayCount then f.count:SetText(A.GetAuraApplicationDisplayCount(u, a.id, 2, 99))
        else local n = not isSecret(a.count) and a.count or 0 f.count:SetText(n > 1 and n or "") end
      end) then f.count:SetText("") end
      -- the time left as a sweep (nothing for a buff that doesn't run out)
      if not pcall(function()
        if a.id and A.GetAuraDuration and f.cd.SetCooldownFromDurationObject then
          f.cd:SetCooldownFromDurationObject(A.GetAuraDuration(u, a.id))
          f.cd:Show()
        elseif a.dur and a.dur > 0 and a.exp then f.cd:SetCooldown(a.exp - a.dur, a.dur) f.cd:Show()
        else f.cd:Hide() end
      end) then f.cd:Hide() end
      f:Show()
    else
      f:Hide()
    end
  end
end

-- heals on their way to b's unit (UnitGetIncomingHeals: secret in a group, so handed to the bars and text as they are).
-- The "+N" is your own heal, shown while you cast one
local casting = false
local function incoming(b, max)
  if not (b.incAll and UnitGetIncomingHeals) then return end
  local u = b.unit
  local okA, all = pcall(UnitGetIncomingHeals, u)
  local okM, mine = pcall(UnitGetIncomingHeals, u, "player")
  for _, p in ipairs({ b.incAll, b.incMine }) do p:SetMinMaxValues(0, max or 1) end
  b.incAll:SetValue(okA and all or 0)
  b.incMine:SetValue(okM and mine or 0)
  -- the tick only with a heal on its way: with none it sat at the end of their health, a white line on everyone (the
  -- user, 2026-10-18). A secret amount can't be tested: then only while you cast
  local function on(ok, v) return ok and v ~= nil and (isSecret(v) and casting or not isSecret(v) and v > 0) or false end
  b.incAll.tick:SetShown(on(okA, all))
  b.incMine.tick:SetShown(on(okM, mine))
  local show = casting and okM and mine ~= nil and (isSecret(mine) or mine > 0)
  if show then show = pcall(b.inc.SetFormattedText, b.inc, "+%d", mine) end
  if not show then b.inc:SetText("") end
end

local function update(b)
  local u = b.unit
  if not UnitExists(u) then return end
  b.name:SetText(UnitName(u) or "")
  local _, class = UnitClass(u)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then b.bar:SetStatusBarColor(c.r, c.g, c.b) else b.bar:SetStatusBarColor(0.2, 0.8, 0.2) end
  local hp, max = UnitHealth(u), UnitHealthMax(u)
  b.bar:SetMinMaxValues(0, max or 1)
  b.bar:SetValue(hp or 0)
  local text = ""
  -- any of these answers can be secret on this client, and an addon may not test a secret: those count as no
  local function yes(fn) local v = fn and fn(u) if isSecret(v) then return false end return v end
  local function no(fn) local v = fn and fn(u) if isSecret(v) or v == nil then return false end return not v end
  if no(UnitIsConnected) then text = "Offline"
  elseif yes(UnitIsDeadOrGhost) then text = "Dead"
  elseif not isSecret(hp) and not isSecret(max) and hp and max and max > 0 and hp < max then text = "-" .. (max - hp) end
  b.hp:SetText(text)
  incoming(b, max)
  -- out of your range (party members only): faded. The answer is secret here (testing it flooded errors, the user
  -- 2026-10-18), so the game applies it: SetAlphaFromBoolean takes a secret as it is.
  local alpha = 1
  if u ~= "player" and UnitInRange then
    local ok, inRange, checked = pcall(UnitInRange, u)
    if ok and (isSecret(inRange) or isSecret(checked)) then
      if b.SetAlphaFromBoolean and isSecret(inRange) then
        b:SetAlphaFromBoolean(inRange, 1, 0.4)
        alpha = nil
      end
    elseif ok and checked and not inRange then alpha = 0.4 end
  end
  if alpha then b:SetAlpha(alpha) end
  showAuras(b)
end
function H.refresh() for _, b in ipairs(units) do update(b) end end

-- The buff row above each bar. This client keeps buffs secret (in combat, and at other times) and then won't list them to
-- an addon at all ("Auras cannot be accessed when secret while tainted": they showed, then went: the user, 2026-10-18).
-- So the game's own aura container shows them: we say whose and how they look, the game fills it, secret or not (as
-- healer frames such as Aptechka do). Yours (your spells, cast by you: heals over time, buffs) along the bottom of the
-- bar, the rest above it. Its icons are the game's to update: once made we never touch them (the game forbids it while auras are secret).
-- A client without the container: icons we fill ourselves, and only while buffs aren't secret.
local function auraIcon(button, size)
  button:SetSize(size or AS, size or AS)
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints()
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
  cd:SetAllPoints()
  cd:SetReverse(true)
  if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
  local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  count:SetPoint("BOTTOMRIGHT", 2, -2)
  button:SetIcon(icon)
  button:SetDurationCooldown(cd)
  button:SetApplicationCount(count)
  if button.SetHideTooltipInCombat then button:SetHideTooltipInCombat(true) end
end
-- your buffs and heals over time: every spell (all ranks) in your spellbook you can cast on someone. The two rows split
-- on these spell ids, not only on who cast it: the game's PLAYER / !PLAYER filter alone let everyone's buffs into both
-- rows on your party (the user, 2026-10-18: "buffs are showing on the bottom ... only Heal over time's and my own buffs
-- should be showing on the bottom")
local function mineFilters()
  local ids = {}
  for _, s in ipairs(H.bookSpells()) do ids[s.id] = true end
  return { includeSpellIDs = ids }, { excludeSpellIDs = next(ids) and ids or nil }
end
-- after you learn a spell (out of combat: the containers can't change in it)
function H.auraFilters()
  if InCombatLockdown() then pending.filters = true return end
  pending.filters = nil
  local mine, others = mineFilters()
  for _, b in ipairs(units) do
    if b.hots and b.hots.SetAuraGroupCandidateFilters then pcall(b.hots.SetAuraGroupCandidateFilters, b.hots, "auras", mine) end
    if b.container and b.container.SetAuraGroupCandidateFilters then
      pcall(b.container.SetAuraGroupCandidateFilters, b.container, "auras", others)
    end
  end
end
-- one of the game's aura containers on bar b: `filter` auras (and only those `cand` allows), laid out left to right
-- from `point`
local function auraContainer(b, filter, size, init, parent, point, rel, x, y, cand)
  local c = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
  if not (c and c.AddAuraGroup and c.SetUnit) then return nil end
  c:SetSize(W, size)
  c:SetPoint(point, b, rel, x, y)
  if c.SetFlowLayoutAnchorPoint then c:SetFlowLayoutAnchorPoint(point) end
  if c.SetFlowLayoutAxis and AnchorUtil and AnchorUtil.FlowLayoutAxis then c:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal) end
  if c.SetFlowLayoutGrowthDirection and AnchorUtil and AnchorUtil.FlowDirection then
    c:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Up)
  end
  if c.SetFlowLayoutMaximumLineSize then c:SetFlowLayoutMaximumLineSize(W) end
  local layout = { elementSpacing = 2, lineSpacing = 2, elementWidth = size, elementHeight = size }
  c:AddAuraGroup("auras", filter, { maxFrameCount = AURAS, initializeFrame = init, layout = layout, candidateFilters = cand })
  c:SetUnit(b.unit)
  if c.SetEnabled then c:SetEnabled(true) end
  return c
end
local function makeAuraRow(b)
  local ok, c = pcall(function()
    if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer")) and C_AddOns and C_AddOns.LoadAddOn then
      pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    -- not in our frame registry: the performance probe wraps its frames' scripts, and these are the game's
    -- everyone else's buffs: a row above the bar
    local mineF, othersF = mineFilters()
    local c = auraContainer(b, "HELPFUL", AS, function(button) auraIcon(button, AS) end, b, "BOTTOMLEFT", "TOPLEFT", 1, 2, othersF)
    if not c then return nil end
    -- yours (your heals over time): inside the bar along its bottom (the user, 2026-10-18: "put the HoTs on the bottom
    -- of the name plate"). They sit on the bar, so a click on one goes through to the bar and casts as usual.
    local mine = auraContainer(b, "HELPFUL|PLAYER", HOT, function(button)
      auraIcon(button, HOT)
      if button.SetMouseClickEnabled then button:SetMouseClickEnabled(false) else button:EnableMouse(false) end
    end, b.bar, "BOTTOMLEFT", "BOTTOMLEFT", 3, 3, mineF)
    if mine and mine.SetFrameLevel then mine:SetFrameLevel(b.bar:GetFrameLevel() + 2) end
    b.hots = mine
    return c
  end)
  if ok and c then b.container = c return end
  log("HEAL_NO_CONTAINER", { err = not ok and tostring(c) or nil })
  b.auras = {}
  for i = 1, AURAS do
    local f = ns.newFrame("Heal", "Frame", nil, b)
    f:SetSize(AS, AS)
    f:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 1 + (i - 1) * (AS + 2), 2)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.cd = ns.newFrame("Heal", "Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints()
    if f.cd.SetReverse then f.cd:SetReverse(true) end
    if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(true) end
    f.count = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    f.count:SetPoint("BOTTOMRIGHT", 2, -2)
    f:Hide()
    b.auras[i] = f
  end
end

local function makeUnit(i, unit)
  local b = ns.newFrame("Heal", "Button", "AuDHDHealUnit" .. i, container, "SecureUnitButtonTemplate,BackdropTemplate")
  b.unit = unit
  b:SetSize(W, HT)
  b:SetAttribute("unit", unit)
  b:RegisterForClicks("AnyUp", "AnyDown")
  if b.SetBackdrop then
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    b:SetBackdropColor(0, 0, 0, 0.7)
    b:SetBackdropBorderColor(0, 0, 0, 1)
  end
  b.bar = ns.newFrame("Heal", "StatusBar", nil, b)
  b.bar:SetPoint("TOPLEFT", 2, -2)
  b.bar:SetPoint("BOTTOMRIGHT", -2, 2)
  b.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  b.bar:SetMinMaxValues(0, 1)
  if b.bar.SetClipsChildren then pcall(b.bar.SetClipsChildren, b.bar, true) end   -- a heal past full stops at the edge
  -- the heal on its way (the user, 2026-10-18: "how much a heal is going to heal while you're casting"): a pale bar
  -- from where health ends, as long as the heal, with a bright tick where it will reach, and "+N" on the right. The
  -- game's numbers are secret in a group: a status bar and a font string take them as they are, nothing adds them up
  -- (as HealForever does). Everyone's heals pale, yours brighter over them.
  local function predict(level, r, g, bl, a)
    local p = CreateFrame("StatusBar", nil, b.bar)
    p:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    p:SetStatusBarColor(r, g, bl, a)
    p:SetPoint("TOPLEFT", b.bar:GetStatusBarTexture(), "TOPRIGHT")
    p:SetPoint("BOTTOMLEFT", b.bar:GetStatusBarTexture(), "BOTTOMRIGHT")
    p:SetWidth(W - 4)
    p:SetMinMaxValues(0, 1)
    p:SetValue(0)
    p:SetFrameLevel(b.bar:GetFrameLevel() + level)
    local tick = p:CreateTexture(nil, "OVERLAY")
    tick:SetColorTexture(0.85, 1, 0.88, 0.85)
    tick:SetWidth(1)
    tick:SetPoint("TOPRIGHT", p:GetStatusBarTexture(), "TOPRIGHT")
    tick:SetPoint("BOTTOMRIGHT", p:GetStatusBarTexture(), "BOTTOMRIGHT")
    tick:Hide()
    p.tick = tick
    return p
  end
  b.incAll = predict(1, 0.55, 0.68, 0.58, 0.32)
  b.incMine = predict(2, 0.72, 0.92, 0.78, 0.45)
  -- the words over the bars
  b.words = CreateFrame("Frame", nil, b.bar)
  b.words:SetAllPoints()
  b.words:SetFrameLevel(b.bar:GetFrameLevel() + 4)
  b.inc = b.words:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.inc:SetPoint("RIGHT", -4, 1)
  b.inc:SetTextColor(0.5, 1, 0.55)
  b.name = b.words:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.name:SetPoint("TOP", 0, -4)
  b.name:SetWidth(W - 10)
  b.name:SetWordWrap(false)
  b.hp = b.words:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.hp:SetPoint("CENTER", 0, 1)   -- the bottom is for your heals over time
  b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "ADD")
  local hl = b:GetHighlightTexture()
  if hl then hl:SetVertexColor(1, 1, 1, 0.12) end
  b:SetScript("OnEnter", function(self)
    if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(GameTooltip, self) else GameTooltip:SetOwner(self, "ANCHOR_TOP") end
    GameTooltip:SetUnit(self.unit)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  makeAuraRow(b)
  if RegisterUnitWatch then RegisterUnitWatch(b) end
  return b
end

local function make()
  container = ns.newFrame("Heal", "Frame", "AuDHDHeal", UIParent)
  container:SetSize(W, HT)
  place()
  for i, u in ipairs(UNITS) do units[i] = makeUnit(i, u) end
  applyBinds()
  H.layout()
end

local function apply()
  local on = db().on
  if not on and not container then return end
  if InCombatLockdown() then pending.show = true return end
  pending.show = nil
  if not container then make() end
  if on then
    container:Show()
    local n = H.layout()
    log("HEAL_SHOWN", { members = n })
    H.refresh()
    -- the range fade: checked twice a second while the frames are up
    if not ticker and C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(0.5, function() if db().on then H.refresh() end end) end
  else
    container:Hide()
  end
end

function H.isOn() return db().on and true or false end
function H.set(button, id)
  local d = db()
  if id then
    local name = spellInfo(id)
    if not name then return false end
    d.binds[button] = { id = id, name = name, rank = spellRank(id) }
  else
    d.binds[button] = nil
  end
  log("HEAL_BIND", { button = button, spell = id and H.label(d.binds[button]) or "none" })
  -- a spell picked: the frames come on with it (picked and nothing on screen read as broken: the user, 2026-10-18)
  if id and not d.on then d.on = true apply() end
  applyBinds()
  if H.setupRefresh then H.setupRefresh() end
  return true
end

-- the setup window: a row per mouse button
local setup, list
local function pickList(row)
  if not list then
    list = ns.newFrame("Heal", "Frame", "AuDHDHealList", UIParent, "BackdropTemplate")
    list:SetSize(230, 12 * 20 + 12)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    if list.SetBackdrop then
      list:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                         tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      list:SetBackdropColor(0, 0, 0, 0.95)
    end
    list.rows = {}
    for i = 1, 12 do
      local r = ns.newFrame("Heal", "Button", nil, list)
      r:SetSize(214, 20)
      r:SetPoint("TOPLEFT", 8, -6 - (i - 1) * 20)
      r.icon = r:CreateTexture(nil, "ARTWORK")
      r.icon:SetSize(16, 16)
      r.icon:SetPoint("LEFT", 0, 0)
      r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
      r.text:SetPoint("RIGHT", 0, 0)
      r.text:SetJustifyH("LEFT")
      r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      r:SetScript("OnClick", function(self) H.set(list.button, self.spell.id) list:Hide() end)
      list.rows[i] = r
    end
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
      self.top = math.max(0, math.min(#self.spells - #self.rows, self.top - delta * 3))
      self.fill()
    end)
    function list.fill()
      for i, r in ipairs(list.rows) do
        local s = list.spells[list.top + i]
        r.spell = s
        if s then
          local _, icon = spellInfo(s.id)
          r.icon:SetTexture(icon or 134400)
          r.text:SetText(s.enemy and ("%s |cffaaaaaa(their target)|r"):format(H.label(s)) or H.label(s))
          r:Show()
        else
          r:Hide()
        end
      end
    end
    if UISpecialFrames then table.insert(UISpecialFrames, "AuDHDHealList") end
  end
  list.button = row.button
  list.spells = H.bookSpells(true)
  list.top = 0
  list:ClearAllPoints()
  list:SetPoint("TOPLEFT", row.slot, "BOTTOMLEFT", 0, -2)
  list:SetHeight(math.max(1, math.min(12, #list.spells)) * 20 + 12)
  list.fill()
  list:Show()
end

-- a spell dragged here from your spellbook: that spell, that rank
local function dropped(row)
  local kind, _, _, id = GetCursorInfo()
  if kind ~= "spell" then return end
  if ClearCursor then ClearCursor() end
  if id then H.set(row.button, id) end
end

function H.setupRefresh()
  if not setup then return end
  for _, row in ipairs(setup.rows) do
    local bind = db().binds[row.button]
    if bind then
      local _, icon = spellInfo(bind.id)
      row.icon:SetTexture(icon or 134400)
      row.slot.text:SetText(H.label(bind))
      row.slot.text:SetTextColor(1, 1, 1)
    else
      row.icon:SetTexture(nil)
      row.slot.text:SetText(row.button == "LeftButton" and "Target them" or row.button:find("-") and "Same as click" or "Nothing")
      row.slot.text:SetTextColor(0.6, 0.6, 0.6)
    end
  end
end

function H.setup(back)
  if not setup then
    setup = ns.newFrame("Heal", "Frame", "AuDHDHealSetup", UIParent, "BackdropTemplate")
    local SLOT, LABEL = 176, 112
    setup:SetSize(LABEL + #MODS * (SLOT + 6) + 14, 76 + #BUTTONS * 30)
    setup:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    setup:SetFrameStrata("DIALOG")
    setup:SetClampedToScreen(true)
    setup:SetMovable(true)
    setup:EnableMouse(true)
    setup:RegisterForDrag("LeftButton")
    setup:SetScript("OnDragStart", setup.StartMoving)
    setup:SetScript("OnDragStop", setup.StopMovingOrSizing)
    -- closed: back to the window it was opened from (the settings hide while it's up: the user, 2026-10-18, "it's
    -- stuck behind the settings UI")
    setup:SetScript("OnHide", function()
      if list then list:Hide() end
      local back = setup.back
      setup.back = nil
      if back then back() end
    end)
    if setup.SetBackdrop then
      setup:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                          tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      setup:SetBackdropColor(0, 0, 0, 0.92)
    end
    local title = setup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Click-cast spells")
    local hint = setup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 12, -30)
    hint:SetText("Click to pick, or drag a spell here from your spellbook. Right-click clears.")
    local close = ns.newFrame("Heal", "Button", nil, setup, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() setup:Hide() end)
    setup.rows = {}
    for c, m in ipairs(MODS) do
      local h = setup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      h:SetPoint("TOPLEFT", LABEL + (c - 1) * (SLOT + 6) + 4, -52)
      h:SetText(m[2])
    end
    for i, mb in ipairs(BUTTONS) do
      local y = -70 - (i - 1) * 30
      local l = setup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      l:SetPoint("TOPLEFT", 14, y - 5)
      l:SetText(mb[2])
      for c, m in ipairs(MODS) do
        local row = { button = m[1] .. mb[1] }
        row.slot = ns.newFrame("Heal", "Button", nil, setup, "BackdropTemplate")
        row.slot:SetSize(SLOT, 24)
        row.slot:SetPoint("TOPLEFT", LABEL + (c - 1) * (SLOT + 6), y)
        if row.slot.SetBackdrop then
          row.slot:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
          row.slot:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
          row.slot:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        end
        row.icon = row.slot:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", 3, 0)
        row.slot.text = row.slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.slot.text:SetPoint("LEFT", 26, 0)
        row.slot.text:SetPoint("RIGHT", -4, 0)
        row.slot.text:SetJustifyH("LEFT")
        row.slot:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.slot:SetScript("OnClick", function(_, which)
          if GetCursorInfo() then dropped(row) return end
          if which == "RightButton" then H.set(row.button, nil) if list then list:Hide() end
          elseif list and list:IsShown() and list.button == row.button then list:Hide()
          else pickList(row) end
        end)
        row.slot:SetScript("OnReceiveDrag", function() dropped(row) end)
        setup.rows[#setup.rows + 1] = row
      end
    end
    if UISpecialFrames then table.insert(UISpecialFrames, "AuDHDHealSetup") end
  end
  H.setupRefresh()
  setup.back = back
  setup:Show()
end

-- /wfn heal auras: what the game gives us for each frame's buffs, by every way there is to ask (buffs not showing on
-- other players: the user, 2026-10-18)
local function count(fn)
  local ok, n = pcall(function()
    local k = 0
    for i = 1, 40 do if fn(i) then k = k + 1 else break end end
    return k
  end)
  return ok and tostring(n) or ("error: " .. tostring(n))
end
function H.auraReport()
  local lines = {}
  for _, b in ipairs(units) do
    local u = b.unit
    if UnitExists(u) then
      local A = C_UnitAuras or {}
      local parts = {
        "buffData " .. (A.GetBuffDataByIndex and count(function(i) return A.GetBuffDataByIndex(u, i) end) or "none"),
        "auraData " .. (A.GetAuraDataByIndex and count(function(i) return A.GetAuraDataByIndex(u, i, "HELPFUL") end) or "none"),
        "UnitBuff " .. (UnitBuff and count(function(i) return UnitBuff(u, i) end) or "none"),
      }
      local ok, list = pcall(H.auras, u)
      parts[#parts + 1] = "read " .. (ok and #list or ("error: " .. tostring(list)))
      local shown = 0
      for _, f in ipairs(b.auras or {}) do if f:IsShown() then shown = shown + 1 end end
      parts[#parts + 1] = (b.container and "shown by the game" or ("icons shown " .. shown)) .. (b:IsShown() and "" or " (frame hidden)")
      local line = (UnitName(u) or u) .. ": " .. table.concat(parts, ", ")
      lines[#lines + 1] = line
      log("HEAL_AURAS", { unit = u, report = line })
    end
  end
  return #lines > 0 and table.concat(lines, "\n") or "click-cast frames aren't up"
end

-- /wfn heal [on | off | setup | auras]
function H.command(rest)
  local cmd = (rest or ""):match("^(%S*)")
  if cmd == "auras" then return H.auraReport() end
  local d = db()
  if cmd == "on" then d.on = true apply()
  elseif cmd == "off" then d.on = nil apply()
  elseif cmd == "setup" then H.setup() end
  local set = {}
  for _, mb in ipairs(BUTTONS) do
    for _, m in ipairs(MODS) do
      local bind = d.binds[m[1] .. mb[1]]
      if bind then set[#set + 1] = (m[1] == "" and "" or m[2]:gsub(" %+ click", " + ")) .. mb[2] .. ": " .. H.label(bind) end
    end
  end
  return ("click-cast healing: %s%s (/wfn heal on | off | setup)"):format(d.on and "on" or "off",
    #set > 0 and (", " .. table.concat(set, ", ")) or ", no spells set")
end

local frame = ns.newFrame("Heal", "Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "UNIT_HEALTH",
                     "UNIT_MAXHEALTH", "UNIT_AURA", "UNIT_CONNECTION", "UNIT_NAME_UPDATE", "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED",
                     "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "UNIT_HEAL_PREDICTION",
                     "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
  pcall(frame.RegisterEvent, frame, e)
end
frame:SetScript("OnEvent", function(_, e, unit)
  if e == "PLAYER_LOGIN" then apply() return end
  if not container then return end
  if e == "PLAYER_REGEN_ENABLED" then
    if pending.show then apply() end
    if pending.binds then applyBinds() end
    if pending.place then place() end
    if pending.layout then H.layout() end
    if pending.filters then H.auraFilters() end
  elseif e:find("^UNIT_SPELLCAST") then
    if unit == "player" then casting = e == "UNIT_SPELLCAST_START" H.refresh() end
  elseif e == "SPELLS_CHANGED" or e == "LEARNED_SPELL_IN_TAB" then
    H.auraFilters()
  elseif e == "GROUP_ROSTER_UPDATE" or e == "PLAYER_ENTERING_WORLD" then
    H.layout()
    for _, b in ipairs(units) do for _, c in ipairs({ b.container, b.hots }) do if c.UpdateAllAuras then pcall(c.UpdateAllAuras, c) end end end
    H.refresh()
  elseif e == "DISPLAY_SIZE_CHANGED" or e == "UI_SCALE_CHANGED" then
    place()
  elseif unit then
    for _, b in ipairs(units) do if b.unit == unit then update(b) end end   -- (UnitIsUnit's answer can be secret)
  end
end)
