-- Dungeons: Polestar's dungeon quests (its Dungeons module, in the engine: AuDHDEngine/Dungeons) in a window of our
-- own. The dungeons for your level, what their quests are worth in levels, each quest's state for you, and guides that
-- pick them up on a travel route ending at the entrance, hand them in after the run, or walk an attunement. The guides
-- run in the route window, which goes back to your route when one is finished, where you left off. A heads-up when a
-- level-up opens a dungeon's quests (off by default), and the switches for the leveling guides' dungeon steps (per
-- character, all off: the solo route). /audhd dungeons [name], or Alt-click the minimap button.
local _, ns = ...
local DG = {}
ns.dungeons = DG
local log = function(e, f) if ns.log then ns.log.add(e, f) end end

local function engine() local A = AuDHDEngine return A and A.Dungeons, A and A.Engine, A end
local SIDE = { Alliance = "A", Horde = "H" }
local function side() return SIDE[UnitFactionGroup("player") or ""] end
local function level() return UnitLevel("player") or 1 end
local function me() return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?") end
-- per character: told = { [dungeon] = true } (the heads-up), back = { from = a dungeon guide, to = the route to go back to }
local function state()
  AuDHDDB.dungeons = type(AuDHDDB.dungeons) == "table" and AuDHDDB.dungeons or {}
  local s = AuDHDDB.dungeons[me()]
  if type(s) ~= "table" then s = {} AuDHDDB.dungeons[me()] = s end
  s.told = s.told or {}
  return s
end
DG.state = state   -- (the smoke test)

