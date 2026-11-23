-- Gathering checklist: a shopping list (Auction.lua) tracked as things to gather while you level or roam, in its own
-- small window beside the guide. Each row: the item, how many you carry of how many the list wants (ticked off as your
-- bags fill), and where it comes from: herb or ore nodes (GatherData.lua, with the skill they need), mobs that drop it
-- and vendors that sell it (the quest database), fishing, or not in our data. The nodes you still need show on the world
-- map and minimap (RouteMap.lua); the arrow points at the nearest one only when you ask (its button), and goes back to
-- the route when you close it. Settings can show every herb or ore node, and the ones you gathered (below).
-- /audhd gather [<list>|show|hide|stop]
local _, ns = ...
local G = {}
ns.gather = G

local function say(msg) print("|cff66ccffAuDHD|r: " .. msg) end
local function log(e, f) if ns.log then ns.log.add(e, f) end end
local function db()
  AuDHDDB.gather = AuDHDDB.gather or {}
  return AuDHDDB.gather
end

-- ------------------------------------------------------------------ what each item is
-- item name (lower case) -> { kinds = { kind }, p = "herb" or "mine", sk = the lowest skill of its nodes }
local byItem
local function nodeKinds(name)
  if not byItem then
    byItem = {}
    for k, v in pairs(ns.gatherKinds or {}) do
      local key = v[3]:lower()
      local e = byItem[key]
      if not e then
        e = { kinds = {}, p = v[4], sk = v[5] }
        byItem[key] = e
      end
      e.kinds[#e.kinds + 1] = k
      e.sk = math.min(e.sk, v[5])
    end
  end
  return byItem[name:lower()]
end
G.nodeKinds = nodeKinds
-- your Herbalism or Mining skill, or nil without it (the professions list first, else the skill list in English)
local LINES = { herb = { 182, "Herbalism" }, mine = { 186, "Mining" } }
function G.skill(p)
  local line = LINES[p]
  if not line then return nil end
  if GetProfessions and GetProfessionInfo then
    local a, b = GetProfessions()
    for _, i in ipairs({ a, b }) do
      local _, _, rank, _, _, _, id, mod = GetProfessionInfo(i)
      if id == line[1] and rank then return rank + (mod or 0) end
    end
  end
  if GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local name, header, _, rank, _, mod = GetSkillLineInfo(i)
      if not header and name == line[2] then return (rank or 0) + (mod or 0) end
    end
  end
  return nil
end
local function idOf(name)
  local A = ns.auction
  local id = A and A.idByName and A.idByName(name)
  if id then return id end
  local ok, iid = pcall(C_Item.GetItemInfoInstant, name)
  return ok and type(iid) == "number" and iid or nil
end
local function zoneName(m)
  local info = C_Map.GetMapInfo and C_Map.GetMapInfo(m)
  return info and info.name or ("map " .. m)
end
local function hereMap()
  local m = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  return m
end
-- how many nodes of these kinds each zone has: the best two zones as text
local function bestZones(kinds)
  local count = {}
  for m, zone in pairs(ns.gatherNodes or {}) do
    for _, k in ipairs(kinds) do
      if zone[k] then count[m] = (count[m] or 0) + #zone[k] / 4 end
    end
  end
  local list = {}
  for m, n in pairs(count) do list[#list + 1] = { m, n } end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  local out = {}
  for i = 1, math.min(2, #list) do out[i] = zoneName(list[i][1]) end
  return table.concat(out, ", ")
end
local function nodesIn(m, kinds)
  local zone = ns.gatherNodes and ns.gatherNodes[m]
  local n = 0
  if zone then for _, k in ipairs(kinds) do if zone[k] then n = n + #zone[k] / 4 end end end
  return n
end
-- the second line of a row: where the item comes from
function G.source(name)
  local nk = nodeKinds(name)
  if nk then
    local trade = nk.p == "herb" and "Herbalism" or "Mining"
    local have = G.skill(nk.p)
    local what = nk.p == "herb" and "Herb" or "Ore"
    if not have then return ("%s: needs %s %d (you don't have %s)"):format(what, trade, nk.sk, trade), false end
    if have < nk.sk then return ("%s: needs %s %d (you have %d)"):format(what, trade, nk.sk, have), false end
    local m = hereMap()
    local n = m and nodesIn(m, nk.kinds) or 0
    if n > 0 then return ("%s: %d spots in this zone, on your map"):format(what, n), true end
    return ("%s: none in this zone; most in %s"):format(what, bestZones(nk.kinds)), true
  end
  if ns.gatherCaught and ns.gatherCaught[name] then return "Fishing: which waters isn't in our data" end
  local Q = AuDHDEngine and AuDHDEngine.QuestDB
  local id = idOf(name)
  local item = Q and Q.GetItem and id and Q.GetItem(id)
  if item then
    if #item.droppers > 0 then
      local t = {}
      for i = 1, math.min(2, #item.droppers) do
        local d = item.droppers[i]
        t[i] = (d.name or ("mob " .. d.id)) .. (d.chance and (" " .. math.floor(d.chance + 0.5) .. "%") or "")
      end
      return "Drops from " .. table.concat(t, ", ") .. (#item.droppers > 2 and (" and " .. (#item.droppers - 2) .. " more") or "")
    end
    if #item.vendors > 0 then return "Vendor: " .. (item.vendors[1].name or "a vendor") end
    if #item.objects > 0 then return "From " .. (item.objects[1].name or "an object") end
  end
  if not id then return "Not known yet: hover over it once (bags, auction house) and it shows" end
  return "Not in our data: the auction house, or tell us where you found it (/audhd log)"
end

-- ------------------------------------------------------------------ the tracked list
local function list()
  local name = db().list
  if not name then return nil end
  for _, l in ipairs(AuDHDDB.ahLists or {}) do if l.name == name then return l end end
end
G.list = list
-- { { name, have, want (or nil), done } } in the list's order
function G.rows()
  local l = list()
  if not l then return {} end
  local A, out = ns.auction, {}
  for _, name in ipairs(l.items) do
    local want = l.want and l.want[name]
    local have = A and A.haveOf and A.haveOf(name) or 0
    out[#out + 1] = { name = name, have = have, want = want, done = want and have >= want or false }
  end
  return out
end
-- the node kinds still wanted, those your skill can gather: { [kind] = true }
function G.wantedKinds()
  local out = {}
  for _, r in ipairs(G.rows()) do
    local nk = not r.done and nodeKinds(r.name)
    if nk then
      local have = G.skill(nk.p)
      for _, k in ipairs(nk.kinds) do
        local v = ns.gatherKinds[k]
        out[k] = have ~= nil and have >= v[5]
      end
    end
  end
  return out
end
-- a zone's nodes of a kind, decoded once: { x, y } in 0..1
local decoded = {}
local function points(m, k)
  local key = m * 1000 + k
  local p = decoded[key]
  if p then return p end
  p = {}
  local s = ns.gatherNodes and ns.gatherNodes[m] and ns.gatherNodes[m][k]
  if s then
    for i = 1, #s - 3, 4 do
      local x, y = tonumber(s:sub(i, i + 1), 36), tonumber(s:sub(i + 2, i + 3), 36)
      if x and y then p[#p + 1] = { x / 1000, y / 1000 } end
    end
  end
  decoded[key] = p
  return p
end
G.points = points
-- ------------------------------------------------------------------ every node, and the ones you gathered
-- Settings' "All herb nodes" and "All ore nodes": every node of that sort we know on the maps, not only the tracked
-- list's. Each herb or ore you gather is remembered for the whole account (AuDHDDB.nodes[uiMapID]: { x, y in 0..1,
-- n = the item, p = "herb" or "mine", k = our kind when we know it, d = true when our data has that node too }) and
-- shown with them, so the nodes our data lacks fill in as you play
local ALL = { herb = "allHerbs", mine = "allOres" }
function G.allOn(p) return db()[ALL[p]] and true or false end
-- what G.nodes gave each map, until something it depends on changes (or 2 seconds: a list edited in the auction
-- helper): the minimap asks five times a second
local nodeCache = {}
function G.dirty() nodeCache = {} end
function G.setAll(p, on)
  db()[ALL[p]] = on or nil
  G.dirty()
  if ns.routemap and ns.routemap.refresh then pcall(ns.routemap.refresh) end
end
local NEAR = 0.005   -- (0..1 of the map: the same node)
local function near(ax, ay, bx, by) return math.abs(ax - bx) < NEAR and math.abs(ay - by) < NEAR end

-- the nodes to draw on a zone map: { { x, y, kind, ok, point, name =, p =, gathered = } } (ok: your skill gathers it;
-- point the decoded or remembered one, where the minimap keeps its world spot)
function G.nodes(m)
  local c = m and nodeCache[m]
  if c and GetTime() - c.t < 2 then return c.out end
  local out = {}
  if not m then return out end
  nodeCache[m] = { t = GetTime(), out = out }
  local skill = {}
  local function can(p, need)
    if skill[p] == nil then skill[p] = G.skill(p) or false end
    return skill[p] and skill[p] >= (need or 0) or false
  end
  local all = { herb = G.allOn("herb"), mine = G.allOn("mine") }
  local kinds = db().list and G.wantedKinds() or {}
  local zone = ns.gatherNodes and ns.gatherNodes[m]
  if zone and (all.herb or all.mine) then
    for k in pairs(zone) do
      local v = ns.gatherKinds[k]
      if v and all[v[4]] and kinds[k] == nil then kinds[k] = can(v[4], v[5]) end
    end
  end
  if zone then
    for k, ok in pairs(kinds) do
      for _, p in ipairs(points(m, k)) do out[#out + 1] = { p[1], p[2], k, ok, p } end
    end
  end
  local mem = type(AuDHDDB.nodes) == "table" and AuDHDDB.nodes[m]
  for _, r in ipairs(type(mem) == "table" and mem or {}) do
    -- (one our data has too is drawn once, as ours)
    if all[r.p] and not (r.d and r.k and kinds[r.k] ~= nil) then
      local v = r.k and ns.gatherKinds[r.k]
      out[#out + 1] = { r.x, r.y, r.k, can(r.p, v and v[5]), r, name = r.n, p = r.p, gathered = true }
    end
  end
  return out
end

-- a node you gathered, at x, y (0..1) on map m: kept unless one of the same sort is already there. -> the entry, new
function G.remember(m, x, y, item, p, object)
  if not (m and x and y and ALL[p]) then return nil end
  AuDHDDB.nodes = type(AuDHDDB.nodes) == "table" and AuDHDDB.nodes or {}
  local list = type(AuDHDDB.nodes[m]) == "table" and AuDHDDB.nodes[m] or {}
  AuDHDDB.nodes[m] = list
  for _, r in ipairs(list) do
    if r.p == p and near(r.x, r.y, x, y) then
      r.n = r.n or item
      return r, false
    end
  end
  -- its kind: the one whose node our data has here, else the item's first
  local nk = item and nodeKinds(item)
  local k, d
  if nk and nk.p == p then
    k = nk.kinds[1]
    for _, kk in ipairs(nk.kinds) do
      for _, q in ipairs(points(m, kk)) do
        if near(q[1], q[2], x, y) then k, d = kk, true break end
      end
      if d then break end
    end
  end
  local r = { x = math.floor(x * 10000 + 0.5) / 10000, y = math.floor(y * 10000 + 0.5) / 10000, n = item, p = p, k = k,
              o = object, d = d, t = GetServerTime and GetServerTime() }
  list[#list + 1] = r
  G.dirty()
  log("NODE_GATHERED", { n = item, p = p, k = k, o = object, known = d })
  if ns.routemap and ns.routemap.refresh then pcall(ns.routemap.refresh) end
  return r, true
end

-- a gather: the cast (Herbalism, as Forever names Herb Gathering, or Mining), then its loot window from a game object
local GATHER_SPELL = { [2366] = "herb", [2368] = "herb", [3570] = "herb", [11993] = "herb",
                       [2575] = "mine", [2576] = "mine", [3564] = "mine", [10248] = "mine" }
local GATHER_NAME = { ["Herb Gathering"] = "herb", Herbalism = "herb", Mining = "mine" }
local isSecret = issecretvalue or function() return false end
local castP, castAt
function G.onCast(unit, spellID)
  if unit ~= "player" or spellID == nil or isSecret(spellID) then return end
  local p = GATHER_SPELL[spellID]
  if not p and C_Spell and C_Spell.GetSpellName then
    local ok, name = pcall(C_Spell.GetSpellName, spellID)
    if ok and name and not isSecret(name) then p = GATHER_NAME[name] end
  end
  if p then castP, castAt = p, GetTime() end
end
function G.onLoot()
  if not (castP and GetTime() - castAt < 5) then return end
  local p = castP
  castP = nil
  local item, object
  for i = 1, (GetNumLootItems and GetNumLootItems() or 0) do
    local ok, guid = pcall(GetLootSourceInfo, i)
    if ok and type(guid) == "string" and not isSecret(guid) and guid:match("^GameObject") then
      local _, name = GetLootSlotInfo(i)
      if name and isSecret(name) then name = nil end
      local id = tonumber((select(6, strsplit("-", guid))))
      local nk = name and nodeKinds(name)
      -- the herb or ore itself rather than a stone or gem with it
      if not item or (nk and nk.p == p) then item, object = name, id end
      if nk and nk.p == p then break end
    end
  end
  if not object then return end
  local m = hereMap()
  local pos = m and C_Map.GetPlayerMapPosition(m, "player")
  if not pos then return end
  local x, y = pos:GetXY()
  if isSecret(x) then return end
  G.remember(m, x, y, item, p, object)
end

-- ------------------------------------------------------------------ the arrow, on request
local arrowOn, mine = false, nil
local visited = {}   -- nodes you've walked up to this session ("map:kind:i"): the arrow moves on to the next
local function worldOf(m, x, y)
  local ok, c, pos = pcall(C_Map.GetWorldPosFromMapPos, m, CreateVector2D(x, y))
  if ok and pos then return c, pos:GetXY() end
end
local function nearest()
  local m = hereMap()
  if not m then return nil end
  local pos = C_Map.GetPlayerMapPosition(m, "player")
  if not pos then return nil end
  local c, px, py = worldOf(m, pos:GetXY())
  if not c then return nil end
  local best, bd
  for k, ok in pairs(G.wantedKinds()) do
    if ok then
      for i, p in ipairs(points(m, k)) do
        local key = m .. ":" .. k .. ":" .. i
        if not visited[key] then
          local c2, x, y = worldOf(m, p[1], p[2])
          if c2 == c then
            local d = math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
            if d < 8 then visited[key] = true
            elseif not bd or d < bd then best, bd = { m = m, x = p[1] * 100, y = p[2] * 100, k = k }, d end
          end
        end
      end
    end
  end
  return best, bd
end
function G.arrowOn() return arrowOn end
function G.aim()
  if not arrowOn then return end
  if mine and ns.core.override ~= mine then   -- closed with the arrow's X, or another errand took it
    arrowOn, mine = false, nil
    if G.refresh then G.refresh() end
    return
  end
  local n = nearest()
  if not n then
    if mine then ns.core.override = nil end
    arrowOn, mine = false, nil
    say("no nodes you can gather left in this zone: the arrow follows the route again")
    if G.refresh then G.refresh() end
    return
  end
  if not (mine and mine.m == n.m and mine.x == n.x and mine.y == n.y) then
    mine = { m = n.m, x = n.x, y = n.y, t = "Gather: " .. ns.gatherKinds[n.k][1] }
    ns.core.override = mine
  end
end
function G.setArrow(on)
  if on and not ns.arrow then return end
  arrowOn = on and true or false
  if not arrowOn then
    if mine and ns.core.override == mine then ns.core.override = nil end
    mine = nil
  end
  G.aim()
  if G.refresh then G.refresh() end
end

-- ------------------------------------------------------------------ the window
local win, rowText = nil, {}
local ROW = 30
local function build()
  win = ns.share.window("AuDHDGatherWindow", 300, 120, "Gathering")
  win:SetFrameStrata("MEDIUM")
  if UISpecialFrames then   -- Escape leaves it up: it runs beside the guide
    for i = #UISpecialFrames, 1, -1 do if UISpecialFrames[i] == "AuDHDGatherWindow" then table.remove(UISpecialFrames, i) end end
  end
  local pos = db().pos
  if pos then
    win:ClearAllPoints()
    win:SetPoint(pos.p, UIParent, pos.rp, pos.x, pos.y)
  end
  win:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    db().pos = { p = p, rp = rp, x = x, y = y }
  end)
  win:HookScript("OnHide", function() if db().list and not win.quiet then db().hidden = true end end)
  win.status = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  win.status:SetPoint("TOPLEFT", 14, -30)
  win.status:SetWidth(272)
  win.status:SetJustifyH("LEFT")
  win.arrow = ns.newFrame("Gather", "Button", nil, win, "UIPanelButtonTemplate")
  win.arrow:SetSize(150, 22)
  win.arrow:SetPoint("BOTTOMLEFT", 12, 10)
  win.arrow:SetScript("OnClick", function() G.setArrow(not arrowOn) end)
  win.stop = ns.newFrame("Gather", "Button", nil, win, "UIPanelButtonTemplate")
  win.stop:SetSize(90, 22)
  win.stop:SetPoint("BOTTOMRIGHT", -12, 10)
  win.stop:SetText("Stop")
  win.stop:SetScript("OnClick", function() G.stop() end)
end
local function rowUI(i)
  local r = rowText[i]
  if r then return r end
  r = {}
  r.name = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.name:SetPoint("TOPLEFT", 14, -48 - (i - 1) * ROW)
  r.name:SetWidth(200)
  r.name:SetJustifyH("LEFT")
  r.count = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.count:SetPoint("TOPRIGHT", -14, -48 - (i - 1) * ROW)
  r.src = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  r.src:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 8, -1)
  r.src:SetWidth(266)
  r.src:SetJustifyH("LEFT")
  r.src:SetWordWrap(false)
  rowText[i] = r
  return r
end
local allDone
function G.refresh()
  if not win then return end
  local l = list()
  if not l then win.quiet = true win:Hide() win.quiet = nil return end
  local rows = G.rows()
  local left = 0
  for i, r in ipairs(rows) do
    local ui = rowUI(i)
    local src, can = G.source(r.name)
    ui.name:SetText((r.done and "|cff40ff40" or "") .. r.name .. (r.done and "|r" or ""))
    ui.count:SetText(r.want and ((r.done and "|cff40ff40%d/%d|r" or "%d/%d"):format(math.min(r.have, r.want), r.want)) or tostring(r.have))
    ui.src:SetText(r.done and "Done" or src)
    if can == false and not r.done then ui.src:SetTextColor(1, 0.45, 0.45) else ui.src:SetTextColor(0.6, 0.6, 0.6) end
    for _, f in pairs(ui) do f:Show() end
    if not r.done then left = left + 1 end
  end
  for i = #rows + 1, #rowText do for _, f in pairs(rowText[i]) do f:Hide() end end
  win:SetHeight(48 + #rows * ROW + 44)
  ns.share.setTitle(win, "Gathering: " .. l.name)
  win.status:SetText(left == 0 and "|cff40ff40Everything gathered|r" or (("%d left; the nodes you still need are on your map"):format(left)))
  if ns.arrow then
    win.arrow:Show()
    win.arrow:SetText(arrowOn and "Arrow: back to route" or "Arrow: nearest node")
  else
    win.arrow:Hide()
  end
  if left == 0 and #rows > 0 and allDone == false then
    say(("everything on %s is gathered"):format(l.name))
    if arrowOn then G.setArrow(false) end
  end
  allDone = left == 0
end

-- ------------------------------------------------------------------ start, stop, show
function G.track(name)
  local found
  for _, l in ipairs(AuDHDDB.ahLists or {}) do if l.name:lower() == (name or ""):lower() then found = l break end end
  if not found then say(("no shopping list called %s"):format(tostring(name))) return false end
  local g = db()
  g.list, g.hidden = found.name, nil
  allDone = nil
  G.dirty()
  if not win then build() end
  win:Show()
  G.refresh()
  if ns.routemap and ns.routemap.refresh then ns.routemap.refresh() end
  log("GATHER_TRACK", { n = #found.items })
  say(("tracking %s: the window shows what's left, the map shows the nodes"):format(found.name))
  return true
end
function G.stop()
  local g = db()
  g.list, g.hidden = nil, nil
  G.dirty()
  G.setArrow(false)
  if win then win.quiet = true win:Hide() win.quiet = nil end
  if ns.routemap and ns.routemap.refresh then ns.routemap.refresh() end
  log("GATHER_STOP", {})
end
function G.show(on)
  if not db().list then return "not tracking a list: pick one in the auction helper's list menu, or /audhd gather <list>" end
  db().hidden = not on or nil
  if not win then build() end
  if on then win:Show() G.refresh() else win.quiet = true win:Hide() win.quiet = nil end
  return on and "gathering window shown" or "gathering window hidden (still tracking; /audhd gather show)"
end
function G.command(rest)
  rest = (rest or ""):match("^%s*(.-)%s*$")
  if rest == "" or rest == "show" then return G.show(true) end
  if rest == "hide" then return G.show(false) end
  if rest == "stop" or rest == "off" then G.stop() return "gathering stopped" end
  if G.track(rest) then return nil end
  return nil
end
G.window = function() return win end   -- (the smoke test)

local ev = CreateFrame("Frame")
local pending
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:RegisterEvent("SKILL_LINES_CHANGED")
ev:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
ev:RegisterEvent("LOOT_OPENED")
ev:SetScript("OnEvent", function(_, event, a, _, c)
  if event == "UNIT_SPELLCAST_SUCCEEDED" then pcall(G.onCast, a, c) return end
  if event == "LOOT_OPENED" then
    local ok, err = pcall(G.onLoot)
    if not ok then log("NODE_ERROR", { err = tostring(err) }) end
    return
  end
  if event == "PLAYER_LOGIN" then
    local g = db()
    if g.list and list() and not g.hidden then
      build()
      win:Show()
      G.refresh()
    end
    C_Timer.NewTicker(1, function() if arrowOn then G.aim() end end)
    return
  end
  G.dirty()   -- (bags and skills: what's still wanted, what you can gather)
  if pending or not (win and win:IsShown()) then return end
  pending = true
  C_Timer.After(0.3, function() pending = nil G.refresh() end)
end)
