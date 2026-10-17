-- The route window: the step you're on, how far it is, the next few steps, and Back / Skip / Done. Drag to move;
-- /wfn hides and shows it.
local _, ns = ...
local U = {}
ns.ui = U

local KIND = { accept = "Accept", ["do"] = "Do", turnin = "Turn in", train = "Train", bind = "Hearth", discover = "Flight path",
               buyweapon = "Buy", craft = "Craft", learn = "Learn", learnweapon = "Weapon skill", buyammo = "Ammo", visit = "Visit", run = "Dungeon", grind = "Grind" }
local frame, title, stepText, distText, nextText

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
  tip(done, "Done: you've done this step")
  local skip = button(frame, "Skip", 56, function() ns.core.markDone("skipped") end)
  skip:SetPoint("RIGHT", done, "LEFT", -4, 0)
  tip(skip, "Skip: never show this step again")
  local later = button(frame, "Later", 56, function() ns.core.later() end)
  later:SetPoint("RIGHT", skip, "LEFT", -4, 0)
  tip(later, "Skip for now: it comes back only once you've been 500+ yards from it and are within 200 yards again")
  local note = button(frame, "Note", 50, function()
    ChatFrame_OpenChat("/wfn note ", DEFAULT_CHAT_FRAME)
  end)
  note:SetPoint("LEFT", back, "RIGHT", 4, 0)
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
    local ammo = ns.ammo and ns.ammo.status()
    distText:SetText((d and ("%d yards"):format(math.floor(d)) or "") .. (ammo and ((d and "   " or "") .. ammo) or ""))
  end)
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
local function current(step)
  step = ns.core.ammoStep(step)
  local need, have = ns.core.weaponShort(step)
  if need then
    return ("Kill mobs until you have |cffffd200%s|r for it (you have %s, junk included); then:\n%s"):format(money(need), money(have), line(step))
  end
  if step.k ~= "do" then
    -- a pick-up or hand-in: who in the party has it, who's done
    local others = (step.k == "accept" or step.k == "turnin") and step.q and ns.party and ns.party.progress(step.q)
    return line(step) .. (others and ("\n    |cff88ccffParty: " .. others .. "|r") or "")
  end
  local members = step.mem or { { q = step.q, on = step.on } }
  local rows = {}
  for i, m in ipairs(members) do
    -- only quests you have (the user, 2026-10-17: "its also telling me to do Miner's Gear and Fire Tar at once, i dont
    -- have a quest for Fire Tar"): a part for a quest you never took or already handed in isn't listed
    if not (m.q and C_QuestLog.GetLogIndexForQuestID(m.q) == nil and #members > 1) then
    local text, done = ns.core.objectiveText(m.q, m.on)
    local title = C_QuestLog.GetTitleForQuestID(m.q) or ("quest " .. m.q)
    local c = ns.PALETTE and ns.PALETTE[(i - 1) % #ns.PALETTE + 1] or { 1, 1, 1 }
    local hex = ("%02x%02x%02x"):format(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
    rows[#rows + 1] = ("%s|cff%s%s|r  |cffaaaaaa(%s)|r"):format(done and "|cff40ff40[done]|r " or "- ", hex, text or m.on or step.t, title)
    -- the party's progress on it (Party.lua: those running AuDHD)
    local others = ns.party and ns.party.progress(m.q, m.o)
    if others then rows[#rows + 1] = "    |cff88ccff" .. others .. "|r" end
    end
  end
  -- a step the planner reaches by hearthstone: say so first (or to walk, while it's cooling down)
  local how = step.hs and not ns.core.hearthNear(step) and (ns.core.text(step):match("^(.-), then: ") or "Hearth") .. ", then:\n" or ""
  return how .. (#members > 1 and "Do together here:\n" or "Do:\n") .. table.concat(rows, "\n")
end

function U.refresh()
  if not frame then return end
  local step, i, pos, total, via = ns.core.current()
  local r = ns.core.route()
  title:SetText(("%s  |cffaaaaaastep %s / %d|r"):format(r.title, pos and tostring(pos) or "-", total or #r.steps))
  if not step then
    local more = ns.picker and #ns.picker.choices() > 0
    stepText:SetText("Route finished." .. (more and "  |cffffd200Pick your next route: the Routes button.|r" or ""))
    nextText:SetText("")
    -- once per finished route: the picker opens by itself
    if more and U.finishedShown ~= AuDHDDB.route then
      U.finishedShown = AuDHDDB.route
      ns.picker.show()
    end
  else
    -- a step the GPS took out of the route's order because it's right here
    -- or an escort's area still has quests to do (Core's escortWait)
    stepText:SetText((via == "escort" and "|cffffd200Before the escort:|r " or via and "|cff40c0ffNearby:|r " or "") .. current(step) .. (step.lv and not via and ("  |cffaaaaaa(level %d after)|r"):format(step.lv) or ""))
    local nexts = {}
    for k = 1, 3 do
      local s = ns.core.peek(k)
      if s then nexts[#nexts + 1] = line(s) end
    end
    nextText:SetText(#nexts > 0 and ("Next: " .. table.concat(nexts, "\n")) or "")
  end
  frame:SetHeight(math.max(140, 60 + stepText:GetStringHeight() + nextText:GetStringHeight() + 40))
end

function U.toggle()
  if not frame then return end
  if frame:IsShown() then frame:Hide(); AuDHDDB.hidden = true else frame:Show(); AuDHDDB.hidden = nil; U.refresh() end
end