-- the dungeons the leveling guides have steps for (`when dungeon`, by the instance's Map id), in level order, and the
-- side whose guides have them (none: both). The smoke test checks it against the guides after each sync
DG.ROUTE = {
  { 389, "Ragefire Chasm", "Horde" }, { 34, "The Stockade", "Alliance" }, { 189, "Scarlet Monastery", "Alliance" },
  { 2959, "City of Dalaran", "Alliance" }, { 209, "Zul'Farrak" }, { 109, "Sunken Temple" }, { 230, "Blackrock Depths" },
  { 229, "Blackrock Spire" }, { 429, "Dire Maul" }, { 289, "Scholomance" }, { 329, "Stratholme" },
}
function DG.chosen(map)
  local _, E = engine()
  return E and E.DungeonChosen and E.DungeonChosen(map) or false
end
function DG.choose(map, on)
  local _, E = engine()
  if E and E.ChooseDungeon then E.ChooseDungeon(map, on) log("DUNGEON_ROUTE", { map = map, on = on }) end
end

-- the engine's Dungeons with its data loaded, else nil and why, in words
local WHY = {
  off = "dungeons are off in the engine",
  missing = "the AuDHD_Codex folder is missing: reinstall AuDHD",
  disabled = "AuDHD_Codex is turned off in the AddOns list",
  combat = "it can't load in combat: try again after the fight",
  nodata = "no dungeon data in AuDHD_Codex",
}
local function ready()
  local D = engine()
  if not D then return nil, WHY.missing end
  local ok, why = D.Load()
  if not ok then return nil, WHY[why] or tostring(why) end
  return D
end
DG.ready = ready

-- ------------------------------------------------------------------ facts
-- the dungeons: for your level (raids only in all), in level order
function DG.list(all)
  local D = ready()
  if not D then return {} end
  local lv, out = level(), {}
  for _, d in ipairs(D.List()) do
    local fits = d.kind == "dungeon" and d.minLevel and lv >= d.minLevel - 3 and lv <= (d.maxLevel or 60)
    if all or fits then out[#out + 1] = d end
  end
  return out
end
-- a quest's state for you: text, colour, and its sort group (1 to do, 2 in the log, 3 later, 4 done)
local function questState(q)
  local C = AuDHDEngine and AuDHDEngine.Compat
  local _, class = UnitClass("player")
  if type(q.classes) == "table" and #q.classes > 0 then
    local mine = false
    for _, c in ipairs(q.classes) do if c == class then mine = true end end
    if not mine then return nil end
  end
  if C and C.IsQuestCompleted and C.IsQuestCompleted(q.id) then return "done", "808080", 4 end
  if C and C.IsOnQuest and C.IsOnQuest(q.id) then
    if C.IsQuestReadyForTurnIn and C.IsQuestReadyForTurnIn(q.id) then
      return "ready to hand in" .. (q.finish and q.finish.name and (" to " .. q.finish.name) or ""), "40ff40", 2
    end
    return "in your log", "ffd200", 2
  end
  if q.minLevel and level() < q.minLevel then return "from level " .. q.minLevel, "ff6060", 3 end
  if q.startItem then return "starts from an item: " .. tostring(q.startItem.name or "?"), "c0c0c0", 1 end
  if q.inside or (q.start and q.start.inside) then return "picked up inside the dungeon", "c0c0c0", 1 end
  local who = q.start and q.start.name
  return "pick up" .. (who and (" from " .. who) or ""), "ffffff", 1
end
DG.questState = questState
-- the page's quests for you, with their state: { { q, text, colour, group } }, to do first
function DG.quests(key)
  local D = ready()
  if not D then return {} end
  local out = {}
  for _, q in ipairs(D.Quests(key, side()) or {}) do
    local text, colour, group = questState(q)
    if text then out[#out + 1] = { q = q, text = text, colour = colour, group = group } end
  end
  table.sort(out, function(a, b)
    if a.group ~= b.group then return a.group < b.group end
    if (a.q.level or 0) ~= (b.q.level or 0) then return (a.q.level or 0) < (b.q.level or 0) end
    return tostring(a.q.title) < tostring(b.q.title)
  end)
  return out
end
-- what the quests still to do are worth: "+1.4 levels (33,650 XP)" or nil
function DG.worth(key)
  local D = ready()
  local ok, s = pcall(function() return D and D.QuestXP(key) end)
  if not (ok and type(s) == "table") or s.maxed or not s.xp or s.xp <= 0 then return nil end
  local xp = BreakUpLargeNumbers and BreakUpLargeNumbers(s.xp) or tostring(s.xp)
  if s.levels and s.levels > 0 then return ("+%.1f levels (%s XP)"):format(s.levels, xp) end
  return xp .. " XP"
end
-- how many you can pick up now
function DG.toTake(key)
  local D = ready()
  local ok, plan = pcall(function() return D and D.PickupPlan(key) end)
  return ok and plan and #plan.take or 0, ok and plan or nil
end
-- any of its quests in your log
function DG.inLog(key)
  local C = AuDHDEngine and AuDHDEngine.Compat
  for _, e in ipairs(DG.quests(key)) do
    if C and C.IsOnQuest and C.IsOnQuest(e.q.id) then return true end
  end
  return false
end

-- ------------------------------------------------------------------ guides, and back to your route
-- a dungeon guide opened (pick up, hand in, attunement): the route window follows it, and goes back to the route you
-- were on once it's finished
local function isOurs(id) return type(id) == "string" and id:find("^lookup/") ~= nil end
-- the route to go back to: the guide you're on, read before the engine opens the new one (its tab goes live at once)
local function routeNow()
  local _, E = engine()
  local cur = E and E.GetGuide and E.GetGuide()
  local to = cur and cur.id
  if isOurs(to) then to = state().back and state().back.to end
  return to
end
local function follow(gid, to)
  state().back = { from = gid, to = to }
  if ns.guide then ns.guide.follow(gid) end
end
local function say(text) print("|cff66ccffAuDHD|r: " .. text) end
local NOTHING = { nothing = true }
function DG.pickUp(key)
  local D, why = ready()
  if not D then say("can't pick up the dungeon's quests: " .. why) return end
  local to = routeNow()
  local gid, reason = D.PickUp(key)
  log("DUNGEON_PICKUP", { key = key, ok = gid ~= nil, why = reason })
  if gid then follow(gid, to) return gid end
  say(NOTHING[reason] and "nothing to pick up for this dungeon right now" or ("no pick-up guide: " .. tostring(reason)))
end
function DG.handIn(key)
  local D, why = ready()
  if not D then say("can't hand in: " .. why) return end
  local to = routeNow()
  local gid, reason = D.HandIn(key)
  log("DUNGEON_HANDIN", { key = key, ok = gid ~= nil, why = reason })
  if gid then follow(gid, to) return gid end
  say(NOTHING[reason] and D.HandinText(D.HandinPlan(key)) or ("no hand-in guide: " .. tostring(reason)))
end
function DG.attune(key, id)
  local D, why = ready()
  if not D then say("can't guide the attunement: " .. why) return end
  local to = routeNow()
  local gid, reason = D.Attune(key, id)
  log("DUNGEON_ATTUNE", { key = key, id = id, ok = gid ~= nil, why = reason })
  if gid then follow(gid, to) return gid end
  say(reason == "done" and "you have that one already" or ("no attunement guide: " .. tostring(reason)))
end
function DG.entrance(key)
  local D, why = ready()
  if not D then say("no entrance: " .. why) return end
  local m, x, y = D.Entrance(key)
  local d = D.Get(key)
  if not (m and x and ns.way) then say("its entrance isn't known") return end
  ns.way.set(m, x, y, ((d and d.name) or key) .. " entrance")
  log("DUNGEON_ENTRANCE", { key = key })
  return true
end
-- the guide you're on is a dungeon guide that goes back to a route when it's finished
function DG.goingBack()
  local _, E = engine()
  local g = E and E.GetGuide and E.GetGuide()
  local s = AuDHDDB and state()
  return s and s.back and g and g.id == s.back.from or false
end
function DG.guideMoved(finished)
  local _, E, A = engine()
  if not (E and AuDHDDB) then return end
  local s = state()
  if not (s.back and finished and finished == s.back.from) then return end
  local to = s.back.to
  s.back = nil
  if to and A.Guides.Get(to) and ns.guide then
    log("DUNGEON_BACK", { from = finished, to = to })
    ns.guide.follow(to)
    for i, t in ipairs(E.GetTabs() or {}) do
      if t.guideId == finished then E.CloseTab(i) break end
    end
    local kind, key = finished:match("^lookup/(%a+)/([^:]+)")
    local D = engine()
    local d = D and key and D.Get(key)
    if kind == "pickup" and d then
      say(("%s: quests picked up. After the run, Hand in on its page (/audhd dungeons). Back to your route"):format(d.name))
    else
      say("dungeon guide done: back to your route")
    end
  end
end

-- ------------------------------------------------------------------ the window
local win, rows, qrows = nil, {}, {}
local view = { all = false, key = nil }
local function button(parent, label, w, onClick)
  local b = ns.newFrame("Dungeons", "Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 22)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end
local function colourOf(lv)
  if GetQuestDifficultyColor and lv then
    local c = GetQuestDifficultyColor(lv)
    if c then return ("%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) end
  end
  return "ffd200"
end
local fillPage
local function fillList()
  local list = DG.list(view.all)
  local y = 0
  for i, d in ipairs(list) do
    local r = rows[i]
    if not r then
      r = ns.newFrame("Dungeons", "Button", nil, win.list)
      r:SetSize(190, 32)
      r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      r.sel = r:CreateTexture(nil, "BACKGROUND")
      r.sel:SetAllPoints()
      r.sel:SetColorTexture(1, 0.82, 0, 0.15)
      r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      r.name:SetPoint("TOPLEFT", 4, -3)
      r.name:SetWidth(182)
      r.name:SetJustifyH("LEFT")
      r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
      r.sub:SetWidth(182)
      r.sub:SetJustifyH("LEFT")
      r:SetScript("OnClick", function(self) view.key = self.key fillList() fillPage() end)
      rows[i] = r
    end
    r.key = d.key
    r:SetPoint("TOPLEFT", 0, y)
    r.name:SetText(d.name .. (d.kind == "raid" and " |cffaaaaaa(raid)|r" or ""))
    local n = (d.quests and d.quests[side() or "A"]) or 0
    r.sub:SetText(("|cff%s%d-%d|r  %s  |cffaaaaaa%d quest%s|r"):format(colourOf(d.minLevel), d.minLevel or 0, d.maxLevel or 0,
      d.zoneName or "", n, n == 1 and "" or "s"))
    if r.sel.SetShown then r.sel:SetShown(d.key == view.key) elseif d.key == view.key then r.sel:Show() else r.sel:Hide() end
    r:Show()
    y = y - 34
  end
  for i = #list + 1, #rows do rows[i]:Hide() end
  win.list:SetHeight(math.max(10, -y))
  win.empty:SetText(#list == 0 and (select(2, ready()) or "No dungeons for your level: tick All dungeons") or "")
  if not view.key and list[1] then view.key = list[1].key fillList() end
end
fillPage = function()
  local p = win.page
  local D = ready()
  local d = D and view.key and D.Get(view.key)
  if not d then
    p.title:SetText("")
    p.facts:SetText("")
    p.content:SetHeight(10)
    for _, r in ipairs(qrows) do r:Hide() end
    for _, b in ipairs({ p.pick, p.hand, p.go, p.att }) do b:Hide() end
    return
  end
  p.title:SetText(d.name)
  local worth = DG.worth(d.key)
  p.facts:SetText(("Level %d-%d, %s%s%s"):format(d.minLevel or 0, d.maxLevel or 0, d.zoneName or "?",
    d.players and (", " .. d.players .. " players") or "", worth and ("\n|cff40ff40Its quests still to do: " .. worth .. "|r") or ""))
  local list = DG.quests(d.key)
  local y = 0
  for i, e in ipairs(list) do
    local r = qrows[i]
    if not r then
      r = ns.newFrame("Dungeons", "Button", nil, p.content)
      r:SetSize(340, 30)
      r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      r.name:SetPoint("TOPLEFT", 2, -2)
      r.name:SetWidth(336)
      r.name:SetJustifyH("LEFT")
      r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 8, -1)
      r.sub:SetWidth(328)
      r.sub:SetJustifyH("LEFT")
      r:SetScript("OnEnter", function(self)
        local q = self.q
        if not q then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(q.title or ("Quest " .. q.id), 1, 0.82, 0)
        GameTooltip:AddLine(("Level %s, from level %s"):format(tostring(q.level or "?"), tostring(q.minLevel or "?")), 1, 1, 1)
        local Dx = engine()
        local obj = Dx and Dx.ObjectiveText and Dx.ObjectiveText(q)
        if obj and obj ~= "" then GameTooltip:AddLine(obj, 0.8, 0.8, 0.8, true) end
        if q.start and q.start.name then GameTooltip:AddLine("Starts: " .. q.start.name .. (q.start.inside and " (inside)" or ""), 1, 1, 1) end
        if q.finish and q.finish.name then GameTooltip:AddLine("Ends: " .. q.finish.name .. (q.finish.inside and " (inside)" or ""), 1, 1, 1) end
        if type(q.chain) == "table" and #q.chain > 0 then
          GameTooltip:AddLine(("%d quest%s before it"):format(#q.chain, #q.chain == 1 and "" or "s"), 0.7, 0.7, 0.7)
        end
        if q.rewards and q.rewards.xp then GameTooltip:AddLine(("%s XP"):format(q.rewards.xp), 0.6, 0.8, 1) end
        GameTooltip:Show()
      end)
      r:SetScript("OnLeave", function() GameTooltip:Hide() end)
      qrows[i] = r
    end
    r.q = e.q
    r:SetPoint("TOPLEFT", 0, y)
    r.name:SetText(("|cff%s[%s] %s|r"):format(e.group == 4 and "808080" or colourOf(e.q.level), tostring(e.q.level or "?"), e.q.title or ("Quest " .. e.q.id)))
    r.sub:SetText(("|cff%s%s|r"):format(e.colour, e.text))
    r:Show()
    y = y - 32
  end
  for i = #list + 1, #qrows do qrows[i]:Hide() end
  p.content:SetHeight(math.max(10, -y))
  p.none:SetText(#list == 0 and "No quests for your side here" or "")
  -- the buttons: what you can do now
  local take = DG.toTake(d.key)
  p.pick:SetText(take > 0 and ("Pick up quests (%d)"):format(take) or "Nothing to pick up")
  p.pick:SetEnabled(take > 0)
  p.hand:SetEnabled(DG.inLog(d.key))
  p.go:SetEnabled(D.Entrance(d.key) ~= nil)
  local att = D.Attunements(d.key, side()) or {}
  p.att.list = att
  if #att > 0 then p.att:Show() else p.att:Hide() end
  for _, b in ipairs({ p.pick, p.hand, p.go }) do b:Show() end
end
function DG.refresh()
  if win and win:IsShown() then fillList() fillPage() end
end
local function create()
  win = ns.newFrame("Dungeons", "Frame", "AuDHDDungeons", UIParent, "BasicFrameTemplateWithInset")
  win:SetSize(600, 470)
  win:SetPoint("CENTER")
  win:SetFrameStrata("DIALOG")
  win:SetMovable(true)
  win:EnableMouse(true)
  win:SetClampedToScreen(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)
  local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", 0, -6)
  title:SetText("Dungeon quests")
  -- left: the dungeons
  win.all = ns.newFrame("Dungeons", "CheckButton", nil, win, "UICheckButtonTemplate")
  win.all:SetSize(24, 24)
  win.all:SetPoint("TOPLEFT", 10, -28)
  win.all.label = win.all:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  win.all.label:SetPoint("LEFT", win.all, "RIGHT", 2, 0)
  win.all.label:SetText("All dungeons and raids")
  win.all:SetScript("OnClick", function(self) view.all = self:GetChecked() and true or false fillList() end)
  local scroll = ns.newFrame("Dungeons", "ScrollFrame", "AuDHDDungeonsList", win, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 10, -56)
  scroll:SetSize(192, 400)
  win.list = ns.newFrame("Dungeons", "Frame", nil, scroll)
  win.list:SetSize(190, 10)
  scroll:SetScrollChild(win.list)
  win.empty = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  win.empty:SetPoint("TOPLEFT", 14, -62)
  win.empty:SetWidth(180)
  win.empty:SetJustifyH("LEFT")
  -- right: the dungeon's page
  local p = ns.newFrame("Dungeons", "Frame", nil, win)
  p:SetPoint("TOPLEFT", 232, -28)
  p:SetPoint("BOTTOMRIGHT", -10, 10)
  win.page = p
  p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  p.title:SetPoint("TOPLEFT", 0, -2)
  p.facts = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  p.facts:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -4)
  p.facts:SetWidth(350)
  p.facts:SetJustifyH("LEFT")
  p.pick = button(p, "Pick up quests", 172, function() if view.key then DG.pickUp(view.key) DG.refresh() end end)
  p.pick:SetPoint("TOPLEFT", 0, -52)
  p.hand = button(p, "Hand in", 172, function() if view.key then DG.handIn(view.key) end end)
  p.hand:SetPoint("LEFT", p.pick, "RIGHT", 4, 0)
  p.go = button(p, "Go to entrance", 172, function() if view.key then DG.entrance(view.key) end end)
  p.go:SetPoint("TOPLEFT", p.pick, "BOTTOMLEFT", 0, -4)
  p.att = button(p, "Attunement", 172, function(self)
    local list = self.list or {}
    if #list == 1 then DG.attune(view.key, list[1].id) return end
    local items = {}
    for _, a in ipairs(list) do items[#items + 1] = { a.name or tostring(a.id), function() DG.attune(view.key, a.id) end } end
    if ns.auction and ns.auction.menu then ns.auction.menu("Which one?", items) end
  end)
  p.att:SetPoint("LEFT", p.go, "RIGHT", 4, 0)
  local qs = ns.newFrame("Dungeons", "ScrollFrame", "AuDHDDungeonsQuests", p, "UIPanelScrollFrameTemplate")
  qs:SetPoint("TOPLEFT", 0, -112)
  qs:SetPoint("BOTTOMRIGHT", -22, 0)
  p.content = ns.newFrame("Dungeons", "Frame", nil, qs)
  p.content:SetSize(340, 10)
  qs:SetScrollChild(p.content)
  p.none = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  p.none:SetPoint("TOPLEFT", 2, -116)
  tinsert(UISpecialFrames, "AuDHDDungeons")
end
function DG.show(key)
  local D, why = ready()
  if not D then say("Dungeons: " .. why) return end
  if not win then create() end
  if key then view.key = key end
  win:Show()
  fillList()
  fillPage()
end
function DG.toggle()
  if win and win:IsShown() then win:Hide() else DG.show() end
end
DG.frame = function() return win end   -- (the smoke test)
-- /audhd dungeons [name]
function DG.command(rest)
  local D = engine()
  local key = rest and rest ~= "" and D and D.Find and select(2, pcall(D.Find, rest)) or nil
  if rest and rest ~= "" and type(key) ~= "string" then return "no dungeon called " .. rest end
  DG.show(type(key) == "string" and key or nil)
  return nil
end

-- ------------------------------------------------------------------ the heads-up
-- after a level-up (only when it's on: Settings, Reminders): a dungeon, not a raid, now in your level range, with
-- quests to pick up, not told before on this character. Polestar's rule (UI/DungeonToast.lua): with quests still to
-- open at later levels, only once 3 are open now. Of several, the one whose range began last
local MIN_OPEN = 3
function DG.candidates(lv)
  if not (AuDHDDB and AuDHDDB.dungeonHeadsUp) then return {} end
  local D = ready()
  if not D then return {} end
  lv = lv or level()
  local told, out = state().told, {}
  for _, d in ipairs(D.List()) do
    if d.kind == "dungeon" and not told[d.key] and d.minLevel and lv >= d.minLevel and lv <= (d.maxLevel or 60)
      and ((d.quests and d.quests[side() or ""]) or 0) > 0 then
      local take, plan = DG.toTake(d.key)
      if take > 0 and (plan.later == 0 or take >= MIN_OPEN) then out[#out + 1] = { d = d, take = take } end
    end
  end
  table.sort(out, function(a, b) return (a.d.minLevel or 0) > (b.d.minLevel or 0) end)
  return out
end
local pop, showing
local function closePop() showing = nil if pop then pop:Hide() end end
local function popup()
  if pop then return pop end
  local f = ns.newFrame("Dungeons", "Frame", "AuDHDDungeonHeadsUp", UIParent, "BackdropTemplate")
  f:SetSize(330, 90)
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
  local function b(label, x, w, onClick)
    local bt = ns.newFrame("Dungeons", "Button", nil, f, "UIPanelButtonTemplate")
    bt:SetSize(w, 20)
    bt:SetPoint("BOTTOM", f, "BOTTOM", x, 8)
    bt:SetText(label)
    bt:SetScript("OnClick", onClick)
    return bt
  end
  f.pick = b("Pick up quests", -104, 100, function() local k = showing closePop() if k then DG.pickUp(k) end end)
  f.open = b("Open Dungeons", 0, 100, function() local k = showing closePop() DG.show(k) end)
  f.later = b("Later", 104, 100, function() closePop() end)
  f:Hide()
  pop = f
  return f
end
function DG.headsUp(lv)
  if InCombatLockdown and InCombatLockdown() then return "combat" end
  local c = DG.candidates(lv)[1]
  if not c then return nil end
  local f = popup()
  showing = c.d.key
  state().told[c.d.key] = true   -- told once it's on screen
  f.msg = ("%s is open to you: %d quest%s to pick up%s"):format(c.d.name, c.take, c.take == 1 and "" or "s",
    DG.worth(c.d.key) and (", worth " .. DG.worth(c.d.key)) or "")
  f.text:SetText(f.msg)
  f:SetHeight(math.max(90, math.ceil(f.text:GetStringHeight() or 14) + 48))
  f:Show()
  ns.playAlert()
  log("DUNGEON_HEADSUP", { key = c.d.key, take = c.take })
  return c.d.key
end
function DG.popupText() return showing and pop and pop.msg or nil end
function DG.click(which)
  local bt = pop and pop[which]
  local fn = bt and (bt.scripts and bt.scripts.OnClick or bt:GetScript("OnClick"))
  if fn then fn(bt) end
end

local frame = CreateFrame("Frame")
local waitCombat
frame:SetScript("OnEvent", function(_, event, arg)
  if event == "PLAYER_LEVEL_UP" then
    -- after the class quest's pop-up
    if AuDHDDB and AuDHDDB.dungeonHeadsUp then
      C_Timer.After(3, function() if DG.headsUp(arg) == "combat" then waitCombat = arg frame:RegisterEvent("PLAYER_REGEN_ENABLED") end end)
    end
  elseif event == "PLAYER_REGEN_ENABLED" then
    frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local lv = waitCombat
    waitCombat = nil
    C_Timer.After(1, function() DG.headsUp(lv) end)
  elseif event == "QUEST_TURNED_IN" or event == "QUEST_ACCEPTED" then
    if win and win:IsShown() then C_Timer.After(0.5, DG.refresh) end
  elseif event == "PLAYER_ENTERING_WORLD" then
    frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
    local _, _, A = engine()
    if A and A.On then
      -- (after the engine's own handling of the finish)
      A.On("GUIDE_COMPLETED", function(id) C_Timer.After(0.5, function() DG.guideMoved(id) end) end)
    end
  end
end)
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("QUEST_TURNED_IN")
frame:RegisterEvent("QUEST_ACCEPTED")
