-- The info bar. Parts, left to right: money | gold an hour (net: spending counts against it) | XP an hour | time to the
-- next level at that pace | free bag slots | gear durability | master volume (wheel: louder/quieter, click: mute)
-- A session runs from logging in (a /reload carries on) or from a reset (right-click, /audhd stats reset). Our own
-- frames only: nothing protected.
-- /audhd stats show | hide | lock | unlock | reset | move | bags | repair | volume | bags used|free
local _, ns = ...
local S = {}
ns.stats = S

local MIN_SECS = 60       -- before a minute has passed the rates are guesses: not shown
local RELOAD_GAP = 300    -- back within 5 minutes of the last tick (a /reload): the same session
local VOL_STEP = 0.05

local frame
local segs = {}
local function db()
  AuDHDDB.statsBar = AuDHDDB.statsBar or {}
  return AuDHDDB.statsBar
end
-- parts the player turned off (bags, repair, volume)
local function partOn(key) return not (db().off or {})[key] end

-- the session: start (GetTime), money at the start, XP gained, last seen, money in/out, XP from kills
local sess
local lastXP, lastMax, lastLevel, lastMoney

function S.money(c)
  c = math.floor(c or 0)
  local neg = c < 0
  c = math.abs(c)
  local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local out
  if g > 0 then out = ("|cffffd700%dg|r |cffc7c7cf%02ds|r"):format(g, s)
  elseif s > 0 then out = ("|cffc7c7cf%ds|r |cffeda55f%02dc|r"):format(s, k)
  else out = ("|cffeda55f%dc|r"):format(k) end
  return (neg and "-" or "") .. out
end
-- every character's money on this realm, as last seen: AuDHDDB.gold[realm][name] = copper
local function goldDB()
  local r = GetRealmName and GetRealmName() or "?"
  AuDHDDB.gold = AuDHDDB.gold or {}
  AuDHDDB.gold[r] = AuDHDDB.gold[r] or {}
  return AuDHDDB.gold[r]
end
function S.noteGold()
  local name = UnitName and UnitName("player")
  if name and GetMoney then goldDB()[name] = GetMoney() end
