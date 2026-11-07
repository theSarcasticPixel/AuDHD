-- log a quest and hand the log over: when we don't know where a mob or objective is, ask the player to log that quest,
-- record what it needs into ns.log (entries with a questId field), then show it as text to copy into a github issue.
-- addons can't open links, use the clipboard or make web requests, so everything to take away sits in a copy box.
-- the copied text has no character name, realm, account name or path: race, class, level and build only.
-- no combat log (blocked in forever): kills come from the xp messages, as in Log.lua.
--
-- the xp line patterns, the removed-then-abandoned check and the text cleaning are adapted from polestar
-- (https://github.com/fitzforge/polestar, GPLv3): addon/Polestar_Recorder/Finds.lua, Quests.lua, addon/Polestar/UI/Report.lua
--
-- /audhd share log <questID> [why] | stop [questID] | show [questID] | list
local _, ns = ...
local S = {}
ns.share = S
local L = ns.log

S.ISSUE_URL = "https://github.com/theSarcasticPixel/AuDHD/issues/new"
S.SAVED_FILE = "WTF/Account/<account>/SavedVariables/AuDHD.lua"
S.PART_MAX = 8000       -- bytes in the copy box at a time; longer logs go in numbered parts
local FORMAT = 1        -- bump when the text layout changes
local LINE_MAX = 240    -- bytes per line of text
local RUN_MAX = 600     -- kills and loot per run, so one farming session can't fill the log; ticks are always kept
local CONTEXT_TTL = 600 -- seconds a quest window's npc still counts for the quest
local REMOVE_WAIT = 1   -- QUEST_REMOVED comes before or after QUEST_TURNED_IN: wait, then call it abandoned

local isSecret = issecretvalue or function() return false end
local function clean(v)
  if v == nil or isSecret(v) then return nil end
  return v
end

-- ------------------------------------------------------------------ saved state
-- what this character is logging, kept across reloads: questID -> { run = start time, accepted, n = kills and loot }
local function charKey()
  return tostring(clean(UnitName("player"))) .. "-" .. tostring(clean(GetRealmName and GetRealmName()))
end
local function runs()
  AuDHDLog = AuDHDLog or { v = 1, sessions = {} }
  AuDHDLog.shareRuns = AuDHDLog.shareRuns or {}
  local key = charKey()
  AuDHDLog.shareRuns[key] = AuDHDLog.shareRuns[key] or {}
  return AuDHDLog.shareRuns[key]
end

-- objectives as last seen, not saved: a reload takes a new baseline
local mem = {}

local function add(q, run, event, fields)
  local e = fields or {}
  e.questId, e.run = q, run.run
  local got = L.add(event, e)
  if not got then
    -- the logger has no session yet: this needs one
    L.start()
    got = L.add(event, e)
  end
  return got
end

local function inLog(q)
  if C_QuestLog.IsOnQuest then return clean(C_QuestLog.IsOnQuest(q)) and true or false end
  return clean(C_QuestLog.GetLogIndexForQuestID(q)) ~= nil
end
local function isReady(q) return clean(C_QuestLog.IsComplete(q)) and true or false end
local function titleOf(q) return clean(C_QuestLog.GetTitleForQuestID(q)) end

local function baseline(q, fresh)
  local m = { cur = {}, done = {}, fresh = fresh, ready = isReady(q) }
  for j, o in ipairs(L.questObjectives(q) or {}) do
    m.cur[j], m.done[j] = o.have or 0, o.done and true or false
    m.fresh = false
  end
  mem[q] = m
end

-- ------------------------------------------------------------------ who we met
-- mobs seen on target, mouseover and nameplates, because the xp line only has the name. identity is often secret in
-- combat, so it's the last clean look that counts
local seenName, seenId, seenCount = {}, {}, 0

local function unitInfo(unit)
  if not clean(UnitExists(unit)) then return nil end
  if UnitIsPlayer and clean(UnitIsPlayer(unit)) then return nil end
  local id, kind = L.npcIdOf(UnitGUID(unit))
  if kind == "Player" then return nil end
  return { id = id, kind = kind, name = clean(UnitName(unit)), level = clean(UnitLevel(unit)) }
end

local function remember(unit)
  local u = unitInfo(unit)
  if not u or not u.name then return end
  if seenCount > 300 then seenName, seenId, seenCount = {}, {}, 0 end
  if not seenName[u.name] then seenCount = seenCount + 1 end
  seenName[u.name] = u
  if u.id then seenId[u.id] = u end
end

-- ------------------------------------------------------------------ the xp line
local function formatPattern(fmt)
  if type(fmt) ~= "string" or fmt == "" then return nil end
  local out, args, n, i = {}, {}, 0, 1
  while i <= #fmt do
    local s, e, pos, conv = fmt:find("^%%(%d*)%$?([sd])", i)
    if s then
      n = n + 1
      args[#args + 1] = pos ~= "" and tonumber(pos) or n
      out[#out + 1] = conv == "s" and "(.-)" or "([%-%+]?%d+)"
      i = e + 1
    elseif fmt:sub(i, i + 1) == "%%" then
      out[#out + 1] = "%%"
      i = i + 2
    else
      local c = fmt:sub(i, i)
      out[#out + 1] = c:find("[%^%$%(%)%%%.%[%]%*%+%-%?]") and "%" .. c or c
      i = i + 1
    end
  end
  return "^" .. table.concat(out) .. "$", args
end

-- most specific first: the plain line would also match the start of the others
local XP_FORMATS = { "COMBATLOG_XPGAIN_EXHAUSTION1_GROUP", "COMBATLOG_XPGAIN_EXHAUSTION1_RAID",
  "COMBATLOG_XPGAIN_EXHAUSTION2_GROUP", "COMBATLOG_XPGAIN_EXHAUSTION2_RAID",
  "COMBATLOG_XPGAIN_EXHAUSTION1", "COMBATLOG_XPGAIN_EXHAUSTION2",
  "COMBATLOG_XPGAIN_FIRSTPERSON_GROUP", "COMBATLOG_XPGAIN_FIRSTPERSON_RAID", "COMBATLOG_XPGAIN_FIRSTPERSON" }
local xpPatterns
local function parseKill(text)
  if type(text) ~= "string" then return nil end
  if not xpPatterns then
    xpPatterns = {}
    for _, name in ipairs(XP_FORMATS) do
      local p, args = formatPattern(_G[name])
      if p then xpPatterns[#xpPatterns + 1] = { p = p, args = args } end
    end
  end
  for _, x in ipairs(xpPatterns) do
    local caps = { text:match(x.p) }
    if caps[1] then
      local v = {}
      for i, a in ipairs(x.args) do v[a] = caps[i] end
      if v[1] and tonumber(v[2]) then return v[1], tonumber(v[2]) end
    end
  end
  return nil
end

-- ------------------------------------------------------------------ events while logging
local ev = ns.newFrame("Share", "Frame")
local handlers = {}

local function anyRuns() return next(runs()) ~= nil end
local function syncEvents()
  local on = anyRuns()
  for event in pairs(handlers) do
    if on then pcall(ev.RegisterEvent, ev, event) else pcall(ev.UnregisterEvent, ev, event) end
  end
end

local function finish(q, why)
  local all = runs()
  local run = all[q]
  if not run then return end
  add(q, run, "SHARE_END", { why = why })
  all[q], mem[q] = nil, nil
  syncEvents()
  print(("AuDHD: finished logging %s (%s). To share it: /audhd share show %d"):format(titleOf(q) or "that quest", why, q))
end

-- the npc or object behind the open quest window
local questNpc
local function noteNpc()
  local id = GetQuestID and clean(GetQuestID())
  questNpc = { q = id and id > 0 and id or nil, at = GetTime(), npc = unitInfo("npc") }
end
local function npcFor(q)
  local c = questNpc
  if not c or (c.q and c.q ~= q) or GetTime() - c.at > CONTEXT_TTL then return nil end
  return c.npc
end
function handlers.QUEST_DETAIL(startItem)
  noteNpc()
  questNpc.item = clean(startItem)
end
handlers.QUEST_PROGRESS = noteNpc
handlers.QUEST_COMPLETE = noteNpc

function handlers.QUEST_ACCEPTED(q)
  local run = runs()[q]
  if not run then return end
  run.accepted = true
  local c = questNpc
  add(q, run, "SHARE_GIVER", { title = titleOf(q), npc = npcFor(q), item = c and c.q == q and c.item or nil,
                               objectives = L.questObjectives(q) })
  baseline(q, true)
end

function handlers.QUEST_TURNED_IN(q)
  local run = runs()[q]
  if not run then return end
  add(q, run, "SHARE_HANDIN", { npc = npcFor(q) })
  finish(q, "turned in")
end

function handlers.QUEST_REMOVED(q)
  local run = runs()[q]
  if not run or not run.accepted then return end
  local id = run.run
  C_Timer.After(REMOVE_WAIT, function()
    local now = runs()[q]
    if not now or now.run ~= id then return end
    if clean(C_QuestLog.IsQuestFlaggedCompleted(q)) then finish(q, "turned in") else finish(q, "abandoned") end
  end)
end

local function scan()
  for q, run in pairs(runs()) do
    local m = mem[q]
    if m and run.accepted then
      for j, o in ipairs(L.questObjectives(q) or {}) do
        local prev = m.cur[j]
        if prev == nil and m.fresh then prev = 0 end
        local have = o.have or 0
        if (prev and have > prev) or (o.done and m.done[j] == false) then
          add(q, run, "SHARE_TICK", { i = j, have = o.have, need = o.need, done = o.done, text = o.text })
        end
        m.cur[j], m.done[j] = have, o.done and true or false
        m.fresh = false
      end
      local ready = isReady(q)
      if ready and not m.ready then add(q, run, "SHARE_READY") end
      m.ready = ready
    end
  end
end

local scanQueued = false
local function queueScan()
  if scanQueued then return end
  scanQueued = true
  C_Timer.After(0.2, function()
    scanQueued = false
    local ok, err = pcall(scan)
    if not ok then L.add("LOGGER_ERROR", { event = "share scan", err = tostring(err) }) end
  end)
end
handlers.QUEST_LOG_UPDATE = queueScan
function handlers.UNIT_QUEST_LOG_CHANGED(unit) if unit == "player" then queueScan() end end

function handlers.PLAYER_TARGET_CHANGED() remember("target") end
function handlers.UPDATE_MOUSEOVER_UNIT() remember("mouseover") end
function handlers.NAME_PLATE_UNIT_ADDED(unit) if clean(unit) then remember(unit) end end
function handlers.PLAYER_REGEN_DISABLED() remember("target") end

-- quests still working on, with room in the log
local function working()
  local out = {}
  for q, run in pairs(runs()) do
    local m = mem[q]
    if run.accepted and m and not m.ready and (run.n or 0) < RUN_MAX then out[q] = run end
  end
  return out
end

function handlers.CHAT_MSG_COMBAT_XP_GAIN(text)
  local name, xp = parseKill(clean(text))
  if not name then return end
  local u = seenName[name]
  for q, run in pairs(working()) do
    run.n = (run.n or 0) + 1
    add(q, run, "SHARE_KILL", { mob = name, level = u and u.level, npc = u and u.id, gain = xp })
  end
end

-- quest items only, and where each came from. a loot window can open twice for one corpse
local lootSeen = {}
function handlers.LOOT_CLOSED() lootSeen = {} end
function handlers.LOOT_OPENED()
  local active = working()
  if next(active) == nil then return end
  for slot = 1, (GetNumLootItems() or 0) do
    local link = clean(GetLootSlotLink(slot))
    local name = link and link:match("%[(.-)%]")
    if name then
      for q, run in pairs(active) do
        local wanted = false
        for _, o in ipairs(L.questObjectives(q) or {}) do
          if o.text and not o.done and o.text:find(name, 1, true) then wanted = true end
        end
        if wanted then
          local src = { GetLootSourceInfo(slot) }
          local from = {}
          for k = 1, #src, 2 do
            local guid = clean(src[k])
            local id, kind = L.npcIdOf(guid)
            local key = tostring(guid) .. ":" .. slot .. ":" .. q
            if id and not lootSeen[key] then
              lootSeen[key] = true
              local u = seenId[id]
              from[#from + 1] = { id = id, kind = kind, name = u and u.name, level = u and u.level, n = clean(src[k + 1]) }
            end
          end
          if #from > 0 or not lootSeen[slot .. ":" .. q] then
            lootSeen[slot .. ":" .. q] = true
            run.n = (run.n or 0) + 1
            add(q, run, "SHARE_LOOT", { item = tonumber(link:match("item:(%d+)")), name = name, from = from })
          end
        end
      end
    end
  end
end

ev:SetScript("OnEvent", function(_, event, ...)
  local h = handlers[event]
  if h then
    local ok, err = pcall(h, ...)
    if not ok then L.add("LOGGER_ERROR", { event = "share " .. event, err = tostring(err) }) end
  end
end)

-- back from a reload or a login: carry on what this character was logging
local boot = ns.newFrame("Share", "Frame")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function()
  boot:UnregisterEvent("PLAYER_ENTERING_WORLD")
  -- a moment later: the logger's session and the quest log come first
  C_Timer.After(1, function()
    local all = runs()
    for q, run in pairs(all) do
      if run.accepted and not inLog(q) then
        -- handed in or dropped while we weren't looking
        if clean(C_QuestLog.IsQuestFlaggedCompleted(q)) then finish(q, "turned in") else finish(q, "abandoned") end
      elseif run.accepted then
        baseline(q, false)
      end
    end
    syncEvents()
  end)
end)

-- ------------------------------------------------------------------ starting and stopping
-- the quest was picked up before logging: the logger may have its giver already. same character only
local function earlierGiver(q)
  local sessions = AuDHDLog and AuDHDLog.sessions or {}
  local name = clean(UnitName("player"))
  for i = #sessions, 1, -1 do
    if sessions[i].char == name then
      local entries = sessions[i].entries or {}
      for j = #entries, 1, -1 do
        local e = entries[j]
        if e.e == "QUEST_ACCEPTED" and e.q == q then return e end
      end
    end
  end
  return nil
end

function S.isLogging(q) return runs()[q] ~= nil end

-- returns what happened, in words
function S.start(q, why)
  q = tonumber(q)
  if not q then return "which quest? /audhd share log <questID>" end
  local all = runs()
  if all[q] then return ("already logging quest %d"):format(q) end
  local run = { run = GetServerTime(), accepted = inLog(q), n = 0 }
  all[q] = run
  local title = titleOf(q)
  add(q, run, "SHARE_START", { why = why, title = title, objectives = run.accepted and L.questObjectives(q) or nil,
                               accepted = run.accepted })
  if run.accepted then
    baseline(q, false)
    local g = earlierGiver(q)
    if g then add(q, run, "SHARE_GIVER", { npc = g.npc, gm = g.m, gx = g.x, gy = g.y, earlier = true }) end
  else
    -- logging from the pick-up on
    mem[q] = { cur = {}, done = {}, fresh = true, ready = false }
  end
  syncEvents()
  return ("logging %s until it's turned in or abandoned. /audhd share stop %d to stop"):format(title or ("quest " .. q), q)
end

function S.stop(q)
  local all = runs()
  q = tonumber(q)
  if not q then
    for id in pairs(all) do q = id break end
    if not q then return "not logging anything" end
  end
  if not all[q] then return ("not logging quest %d"):format(q) end
  finish(q, "stopped")
  return ("stopped logging quest %d"):format(q)
end

-- ------------------------------------------------------------------ the compact text
-- text as it reads: colour, link and texture codes out, one line
local function plain(s)
  s = tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", ""):gsub("|T.-|t", "")
  return (s:gsub("|", ""):gsub("%s+", " "))
end

-- objective text without its count: "Thistle Boar slain: 0/2" -> "Thistle Boar slain"
local function noCount(s)
  return (plain(s):gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", ""):gsub("^%s*%d+%s*/%s*%d+%s*", ""))
end

-- s cut to n bytes, never inside a character
local function cut(s, n)
  if #s <= n then return s end
  return (s:sub(1, n - 3):gsub("[\192-\255][\128-\191]*$", "")) .. "..."
end

-- any case, and no magic characters
local function anyCase(s)
  return (s:gsub("%W", "%%%0"):gsub("%a", function(c) return "[" .. c:lower() .. c:upper() .. "]" end))
end

-- every name this log file knows for the player, for taking them out of quest text ("$N's task") or a mob called after them
local function privateWords()
  local words, seen = {}, {}
  local function put(w, as)
    w = clean(w)
    if type(w) == "string" and w ~= "" and not seen[w] then
      seen[w] = true
      words[#words + 1] = { anyCase(w), as }
    end
  end
  for _, s in ipairs(AuDHDLog and AuDHDLog.sessions or {}) do
    put(s.char, "[name]")
    put(s.realm, "[realm]")
  end
  put(UnitName("player"), "[name]")
  local _, realm = UnitFullName("player")
  put(realm, "[realm]")
  put(GetRealmName and GetRealmName(), "[realm]")
  return words
end

local function num(v) return v and ("%d"):format(math.floor(v)) or "?" end

local function at(m, x, y)
  if m and x and y then return ("@%s %.1f,%.1f"):format(num(m), x, y) end
  if m then return "@" .. num(m) end
  return "@?"
end

local function who(u)
  if not u then return "unknown" end
  local parts = { u.kind == "GameObject" and "object" or "npc", u.id and num(u.id) or "?", plain(u.name or "?") }
  if u.level then parts[#parts + 1] = "L" .. num(u.level) end
  return table.concat(parts, " ")
end

-- the latest run of a quest, across sessions (a reload starts a new session): its entries in order and its first session
local function collect(q)
  local latest
  local sessions = AuDHDLog and AuDHDLog.sessions or {}
  for _, s in ipairs(sessions) do
    for _, e in ipairs(s.entries or {}) do
      if e.questId == q and (not latest or e.run > latest) then latest = e.run end
    end
  end
  if not latest then return nil end
  local out, first = {}, nil
  for _, s in ipairs(sessions) do
    for _, e in ipairs(s.entries or {}) do
      if e.questId == q and e.run == latest then
        first = first or s
        out[#out + 1] = e
      end
    end
  end
  return out, first
end

local LINES = {
  SHARE_START = function(e)
    return "start " .. at(e.m, e.x, e.y) .. (e.accepted and "" or " not picked up yet")
  end,
  SHARE_GIVER = function(e)
    if e.earlier then return "giver " .. who(e.npc) .. " " .. at(e.gm, e.gx, e.gy) .. " from the earlier log" end
    local what = e.npc and who(e.npc) or (e.item and ("item " .. num(e.item)) or "unknown")
    return "giver " .. what .. " " .. at(e.m, e.x, e.y)
  end,
  SHARE_TICK = function(e)
    return ("tick %s %s/%s %s %s"):format(num(e.i), num(e.have), num(e.need), at(e.m, e.x, e.y), noCount(e.text))
  end,
  SHARE_READY = function(e) return "ready " .. at(e.m, e.x, e.y) end,
  SHARE_KILL = function(e)
    return ("kill %s L%s npc %s %s"):format(plain(e.mob), num(e.level), num(e.npc), at(e.m, e.x, e.y))
  end,
  SHARE_LOOT = function(e)
    local from = {}
    for i, f in ipairs(e.from or {}) do from[i] = who(f) .. (f.n and (" x" .. num(f.n)) or "") end
    return ("loot item %s %s from %s %s"):format(num(e.item), plain(e.name), #from > 0 and table.concat(from, ", ") or "unknown",
                                                 at(e.m, e.x, e.y))
  end,
  SHARE_HANDIN = function(e) return "handin " .. who(e.npc) .. " " .. at(e.m, e.x, e.y) end,
  SHARE_END = function(e) return "end " .. plain(e.why) end,
}

-- the whole log as text, or nil when there's none
function S.text(q)
  q = tonumber(q)
  local entries, session = collect(q)
  if not entries then return nil end
  local words = privateWords()
  local lines = {}
  local function put(line)
    for _, w in ipairs(words) do line = line:gsub(w[1], w[2]) end
    lines[#lines + 1] = cut(line, LINE_MAX)
  end
  local start, title, why, objectives = entries[1], nil, nil, nil
  local lvLow, lvHigh
  for _, e in ipairs(entries) do
    title = title or e.title
    why = why or e.why
    objectives = objectives or e.objectives
    if e.lv then
      lvLow = math.min(lvLow or e.lv, e.lv)
      lvHigh = math.max(lvHigh or e.lv, e.lv)
    end
  end
  put(("AuDHD quest log v%d quest %d %s"):format(FORMAT, q, plain(title or "?")))
  local level = lvLow == lvHigh and num(lvLow) or (num(lvLow) .. "-" .. num(lvHigh))
  put(("race %s class %s level %s build %s"):format(plain(session.race or "?"), plain(session.class or "?"), level,
                                                     plain(session.build or "?")))
  if why and entries[1].e == "SHARE_START" then put("why " .. plain(why)) end
  for j, o in ipairs(objectives or {}) do
    put(("need %d %s %s %s"):format(j, plain(o.type or "?"), num(o.need), noCount(o.text)))
  end
  for _, e in ipairs(entries) do
    local make = LINES[e.e]
    if make then put(("+%s %s"):format(num(e.t - start.t), make(e))) end
  end
  return table.concat(lines, "\n")
end

-- the text in numbered parts, each with its own heading, broken between lines
function S.parts(q)
  local text = S.text(q)
  if not text then return nil end
  if #text <= S.PART_MAX then return { text } end
  local head = "AuDHD quest log quest " .. tostring(q) .. " part 000/000\n"
  local room = S.PART_MAX - #head
  local chunks, cur = {}, {}
  local used = 0
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if used + #line + 1 > room and #cur > 0 then
      chunks[#chunks + 1] = table.concat(cur, "\n")
      cur, used = {}, 0
    end
    cur[#cur + 1] = line
    used = used + #line + 1
  end
  chunks[#chunks + 1] = table.concat(cur, "\n")
  for i, c in ipairs(chunks) do
    chunks[i] = ("AuDHD quest log quest %s part %d/%d\n%s"):format(tostring(q), i, #chunks, c)
  end
  return chunks
end

-- quests with a log, newest first: { q, run }
local function logged()
  local best = {}
  for _, s in ipairs(AuDHDLog and AuDHDLog.sessions or {}) do
    for _, e in ipairs(s.entries or {}) do
      if e.questId and (not best[e.questId] or e.run > best[e.questId]) then best[e.questId] = e.run end
    end
  end
  local out = {}
  for q, run in pairs(best) do out[#out + 1] = { q = q, run = run } end
  table.sort(out, function(a, b)
    if a.run ~= b.run then return a.run > b.run end
    return a.q < b.q
  end)
  return out
end

-- ------------------------------------------------------------------ windows
local function setTitle(f, text)
  local t = f.TitleText
  if type(t) ~= "table" and type(f.TitleContainer) == "table" then t = f.TitleContainer.TitleText end
  if type(t) ~= "table" then
    t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOP", f, "TOP", 0, -5)
  end
  t:SetText(text)
end

local function window(name, w, h, title)
  local f = ns.newFrame("Share", "Frame", name, UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(w, h)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  f:Hide()
  setTitle(f, title)
  if UISpecialFrames then table.insert(UISpecialFrames, name) end
  return f
end

local function label(parent, font, width)
  local t = parent:CreateFontString(nil, "OVERLAY", font)
  t:SetWidth(width)
  t:SetJustifyH("LEFT")
  t:SetJustifyV("TOP")
  return t
end

local function button(parent, text, width, onClick)
  local b = ns.newFrame("Share", "Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

-- the box can be selected and copied but not changed
local function readOnly(box)
  box:SetAutoFocus(false)
  box:SetScript("OnTextChanged", function(self, user)
    if user then
      self:SetText(self.keep or "")
      self:HighlightText()
    end
  end)
  box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  box:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
end
local function keepText(box, text)
  box.keep = text
  box:SetText(text)
end

-- the ask: never takes the keyboard, and waits out a fight
local ask, askPending
local asked = {}
local function showAsk(q, text)
  if not ask then
    ask = window("AuDHDShareAsk", 360, 150, "AuDHD: help find this")
    ask.Text = label(ask, "GameFontHighlight", 330)
    ask.Text:SetPoint("TOPLEFT", ask, "TOPLEFT", 16, -34)
    ask.Start = button(ask, "Start logging", 130, function()
      ask:Hide()
      print("AuDHD: " .. S.start(ask.q, ask.why))
    end)
    ask.Start:SetPoint("BOTTOMLEFT", ask, "BOTTOMLEFT", 16, 12)
    ask.Later = button(ask, "Not now", 100, function() ask:Hide() end)
    ask.Later:SetPoint("LEFT", ask.Start, "RIGHT", 8, 0)
  end
  ask.Text:SetText(text)
  ask:Show()
end

local waiter
local function whenOutOfCombat(fn)
  if not InCombatLockdown() then return fn() end
  askPending = fn
  if not waiter then
    waiter = ns.newFrame("Share", "Frame")
    waiter:SetScript("OnEvent", function(self)
      self:UnregisterEvent("PLAYER_REGEN_ENABLED")
      local go = askPending
      askPending = nil
      if go then go() end
    end)
  end
  waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- we don't know where a mob or objective is. once per quest per session; false if nothing was asked
function S.askToLog(questID, why)
  local q = tonumber(questID)
  if not q or asked[q] or S.isLogging(q) then return false end
  asked[q] = true
  why = why and plain(clean(why)) or nil
  if why == "" then why = nil end
  local title = titleOf(q) or ("quest " .. q)
  local line = ("We don't know where to send you for %s%s."):format(title, why and (" (" .. why .. ")") or "")
  print(("AuDHD: %s Log it and share it? /audhd share log %d"):format(line, q))
  whenOutOfCombat(function()
    showAsk(q, line .. " If you log it while you do it, you can send us the log and we can fix the route for everyone.")
    ask.q, ask.why = q, why
  end)
  return true
end

local F
local function showPart()
  local total = #F.parts
  F.part = math.max(1, math.min(F.part, total))
  keepText(F.Box, F.parts[F.part])
  F.Part:SetText(total > 1 and ("Part %d of %d: paste each part in order"):format(F.part, total) or "One part")
  if total > 1 then
    F.Prev:Show()
    F.Next:Show()
    F.Prev:SetEnabled(F.part > 1)
    F.Next:SetEnabled(F.part < total)
  else
    F.Prev:Hide()
    F.Next:Hide()
  end
  F.Box:SetCursorPosition(0)
  F.Scroll:SetVerticalScroll(0)
end

local function buildShow()
  F = window("AuDHDShareWindow", 540, 470, "AuDHD: share a quest log")
  local width = 500
  F.Intro = label(F, "GameFontHighlightSmall", width)
  F.Intro:SetPoint("TOPLEFT", F, "TOPLEFT", 18, -32)
  F.Intro:SetText("Click in the box, press Ctrl+A then Ctrl+C. Open the link below in your browser, paste it in a new issue and post it.")

  local inset = ns.newFrame("Share", "ScrollFrame", "AuDHDShareScroll", F, "UIPanelScrollFrameTemplate")
  inset:SetPoint("TOPLEFT", F, "TOPLEFT", 18, -66)
  inset:SetSize(width - 22, 210)
  F.Scroll = inset
  F.Box = ns.newFrame("Share", "EditBox", "AuDHDShareBox", inset)
  F.Box:SetMultiLine(true)
  F.Box:SetMaxLetters(0)
  F.Box:SetFontObject("GameFontHighlightSmall")
  F.Box:SetWidth(width - 26)
  readOnly(F.Box)
  inset:SetScrollChild(F.Box)

  F.Part = label(F, "GameFontNormalSmall", 250)
  F.Part:SetPoint("TOPLEFT", inset, "BOTTOMLEFT", 0, -12)
  F.Next = button(F, "Next", 70, function()
    F.part = F.part + 1
    showPart()
  end)
  F.Next:SetPoint("TOPRIGHT", F, "TOPRIGHT", -18, -282)
  F.Prev = button(F, "Previous", 80, function()
    F.part = F.part - 1
    showPart()
  end)
  F.Prev:SetPoint("RIGHT", F.Next, "LEFT", -6, 0)
  F.Select = button(F, "Select all", 80, function()
    F.Box:SetFocus()
    F.Box:HighlightText()
  end)
  F.Select:SetPoint("RIGHT", F.Prev, "LEFT", -6, 0)

  F.LinkLabel = label(F, "GameFontNormalSmall", width)
  F.LinkLabel:SetPoint("TOPLEFT", F, "TOPLEFT", 18, -312)
  F.LinkLabel:SetText("New issue link (click, Ctrl+A, Ctrl+C):")
  F.Link = ns.newFrame("Share", "EditBox", "AuDHDShareLink", F, "InputBoxTemplate")
  F.Link:SetSize(width - 8, 20)
  F.Link:SetPoint("TOPLEFT", F, "TOPLEFT", 24, -328)
  F.Link:SetFontObject("GameFontHighlightSmall")
  readOnly(F.Link)
  keepText(F.Link, S.ISSUE_URL)

  F.Other = label(F, "GameFontHighlightSmall", width)
  F.Other:SetPoint("TOPLEFT", F, "TOPLEFT", 18, -358)
  F.Other:SetText("Or, after a /reload or logging out, attach the saved file to the issue, or send it through the CurseForge project page: "
    .. S.SAVED_FILE .. ". That file has your character names and realms in it. The text above doesn't: only race, class, level and build.")
end

-- the window, on a quest's log. returns what happened, in words
function S.show(questID)
  local q = tonumber(questID)
  if not q then
    local list = logged()
    q = list[1] and list[1].q
    if not q then return "no quest logged yet" end
  end
  local parts = S.parts(q)
  if not parts then return ("no log for quest %d"):format(q) end
  if not F then buildShow() end
  F.q, F.parts, F.part = q, parts, 1
  showPart()
  F:Show()
  return #parts > 1 and ("quest %d: %d parts"):format(q, #parts) or ("quest %d"):format(q)
end

-- ------------------------------------------------------------------ report a problem
-- One button: the last half hour of the log, packed into one code to copy and paste into a GitHub issue or a CurseForge
-- comment, with a line from the player on what went wrong. An addon can't send anything out of the game, so copying is
-- the one step left. No character names, realm or account: the player's own and their alts' names become [name] and
-- [alt], other players' [player]. tools/read_report.mjs turns the code back into text.
S.CURSEFORGE_URL = "https://www.curseforge.com/projects/1749872"
local REPORT_MINUTES = 30
local REPORT_MAX = 12000   -- characters of code in the box; older entries go first when it's longer
local POS_EVERY = 30       -- seconds between position entries kept
local NOTE_MAX = 300
local DROP_KEYS = { char = true, realm = true, account = true }
local PLAYER_KEYS = { who = true }   -- other players' names

-- names to take out: this character's and every alt's this file knows (full and first names)
local function reportWords()
  local words = privateWords()
  local seen = {}
  local function put(n, as)
    if type(n) ~= "string" or n == "" or seen[n] then return end
    seen[n] = true
    words[#words + 1] = { anyCase(n), as }
  end
  local function name(n, as)
    put(n, as)
    local first = type(n) == "string" and n:match("^(%S+)%s")
    if first and #first > 2 then put(first, as) end
  end
  for _, list in pairs(AuDHDDB and AuDHDDB.chars or {}) do
    if type(list) == "table" then for n in pairs(list) do name(n, "[alt]") end end
  end
  name(AuDHDDB and AuDHDDB.bankAlt, "[alt]")
  for _, r in pairs(AuDHDDB and AuDHDDB.altMail and AuDHDDB.altMail.rows or {}) do name(r.name, "[alt]") end
  -- (each character's own alt mail settings)
  for _, c in pairs(AuDHDDB and AuDHDDB.mailChars or {}) do
    if type(c) == "table" then
      name(c.bankAlt, "[alt]")
      for _, r in pairs(c.altMail and c.altMail.rows or {}) do name(r.name, "[alt]") end
    end
  end
  -- longest first, so "Bankie Smith" goes before "Bankie"
  table.sort(words, function(a, b) return #a[1] > #b[1] end)
  return words
end
local function scrub(s, words)
  s = plain(s)
  for _, w in ipairs(words) do s = s:gsub(w[1], w[2]) end
  return s
end

local function value(v, words, depth)
  if type(v) == "number" then return v == math.floor(v) and ("%d"):format(v) or ("%.2f"):format(v) end
  if type(v) == "boolean" then return v and "yes" or "no" end
  if type(v) == "table" then
    if (depth or 0) >= 2 then return "{...}" end
    local parts = {}
    if #v > 0 then
      for i = 1, math.min(#v, 12) do parts[#parts + 1] = value(v[i], words, (depth or 0) + 1) end
      if #v > 12 then parts[#parts + 1] = "+" .. (#v - 12) end
    else
      local keys = {}
      for k in pairs(v) do if not DROP_KEYS[k] then keys[#keys + 1] = tostring(k) end end
      table.sort(keys)
      for _, k in ipairs(keys) do
        local x = v[k]
        if k == "name" and v.kind == "Player" then x = "[player]" end
        parts[#parts + 1] = k .. "=" .. value(x, words, (depth or 0) + 1)
      end
    end
    return "{" .. table.concat(parts, " ") .. "}"
  end
  return scrub(v, words)
end
local SKIP = { t = true, e = true, m = true, x = true, y = true, lv = true, xp = true }
local function entryLine(e, now, words)
  local ago = math.max(0, now - (e.t or now))
  local parts = { ("-%d:%02d"):format(math.floor(ago / 60), ago % 60), tostring(e.e or "?") }
  if e.m then parts[#parts + 1] = at(e.m, e.x, e.y) end
  if e.lv then parts[#parts + 1] = "L" .. num(e.lv) end
  local keys = {}
  for k in pairs(e) do if not SKIP[k] and not DROP_KEYS[k] then keys[#keys + 1] = tostring(k) end end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local v = e[k]
    if PLAYER_KEYS[k] then v = "[player]" end
    if k == "name" and e.e and e.e:find("^PARTY") then v = "[player]" end
    parts[#parts + 1] = k .. "=" .. value(v, words)
  end
  return cut(table.concat(parts, " "), LINE_MAX)
end

-- the report as text: what, who (race, class, level), where on the route, the player's note, then the log, oldest first
function S.reportText(note, minutes)
  local now = time and time() or 0
  local from = now - (minutes or REPORT_MINUTES) * 60
  local words = reportWords()
  local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("AuDHD", "Version") or "?"
  local build = GetBuildInfo and select(2, GetBuildInfo()) or "?"
  local _, race = UnitRace("player")
  local _, class = UnitClass("player")
  local guide, step
  local E = AuDHDEngine and AuDHDEngine.Engine
  if E then
    local ok, g = pcall(E.GetGuide)
    guide = ok and g and g.id
    local ok2, s = pcall(E.GetLiveStep)
    step = ok2 and s
  end
  local m = C_Map.GetBestMapForUnit("player")
  local p = m and not isSecret(m) and C_Map.GetPlayerMapPosition(m, "player")
  local px, py
  if p then px, py = p:GetXY() end
  local lines = {
    ("AuDHD report %d, addon %s, build %s"):format(FORMAT, tostring(version), tostring(build)),
    ("%s %s level %s %s, %s"):format(tostring(race), tostring(class), num(UnitLevel("player")),
      tostring(UnitFactionGroup and UnitFactionGroup("player") or "?"), at(m, px and px * 100, py and py * 100)),
    ("guide %s, step %s"):format(tostring(guide or "none"), tostring(step or "?")),
    "note: " .. (note and note ~= "" and scrub(note, words) or "(none)"),
    ("log, last %d minutes (time before now, event, place, level, the rest):"):format(minutes or REPORT_MINUTES),
  }
  local lastPos
  for _, s in ipairs(AuDHDLog and AuDHDLog.sessions or {}) do
    for _, e in ipairs(s.entries or {}) do
      if (e.t or 0) >= from then
        local keep = true
        if e.e == "POS" then
          keep = not lastPos or e.t - lastPos >= POS_EVERY
          if keep then lastPos = e.t end
        end
        if keep then lines[#lines + 1] = entryLine(e, now, words) end
      end
    end
  end
  return table.concat(lines, "\n")
end

-- packed: zlib, then base64, behind "AuDHD-R1:"; plain text behind "AuDHD-T1:" when the client can't pack
local function pack(text)
  local enc = C_EncodingUtil
  local method = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Zlib
  if enc and enc.CompressString and enc.EncodeBase64 and method then
    local ok, z = pcall(enc.CompressString, text, method)
    if ok and type(z) == "string" then
      local ok2, b = pcall(enc.EncodeBase64, z)
      if ok2 and type(b) == "string" and b ~= "" then return "AuDHD-R1:" .. b end
    end
  end
  return "AuDHD-T1:\n" .. text
end
-- the code to copy: a plain first line (so a report reads at a glance) and the packed report; shorter windows of time
-- until it fits the box
function S.report(note)
  note = note and cut(plain(note), NOTE_MAX) or ""
  local _, class = UnitClass("player")
  local head = ("AuDHD problem report (%s %s): %s"):format(tostring(select(2, UnitRace("player"))), tostring(class),
    note ~= "" and scrub(note, reportWords()) or "no note")
  local code, minutes
  for _, mins in ipairs({ REPORT_MINUTES, 15, 8, 4, 2 }) do
    minutes = mins
    code = pack(S.reportText(note, mins))
    if #code <= REPORT_MAX then break end
  end
  if #code > REPORT_MAX then code = code:sub(1, REPORT_MAX) end
  if L then L.add("REPORT_MADE", { minutes = minutes, size = #code }) end
  return head .. "\n" .. code, minutes
end

local R
local function buildReport()
  R = window("AuDHDReport", 540, 452, "AuDHD: report a problem")
  local width = 500
  R.Intro = label(R, "GameFontHighlightSmall", width)
  R.Intro:SetPoint("TOPLEFT", R, "TOPLEFT", 18, -32)
  R.Intro:SetText("1. Say what went wrong, then press Make report.\n2. Press Select all, then Ctrl+C.\n"
    .. "3. Paste it into a new GitHub issue or a comment on the CurseForge page (links below).")
  R.Note = ns.newFrame("Share", "EditBox", "AuDHDReportNote", R, "InputBoxTemplate")
  R.Note:SetSize(width - 120, 20)
  R.Note:SetPoint("TOPLEFT", R, "TOPLEFT", 24, -84)
  R.Note:SetAutoFocus(false)
  R.Note:SetMaxLetters(NOTE_MAX)
  R.Note:SetFontObject("GameFontHighlightSmall")
  R.Note:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  R.NoteHint = label(R, "GameFontDisableSmall", width - 140)
  R.NoteHint:SetPoint("LEFT", R.Note, "LEFT", 2, 0)
  R.NoteHint:SetText("What went wrong? (e.g. Send all left my leather behind)")
  R.Note:SetScript("OnTextChanged", function(self) R.NoteHint:SetShown(self:GetText() == "") end)
  R.Make = button(R, "Make report", 100, function()
    R.Note:ClearFocus()
    local text, minutes = S.report(R.Note:GetText())
    keepText(R.Box, text)
    R.Box:SetCursorPosition(0)
    R.Scroll:SetVerticalScroll(0)
    R.Status:SetText(("The last %d minutes of what AuDHD saw. Now press Select all, then Ctrl+C."):format(minutes))
    R.Select:Enable()
  end)
  R.Make:SetPoint("LEFT", R.Note, "RIGHT", 8, 0)
  R.Note:SetScript("OnEnterPressed", function() R.Make:Click() end)

  local inset = ns.newFrame("Share", "ScrollFrame", "AuDHDReportScroll", R, "UIPanelScrollFrameTemplate")
  inset:SetPoint("TOPLEFT", R, "TOPLEFT", 18, -114)
  inset:SetSize(width - 22, 150)
  R.Scroll = inset
  R.Box = ns.newFrame("Share", "EditBox", "AuDHDReportBox", inset)
  R.Box:SetMultiLine(true)
  R.Box:SetMaxLetters(0)
  R.Box:SetFontObject("GameFontHighlightSmall")
  R.Box:SetWidth(width - 26)
  readOnly(R.Box)
  inset:SetScrollChild(R.Box)

  R.Status = label(R, "GameFontNormalSmall", width - 100)
  R.Status:SetPoint("TOPLEFT", inset, "BOTTOMLEFT", 0, -10)
  R.Select = button(R, "Select all", 90, function()
    R.Box:SetFocus()
    R.Box:HighlightText()
  end)
  R.Select:SetPoint("TOPRIGHT", R, "TOPRIGHT", -18, -272)

  local y = -304
  local function link(text, url)
    local l = label(R, "GameFontNormalSmall", width)
    l:SetPoint("TOPLEFT", R, "TOPLEFT", 18, y)
    l:SetText(text)
    local b = ns.newFrame("Share", "EditBox", nil, R, "InputBoxTemplate")
    b:SetSize(width - 8, 20)
    b:SetPoint("TOPLEFT", R, "TOPLEFT", 24, y - 14)
    b:SetFontObject("GameFontHighlightSmall")
    readOnly(b)
    keepText(b, url)
    b:SetCursorPosition(0)
    y = y - 42
  end
  link("GitHub, a new issue (click, Ctrl+A, Ctrl+C, open it in your browser):", S.ISSUE_URL)
  link("CurseForge, the AuDHD page (comments):", S.CURSEFORGE_URL)
  R.Private = label(R, "GameFontDisableSmall", width)
  R.Private:SetPoint("TOPLEFT", R, "TOPLEFT", 18, y - 4)
  R.Private:SetText("The report has your race, class, level, the route step and what AuDHD logged: steps, quests, places, "
    .. "items and money. No character names, realm or account.")
end
function S.showReport()
  if not R then buildReport() end
  keepText(R.Box, "")
  R.Status:SetText("")
  R.Select:Disable()
  R:Show()
  R.Note:SetFocus()
  return "report window open"
end

-- ------------------------------------------------------------------ /audhd share
local USAGE = "share log <questID> [why] | stop [questID] | show [questID] | list"
function S.command(rest)
  local word, arg = (rest or ""):match("^%s*(%S*)%s*(.-)%s*$")
  word = word:lower()
  if word == "log" or word == "start" then
    local id, why = arg:match("^(%d+)%s*(.-)$")
    if not id then return USAGE end
    return S.start(id, why ~= "" and why or nil)
  elseif word == "stop" then
    return S.stop(arg ~= "" and arg or nil)
  elseif word == "show" then
    return S.show(arg ~= "" and arg or nil)
  elseif tonumber(word) then
    return S.show(word)
  elseif word == "list" then
    local out = {}
    for _, r in ipairs(logged()) do
      out[#out + 1] = tostring(r.q) .. (S.isLogging(r.q) and " (logging)" or "")
    end
    return #out > 0 and ("logged quests: " .. table.concat(out, ", ")) or "no quest logged yet"
  end
  return USAGE
end
