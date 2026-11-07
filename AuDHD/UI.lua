-- The route window: the step you're on, how far it is, the next few steps, and Back / Skip / Done. Drag to move;
-- /audhd hides and shows it.
local _, ns = ...
local U = {}
ns.ui = U

local KIND = { accept = "Accept", ["do"] = "Do", turnin = "Turn in", train = "Train", bind = "Hearth", discover = "Flight path",
               buyweapon = "Buy", craft = "Craft", learn = "Learn", learnweapon = "Weapon skill", buyammo = "Ammo", visit = "Visit", run = "Dungeon", grind = "Grind", done = "Done" }
local frame, title, stepText, distText, nextText, listen, skip

-- one spawn the whole server shares (cw, from manual_overrides "contested"): the warning, and whether Skip drops only
-- that quest (a pick-up, or a step that's only that quest's work) or a whole step done together
local function contested(step)
  if step.k == "accept" then return step.cw, true end
  if step.k ~= "do" then return nil end
  if not step.mem then return step.cw, true end
  local warn, open = nil, 0
  for _, m in ipairs(step.mem) do
    if m.q and C_QuestLog.GetLogIndexForQuestID(m.q) and not (C_QuestLog.IsComplete and C_QuestLog.IsComplete(m.q)) then
      open = open + 1
      if m.cw then warn = m.cw end
    end
  end
  return warn, open <= 1
end
U.contested = contested   -- (the smoke test)

-- Skip lit up (an orange border and its highlight held) while the step warns of a shared spawn
local function lightSkip(on)
  if not skip then return end
  if on then skip:LockHighlight() else skip:UnlockHighlight() end
  if skip.glow then skip.glow:SetShown(on and true or false) end
  U.skipLit = on and true or false
end

-- the Listen button: shown when Chronicle has lines for the current step, saying Stop while they play
local function updateListen()
  if not listen then return end
  local C = ns.chronicle
  local show = C and C.isOn() and #C.keys((ns.core.current())) > 0
  listen:SetShown(show and true or false)
  if show then listen:SetText(C.playing() and "Stop" or "Listen") end
end

-- [log] after each quest in the window: logs it for us (Share.lua), [logging] while it does, click to stop. Links in
-- the window's text, so only where the game lets a frame take link clicks
local linksOn = false
local function logLink(q)
  if not (linksOn and q and ns.share) then return "" end
  if ns.share.isLogging(q) then return ("  |cff40ff40|Haudhdlog:%d|h[logging]|h|r"):format(q) end
  return ("  |cff9d9d9d|Haudhdlog:%d|h[log]|h|r"):format(q)
end
local function linkQuest(link) return type(link) == "string" and tonumber(link:match("^audhdlog:(%d+)")) end
local function logToggle(q)
  if not (q and ns.share) then return nil end
  local msg = ns.share.isLogging(q) and ns.share.stop(q) or ns.share.start(q, "from the window")
  print("|cff66ccffAuDHD|r: " .. msg)
  U.refresh()
  return msg
end
function U.logClick(link) return logToggle(linkQuest(link)) end

