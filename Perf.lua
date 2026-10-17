-- /wfn perf: how much of your frame time the addon takes (the user, 2026-10-16: "we usually get 60fps we are getting
-- 13fps"). For 10 seconds each part's functions are timed (debugprofilestop), then: milliseconds per second of play for
-- each part, its slowest single call, and your frame rate over the same time. The functions are put back afterwards.
local _, ns = ...
local P = {}
ns.perf = P

-- the parts, by module and function name; the walk's run inside the arrow's and the maps' (not added to the total)
local PARTS = {
  { "arrow", "update", "Arrow" }, { "routemap", "drawWorld", "Map: route" }, { "routemap", "drawSpawnsWorld", "Map: spawns" },
  { "routemap", "drawRaresWorld", "Map: rares" }, { "routemap", "drawMinimap", "Minimap: route" },
  { "routemap", "drawSpawnsMinimap", "Minimap: spawns" }, { "walk", "path", "Walk: path search", true },
  { "walk", "toStep", "Walk: way to step", true }, { "rare", "scan", "Rares: units" }, { "rare", "checkSpawns", "Rares: spawn points" },
  { "drops", "scan", "Drop counts" }, { "range", "update", "Range" }, { "threat", "update", "Threat" },
  { "core", "advance", "GPS (advance)" }, { "ui", "refresh", "Window" },
  { "core", "repick", "GPS (pick)", true }, { "core", "roamTick", "Spawn hopping" }, { "core", "caveTick", "Caves" },
  { "imbue", "check", "Weapon / self buffs" }, { "services", "check", "Vendor pop-ups" },
}
local SECS = 10
local running = false

function P.run(report)
  if running then return "already timing" end
  if not debugprofilestop then return "this client can't time functions (no debugprofilestop)" end
  running = true
  local stats, saved = {}, {}
  for _, p in ipairs(PARTS) do
    local mod = ns[p[1]]
    local fn = mod and mod[p[2]]
    if type(fn) == "function" then
      local s = { name = p[3], ms = 0, n = 0, max = 0, inside = p[4] }
      stats[#stats + 1] = s
      saved[#saved + 1] = { mod, p[2], fn }
      mod[p[2]] = function(...)
        local t0 = debugprofilestop()
        local r = { pcall(fn, ...) }
        local dt = debugprofilestop() - t0
        s.ms, s.n = s.ms + dt, s.n + 1
        if dt > s.max then s.max = dt end
        if not r[1] then error(r[2], 0) end
        return (unpack or table.unpack)(r, 2)
      end
    end
  end
  -- the addon's memory (KB), before and after: a steady climb would be a leak
  local function mem()
    if not (UpdateAddOnMemoryUsage and GetAddOnMemoryUsage) then return nil end
    UpdateAddOnMemoryUsage()
    return GetAddOnMemoryUsage("AuDHD")
  end
  local mem0 = mem()
  local frames, start = 0, GetTime()
  local f = CreateFrame("Frame")
  f:SetScript("OnUpdate", function() frames = frames + 1 end)
  C_Timer.After(SECS, function()
    f:SetScript("OnUpdate", nil)
    for _, s in ipairs(saved) do s[1][s[2]] = s[3] end
    running = false
    local secs = math.max(0.1, GetTime() - start)
    table.sort(stats, function(a, b) return a.ms > b.ms end)
    local total = 0
    for _, s in ipairs(stats) do if not s.inside then total = total + s.ms end end
    report(("over %.0f s: %.0f fps; AuDHD used %.1f ms per second (%.1f%% of the time)"):format(secs, frames / secs,
      total / secs, total / secs / 10))
    local mem1 = mem()
    if mem0 and mem1 then
      report(("  memory: %.1f MB (%+.0f KB in %.0f s)"):format(mem1 / 1024, mem1 - mem0, secs))
    end
    for i = 1, math.min(8, #stats) do
      local s = stats[i]
      if s.n > 0 then report(("  %s: %.2f ms/s, %d calls, slowest %.1f ms"):format(s.name, s.ms / secs, s.n, s.max)) end
    end
    if ns.log then
      local parts = {}
      for i = 1, math.min(8, #stats) do
        local s = stats[i]
        if s.n > 0 then parts[#parts + 1] = { name = s.name, ms = math.floor(s.ms / secs * 100) / 100, n = s.n, max = math.floor(s.max * 10) / 10 } end
      end
      ns.log.add("PERF", { fps = math.floor(frames / secs), ms = math.floor(total / secs * 10) / 10, parts = parts,
                           memKB = mem1 and math.floor(mem1), memGrowKB = mem0 and mem1 and math.floor(mem1 - mem0) })
    end
  end)
  return ("timing for %d seconds: play as usual (open the world map too if that's when it's slow)"):format(SECS)
end
