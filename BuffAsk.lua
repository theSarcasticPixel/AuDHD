-- Asking the party for buffs: in a group with a class that has buffs for you, a bar of buttons, one per buff you could
-- get; a click says to the party "<AuDHD>{star}Hey <name>, could I please get <buff>? <3" (the tag first, so it's
-- plain it's the addon: the user, 2026-10-17). The user, 2026-10-17: "when you join
-- a party with a class that has buffs, you get a series of buttons that you can click that automatically sends to the
-- party chat".
--  Who's asked: the first in the party of that class who was high enough level for it when they joined you (their level
--    then, not now: someone who dings it in the party hasn't trained it yet). Levels are Forever's trainer levels
--    (ForeverDB's Spells.json: Kings at 20, Divine Spirit at 30 from the trainer).
--  Blessings: a paladin gives you one each, so there are as many to ask for as paladins in the party. The first
--    blessing goes to the first paladin, the next to the second, and so on; once you have (or have asked for) one per
--    paladin, the blessing buttons go.
--  A buff goes from the bar while it's on you, or for 2 minutes after you asked (back if it never came); one you know
--    yourself isn't asked for; Intellect, Wisdom and Spirit aren't asked for by warriors and rogues.
-- Plain buttons (chat, no casting), so they work in a fight too. /wfn askbuffs [off|on].
local _, ns = ...
local A = {}
ns.buffAsk = A
local log = function(e, f) if ns.log then ns.log.add(e, f) end end

local WAIT = 120   -- seconds an ask holds its buff (and its paladin) off the bar
-- { name, class, level, rank 1 id, other names that count as on, mana = only for mana users, blessing = one per paladin }
local BUFFS = {
  { "Power Word: Fortitude", "PRIEST", 1, 1243, { "Prayer of Fortitude" } },
  { "Divine Spirit", "PRIEST", 30, 14752, { "Prayer of Spirit" }, mana = true },
  { "Shadow Protection", "PRIEST", 30, 976, { "Prayer of Shadow Protection" } },
  { "Fear Ward", "PRIEST", 20, 6346 },
  { "Arcane Intellect", "MAGE", 1, 1459, { "Arcane Brilliance" }, mana = true },
  { "Mark of the Wild", "DRUID", 1, 1126, { "Gift of the Wild" } },
  { "Thorns", "DRUID", 6, 467 },
  { "Blessing of Might", "PALADIN", 4, 19740, { "Greater Blessing of Might" }, blessing = true },
  { "Blessing of Wisdom", "PALADIN", 14, 19742, { "Greater Blessing of Wisdom" }, blessing = true, mana = true },
  { "Blessing of Kings", "PALADIN", 20, 20217, { "Greater Blessing of Kings" }, blessing = true },
  { "Blessing of Salvation", "PALADIN", 26, 1038, { "Greater Blessing of Salvation" }, blessing = true },
  { "Blessing of Light", "PALADIN", 40, 19977, { "Greater Blessing of Light" }, blessing = true },
}
A.BUFFS = BUFFS

local function db()
  AuDHDDB.buffAsk = AuDHDDB.buffAsk or {}
  local d = AuDHDDB.buffAsk
  d.joined = d.joined or {}   -- guid -> level when they joined you
  return d
end
local asks = {}   -- { guid, buff, t } this session

local function now() return GetTime() end
local function buffsOn()
  local on = {}
  for i = 1, 40 do
    local name
    if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
      local a = C_UnitAuras.GetBuffDataByIndex("player", i)
      if not a then break end
      name = a.name
    elseif UnitBuff then
      name = UnitBuff("player", i)
      if not name then break end
    else
      break
    end
    if name then on[name] = true end
  end
  return on
end
local function isOn(b, on)
  if on[b[1]] then return true end
  for _, n in ipairs(b[5] or {}) do if on[n] then return true end end
  return false
end
local function knowsIt(id) return (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) or false end
local function usesMana()
  local _, class = UnitClass("player")
  return class ~= "WARRIOR" and class ~= "ROGUE"
end

-- the party in its order: { unit, guid, name, class, level when they joined }
local function members()
  local out = {}
  if not (IsInGroup and IsInGroup()) then return out end
  local joined = db().joined
  for i = 1, 4 do
    local u = "party" .. i
    if UnitExists(u) then
      local guid = UnitGUID(u)
      local _, class = UnitClass(u)
      if guid and class then
        out[#out + 1] = { unit = u, guid = guid, name = (UnitName(u)), class = class, level = joined[guid] }
      end
    end
  end
  return out
end
-- their level the first time they're seen in your party; forgotten once they've left
function A.roster()
  local d, seen = db(), {}
  if IsInGroup and IsInGroup() then
    for i = 1, 4 do
      local u = "party" .. i
      local guid = UnitExists(u) and UnitGUID(u)
      if guid then
        seen[guid] = true
        local lv = UnitLevel(u)
        if not d.joined[guid] and lv and lv > 0 then
          d.joined[guid] = lv
          log("PARTY_JOINED", { name = (UnitName(u)), class = select(2, UnitClass(u)), lv = lv })
        end
      end
    end
  end
  for guid in pairs(d.joined) do if not seen[guid] then d.joined[guid] = nil end end
  for i = #asks, 1, -1 do if not seen[asks[i].guid] then table.remove(asks, i) end end
end

-- what to show: { { buff = b, who = member } ... } in BUFFS order
function A.choices()
  local out = {}
  if db().off then return out end
  local party = members()
  if #party == 0 then return out end
  local on, t = buffsOn(), now()
  -- asks still waiting: dropped once it's on you or the wait is over
  for i = #asks, 1, -1 do
    local a = asks[i]
    if t - a.t > WAIT or isOn(a.buff, on) then table.remove(asks, i) end
  end
  local pending, pendingWho, pendingBlessings = {}, {}, 0
  for _, a in ipairs(asks) do
    pending[a.buff] = true
    if a.buff.blessing then pendingWho[a.guid] = true pendingBlessings = pendingBlessings + 1 end
  end
  -- paladins in party order; the ones already used: one per blessing on you or asked for
  local pals, blessed = {}, 0
  for _, m in ipairs(party) do if m.class == "PALADIN" then pals[#pals + 1] = m end end
  for _, b in ipairs(BUFFS) do if b.blessing and isOn(b, on) then blessed = blessed + 1 end end
  local used = blessed + pendingBlessings
  for _, b in ipairs(BUFFS) do
    if not isOn(b, on) and not pending[b] and not knowsIt(b[4]) and not (b.mana and not usesMana()) then
      local who
      if b.blessing then
        if used < #pals then
          for k = used + 1, #pals do
            local p = pals[k]
            if not pendingWho[p.guid] and p.level and p.level >= b[3] then who = p break end
          end
        end
      else
        for _, m in ipairs(party) do
          if m.class == b[2] and m.level and m.level >= b[3] then who = m break end
        end
      end
      if who then out[#out + 1] = { buff = b, who = who } end
    end
  end
  return out
end

local function message(c) return ("<AuDHD>{rt1}Hey %s, could I please get %s? <3"):format(c.who.name, c.buff[1]) end
A.message = message
function A.ask(c)
  SendChatMessage(message(c), "PARTY")
  asks[#asks + 1] = { guid = c.who.guid, buff = c.buff, t = now() }
  log("BUFF_ASK", { buff = c.buff[1], who = c.who.name, lv = c.who.level })
  A.refresh()
end

-- ------------------------------------------------------------------ the bar
local bar, buttons = nil, {}
local function spellIcon(id)
  local t = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
  if not t and GetSpellTexture then t = GetSpellTexture(id) end
  return t or 134400
end
local function makeBar()
  bar = CreateFrame("Frame", "AuDHDBuffAsk", UIParent, "BackdropTemplate")
  bar:SetSize(120, 54)
  if bar.SetBackdrop then
    bar:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                      tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    bar:SetBackdropColor(0.05, 0.12, 0.25, 0.92)
  end
  local pos = AuDHDDB.buffAskPos
  if pos then bar:SetPoint(pos.p, UIParent, pos.rp, pos.x, pos.y) else bar:SetPoint("TOP", UIParent, "TOP", 0, -100) end
  bar:SetClampedToScreen(true)
  bar:SetMovable(true)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", bar.StartMoving)
  bar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    AuDHDDB.buffAskPos = { p = p, rp = rp, x = x, y = y }
  end)
  bar.title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  bar.title:SetPoint("TOPLEFT", 8, -6)
  bar.title:SetText("Ask the party for:")
  bar:Hide()
end
local function button(i)
  if buttons[i] then return buttons[i] end
  local b = CreateFrame("Button", nil, bar)
  b:SetSize(28, 28)
  b:SetPoint("TOPLEFT", 8 + (i - 1) * 32, -20)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.25)
  b:SetScript("OnClick", function(self) if self.c then A.ask(self.c) end end)
  b:SetScript("OnEnter", function(self)
    if not self.c then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(("Ask %s for %s"):format(self.c.who.name, self.c.buff[1]), 1, 1, 1)
    GameTooltip:AddLine((message(self.c):gsub("{rt1}", "* ")), 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  buttons[i] = b
  return b
end

function A.refresh()
  local list = A.choices()
  if not bar then
    if #list == 0 then return end
    makeBar()
  end
  for i, c in ipairs(list) do
    local b = button(i)
    b.c = c
    b.icon:SetTexture(spellIcon(c.buff[4]))
    b:Show()
  end
  for i = #list + 1, #buttons do buttons[i].c = nil buttons[i]:Hide() end
  if #list == 0 then bar:Hide() return end
  bar:SetWidth(math.max(120, 16 + #list * 32))
  bar:Show()
end
-- the smoke test: what the bar offers, "buff>name" each
function A.shown()
  local out = {}
  for _, c in ipairs(A.choices()) do out[#out + 1] = c.buff[1] .. ">" .. c.who.name end
  return table.concat(out, ", ")
end

function A.command(arg)
  arg = (arg or ""):lower()
  if arg == "off" or arg == "on" then
    db().off = arg == "off" or nil
    A.refresh()
    return "asking the party for buffs " .. arg
  end
  local s = A.shown()
  return s ~= "" and ("you could ask for: " .. s) or "no buffs to ask the party for now"
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("UNIT_AURA")
frame:SetScript("OnEvent", function(_, event, unit)
  if event == "UNIT_AURA" and unit ~= "player" then return end
  if event == "PLAYER_LOGIN" then
    -- every few seconds too: asks run out, and a level that wasn't known yet (someone far away) gets read
    C_Timer.NewTicker(5, function() pcall(A.roster) pcall(A.refresh) end)
  end
  pcall(A.roster)
  pcall(A.refresh)
end)
