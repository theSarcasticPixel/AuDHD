-- Puts RouteFixes.lua into the guides as they register, or straight away if they got in first. Goals go into (or move
-- between) steps that are already there, never as new steps: the engine's walking data is numbered by step.
local _, ns = ...
local F = {}
ns.routeFix = F
F.missed = {}   -- what no longer matches the guides: looked at after each new guide version (tools/smoke_engine.mjs)

local function find(def, t, q)
  for s, step in ipairs(def.steps) do
    for g, goal in ipairs(step.goals) do
      if goal.t == t and goal.quest == q then return step, g, goal end
    end
  end
end
local function missed(id, what) F.missed[#F.missed + 1] = id .. ": " .. what end

local function lift(def, quests)
  local set = {}
  for _, q in ipairs(quests) do set[q] = true end
  for _, step in ipairs(def.steps) do
    local all = #step.goals > 0
    for _, goal in ipairs(step.goals) do
      if set[goal.quest] then goal.only = nil else all = false end
    end
    -- a step just for those quests, kept from the same races
    if all and step.only and step.only.races then step.only = nil end
  end
end

-- Every guide: a "Use item" goal with no quest is only ticked off by hand in the engine, so it stayed the step to do
-- after its work was done. It is for the quest goal after it in its step (notes and other such uses passed over): it
-- takes that goal's quest and objective, and is done when that objective is, or the quest is ready to hand in. One with
-- no quest goal after it stays a tick.
local QUEST_WORK = { collect = true, kill = true, complete = true, turnin = true, interact = true, use = true }
local function useQuests(def)
  local steps = rawget(def, "steps")
  if not steps then return 0 end
  local n = 0
  for _, step in ipairs(steps) do
    local goals = step.goals or {}
    for g, goal in ipairs(goals) do
      if goal.t == "use" and not goal.quest then
        for j = g + 1, #goals do
          local nxt = goals[j]
          if nxt.t ~= "note" and not (nxt.t == "use" and not nxt.quest) then
            if nxt.quest and QUEST_WORK[nxt.t] then
              goal.quest, goal.oi, goal.title = nxt.quest, nxt.oi, goal.title or nxt.title
              n = n + 1
            end
            break
          end
        end
      end
    end
  end
  return n
end
F.useQuests = useQuests   -- (the smoke test)

local patched = {}
local function patch(def)
  local fix = ns.routeFixes
  local id = def.id
  if patched[id] or not rawget(def, "steps") then return end
  patched[id] = true
  if fix.lift[id] then lift(def, fix.lift[id]) end
  for _, mv in ipairs(fix.move) do
    if mv.guide == id then
      local from
      for _, step in ipairs(def.steps) do
        for g, goal in ipairs(step.goals) do
          local named = mv.q and goal.quest == mv.q or (not mv.q and goal.item == mv.item)
          if goal.t == mv.t and named and not from then from = { step, g, goal } end
        end
      end
      local at = mv.after or mv.before
      if from then
        table.remove(from[1].goals, from[2])
        local step, g = find(def, at[1], at[2])
        if step then
          table.insert(step.goals, mv.after and g + 1 or g, from[3])
          -- a step left with none keeps a note, as for `drop`
          if #from[1].goals == 0 then from[1].goals[1] = { t = "note", text = mv.note or "Nothing to do here" } end
        else
          table.insert(from[1].goals, from[2], from[3])
          missed(id, "move to " .. at[1] .. " " .. at[2])
        end
      else
        missed(id, "move " .. mv.t .. " " .. (mv.q and ("quest " .. mv.q) or ("item " .. tostring(mv.item))))
      end
    end
  end
  -- a prerequisite the quest data leaves out, on every accept of that quest
  for _, p in ipairs(fix.pre or {}) do
    if p.guide == id then
      local n = 0
      for _, step in ipairs(def.steps) do
        for _, goal in ipairs(step.goals) do
          if goal.t == "accept" and goal.quest == p.q then
            goal.pre = { p.pre }
            goal.preTitles = { [p.pre] = p.title }
            n = n + 1
          end
        end
      end
      if n == 0 then missed(id, "pre for accept " .. p.q) end
    end
  end
  -- a quest out of the route: every goal of it. A step left with none keeps a note (the engine refuses a guide with an
  -- empty step); a note holds nothing, so the step counts as done and is passed
  for _, d in ipairs(fix.drop or {}) do
    if d.guide == id then
      local n = 0
      for _, step in ipairs(def.steps) do
        local had = #step.goals
        for g = #step.goals, 1, -1 do
          local goal = step.goals[g]
          if goal.quest == d.q and (not d.t or goal.t == d.t) then table.remove(step.goals, g) n = n + 1 end
        end
        if had > 0 and #step.goals == 0 then step.goals[1] = { t = "note", text = d.note or "Nothing to do here" } end
      end
      if n == 0 then missed(id, "drop " .. d.q) end
    end
  end
  for _, n in ipairs(fix.notes) do
    if n.guide == id then
      local _, _, goal = find(def, n.t, n.q)
      if goal then goal.note = n.note else missed(id, n.t .. " " .. n.q) end
    end
  end
  for _, a in ipairs(fix.add) do
    if a.guide == id then
      local at = a.after or a.before
      local step, g, anchor = find(def, at[1], at[2])
      if step then
        local first = a.after and g + 1 or g
        for k, goal in ipairs(a.goals) do
          -- a wait has no place of its own: stay where the hand-in was
          if goal.t == "wait" then goal.map, goal.x, goal.y, goal.f = anchor.map, anchor.x, anchor.y, anchor.f end
          table.insert(step.goals, first + k - 1, goal)
        end
      else
        missed(id, at[1] .. " " .. at[2])
      end
    end
  end
end

-- which guides have fixes
local wanted = {}
for id in pairs(ns.routeFixes.lift) do wanted[id] = true end
for _, n in ipairs(ns.routeFixes.notes) do wanted[n.guide] = true end
for _, mv in ipairs(ns.routeFixes.move) do wanted[mv.guide] = true end
for _, p in ipairs(ns.routeFixes.pre or {}) do wanted[p.guide] = true end
for _, d in ipairs(ns.routeFixes.drop or {}) do wanted[d.guide] = true end
for _, a in ipairs(ns.routeFixes.add) do wanted[a.guide] = true end
F.wanted = wanted

local E = AuDHDEngine
if E and E.RegisterGuide then
  local register = E.RegisterGuide
  E.RegisterGuide = function(def)
    if type(def) == "table" then
      if wanted[def.id] then patch(def) end
      pcall(useQuests, def)
    end
    return register(def)
  end
  for id in pairs(wanted) do
    local def = E.Guides and E.Guides.Get(id)
    if def then patch(def) end
  end
  for _, h in ipairs(E.Guides and E.Guides.List() or {}) do
    local def = h.id and E.Guides.Get(h.id)
    if def then pcall(useQuests, def) end
  end
end
