-- The game's quest log (the panel beside the world map): a + on each quest the route doesn't do, to fit it in, and a -
-- on each you added yourself (Extra.lua), to take it off again; nothing on the route's own. Each sits left of the row's
-- tracking checkbox, or of a tag such as "(Elite)" beside it. Beside the log, a list of every quest you added, picked
-- up or not, each with a -. Settings "questLogMarksOff" and "addedListOff".
-- The rows: the log's QuestLogQuests_Update, then QuestScrollFrame.titleFramePool's active buttons and their questID.
local _, ns = ...
local Q = {}
ns.questMarks = Q

local isSecret = issecretvalue or function() return false end
local function say(msg) print("|cff66ccffAuDHD|r: " .. msg) end
function Q.on() return not AuDHDDB.questLogMarksOff end
function Q.listOn() return not AuDHDDB.addedListOff end

-- the quests the guide you're on takes: any step's goal, worked out again when the guide changes
local guideOf, guideSet
local function onRoute(q)
  local E = AuDHDEngine and AuDHDEngine.Engine
  local g = E and E.GetGuide and E.GetGuide()
  if g ~= guideOf then
    guideOf, guideSet = g, {}
    for _, st in ipairs(g and g.steps or {}) do
      for _, goal in ipairs(st.goals or {}) do
        if type(goal.quest) == "number" then guideSet[goal.quest] = true end
      end
    end
  end
  return guideSet[q] or false
end
local function added() return ns.extra and ns.extra.list and ns.extra.list() or {} end
-- "route" the guide takes it, "added" you added it, "off" neither
function Q.kind(q)
  if onRoute(q) then return "route" end
  if added()[q] then return "added" end
  return "off"
end
local function title(q)
  local db = AuDHDEngine and AuDHDEngine.QuestDB
  local rec = db and db.GetQuest and db.GetQuest(q)
  return (rec and rec.title) or (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(q)) or ("quest " .. q)
end

-- + fits a quest in, - takes an added one off (it stays in your log)
local function tipButton(b)
  if not GameTooltip then return end
  GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
  GameTooltip:SetText(b.kind == "added" and "Take off your route" or "Add to your route", 1, 1, 1)
  if b.kind == "added" then GameTooltip:AddLine("It stays in your quest log", 0.7, 0.7, 0.7) end
  GameTooltip:Show()
end
function Q.click(q, kind)
  if not (ns.extra and q) then return end
  if kind == "added" then
    ns.extra.remove(q)
    say(title(q) .. " taken off your route")
  else
    say(ns.extra.add(q))
  end
  Q.refresh()
end
local function plusMinus(parent, size)
  local b = ns.newFrame("QuestLog", "Button")
  b:SetParent(parent)
  b:SetSize(size, size)
  b:SetScript("OnClick", function(self) Q.click(self.q, self.kind) end)
  b:SetScript("OnEnter", tipButton)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  return b
end
local function setSign(b, kind)
  local sign = kind == "added" and "Minus" or "Plus"
  b:SetNormalTexture("Interface\\Buttons\\UI-" .. sign .. "Button-Up")
  b:SetPushedTexture("Interface\\Buttons\\UI-" .. sign .. "Button-Down")
  b:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
end

-- ------------------------------------------------------------------ the log's rows
local deco = setmetatable({}, { __mode = "k" })   -- a row -> its + or - button
-- what the button goes left of: a tag's text on the row ("(Elite)", "(Dungeon)"), else its tracking checkbox (by the
-- names the game's quest log gives it), else nil (the row's right edge)
local function anchorOf(row)
  for _, r in ipairs({ row:GetRegions() }) do
    if r ~= row.Text and r.GetObjectType and r:GetObjectType() == "FontString" and r:IsShown() then
      local t = r:GetText()
      if type(t) == "string" and not isSecret(t) and t ~= "" then return r end
    end
  end
  return row.Checkbox or row.Check
end
local function decorate(row)
  local q = row.questID
  local b = deco[row]
  local kind = Q.on() and type(q) == "number" and not isSecret(q) and Q.kind(q)
  if not kind or kind == "route" then
    if b then b:Hide() end
    return
  end
  if not b then
    b = plusMinus(row, 14)
    deco[row] = b
  end
  b:SetFrameLevel((row:GetFrameLevel() or 0) + 3)
  b:ClearAllPoints()
  local at = anchorOf(row)
  if at then b:SetPoint("RIGHT", at, "LEFT", -3, 0) else b:SetPoint("RIGHT", row, "RIGHT", -30, 0) end
  b.q, b.kind = q, kind
  setSign(b, kind)
  b:Show()
