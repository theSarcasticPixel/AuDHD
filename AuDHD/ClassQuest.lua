-- Class quests: reaching the level a class guide starts at brings a pop-up to swap to it, put it off 10 / 20 / 30
-- minutes or until the route you're on is finished, or say no to it for good. Only class guides for you (class, race
-- and side), not done, below level 60 (the raid ones:), not done (a way through it handed in), and not in a leveling
-- route already (a route for you has steps only for your class with its quests, like Taming the Beast). One at a time,
-- the lowest level first. A class guide you swapped to goes back to your route when it's finished, where you left off.
local _, ns = ...
local CQ = {}
ns.classQuest = CQ
local log = function(e, f) if ns.log then ns.log.add(e, f) end end

local TOP_LEVEL = 60          -- class guides from this level on are left out
local LATER = { 10, 20, 30 }  -- minutes

local function engine() local A = AuDHDEngine return A and A.Engine, A and A.Guides, A end
local function me() return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?") end
-- per character: no = { [guide] = true }, later = { [guide] = time() it's due }, after = { [guide] = the route it waits
-- for }, back = { from = the class guide, to = the route to go back to }
local function state()
  AuDHDDB.classQuest = type(AuDHDDB.classQuest) == "table" and AuDHDDB.classQuest or {}
  local s = AuDHDDB.classQuest[me()]
  if type(s) ~= "table" then s = {} AuDHDDB.classQuest[me()] = s end
  s.no, s.later, s.after = s.no or {}, s.later or {}, s.after or {}
  return s
end
CQ.state = state   -- (the smoke test)

-- for a class's (or any) guide's quests: { all = { [q] = true }, mine = quests on goals or steps only for your class,
-- ends = the hand-ins nothing in the guide needs first (each way through it ends at one) }. Its steps load for this
-- (facts lets them go again)
local function onlyMine(only, class)
  local _, Guides = engine()
  local list = type(only) == "table" and only.classes
  if type(list) ~= "table" or #list == 0 then return false end
  local positive = false
  for _, c in ipairs(list) do if c:sub(1, 1) ~= "!" then positive = true end end
  return positive and Guides.ListMatches(list, class) or false