local function button(parent, label, width, onClick)
  local b = ns.newFrame("UI", "Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 20)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end

function U.create()
  if frame then return end
  frame = ns.newFrame("UI", "Frame", "AuDHDFrame", UIParent, "BackdropTemplate")
  frame:SetSize(360, 168)
  frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                      tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  frame:SetBackdropColor(0, 0, 0, 0.8)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  if frame.SetHyperlinksEnabled then
    frame:SetHyperlinksEnabled(true)
    linksOn = true
    frame:SetScript("OnHyperlinkClick", function(_, link) U.logClick(link) end)
    frame:SetScript("OnHyperlinkEnter", function(self, link)
      local q = linkQuest(link)
      if not q then return end
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
      if ns.share and ns.share.isLogging(q) then
        GameTooltip:SetText("Logging this quest. Click to stop.", 1, 1, 1, 1, true)
      else
        GameTooltip:SetText("Log this quest: your kills, loot and objective progress, and where each happened, until you turn it in or abandon it. Then send us the log (Settings, Help/Info).", 1, 1, 1, 1, true)
      end
      GameTooltip:Show()
    end)
    frame:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
  end
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    AuDHDDB.ui = { p = p, rp = rp, x = x, y = y }
  end)
  local pos = AuDHDDB.ui
  if pos then frame:SetPoint(pos.p, UIParent, pos.rp, pos.x, pos.y) else frame:SetPoint("RIGHT", UIParent, "RIGHT", -60, 120) end

  title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -8)
  title:SetPoint("RIGHT", -70, 0)
  title:SetJustifyH("LEFT")

  stepText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  stepText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  stepText:SetPoint("RIGHT", -10, 0)
  stepText:SetJustifyH("LEFT")
  stepText:SetWordWrap(true)

  distText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  distText:SetPoint("TOPLEFT", stepText, "BOTTOMLEFT", 0, -4)
  distText:SetWidth(340)   -- one line in the window: a long leg ("Hearth (to ...), then: ...") ends in "..."
  distText:SetWordWrap(false)
  distText:SetJustifyH("LEFT")

  nextText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  nextText:SetPoint("TOPLEFT", distText, "BOTTOMLEFT", 0, -6)
  nextText:SetPoint("RIGHT", -10, 0)
  nextText:SetJustifyH("LEFT")
  nextText:SetWordWrap(true)

  local function tip(b, text)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(text, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  local back = button(frame, "Back", 56, function() ns.core.back() end)
  back:SetPoint("BOTTOMLEFT", 8, 8)
  local done = button(frame, "Done", 56, function() ns.core.markDone("manual") end)
  done:SetPoint("BOTTOMRIGHT", -8, 8)
  tip(done, "Done: tick off the top task. The step moves on once its last task is done (a row's own Done button ticks off just that one)")
  skip = button(frame, "Skip", 56, function() ns.core.markDone("skipped") end)
  skip:SetPoint("RIGHT", done, "LEFT", -4, 0)
  tip(skip, "Skip the top task: on a quest, that quest is skipped in the whole route (/audhd unskip brings it back); on anything else, it's ticked off")
  skip.glow = skip:CreateTexture(nil, "OVERLAY")
  skip.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  skip.glow:SetBlendMode("ADD")
  skip.glow:SetVertexColor(1, 0.5, 0)
  skip.glow:SetPoint("TOPLEFT", -14, 12)
  skip.glow:SetPoint("BOTTOMRIGHT", 14, -12)
  skip.glow:Hide()
  local later = button(frame, "Later", 56, function() ns.core.later() end)
  later:SetPoint("RIGHT", skip, "LEFT", -4, 0)
  tip(later, "Skip for now: it comes back only once you've been 500+ yards from it and are within 200 yards again")
  local note = button(frame, "Note", 50, function()
    ChatFrame_OpenChat("/audhd note ", DEFAULT_CHAT_FRAME)
  end)
  note:SetPoint("LEFT", back, "RIGHT", 4, 0)
  -- Chronicle installed (Chronicle.lua): play the current step's quest lines; hidden without it
  listen = button(frame, "Listen", 50, function() if ns.chronicle then ns.chronicle.toggle(ns.core.current()) end end)
  listen:SetPoint("LEFT", note, "RIGHT", 4, 0)
  tip(listen, "Chronicle reads this step's quest out: what the quest giver said, and the turn-in. Click again to stop")
  listen:Hide()
  U.listen = listen   -- (the smoke test)
  -- the route picker: the routes planned for you, with their times (RoutePicker.lua)
  local routes = button(frame, "Routes", 60, function() if ns.picker then ns.picker.toggle() end end)
  routes:SetHeight(18)
  routes:SetPoint("TOPRIGHT", -6, -6)
  tip(routes, "Pick your next route: the planned ones, with how long each takes")

  -- the distance, twice a second (the arrow has its own window: Arrow.lua)
  local acc = 0
  frame:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.5 then return end
    acc = 0
    local d = ns.core.bearing(ns.core.target)
    -- what's left to walk, not the straight line; and the way's leg now, as under the arrow ("Fly to Menethil Harbor":)
    local how
    if d and ns.walk then
      local _, _, left, what = ns.walk.aim(ns.core.target)
      d = left or d
      if type(what) == "string" and what ~= "" then how = what end
    end
    -- the rest of a way round after the point the arrow is at (Track.lua)
    local g = ns.core.goalTarget
    if d and g and g.after then d = d + g.after end
    local timer = g and g.q and (g.i or 0) < 0 and ns.track and ns.track.isTimed(g.q) and ns.track.timeText(g.q)
    local ammo = ns.ammo and ns.ammo.status()
    local parts = {}
    if d then parts[#parts + 1] = ("%d yards"):format(math.floor(d)) .. (how and ("  |cffffd200%s|r"):format(how) or "") end
    if timer then parts[#parts + 1] = timer end
    if ammo then parts[#parts + 1] = ammo end
    distText:SetText(table.concat(parts, "   "))
    updateListen()
  end)
  frame:HookScript("OnShow", function() U.applyTracker() end)
  frame:HookScript("OnHide", function() U.applyTracker() end)
  if AuDHDDB.hidden then frame:Hide() end
  U.refresh()
end

local function line(step)
  local kind, text = KIND[step.k] or step.k, ns.core.text(step)
  -- a text that already starts with its kind ("Do The Balance of Nature") doesn't need it twice
  if text:sub(1, #kind + 1) == kind .. " " then return text end
  return ("%s: %s"):format(kind, text)
end
U.line = line   -- the map pins' tooltips (RouteMap.lua)

-- the current step in full: objectives with their live counts from your quest log
local function money(c) return c >= 100 and ("%ds %dc"):format(math.floor(c / 100), c % 100) or ("%dc"):format(c) end
-- a guide step: a row for each thing still to do, with its progress and the guide's note under it, and its own Log and
-- Done buttons. Returns it all as text (the tests), the rows, and the line above them
local function guideRows(step)
  local blocks, all, allDo, told = {}, {}, true, {}
  for i, r in ipairs(step.rows) do
    if r.k ~= "do" then allDo = false end
    local text = r.text
    if r.k == "do" then
      local c = ns.PALETTE and ns.PALETTE[(i - 1) % #ns.PALETTE + 1] or { 1, 1, 1 }
      text = ("|cff%02x%02x%02x%s|r"):format(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255), text)
    end
    local title = r.q and C_QuestLog.GetTitleForQuestID(r.q)
    if title and not r.text:find(title, 1, true) then text = ("%s  |cffaaaaaa(%s)|r"):format(text, title) end
    local lines = { "- " .. text }
    if r.warn then lines[#lines + 1] = "    |cffff8000" .. r.warn .. "|r" end
    if r.note and r.note ~= "" then lines[#lines + 1] = "    |cffaaaaaa" .. r.note .. "|r" end
    -- the party's progress, once for each quest (Party.lua: those running AuDHD)
    local first = r.q and not told[r.q]
    local others = first and ns.party and ns.party.progress(r.q)
    if r.q then told[r.q] = true end
    if others then lines[#lines + 1] = "    |cff88ccff" .. others .. "|r" end
    local block = table.concat(lines, "\n")
    -- (Log once for each quest; Done on every row while the step has two or more)
    blocks[#blocks + 1] = { text = block, q = first and r.q or nil, i = step.i, g = r.g }
    all[#all + 1] = block
  end
  local hearth = ns.core.text(step):match("^Hearth %(to .-%), then: ")
  local head = (hearth or "") .. (allDo and ((hearth and "\n" or "") .. "Do:") or "")
  return (head ~= "" and head .. "\n" or "") .. table.concat(all, "\n"), blocks, head
end
local function current(step)
  step = ns.core.ammoStep(step)
  local need, have = ns.core.weaponShort(step)
  if need then
    return ("Kill mobs until you have |cffffd200%s|r for it (you have %s, junk included); then:\n%s"):format(money(need), money(have), line(step))
  end
  if step.rows then return guideRows(step) end
  if step.k ~= "do" then
    -- a pick-up or hand-in: who in the party has it, who's done; its Log button
    local pick = (step.k == "accept" or step.k == "turnin") and step.q
    local others = pick and ns.party and ns.party.progress(step.q)
    local text = line(step) .. (others and ("\n    |cff88ccffParty: " .. others .. "|r") or "")
    if pick then return text, { { text = text, q = step.q } }, "" end
    return text
  end
  local members = step.mem or { { q = step.q, on = step.on } }
  local rows, linked = {}, {}
  for i, m in ipairs(members) do
    -- only quests you have: a part for a quest you never took or already handed in isn't listed
    if not (m.q and C_QuestLog.GetLogIndexForQuestID(m.q) == nil and #members > 1) then
    local text, done = ns.core.objectiveText(m.q, m.on)
    local title = C_QuestLog.GetTitleForQuestID(m.q) or ("quest " .. m.q)
    local c = ns.PALETTE and ns.PALETTE[(i - 1) % #ns.PALETTE + 1] or { 1, 1, 1 }
    local hex = ("%02x%02x%02x"):format(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
    rows[#rows + 1] = ("%s|cff%s%s|r  |cffaaaaaa(%s)|r%s"):format(done and "|cff40ff40[done]|r " or "- ", hex, text or m.on or step.t, title, not linked[m.q] and logLink(m.q) or "")
    linked[m.q] = true
    -- the party's progress on it (Party.lua: those running AuDHD)
    local others = ns.party and ns.party.progress(m.q, m.o)
    if others then rows[#rows + 1] = "    |cff88ccff" .. others .. "|r" end
    end
  end
  -- a step the planner reaches by hearthstone: say so first (or to walk, while it's cooling down)
  local how = step.hs and not ns.core.hearthNear(step) and (ns.core.text(step):match("^(.-), then: ") or "Hearth") .. ", then:\n" or ""
  -- a warning for the way there (Track.lua: a timed quest's way round)
  if step.note then rows[#rows + 1] = "    |cffff8000" .. step.note .. "|r" end
  return how .. (#members > 1 and "Do together here:\n" or "Do:\n") .. table.concat(rows, "\n")
end

U.current = current   -- (the smoke test)

-- what's coming, one line each and only the first few: the window stays small
local NEXT_LINES = 6
local function comingUp()
  local out, more = {}, 0
  for k = 1, 3 do
    local s = ns.core.peek(k)
    if s then
      for _, r in ipairs(s.rows or { { text = line(s) } }) do
        if #out < NEXT_LINES then out[#out + 1] = "- " .. r.text else more = more + 1 end
      end
    end
  end
  if #out == 0 then return "" end
  if more > 0 then out[#out + 1] = ("and %d more"):format(more) end
  return "Next:\n" .. table.concat(out, "\n")
end
U.comingUp = comingUp   -- (the smoke test)

-- the rows of a guide step, each its own text with its buttons at the right: Log (Logging while it logs) once for each
-- quest, Done on every row while the step has two or more (G.tickGoal: a pick-up you can't take is skipped in the route)
local ROW_W, BTN_H, LOG_W, DONE_W = 340, 18, 54, 44
local rowsUI = {}
U.rowsUI = rowsUI   -- (the smoke test)
local function smallFont(b)
  if GameFontNormalSmall and b.SetNormalFontObject then b:SetNormalFontObject(GameFontNormalSmall) end
  if GameFontHighlightSmall and b.SetHighlightFontObject then b:SetHighlightFontObject(GameFontHighlightSmall) end
end
local function rowUI(k)
  if rowsUI[k] then return rowsUI[k] end
  local r = {}
  r.fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.fs:SetJustifyH("LEFT")
  r.fs:SetWordWrap(true)
  r.log = button(frame, "Log", LOG_W, function() logToggle(r.q) end)
  r.done = button(frame, "Done", DONE_W, function()
    if r.i and r.g and ns.guide then ns.guide.tickGoal(r.i, r.g) end
    U.refresh()
  end)
  for _, b in ipairs({ r.log, r.done }) do b:SetHeight(BTN_H) smallFont(b) end
  r.log:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if r.q and ns.share and ns.share.isLogging(r.q) then
      GameTooltip:SetText("Logging this quest. Click to stop.", 1, 1, 1, 1, true)
    else
      GameTooltip:SetText("Log this quest: your kills, loot and objective progress, and where each happened, until you turn it in or abandon it. Then send us the log (Settings, Help/Info).", 1, 1, 1, 1, true)
    end
    GameTooltip:Show()
  end)
  r.log:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r.done:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Done: tick off just this task; the rest of the step stays. A quest you can't pick up is skipped in the route (/audhd unskip brings it back).", 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  r.done:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rowsUI[k] = r
  return r
end
-- lays the rows out under the step's first line; returns their height, the last row's text and the gap under it (the
-- distance line goes there)
local function layoutRows(blocks)
  local prev, height, gap = stepText, 0, 2
  local multi = blocks and #blocks > 1
  for k = 1, math.max(blocks and #blocks or 0, #rowsUI) do
    local b = blocks and blocks[k]
    local r = b and rowUI(k) or rowsUI[k]
    if b then
      local showLog = b.q and ns.share and true or false
      local showDone = multi and b.g and b.i and b.i > 0 and true or false
      r.q, r.i, r.g = b.q, b.i, b.g
      r.fs:ClearAllPoints()
      r.fs:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -gap)
      height = height + gap
      r.fs:SetWidth(ROW_W - (showLog and LOG_W + 4 or 0) - (showDone and DONE_W + 4 or 0))
      r.fs:SetText(b.text)
      r.fs:Show()
      local anchor = r.fs
      if showLog then
        r.log:ClearAllPoints()
        r.log:SetPoint("TOPLEFT", r.fs, "TOPRIGHT", 4, 2)
        r.log:SetText(ns.share.isLogging(b.q) and "Logging" or "Log")
        r.log:Show()
        anchor = r.log
      else
        r.log:Hide()
      end
      if showDone then
        r.done:ClearAllPoints()
        r.done:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, anchor == r.fs and 2 or 0)
        r.done:Show()
      else
        r.done:Hide()
      end
      r.shownLog, r.shownDone = showLog, showDone
      -- a one-line row is shorter than its buttons: the next starts below them
      local th = r.fs:GetStringHeight() or 0
      local h = math.max(th, (showLog or showDone) and BTN_H or 0)
      height = height + th
      gap = 4 + (h - th)
      prev = r.fs
    elseif r then
      r.fs:Hide() r.log:Hide() r.done:Hide()
      r.q, r.i, r.g, r.shownLog, r.shownDone = nil, nil, nil, false, false
    end
  end
  return height, prev, gap
end
U.layoutRows = layoutRows   -- (the smoke test)

function U.refresh()
  if not frame then return end
  local step, i, pos, total, via = ns.core.current()
  local r = ns.core.route()
  local rowsShown
  if not r then
    title:SetText("AuDHD")
    lightSkip(false)
    U.warned = nil
    stepText:SetText("No guide picked: the Routes button.")
    nextText:SetText("")
    layoutRows(nil)
    distText:ClearAllPoints()
    distText:SetPoint("TOPLEFT", stepText, "BOTTOMLEFT", 0, -4)
    frame:SetHeight(140)
    updateListen()
    return
  end
  title:SetText(("%s  |cffaaaaaastep %s / %d|r"):format(r.title, pos and tostring(pos) or "-", total or #(r.steps or {})))
  if not step then
    local more = ns.picker and #ns.picker.choices() > 0
    lightSkip(false)
    U.warned = nil
    stepText:SetText("Route finished." .. (more and "  |cffffd200Pick your next route: the Routes button.|r" or ""))
    nextText:SetText("")
    -- once per finished route: the picker opens by itself
    if more and U.finishedShown ~= AuDHDDB.route and not (ns.classQuest and ns.classQuest.goingBack())
      and not (ns.dungeons and ns.dungeons.goingBack()) then
      U.finishedShown = AuDHDDB.route
      ns.picker.show()
    end
  else
    -- a step the GPS took out of the route's order because it's right here
    -- or an escort's area still has quests to do (Core's escortWait)
    local warn, alone = contested(step)
    local busy = warn and ("\n|cffff8000Busy server? %s %s|r"):format(warn, alone and "If someone's already waiting, Skip it."
      or "To drop just this quest, abandon it in your quest log (Skip would drop the whole step).") or ""
    local full, blocks, head = current(step)
    local pre = via == "timed" and "|cffff8000Timed:|r " or via == "extra" and "|cff40c0ffExtra quest:|r " or via == "escort" and "|cffffd200Before the escort:|r " or via and "|cff40c0ffNearby:|r " or ""
    local post = (step.lv and not via and ("  |cffaaaaaa(level %d after)|r"):format(step.lv) or "") .. busy
    stepText:SetText(pre .. (blocks and head or full) .. post)
    rowsShown = blocks
    lightSkip(warn and alone)
    U.warned = warn
    nextText:SetText(comingUp())
  end
  local rowsH, last, gap = layoutRows(step and rowsShown or nil)
  distText:ClearAllPoints()
  distText:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, last == stepText and -4 or -gap)
  frame:SetHeight(math.max(140, 60 + stepText:GetStringHeight() + rowsH + nextText:GetStringHeight() + 40))
  updateListen()
end

-- the game's quest list (All Objectives), hidden while the route window shows when that's switched on. Hidden again each
-- time the game shows it; when it's let go, the game's own Update decides, which shows it only if it has something to show.
-- Not with the gamepad interface, whose navigation starts at that list. A list another addon made protected waits for the
-- end of the fight.
local trackerHidden, trackerHooked = false, false
function U.applyTracker()
  local f = ObjectiveTrackerFrame
  if not (f and f.Hide and AuDHDDB) then return end
  if f.IsProtected and f:IsProtected() and InCombatLockdown() then return end
  local gamepad = AuDHDEngine and AuDHDEngine.GamepadUI and AuDHDEngine.GamepadUI()
  if AuDHDDB.hideTracker and frame and frame:IsShown() and not gamepad then
    if not trackerHooked then
      trackerHooked = true
      f:HookScript("OnShow", function() if trackerHidden then U.applyTracker() end end)
    end
    trackerHidden = true
    if f:IsShown() then f:Hide() end
  elseif trackerHidden then
    trackerHidden = false
    if f.Update then f:Update() else f:Show() end
  end
end
local trackerEvents = ns.newFrame("UI", "Frame")
trackerEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
trackerEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
trackerEvents:RegisterEvent("ADDON_LOADED")   -- (the list is a load-on-demand part of the game's interface)
trackerEvents:SetScript("OnEvent", function() U.applyTracker() end)

function U.toggle()
  if not frame then return end
  if frame:IsShown() then frame:Hide(); AuDHDDB.hidden = true else frame:Show(); AuDHDDB.hidden = nil; U.refresh() end
end
