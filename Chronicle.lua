-- Chronicle (a separate addon that voices quest dialogue): when it's installed, the route window gets a Listen button
-- that asks Chronicle to play the current step's quest lines. AuDHD ships no voices; Chronicle decides what may play
-- (only lines this character has earned, so no spoilers). Nothing here runs without Chronicle.
local _, ns = ...
local C = {}
ns.chronicle = C

-- Chronicle's playback library, once it's loaded (looked up each time: no load order needed)
local function lib()
  local ls = _G.LibStub
  local api = ls and ls("Chronicle-1.0", true)
  return api and (api.apiVersion or 0) >= 4 and api or nil
end
C.installed = function() return lib() ~= nil end

function C.isOn() return not AuDHDDB.chronicleOff and lib() ~= nil end

-- the step's quest: a pick-up or hand-in's own, else the first part of a "do" step that's in your log
local function questOf(step)
  if not step then return nil end
  if step.q and (step.k ~= "do" or not step.mem) then return step.q end
  for _, m in ipairs(step.mem or {}) do
    if m.q and C_QuestLog.GetLogIndexForQuestID(m.q) then return m.q end
  end
  return step.q
end

-- the lines Chronicle will play for this step (empty for a quest you haven't taken yet)
function C.keys(step)
  local api = C.isOn() and lib()
  local q = api and questOf(step)
  if not q then return {} end
  local ok, keys = pcall(api.QuestKeys, api, q)
  return ok and type(keys) == "table" and keys or {}
end

function C.playing()
  local api = lib()
  local ok, on = pcall(function() return api and api:IsPlaying() end)
  return ok and on or false
end

-- Listen / Stop
function C.toggle(step)
  local api = lib()
  if not api then return end
  if C.playing() then pcall(api.Stop, api) return end
  local keys = C.keys(step)
  if #keys > 0 then pcall(api.Play, api, keys) end
end
