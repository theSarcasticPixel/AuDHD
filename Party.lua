-- Party quest progress: what the people you're grouped with have done on the quests you share (the user, 2026-10-16:
-- "show what other peoples quest progress is if they are on the same ones"). The game doesn't tell you anyone else's
-- quest log, so each AuDHD sends its own over addon messages to the party (or raid) when it changes; party
-- members without the addon don't show. Addon messages only: nothing protected.
-- Messages (prefix WFNQ): "R" = send me everything; "Q<id>:<c>:<have>/<need>,<have>/<need>..." = one quest
-- (c = 1 when it's ready to hand in); "X<id>" = that quest left their log.
local _, ns = ...
local P = {}
ns.party = P

local PREFIX = "WFNQ"
local data = {}      -- data[name][q] = { c = true/false, o = { { h, n }, ... } }
local sent = {}      -- what we last sent, by quest: the message
local isSecret = issecretvalue or function() return false end

local function channel()
  if IsInRaid and IsInRaid() then return "RAID" end
  if IsInGroup and IsInGroup() then return "PARTY" end
end
local function send(msg)
  local ch = channel()
  if ch and C_ChatInfo and C_ChatInfo.SendAddonMessage then C_ChatInfo.SendAddonMessage(PREFIX, msg, ch) end
end

-- my quests now: { [q] = message }
local function mine()
  local out = {}
  local ok, n = pcall(C_QuestLog.GetNumQuestLogEntries)
  for li = 1, (ok and n or 0) do
    local info = C_QuestLog.GetInfo(li)
    local q = info and not info.isHeader and info.questID
    if q and not isSecret(q) then
      local parts = {}
      local okO, objs = pcall(C_QuestLog.GetQuestObjectives, q)
      for _, o in ipairs(okO and type(objs) == "table" and objs or {}) do
        local h, need = o.numFulfilled, o.numRequired
        if isSecret(h) or isSecret(need) then h, need = nil, nil end
        parts[#parts + 1] = ("%d/%d"):format(h or (o.finished and 1 or 0), need or 1)
      end
      local c = C_QuestLog.IsComplete(q) and 1 or 0
      out[q] = ("Q%d:%d:%s"):format(q, c, table.concat(parts, ","))
    end
  end
  return out
end

-- send what changed (all of it when asked)
local pending, asked = nil, -100
function P.push(all)
  if not channel() then sent = {} return end
  local now = mine()
  for q, msg in pairs(now) do
    if all or sent[q] ~= msg then send(msg); sent[q] = msg end
  end
  for q in pairs(sent) do
    if not now[q] then send("X" .. q); sent[q] = nil end
  end
end
local function later(all)   -- the quest log fires in bursts: send once, a moment after
  if pending then pending.all = pending.all or all return end
  pending = { all = all }
  C_Timer.After(1, function() local a = pending.all; pending = nil; pcall(P.push, a) end)
end

local function short(name) return Ambiguate and Ambiguate(name, "short") or (name:match("^[^-]+") or name) end
local function receive(msg, sender)
  local who = short(sender)
  if who == UnitName("player") then return end
  if msg == "R" then later(true) return end
  local x = msg:match("^X(%d+)$")
  if x then
    if data[who] then data[who][tonumber(x)] = nil end
  else
    local q, c, rest = msg:match("^Q(%d+):(%d):(.*)$")
    if not q then return end
    local o = {}
    for h, n in rest:gmatch("(%d+)/(%d+)") do o[#o + 1] = { tonumber(h), tonumber(n) } end
    data[who] = data[who] or {}
    data[who][tonumber(q)] = { c = c == "1", o = o }
  end
  if ns.ui then ns.ui.refresh() end
end

-- people no longer in the group drop out
local function prune()
  local here = {}
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  local unit = (IsInRaid and IsInRaid()) and "raid" or "party"
  for i = 1, n do
    local name = UnitName(unit .. i)
    if name then here[name] = true end
  end
  for who in pairs(data) do if not here[who] then data[who] = nil end end
end

-- what the others have on quest q: "Bob 3/7, Amy done" for objective o (1-based; nil: the whole quest), or nil
function P.progress(q, o)
  local out = {}
  for who, qs in pairs(data) do
    local d = qs[q]
    if d then
      local ob = o and d.o[o]
      if d.c then out[#out + 1] = who .. " |cff40ff40done|r"
      elseif ob then out[#out + 1] = ob[1] >= ob[2] and (who .. " |cff40ff40done|r") or ("%s %d/%d"):format(who, ob[1], ob[2])
      else out[#out + 1] = who .. " has it" end
    end
  end
  if #out == 0 then return nil end
  table.sort(out)
  return table.concat(out, ", ")
end

function P.enable()
  if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) then return end
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  local f = CreateFrame("Frame")
  for _, e in ipairs({ "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "QUEST_LOG_UPDATE", "QUEST_REMOVED", "PLAYER_ENTERING_WORLD" }) do
    pcall(f.RegisterEvent, f, e)
  end
  f:SetScript("OnEvent", function(_, event, a, b, c, d)
    if event == "CHAT_MSG_ADDON" then
      if a == PREFIX then pcall(receive, b, d) end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
      prune()
      if channel() and GetTime() - asked > 10 then
        -- someone joined (or we did): everyone sends everything (roster updates come in bursts: once per 10 s)
        asked = GetTime()
        send("R")
        later(true)
      end
      if ns.ui then ns.ui.refresh() end
    else
      later(false)
    end
  end)
end
