-- At a class trainer without the money for everything: what it costs, what your junk and spare BoE gear would sell for,
-- and which spells to train now and which to leave for the next trainer on your route. Prices come from the trainer
-- window itself. Spells on your action bars come first (the ones you use), then the newest ranks. A spell you use that
-- has waited 2 levels or more gets a line of its own.
local _, ns = ...
local M = {}
ns.train = M

local log = function(e, f) if ns.log then ns.log.add(e, f) end end
local WAIT_LEVELS = 2

function M.money(c)
  c = math.floor(c or 0)
  local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "g" end
  if s > 0 then out[#out + 1] = s .. "s" end
  if k > 0 or #out == 0 then out[#out + 1] = k .. "c" end
  return table.concat(out, " ")
end
local money = M.money

-- the spells on your action bars, by name
local function onBars()
  local names = {}
  if not GetActionInfo then return names end
  for slot = 1, 120 do
    local kind, id = GetActionInfo(slot)
    if kind == "spell" and id then
      local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
      if not n and GetSpellInfo then n = GetSpellInfo(id) end
      if n then names[n] = true end
    end
  end
  return names
end

-- what this trainer will teach you now: { name, rank, cost, lv, bar }
function M.available()
  local out = {}
  if not (GetNumTrainerServices and GetTrainerServiceInfo and GetTrainerServiceCost) then return out end
  local bars = onBars()
  for i = 1, (GetNumTrainerServices() or 0) do
    local name, rank, cat = GetTrainerServiceInfo(i)
    if cat == "available" and name then
      out[#out + 1] = { name = name, rank = rank, cost = GetTrainerServiceCost(i) or 0,
        lv = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or 0, bar = bars[name] == true }
    end
  end
  return out
end

-- what to train with the money you have: spells you use first, then the newest, the cheaper first; whatever doesn't fit
-- waits (a dear one skipped doesn't stop a cheaper one after it)
function M.plan(list, have)
  local sorted = {}
  for _, s in ipairs(list) do sorted[#sorted + 1] = s end
  table.sort(sorted, function(a, b)
    if a.bar ~= b.bar then return a.bar end
    if a.lv ~= b.lv then return a.lv > b.lv end
    if a.cost ~= b.cost then return a.cost < b.cost end
    return a.name < b.name
  end)
  local now, later, spent = {}, {}, 0
  for _, s in ipairs(sorted) do
    if spent + s.cost <= have then now[#now + 1] = s spent = spent + s.cost else later[#later + 1] = s end
  end
  return now, later, spent
end

-- what your bags would sell for: junk, and BoE gear you won't wear (the bank-alt list; worth more on the auction
-- house, but this is about training now)
local function sellable()
  local junk = ns.auto and ns.auto.junkValue and ns.auto.junkValue() or 0
  local boe = 0
  if ns.services and ns.services.mailables and C_Container and C_Item then
    for _, it in ipairs(ns.services.mailables()) do
      if it.kind == "boe" then
        local info = C_Container.GetContainerItemInfo(it.bag, it.slot)
        local price = info and info.hyperlink and select(11, C_Item.GetItemInfo(info.hyperlink))
        boe = boe + (price or 0) * (info and info.stackCount or 1)
      end
    end
  end
  return junk, boe
end

local function names(list)
  local t = {}
  for _, s in ipairs(list) do t[#t + 1] = s.rank and s.rank ~= "" and (s.name .. " (" .. s.rank .. ")") or s.name end
  return table.concat(t, ", ")
end

-- the advice, or nil when you can pay for everything
function M.advice()
  local list = M.available()
  if #list == 0 then return nil end
  local total = 0
  for _, s in ipairs(list) do total = total + s.cost end
  local have = GetMoney and GetMoney() or 0
  local level = UnitLevel and UnitLevel("player") or 0
  AuDHDDB.trainWait = AuDHDDB.trainWait or {}
  local wait = AuDHDDB.trainWait
  -- a spell no longer offered was trained (or isn't yours any more): stop counting its wait
  local offered = {}
  for _, s in ipairs(list) do offered[s.name] = true end
  for n in pairs(wait) do if not offered[n] then wait[n] = nil end end
  if total <= have then return nil end
  local short = total - have
  local junk, boe = sellable()
  local lines = { ("Training here costs %s; you have %s (%s short)."):format(money(total), money(have), money(short)) }
  if junk >= short then
    lines[#lines + 1] = ("Sell your junk (%s) at a vendor and come back: that covers it."):format(money(junk))
    return table.concat(lines, "\n"), { total = total, have = have, junk = junk, boe = boe, sell = true }
  elseif junk + boe >= short then
    lines[#lines + 1] = ("Sell your junk (%s) and the BoE gear you won't wear (%s) at a vendor and come back: that covers it.")
      :format(money(junk), money(boe))
    return table.concat(lines, "\n"), { total = total, have = have, junk = junk, boe = boe, sell = true }
  end
  local now, later, spent = M.plan(list, have)
  local long = {}
  for _, s in ipairs(later) do
    if s.bar then
      wait[s.name] = wait[s.name] or level
      if level - wait[s.name] >= WAIT_LEVELS then long[#long + 1] = s.name end
    end
  end
  -- a spell you use has waited long enough: don't spend its money on ones you don't use
  if #long > 0 then
    local keep = {}
    spent = 0
    for _, s in ipairs(now) do
      if s.bar then keep[#keep + 1] = s spent = spent + s.cost else later[#later + 1] = s end
    end
    now = keep
  end
  if #now > 0 then lines[#lines + 1] = ("Train now (%s): %s."):format(money(spent), names(now)) end
  lines[#lines + 1] = ("Leave for the next trainer on your route: %s."):format(names(later))
  if junk + boe > 0 then
    lines[#lines + 1] = ("Selling your junk%s at the next vendor gives you %s towards them.")
      :format(boe > 0 and " and spare BoE gear" or "", money(junk + boe))
  end
  if #long > 0 then
    lines[#lines + 1] = ("%s %s waited since level %d: put money aside for %s before anything else (no ammo or gear "
      .. "upgrades you can do without) until your next trainer."):format(table.concat(long, ", "), #long > 1 and "have" or "has",
      wait[long[1]], #long > 1 and "them" or "it")
  end
  return table.concat(lines, "\n"), { total = total, have = have, junk = junk, boe = boe, now = #now, later = #later, long = #long }
end

-- the note beside the trainer window
local note
local function show(text)
  if not note then
    note = ns.newFrame("Train", "Frame", "AuDHDTrainNote", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    note:SetSize(300, 120)
    note:SetFrameStrata("DIALOG")
    if note.SetBackdrop then
      note:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      note:SetBackdropColor(0.05, 0.05, 0.1, 0.92)
    end
    note.text = note:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    note.text:SetPoint("TOPLEFT", 10, -10)
    note.text:SetWidth(280)
    note.text:SetJustifyH("LEFT")
  end
  note:ClearAllPoints()
  if ClassTrainerFrame and ClassTrainerFrame.IsShown and ClassTrainerFrame:IsShown() then
    note:SetPoint("TOPLEFT", ClassTrainerFrame, "TOPRIGHT", -30, -12)
  else
    note:SetPoint("CENTER", UIParent, "CENTER", 260, 80)
  end
  note.text:SetText(text)
  note:SetHeight(math.max(60, (note.text.GetStringHeight and note.text:GetStringHeight() or 90) + 20))
  note:Show()
  M.shown = text
end
local function hide()
  if note then note:Hide() end
  M.shown = nil
end

local open, logged = false, nil
function M.check()
  if not open then return end
  local text, info = M.advice()
  if text then
    show(text)
    if logged ~= text then logged = text log("TRAIN_SHORT", info) end
  else
    hide()
  end
end

local frame = ns.newFrame("Train", "Frame")
frame:SetScript("OnEvent", function(_, event)
  if event == "TRAINER_CLOSED" then open = false hide() return end
  if event == "TRAINER_SHOW" then open = true logged = nil end
  local ok, err = pcall(M.check)
  if not ok then log("TRAIN_ERROR", { err = tostring(err) }) end
end)
for _, e in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED", "PLAYER_MONEY" }) do pcall(frame.RegisterEvent, frame, e) end
