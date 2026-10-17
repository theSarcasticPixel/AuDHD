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
local HIDE_SECS = 3

-- fps with the addon's frames shown, then all hidden, then each file's alone hidden when that made a difference: a cost
-- the timer can't see (drawing: the user, 2026-10-17, "huge gpu usage")
local function fpsFor(secs, hide, done)
  local n, t0 = 0, GetTime()
  local f = CreateFrame("Frame")
  f:SetScript("OnUpdate", function()
    n = n + 1
    for _, fr in ipairs(hide) do if fr:IsShown() then fr:Hide() end end   -- the addon may show one again meanwhile
    if GetTime() - t0 >= secs then f:SetScript("OnUpdate", nil) done(n / (GetTime() - t0)) end
  end)
end
function P.hideTest(report, done)
  if InCombatLockdown and InCombatLockdown() then report("  (in combat: no hiding test)") done(nil) return end
  local shown, byFile, regions = {}, {}, 0
  for _, r in ipairs(ns.frames or {}) do
    local fr = r.f
    if r.file ~= "Perf" and fr:IsShown() and fr.Hide then
      shown[#shown + 1] = fr
      byFile[r.file] = byFile[r.file] or {}
      table.insert(byFile[r.file], fr)
      if fr:IsVisible() then regions = regions + (fr.GetNumRegions and fr:GetNumRegions() or 0) end
    end
  end
  local function restore(list) for _, fr in ipairs(list) do fr:Show() end end
  fpsFor(HIDE_SECS, {}, function(base)
    fpsFor(HIDE_SECS, shown, function(hidden)
      restore(shown)
      local hid = { base = math.floor(base), hidden = math.floor(hidden), frames = #(ns.frames or {}), shown = #shown, regions = regions }
      report(("  %d frames made, %d shown (%d textures and texts on screen); fps %.0f with them, %.0f all hidden")
        :format(hid.frames, hid.shown, regions, base, hidden))
      if hidden < base * 1.2 then done(hid) return end
      -- it's the addon: which file's frames
      local files = {}
      for file in pairs(byFile) do files[#files + 1] = file end
      table.sort(files)
      hid.files = {}
      local i = 0
      local function nextFile()
        i = i + 1
        local file = files[i]
        if not file then
          table.sort(hid.files, function(a, b) return a.fps > b.fps end)
          for k = 1, math.min(4, #hid.files) do
            report(("    hiding %s's %d frames: %.0f fps"):format(hid.files[k].file, hid.files[k].n, hid.files[k].fps))
          end
          done(hid)
          return
        end
        fpsFor(2, byFile[file], function(f)
          restore(byFile[file])
          hid.files[#hid.files + 1] = { file = file, n = #byFile[file], fps = math.floor(f) }
          nextFile()
        end)
      end
      nextFile()
    end)
  end)
end
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
  -- every frame's handlers, by file and script: the functions above miss whatever a file's own frames run
  -- (protected frames left alone: their scripts can't be swapped safely)
  local wrapped = {}
  for _, r in ipairs(ns.frames or {}) do
    local fr = r.f
    if r.file ~= "Perf" and not (fr.IsProtected and fr:IsProtected()) then
      for _, script in ipairs({ "OnUpdate", "OnEvent" }) do
        local fn = fr:GetScript(script)
        if fn then
          local key = r.file .. " " .. script
          local s = stats[key]
          if not s then s = { name = key .. " (handlers)", ms = 0, n = 0, max = 0, handler = true } stats[key] = s stats[#stats + 1] = s end
          local w = function(...)
            local t0 = debugprofilestop()
            fn(...)
            local dt = debugprofilestop() - t0
            s.ms, s.n = s.ms + dt, s.n + 1
            if dt > s.max then s.max = dt end
          end
          fr:SetScript(script, w)
          wrapped[#wrapped + 1] = { fr, script, fn, w }
        end
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
  local f = ns.newFrame("Perf", "Frame")
  f:SetScript("OnUpdate", function() frames = frames + 1 end)
  C_Timer.After(SECS, function()
    f:SetScript("OnUpdate", nil)
    for _, s in ipairs(saved) do s[1][s[2]] = s[3] end
    -- put the handlers back, unless the file swapped its own script meanwhile
    for _, w in ipairs(wrapped) do if w[1]:GetScript(w[2]) == w[4] then w[1]:SetScript(w[2], w[3]) end end
    local secs = math.max(0.1, GetTime() - start)
    table.sort(stats, function(a, b) return a.ms > b.ms end)
    local total = 0
    local listed, handlers = 0, 0
    for _, s in ipairs(stats) do
      if s.handler then handlers = handlers + s.ms elseif not s.inside then listed = listed + s.ms end
    end
    total = math.max(listed, handlers)
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
    local fps = frames / secs
    local parts = {}
    for i = 1, math.min(8, #stats) do
      local s = stats[i]
      if s.n > 0 then parts[#parts + 1] = { name = s.name, ms = math.floor(s.ms / secs * 100) / 100, n = s.n, max = math.floor(s.max * 10) / 10 } end
    end
    P.hideTest(report, function(hid)
      if ns.log then
        ns.log.add("PERF", { fps = math.floor(fps), ms = math.floor(total / secs * 10) / 10, parts = parts,
                             memKB = mem1 and math.floor(mem1), memGrowKB = mem0 and mem1 and math.floor(mem1 - mem0), hide = hid })
      end
      running = false
    end)
  end)
  return ("timing for %d seconds, then %d seconds with the addon's windows hidden: play as usual (open the world map too if that's when it's slow)"):format(SECS, HIDE_SECS * 2)
end