end
function Q.markLog()
  local pool = QuestScrollFrame and QuestScrollFrame.titleFramePool
  if not pool then return end
  for row in pool:EnumerateActive() do decorate(row) end
end
Q.decoration = function(row) return deco[row] end   -- (the smoke test)

-- ------------------------------------------------------------------ the list of added quests, beside the log
local panel, rows = nil, {}
local MAX_ROWS = 20
local function buildPanel()
  panel = ns.newFrame("QuestLog", "Frame", "AuDHDAddedQuests", nil, "BackdropTemplate")
  panel:SetParent(WorldMapFrame)
  panel:SetPoint("TOPLEFT", WorldMapFrame, "TOPRIGHT", 0, 0)
  panel:SetWidth(260)
  panel:SetClampedToScreen(true)
  panel:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                      tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
  panel:EnableMouse(true)
  panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.title:SetPoint("TOPLEFT", 18, -18)
  panel.title:SetText("Added to your route")
  panel.more = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
end
local function panelRow(i)
  local r = rows[i]
  if r then return r end
  r = {}
  r.btn = plusMinus(panel, 14)
  r.btn:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -40 - (i - 1) * 30)
  r.name = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.name:SetPoint("TOPLEFT", r.btn, "TOPRIGHT", 6, 1)
  r.name:SetPoint("RIGHT", panel, "RIGHT", -18, 0)
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r.state = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  r.state:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
  rows[i] = r
  return r
end
-- the quests you added: { { q, title, inLog } }, by title
function Q.addedList()
  local out = {}
  for q in pairs(added()) do
    if not onRoute(q) and not (C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(q)) then
      out[#out + 1] = { q = q, title = title(q), inLog = C_QuestLog.GetLogIndexForQuestID(q) ~= nil }
    end
  end
  table.sort(out, function(a, b) return a.title < b.title end)
  return out
end
function Q.drawPanel()
  local list = Q.listOn() and ns.extra and QuestMapFrame and QuestMapFrame:IsVisible() and WorldMapFrame and Q.addedList()
  if not (list and #list > 0) then
    if panel then panel:Hide() end
    return
  end
  if not panel then buildPanel() end
  local n = math.min(#list, MAX_ROWS)
  for i, r in ipairs(rows) do
    local e = i <= n and list[i]
    r.btn:SetShown(e and true or false)
    r.name:SetShown(e and true or false)
    r.state:SetShown(e and true or false)
  end
  for i = 1, n do
    local e, r = list[i], panelRow(i)
    r.btn.q, r.btn.kind = e.q, "added"
    setSign(r.btn, "added")
    r.btn:Show()
    r.name:SetText(e.title)
    r.name:Show()
    r.state:SetText(e.inLog and "in your quest log" or "not picked up yet")
    r.state:Show()
  end
  local h = 40 + n * 30
  if #list > n then
    panel.more:ClearAllPoints()
    panel.more:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -h)
    panel.more:SetText(("... and %d more (/audhd extra)"):format(#list - n))
    panel.more:Show()
    h = h + 16
  else
    panel.more:Hide()
  end
  panel:SetHeight(h + 14)
  panel:Show()
end
Q.panel = function() return panel end   -- (the smoke test)

function Q.refresh()
  local ok, err = pcall(Q.markLog)
  if not ok and ns.log then ns.log.add("QUEST_MARKS_ERROR", { err = tostring(err):sub(1, 300) }) end
  ok, err = pcall(Q.drawPanel)
  if not ok and ns.log then ns.log.add("QUEST_MARKS_ERROR", { err = tostring(err):sub(1, 300) }) end
end

-- hooked once the log's frames are there (they can come after login)
local hookedLog, hookedFrame
local function hook()
  if not hookedLog and type(QuestLogQuests_Update) == "function" then
    hookedLog = true
    hooksecurefunc("QuestLogQuests_Update", Q.refresh)
  end
  if not hookedFrame and QuestMapFrame and QuestMapFrame.HookScript then
    hookedFrame = true
    QuestMapFrame:HookScript("OnShow", Q.refresh)
    QuestMapFrame:HookScript("OnHide", Q.refresh)
  end
  return hookedLog and hookedFrame
end
function Q.enable()
  if hook() then return end
  local f = ns.newFrame("QuestLog", "Frame")
  f:RegisterEvent("ADDON_LOADED")
  f:SetScript("OnEvent", function(self) if hook() then self:UnregisterEvent("ADDON_LOADED") end end)
end