end
-- the total, and { { name, copper } } richest first
function S.allGold()
  S.noteGold()
  local total, list = 0, {}
  for name, c in pairs(goldDB()) do
    total = total + c
    list[#list + 1] = { name, c }
  end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  return total, list
end
function S.allOn() return db().allGold and true or false end
function S.bagGoldOn() return db().bagGold and true or false end
function S.setAll(on) db().allGold = on or nil S.refresh() end
function S.setBagGold(on) db().bagGold = on or nil S.bagGold() end
local function thousands(n)
  if n >= 10000 then return ("%.1fk"):format(n / 1000) end
  return tostring(math.floor(n + 0.5))
end
local function clock(secs)
  secs = math.floor(secs)
  local h, m = math.floor(secs / 3600), math.floor(secs / 60) % 60
  if h > 0 then return ("%dh %02dm"):format(h, m) end
  return ("%dm"):format(m)
end
local function seen()
  lastXP, lastMax, lastLevel = UnitXP("player"), UnitXPMax and UnitXPMax("player") or 0, UnitLevel("player")
  lastMoney = GetMoney()
end

function S.reset()
  sess = { start = GetTime(), money = GetMoney(), xp = 0, seen = GetTime(), gained = 0, spent = 0, killXP = 0, kills = 0 }
  db().sess = sess
  seen()
  S.refresh()
end
-- XP gained since the last look (a level up in between: the rest of the old level plus the new)
local function xpTick()
  local xp, max, level = UnitXP("player"), UnitXPMax and UnitXPMax("player") or 0, UnitLevel("player")
  if lastXP and sess then
    local d = xp - lastXP
    if level > (lastLevel or level) then d = (lastMax or 0) - lastXP + xp end
    if d > 0 then sess.xp = sess.xp + d end
  end
  lastXP, lastMax, lastLevel = xp, max, level
end
-- money in and money out kept apart (the tooltip shows both)
local function moneyTick()
  local m = GetMoney()
  if lastMoney and sess then
    local d = m - lastMoney
    if d > 0 then sess.gained = (sess.gained or 0) + d elseif d < 0 then sess.spent = (sess.spent or 0) - d end
  end
  lastMoney = m
end
-- XP from kills, read from the game's own "X dies, you gain N experience." line (in whatever language): the rest of
-- the session's XP is quests and exploring. Also gives kills to the next level at this session's average.
local KILL_PAT
local function killPattern()
  if KILL_PAT then return KILL_PAT end
  local f = COMBATLOG_XPGAIN_FIRSTPERSON or "%s dies, you gain %d experience."
  f = f:gsub("%%%d%$", "%%")                                  -- "%1$s" -> "%s"
  f = f:gsub("[%(%)%.%[%]%*%+%-%?%^%$]", "%%%0")              -- magic characters
  f = f:gsub("%%s", "(.-)"):gsub("%%d", "(%%d+)")
  KILL_PAT = "^" .. f
  return KILL_PAT
end
function S.killXP(msg)
  if not sess or type(msg) ~= "string" then return end
  local _, xp = msg:match(killPattern())
  xp = tonumber(xp)
  if xp and xp > 0 then sess.killXP = (sess.killXP or 0) + xp sess.kills = (sess.kills or 0) + 1 end
end

-- the numbers: money, perHour (copper), xpHour, toLevel (secs), secs, ...; nil rates before MIN_SECS
function S.numbers()
  if not sess then return nil end
  local secs = GetTime() - sess.start
  local money = GetMoney()
  local n = { money = money, secs = secs, earned = money - sess.money, xp = sess.xp, gained = sess.gained or 0,
    spent = sess.spent or 0, killXP = math.min(sess.killXP or 0, sess.xp), kills = sess.kills or 0 }
  local max = UnitXPMax and UnitXPMax("player") or 0
  if max > 0 then
    n.toGo = max - UnitXP("player")
    n.pct = UnitXP("player") / max * 100
    n.rested = GetXPExhaustion and GetXPExhaustion() or nil
    if n.kills > 0 and n.killXP > 0 then n.killsToLevel = math.ceil(n.toGo / (n.killXP / n.kills)) end
  end
  if secs >= MIN_SECS then
    n.perHour = (money - sess.money) / secs * 3600
    n.xpHour = sess.xp / secs * 3600
    if n.xpHour > 0 and n.toGo then n.toLevel = n.toGo / n.xpHour * 3600 end
  end
  return n
end

-- free slots in ordinary bags (quivers, ammo pouches and soul bags hold one kind of thing: not counted)
function S.bags()
  local free, total = 0, 0
  local C = C_Container or {}
  local numFree = C.GetContainerNumFreeSlots or GetContainerNumFreeSlots
  local numSlots = C.GetContainerNumSlots or GetContainerNumSlots
  if not numFree or not numSlots then return nil end
  for bag = 0, NUM_BAG_SLOTS or 4 do
    local f, kind = numFree(bag)
    if (kind or 0) == 0 then
      free = free + (f or 0)
      total = total + (numSlots(bag) or 0)
    end
  end
  return free, total
end
-- the worst-worn piece of gear: percent left, and every damaged piece { slot, pct }
local GEAR_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }
function S.durability()
  if not GetInventoryItemDurability then return nil end
  local low, worn = nil, {}
  for _, slot in ipairs(GEAR_SLOTS) do
    local cur, max = GetInventoryItemDurability(slot)
    if cur and max and max > 0 then
      local pct = cur / max * 100
      low = math.min(low or 100, pct)
      if pct < 100 then worn[#worn + 1] = { slot = slot, pct = pct } end
    end
  end
  table.sort(worn, function(a, b) return a.pct < b.pct end)
  return low, worn
end
-- master volume 0-100 and whether all sound is off
function S.volume()
  local v = tonumber(GetCVar("Sound_MasterVolume")) or 1
  return math.floor(v * 100 + 0.5), GetCVar("Sound_EnableAllSound") == "0"
end
function S.setVolume(pct)
  pct = math.max(0, math.min(100, pct))
  SetCVar("Sound_MasterVolume", tostring(pct / 100))
  S.refresh()
  return pct
end
function S.toggleMute()
  local _, muted = S.volume()
  SetCVar("Sound_EnableAllSound", muted and "1" or "0")
  S.refresh()
end

local function colour(pct, red, yellow)
  if pct <= red then return "|cffff5050" elseif pct <= yellow then return "|cffffd040" end
  return "|cffffffff"
end
-- the bar's parts, in order: { key, text }
function S.parts()
  local out = {}
  local n = S.numbers()
  if not n then return out end
  out[#out + 1] = { key = "money", text = S.money(n.money) }
  if S.allOn() then out[#out + 1] = { key = "all", text = "|cff999999All:|r " .. S.money((S.allGold())) } end
  if n.perHour then
    out[#out + 1] = { key = "money", text = S.money(n.perHour) .. "/h" }
    local maxLevel = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
    if UnitLevel("player") < maxLevel then
      out[#out + 1] = { key = "xp", text = "|cff88ccff" .. thousands(n.xpHour) .. " XP/h|r" }
      if n.toLevel then out[#out + 1] = { key = "xp", text = "level in " .. clock(n.toLevel) } end
    end
  else
    out[#out + 1] = { key = "money", text = "|cff999999rates after a minute|r" }
  end
  if partOn("bags") then
    local free, total = S.bags()
    if free and total > 0 then
      -- free slots, or the slots in use; red as they run out
      local n = db().bagsUsed and (total - free) or free
      out[#out + 1] = { key = "bags", text = "Bags " .. colour(free, 2, 6) .. n .. "|r/" .. total }
    end
  end
  if partOn("repair") then
    local low = S.durability()
    if low then out[#out + 1] = { key = "repair", text = "Gear " .. colour(low, 20, 50) .. math.floor(low) .. "%|r" } end
  end
  if partOn("volume") then
    local v, muted = S.volume()
    out[#out + 1] = { key = "volume", text = muted and "|cffff5050Muted|r" or ("Vol " .. v .. "%") }
  end
  return out
end
-- the money and XP part as one line
function S.line()
  local parts = {}
  for _, p in ipairs(S.parts()) do
    if p.key == "money" or p.key == "xp" then parts[#parts + 1] = p.text end
  end
  return table.concat(parts, "   ")
end
-- the tooltips: the session's numbers (our bar), and one each for bags, gear and volume
local W = 1
function S.tooltip(tt, movable)
  local n = S.numbers()
  tt:AddLine("AuDHD: this session")
  if n then
    tt:AddDoubleLine("Time", clock(n.secs), W, W, W, W, W, W)
    tt:AddDoubleLine("Money in / out", S.money(n.gained) .. "  /  " .. S.money(n.spent), W, W, W, W, W, W)
    tt:AddDoubleLine("Net", (n.earned < 0 and "-" or "+") .. S.money(math.abs(n.earned))
      .. (n.perHour and ("   (" .. S.money(n.perHour) .. "/h)") or ""), W, W, W, W, W, W)
    tt:AddDoubleLine("XP gained", thousands(n.xp), W, W, W, W, W, W)
    if n.xp > 0 then
      tt:AddDoubleLine("   from kills / quests and the rest", thousands(n.killXP) .. " / " .. thousands(n.xp - n.killXP),
        0.8, 0.8, 0.8, W, W, W)
    end
    if n.pct then
      tt:AddDoubleLine("This level", ("%d%%, %s to go"):format(math.floor(n.pct), thousands(n.toGo)), W, W, W, W, W, W)
      if n.rested and n.rested > 0 then tt:AddDoubleLine("Rested", thousands(n.rested), W, W, W, 0.5, 0.7, 1) end
      if n.killsToLevel then
        tt:AddDoubleLine("Kills to level", ("about %d (%d XP a kill)"):format(n.killsToLevel,
          math.floor(n.killXP / n.kills + 0.5)), W, W, W, W, W, W)
      end
    end
  end
  tt:AddLine("Right-click: start a new session" .. (movable and ". Drag to move" or ""), 0.6, 0.6, 0.6, true)
end
local SLOT_NAMES = { [1] = "Head", [3] = "Shoulders", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
  [9] = "Wrists", [10] = "Hands", [16] = "Main hand", [17] = "Off hand", [18] = "Ranged" }
local TIPS = {
  all = function(tt)
    local total, list = S.allGold()
    tt:AddLine("All your characters on this realm")
    for _, c in ipairs(list) do tt:AddDoubleLine(c[1], S.money(c[2]), W, W, W, W, W, W) end
    tt:AddDoubleLine("Total", S.money(total), 1, 0.82, 0, W, W, W)
    tt:AddLine("As each was when you last logged it in", 0.6, 0.6, 0.6, true)
  end,
  bags = function(tt)
    local free, total = S.bags()
    tt:AddLine("Bags")
    tt:AddLine(("%d free, %d used, of %d (quivers, ammo pouches and soul bags not counted)"):format(free or 0,
      (total or 0) - (free or 0), total or 0), W, W, W, true)
    tt:AddLine("Click: open your bags", 0.6, 0.6, 0.6)
  end,
  repair = function(tt)
    local low, worn = S.durability()
    tt:AddLine("Gear durability")
    if not worn or #worn == 0 then tt:AddLine("Nothing worn down", W, W, W) end
    for _, w in ipairs(worn or {}) do
      tt:AddDoubleLine(SLOT_NAMES[w.slot] or ("Slot " .. w.slot), colour(w.pct, 20, 50) .. math.floor(w.pct) .. "%|r",
        W, W, W, W, W, W)
    end
    if low and low <= 20 then tt:AddLine("Repair soon: broken gear gives no stats", 1, 0.4, 0.4, true) end
    tt:AddLine("Repair at a vendor who sells armour or weapons (the anvil button)", 0.6, 0.6, 0.6, true)
  end,
  volume = function(tt)
    local v, muted = S.volume()
    tt:AddLine("Volume")
    tt:AddLine(muted and "All sound is off" or ("Master volume " .. v .. "%"), W, W, W)
    tt:AddLine("Mouse wheel: louder / quieter. Click: sound on / off", 0.6, 0.6, 0.6, true)
  end,
}

local function place()
  frame:ClearAllPoints()
  local p = db().point
  if p then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4]) return end
  frame:SetPoint("TOP", UIParent, "TOP", 0, -4)
end
function S.place() if frame then place() end end

local function startMove() if not db().locked then frame:StartMoving() end end
local function stopMove()
  frame:StopMovingOrSizing()
  local a, _, b, x, y = frame:GetPoint()
  db().point = { a, b, x, y }
end
local function segment(i)
  if segs[i] then return segs[i] end
  local b = ns.newFrame("Stats", "Button", nil, frame)
  b:SetHeight(18)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.text:SetPoint("CENTER")
  b:SetScript("OnDragStart", startMove)
  b:SetScript("OnDragStop", stopMove)
  b:SetScript("OnClick", function(self, button)
    if button == "RightButton" then S.reset() return end
    if self.key == "volume" then S.toggleMute()
    elseif self.key == "bags" then
      if ToggleAllBags then ToggleAllBags() elseif OpenAllBags then OpenAllBags() end
    end
  end)
  b:EnableMouseWheel(true)
  b:SetScript("OnMouseWheel", function(self, delta)
    if self.key == "volume" then S.setVolume(S.volume() + delta * VOL_STEP * 100) S.showTip(self) end
  end)
  b:SetScript("OnEnter", function(self) S.showTip(self) end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  segs[i] = b
  return b
end
function S.showTip(self)
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
  if TIPS[self.key] then TIPS[self.key](GameTooltip) else S.tooltip(GameTooltip, not db().locked) end
  GameTooltip:Show()
end

local function create()
  frame = ns.newFrame("Stats", "Frame", "AuDHDStatsBar", UIParent, "BackdropTemplate")
  frame:SetSize(360, 22)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  place()
  if frame.SetBackdrop then
    frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    frame:SetBackdropColor(0.05, 0.05, 0.1, 0.8)
  end
  frame:SetScript("OnDragStart", startMove)
  frame:SetScript("OnDragStop", stopMove)
  frame:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then S.reset() end end)
end

function S.refresh()
  if db().hidden then if frame then frame:Hide() end return end
  if not frame then create() end
  local x = 8
  local parts = S.parts()
  for i, p in ipairs(parts) do
    local b = segment(i)
    b.key = p.key
    b.text:SetText(p.text)
    local w = (b.text.GetStringWidth and b.text:GetStringWidth() or 60) + 12
    b:SetWidth(w)
    b:ClearAllPoints()
    b:SetPoint("LEFT", frame, "LEFT", x, 0)
    b:Show()
    x = x + w
  end
  for i = #parts + 1, #segs do segs[i]:Hide() end
  frame:SetWidth(math.max(200, x + 8))
  frame:Show()
end
function S.isShown() return not db().hidden end
function S.isLocked() return db().locked and true or false end
function S.partShown(key) return partOn(key) end
function S.bagsUsed() return db().bagsUsed and true or false end
function S.setBagsUsed(on)
  db().bagsUsed = on or nil
  S.refresh()
end
function S.setPart(key, on)
  local d = db()
  d.off = d.off or {}
  d.off[key] = (not on) or nil
  S.refresh()
end

local PART_NAMES = { bags = "bag space", repair = "durability", volume = "volume" }
function S.command(rest)
  local d = db()
  local word, arg = (rest or ""):match("^(%S*)%s*(.-)$")
  if word == "hide" or word == "off" then d.hidden = true
  elseif word == "show" or word == "on" then d.hidden = nil
  elseif word == "lock" then d.locked = true
  elseif word == "unlock" then d.locked = nil
  elseif word == "reset" then S.reset() return "new session"
  elseif word == "move" then d.point = nil S.place() return "back at the top"
  elseif word == "bags" and (arg == "used" or arg == "free") then
    S.setBagsUsed(arg == "used")
    return "bags show the slots " .. arg
  elseif PART_NAMES[word] then
    local on = arg == "on" or (arg ~= "off" and not partOn(word))
    S.setPart(word, on)
    return PART_NAMES[word] .. (on and " shown" or " hidden")
  else
    d.hidden = not d.hidden or nil
  end
  S.refresh()
  return (d.hidden and "hidden" or "shown") .. (d.locked and ", locked" or "")
end

-- in the backpack, left of your own money: "All: <total>"
local bagText
local function backpack()
  local c = ContainerFrameCombinedBags
  if c and c.IsShown and c:IsShown() then return c end
  for i = 1, NUM_CONTAINER_FRAMES or 13 do
    local f = _G["ContainerFrame" .. i]
    if f and f.IsShown and f:IsShown() and f.GetID and f:GetID() == 0 then return f end
  end
end
function S.bagGold()
  local bag = backpack()
  if not (bag and S.bagGoldOn()) then
    if bagText then bagText:Hide() end
    return
  end
  local money = bag.MoneyFrame or (bag.GetName and bag:GetName() and _G[bag:GetName() .. "MoneyFrame"])
  -- the leftmost coin shown: the combined backpack's money frame is the whole bar along its bottom, with the coins at
  -- its right end
  local coin
  if money then
    local name = money.GetName and money:GetName()
    for _, c in ipairs({ "Gold", "Silver", "Copper" }) do
      local b = money[c .. "Button"] or (name and _G[name .. c .. "Button"])
      if b and b.IsShown and b:IsShown() then coin = b break end
    end
  end
  if not bagText then
    bagText = ns.newFrame("Stats", "Button", nil, UIParent)
    bagText:SetSize(10, 14)
    bagText.text = bagText:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bagText.text:SetPoint("RIGHT")
    bagText:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      TIPS.all(GameTooltip)
      GameTooltip:Show()
    end)
    bagText:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  bagText:SetParent(bag)
  bagText:SetFrameLevel((money or bag):GetFrameLevel() + 2)
  bagText:ClearAllPoints()
  -- the money frame is as wide as the coins it shows (MoneyFrame_Update)
  if coin then bagText:SetPoint("RIGHT", coin, "LEFT", -10, 0)
  elseif money then bagText:SetPoint("RIGHT", money, "LEFT", -8, 0) else bagText:SetPoint("BOTTOMLEFT", bag, "BOTTOMLEFT", 12, 8) end
  bagText.text:SetText("|cff999999All:|r " .. S.money((S.allGold())))
  bagText:SetWidth(bagText.text:GetStringWidth() + 2)
  bagText:Show()
end
local function hookBackpack()
  local function soon() if C_Timer then C_Timer.After(0, function() pcall(S.bagGold) end) end end
  for i = 1, NUM_CONTAINER_FRAMES or 13 do
    local f = _G["ContainerFrame" .. i]
    if f and f.HookScript then f:HookScript("OnShow", soon) end
  end
  if ContainerFrameCombinedBags and ContainerFrameCombinedBags.HookScript then
    ContainerFrameCombinedBags:HookScript("OnShow", soon)
  end
end

local ev = ns.newFrame("Stats", "Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_XP_UPDATE")
ev:RegisterEvent("PLAYER_MONEY")
ev:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
ev:SetScript("OnEvent", function(_, event, msg)
  if event == "PLAYER_LOGIN" then
    -- a /reload carries the session on; logging in again later starts a new one
    local old = db().sess
    local now = GetTime()
    if old and old.seen and now >= old.seen and now - old.seen <= RELOAD_GAP and now >= old.start then
      sess = old
      seen()
    else
      S.reset()
    end
    S.noteGold()
    pcall(hookBackpack)
    -- every second: the clock, bags, durability and volume (all cheap to read)
    C_Timer.NewTicker(1, function()
      if sess then sess.seen = GetTime() end
      pcall(S.refresh)
    end)
  elseif event == "PLAYER_XP_UPDATE" then   -- (not PLAYER_LEVEL_UP: the XP isn't new yet then)
    xpTick()
  elseif event == "PLAYER_MONEY" then
    moneyTick()
    S.noteGold()
    pcall(S.bagGold)
  elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
    S.killXP(msg)
    return
  end
  if sess then pcall(S.refresh) end
end)