end
local function questsOf(id, class)
  local _, Guides = engine()
  local g = Guides and Guides.Get(id)
  if not g then return nil end
  local all, mine, turnins, pres = {}, {}, {}, {}
  local ok = pcall(function()
    for _, step in ipairs(g.steps or {}) do
      local stepMine = class and onlyMine(step.only, class)
      for _, goal in ipairs(step.goals or {}) do
        if type(goal.quest) == "number" then
          all[goal.quest] = true
          if class and (stepMine or onlyMine(goal.only, class)) then mine[goal.quest] = true end
          if goal.t == "turnin" then turnins[#turnins + 1] = goal.quest end
        end
        for _, q in ipairs(type(goal.pre) == "table" and goal.pre or {}) do pres[q] = true end
      end
    end
  end)
  if not ok then return nil end
  local ends, seen = {}, {}
  for _, q in ipairs(turnins) do
    if not pres[q] and not seen[q] then seen[q] = true ends[#ends + 1] = q end
  end
  return { all = all, mine = mine, ends = ends }
end
-- for this class, race and side: each class guide's ends, and the ones a leveling route for you already does (it has
-- steps only for your class with that guide's quests: Taming the Beast in Teldrassil). Worked out once per kind of
-- character and guide data (it reads every leveling route), and kept
local function facts(list, p)
  local _, Guides = engine()
  local meta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  local ver = meta and meta("AuDHD", "Version") or "?"
  local key = table.concat({ tostring(p.class), tostring(p.race), tostring(p.faction), #list, ver }, "|")
  AuDHDDB.classFacts = type(AuDHDDB.classFacts) == "table" and AuDHDDB.classFacts or {}
  local f = AuDHDDB.classFacts[key]
  if f then return f end
  local inRoutes = {}
  for _, h in ipairs(list) do
    if (h.category or "Leveling") == "Leveling" and Guides.GuideMatches(h, p) then
      local qs = questsOf(h.id, p.class)
      for q in pairs(qs and qs.mine or {}) do inRoutes[q] = true end
    end
  end
  f = { ends = {}, covered = {} }
  for _, h in ipairs(list) do
    if h.category == "Class" and Guides.GuideMatches(h, p) then
      local qs = questsOf(h.id)
      f.ends[h.id] = qs and qs.ends or {}
      for q in pairs(qs and qs.all or {}) do
        if inRoutes[q] then f.covered[h.id] = true break end
      end
    end
  end
  AuDHDDB.classFacts[key] = f
  -- the steps read in go again, but for the guides a tab shows (as the engine does on a tab change)
  local E = engine()
  if Guides.ReleaseExcept and E and E.TabIds then pcall(Guides.ReleaseExcept, E.TabIds()) end
  return f
end
local function handedIn(q) return C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(q) end

local function lv(h) return h.minLevel or 1 end
-- the class guides to offer at this level, the lowest level first (not counting the ones put off)
function CQ.candidates(level)
  local E, Guides, A = engine()
  if not (E and Guides and A.Compat and A.Compat.GetPlayerInfo) then return {} end
  local p = A.Compat.GetPlayerInfo()
  local list = Guides.List()
  local f = facts(list, p)
  local s = state()
  level = level or UnitLevel("player") or 1
  local tabs = E.TabIds and E.TabIds() or {}
  local out = {}
  for _, h in ipairs(list) do
    if h.category == "Class" and lv(h) <= level and lv(h) < TOP_LEVEL and not s.no[h.id] and not f.covered[h.id]
        and not tabs[h.id] and Guides.GuideMatches(h, p) and E.GetGuideState(h.id) ~= "done" then
      local done = false
      for _, q in ipairs(f.ends[h.id] or {}) do if handedIn(q) then done = true break end end
      if not done then out[#out + 1] = h end
    end
  end
  table.sort(out, function(a, b)
    if lv(a) ~= lv(b) then return lv(a) < lv(b) end
    return tostring(a.title) < tostring(b.title)
  end)
  return out
end

-- ------------------------------------------------------------------ the pop-up
local pop, showing
local function title(h) return ns.guide and ns.guide.named and ns.guide.named(h) or tostring(h.title or h.id) end
local function close()
  showing = nil
  if pop then pop:Hide() end
end
local function choose(choice, mins)
  local h = showing
  if not h then return end
  local s = state()
  local E = engine()
  log("CLASS_QUEST", { id = h.id, choice = choice, mins = mins })
  close()
  if choice == "swap" then
    local cur = E and E.GetGuide()
    s.back = { from = h.id, to = cur and cur.id ~= h.id and cur.id or nil }
    s.later[h.id], s.after[h.id] = nil, nil
    if ns.guide then ns.guide.follow(h.id) end
    return
  elseif choice == "later" then
    s.later[h.id] = time() + 60 * mins
  elseif choice == "after" then
    local cur = E and E.GetGuide()
    s.after[h.id] = cur and cur.id or true
  elseif choice == "no" then
    s.no[h.id] = true
  end
  CQ.check()   -- the next one, if another is due
end
local function popup()
  if pop then return pop end
  local f = ns.newFrame("ClassQuest", "Frame", "AuDHDClassQuest", UIParent, "BackdropTemplate")
  f:SetSize(330, 118)
  f:SetPoint("TOP", UIParent, "TOP", 0, -150)
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.05, 0.05, 0.1, 0.92)
  end
  f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.text:SetPoint("TOP", 0, -10)
  f.text:SetWidth(314)
  f.why = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.why:SetPoint("TOP", f.text, "BOTTOM", 0, -3)
  f.why:SetWidth(314)
  local function button(label, x, y, w, onClick)
    local b = ns.newFrame("ClassQuest", "Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(w, 20)
    b:SetPoint("BOTTOM", f, "BOTTOM", x, y)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
  end
  f.swap = button("Swap to it", -104, 32, 96, function() choose("swap") end)
  f.after = button("After this route", 0, 32, 108, function() choose("after") end)
  f.no = button("Not this one", 104, 32, 96, function() choose("no") end)
  for i, mins in ipairs(LATER) do
    f["later" .. mins] = button(mins .. " min", -34 + 68 * (i - 1), 8, 64, function() choose("later", mins) end)
  end
  f.zz = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.zz:SetPoint("RIGHT", f["later" .. LATER[1]], "LEFT", -6, 0)
  f.zz:SetText("Later:")
  f:Hide()
  pop = f
  return f
end
local function show(h)
  if showing and showing.id == h.id and pop and pop:IsShown() then return end
  showing = h
  local f = popup()
  f.msg = ("Class quest: %s (from level %d)"):format(title(h), lv(h))
  f.text:SetText(f.msg)
  f.why:SetText(h.why or "")
  f:Show()
  ns.playAlert()
  log("CLASS_QUEST_SHOWN", { id = h.id, lv = lv(h) })
end
-- the smoke test: what the pop-up says (nil when it's not up), and its buttons
function CQ.popupText() return showing and pop and pop.msg or nil end
function CQ.click(which)
  local b = pop and pop[which]
  local fn = b and (b.scripts and b.scripts.OnClick or b:GetScript("OnClick"))
  if fn then fn(b) end
end

-- the active guide is a class guide: nothing offered until you're back on a route
local function inClassGuide()
  local E = engine()
  local g = E and E.GetGuide()
  return g and g.category == "Class"
end
function CQ.check()
  if not AuDHDDB or AuDHDDB.classQuestOff or inClassGuide() then close() return end
  local s, now = state(), time()
  for _, h in ipairs(CQ.candidates()) do
    if not (s.later[h.id] and s.later[h.id] > now) and not s.after[h.id] then
      show(h)
      return h
    end
  end
  close()
end
-- the route you were on finished (or you're on another one now): what waited for it is due. A class guide you swapped
-- to finished: back to that route
function CQ.guideMoved(finished)
  local E, Guides = engine()
  if not (E and AuDHDDB) then return end
  local s = state()
  local cur = E.GetGuide()
  for id, route in pairs(s.after) do
    if route == finished or (cur and cur.id ~= route and cur.category ~= "Class" and cur.category ~= "Lookup") then s.after[id] = nil end
  end
  if s.back and finished == s.back.from then
    local to = s.back.to
    s.back = nil
    if to and Guides.Get(to) and ns.guide then
      log("CLASS_QUEST_BACK", { from = finished, to = to })
      ns.guide.follow(to)
      local tabs = E.GetTabs()
      for i, t in ipairs(tabs or {}) do
        if t.guideId == finished then E.CloseTab(i) break end
      end
      print(("|cff66ccffAuDHD|r: %s done: back to your route"):format(title(Guides.Get(finished) or { id = finished })))
    end
  end
  CQ.check()
end
-- the window's "Route finished" opens the route picker: not for a class guide that goes back to your route
function CQ.goingBack()
  local E = engine()
  local g = E and E.GetGuide()
  local s = AuDHDDB and state()
  return s and s.back and g and g.id == s.back.from or false
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LEVEL_UP" then C_Timer.After(2, CQ.check)
  elseif event == "PLAYER_ENTERING_WORLD" then
    frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
    C_Timer.After(10, CQ.check)
    -- put-off ones come back when they're due
    C_Timer.NewTicker(30, function() if not showing then CQ.check() end end)
    local _, _, A = engine()
    if A and A.On then
      -- (after the engine's own handling of the finish)
      A.On("GUIDE_COMPLETED", function(id) C_Timer.After(0.5, function() CQ.guideMoved(id) end) end)
      A.On("GUIDE_CHANGED", function() C_Timer.After(0.5, function() CQ.guideMoved(nil) end) end)
    end
  end
end)
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
