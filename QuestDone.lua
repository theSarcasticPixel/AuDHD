-- A quest's objectives all done: said in your chat, and to your party when you're in one, as
-- "{star} <quest> Complete (AuDHD)" (the user, 2026-10-17: "notifications for when a quest objective is complete,
-- sending it to your party if you're in one"; AuDHD: the addon's name to come, zQuest was taken). Only as it happens: a quest already
-- done when you log in, or done as you take it (a letter to deliver), isn't said. /wfn announce [off|on].
local _, ns = ...
local Q = {}
ns.questDone = Q

local TAG = "(AuDHD)"
local STAR_CHAT = "{rt1}"   -- the star raid icon in party chat
local STAR_TEXT = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t"
local isSecret = issecretvalue or function() return false end

local state       -- [q] = true (done) / false (not yet); nil until the first look after login
local function off() return AuDHDDB and AuDHDDB.announceOff end

local function channel()
  if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
      and not (LE_PARTY_CATEGORY_HOME and IsInGroup(LE_PARTY_CATEGORY_HOME)) then return "INSTANCE_CHAT" end
  if IsInGroup and IsInGroup() then return "PARTY" end   -- in a raid: your group of it
end

function Q.say(title)
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then DEFAULT_CHAT_FRAME:AddMessage(("%s |cffffd200%s Complete|r %s"):format(STAR_TEXT, title, TAG)) end
  local ch = channel()
  if ch and SendChatMessage then pcall(SendChatMessage, ("%s %s Complete %s"):format(STAR_CHAT, title, TAG), ch) end
  if ns.log then ns.log.add("QUEST_DONE_SAID", { title = title, ch = ch }) end
end

-- what's done in your log now: { [q] = { done, title } }
local function now()
  local out = {}
  local ok, n = pcall(C_QuestLog.GetNumQuestLogEntries)
  for li = 1, (ok and n or 0) do
    local info = C_QuestLog.GetInfo(li)
    local q = info and not info.isHeader and info.questID
    local title = q and (info.title or (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(q)))
    if q and not isSecret(q) and title and not isSecret(title) then
      out[q] = { done = C_QuestLog.IsComplete(q) and true or false, title = title }
    end
  end
  return out
end

function Q.check()
  local cur = now()
  if state and not off() then
    for q, c in pairs(cur) do
      if c.done and state[q] == false then Q.say(c.title) end
    end
  end
  state = {}
  for q, c in pairs(cur) do state[q] = c.done end
end

function Q.command(arg)
  arg = (arg or ""):lower()
  if arg == "off" or arg == "on" then
    AuDHDDB.announceOff = arg == "off" or nil
    return "quest complete messages " .. arg
  end
  return "quest complete messages are " .. (off() and "off" or "on") .. " (/wfn announce off|on)"
end

local frame = ns.newFrame("QuestDone", "Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    -- the log isn't all there at login: the first look a few seconds on, said nothing
    C_Timer.After(5, function() state = nil pcall(Q.check) end)
  elseif state then
    pcall(Q.check)
  end
end)
