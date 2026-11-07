-- The auction house: prices (a full scan when it opens, once every 15 minutes, and every search seen), a price line on
-- item tooltips, and a window beside the game's auction house with Sell, Your auctions and Shopping. Forever's auction
-- house is the modern one (C_AuctionHouse), stackable trade goods are commodities bought by quantity, a full scan
-- (ReplicateItems) is allowed every 15 minutes, posting and buying only work from a click, durations 1-3 are 2, 8 and
-- 24 hours, gear is priced in whole silver, and the newest listing at a price sells first, so a matching price is
-- enough (no undercut needed).
-- Saved: AuDHDDB.ah[realm] = { prices = { [itemID] = { p = cheapest each, t = time, d = { [day] = cheapest, 30 days } }
-- }, scanAt }, AuDHDDB.ahLists = { { name, items = { names } } }
local _, ns = ...
local A = {}
ns.auction = A

local SCAN_GAP = 15 * 60
local WAIT = 10            -- seconds for the auction house to answer a search
local DAYS = 30            -- days of cheapest prices kept: the history shown with Shift on a tooltip
local USUAL_DAYS = 7       -- the last days the usual price is the middle of
local DURATIONS = { { 1, "2 h" }, { 2, "8 h" }, { 3, "24 h" } }
local GAIN = 5000          -- the reminder: what the auction house adds over a vendor, in all (50s)

local function say(msg) print("|cff66ccffAuDHD|r: " .. msg) end
local function coins(c) return ns.services and ns.services.coins and ns.services.coins(c) or tostring(c) end
local function now() return time and time() or 0 end
local function log(e, f) if ns.log then ns.log.add(e, f) end end
local AH = C_AuctionHouse or {}
A.api = AH   -- (the smoke test)

-- an error in the window's own code is said in chat once and logged (AH_ERROR), never swallowed
local told = {}
local function failed(what, err)
  err = tostring(err)
  log("AH_ERROR", { e = what, err = err })
  if not told[err] then
    told[err] = true
    say(("the auction window hit an error (%s): %s. It's in your AuDHD log."):format(what, err))
  end
end
local function try(what, fn, ...)
  if not fn then return end
  local ok, err = pcall(fn, ...)
  if not ok then failed(what, err) end
end
local function guard(what, fn) return function(...) try(what, fn, ...) end end
A.failed = failed   -- (the smoke test)

-- ------------------------------------------------------------------ settings
function A.on() return not AuDHDDB.ahOff end
function A.scanOn() return not AuDHDDB.ahScanOff end
function A.tipsOn() return not AuDHDDB.ahTipsOff end
function A.remindOn() return not AuDHDDB.ahRemindOff end
-- the Sell list's red V and line, the bags' V/DE, and how close a vendor's price must be (within this % of the auction
-- price, or more)
function A.strikeOn() return not AuDHDDB.ahStrikeOff end
function A.bagMarksOn() return not AuDHDDB.ahBagMarksOff end
function A.cheapMarkOn() return not AuDHDDB.ahCheapOff end
function A.vendorWithin() return AuDHDDB.ahVendorWithin or 20 end
function A.setVendorWithin(v)
  v = tonumber(v)
  if not v then return end
  v = math.max(0, math.min(100, math.floor(v)))
  AuDHDDB.ahVendorWithin = v ~= 20 and v or nil
  A.changed()
end
function A.set(key, on) AuDHDDB[key] = not on or nil end

-- ------------------------------------------------------------------ prices
local function db()
  local r = GetRealmName and GetRealmName() or "?"
  AuDHDDB.ah = AuDHDDB.ah or {}
  AuDHDDB.ah[r] = AuDHDDB.ah[r] or {}
  local d = AuDHDDB.ah[r]
  d.prices = d.prices or {}
  return d
end
local function today() return math.floor(now() / 86400) end
-- an item's name, when the game knows it
local function nameOf(id)
  local f = C_Item and C_Item.GetItemNameByID
  local n = f and f(id)
  if not n then
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    n = info and info(id)
  end
  return type(n) == "string" and n ~= "" and n or nil
end
local byName, namedAt   -- name -> itemID, of items with a price
-- the cheapest price each for an item, seen now
function A.note(id, each)
  if not (id and each and each > 0) then return end
  local prices = db().prices
  local rec = prices[id] or {}
  rec.p, rec.t = math.floor(each), now()
  rec.n = rec.n or nameOf(id)   -- (a crate's bundles are named, not linked)
  if byName and rec.n then byName[rec.n] = id end
  rec.d = rec.d or {}
  local day = today()
  rec.d[day] = math.min(rec.d[day] or rec.p, rec.p)
  for k in pairs(rec.d) do if k <= day - DAYS then rec.d[k] = nil end end
  prices[id] = rec
  A.changed()
end
-- a price noted while the window is open: the lists show it straight away; and the bags' marks
local redrawSoon
function A.changed()
  if redrawSoon or not (C_Timer and C_Timer.After) then return end
  redrawSoon = true
  C_Timer.After(0.2, function()
    redrawSoon = false
    local p = A.pages and A.pages.sell
    if p and p.list then pcall(p.list.show) end
    if A.markBags then pcall(A.markBags) end
  end)
end
-- the latest cheapest price, when it was seen, and the usual price (the middle of the last days' cheapest)
function A.price(id)
  local rec = id and db().prices[id]
  if not rec then return nil end
  local days, from = {}, today() - USUAL_DAYS
  for k, v in pairs(rec.d or {}) do if k > from then days[#days + 1] = v end end
  table.sort(days)
  local usual = #days > 0 and days[math.floor((#days + 1) / 2)] or rec.p
  return rec.p, rec.t, usual
end
-- the price history: the lowest, middle and highest of each day's cheapest, over the days kept, and how many days
function A.history(id)
  local rec = id and db().prices[id]
  if not (rec and rec.d) then return nil end
  local days = {}
  for _, v in pairs(rec.d) do days[#days + 1] = v end
  if #days == 0 then return nil end
  table.sort(days)
  return days[1], days[math.floor((#days + 1) / 2)], days[#days], #days
end
local function ago(t)
  local s = now() - (t or 0)
  if s < 3600 then return "just now" end
  if s < 86400 then return math.floor(s / 3600) .. " h ago" end
  local d = math.floor(s / 86400)
  return d == 1 and "yesterday" or (d .. " days ago")
end
A.ago = ago

-- ------------------------------------------------------------------ searches, one at a time
-- A search is sent when the auction house's message system is ready and answered by its event; the next waits for it.
-- Every answer also teaches prices, whoever asked (our window or the game's).
local open = false
local queue, busy = {}, nil
local pump
local function finish(rows)
  local job = busy
  busy = nil
  if job and job.done then pcall(job.done, rows) end
  C_Timer.After(0, pump)
end
function pump()
  if busy or #queue == 0 then return end
  if not open then queue = {} return end
  if AH.IsThrottledMessageSystemReady and not AH.IsThrottledMessageSystemReady() then C_Timer.After(0.3, pump) return end
  local job = table.remove(queue, 1)
  busy = job
  local ok = pcall(job.send)
  if not ok then finish(nil) return end
  C_Timer.After(WAIT, function() if busy == job then finish(nil) end end)
end
local SORT = { { sortOrder = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0, reverseSort = false } }
local function sameKey(a, b)
  return a and b and a.itemID == b.itemID and (a.itemSuffix or 0) == (b.itemSuffix or 0)
end
-- one item's auctions, cheapest first: { { each, n, mine, id, link } }
local function commodityRows(id)
  local out = {}
  for i = 1, AH.GetNumCommoditySearchResults(id) or 0 do
    local r = AH.GetCommoditySearchResultInfo(id, i)
    if r and r.unitPrice then
      out[#out + 1] = { each = r.unitPrice, n = r.quantity or 1, mine = (r.numOwnerItems or 0) > 0 or r.containsOwnerItem, id = r.auctionID }
    end
  end
  table.sort(out, function(a, b) return a.each < b.each end)
  return out
end
-- A row is a bucket of `quantity` identical auctions, its buyout for one item, and PlaceBid buys one auction at it
local function itemRows(key)
  local out = {}
  for i = 1, AH.GetNumItemSearchResults(key) or 0 do
    local r = AH.GetItemSearchResultInfo(key, i)
    if r and r.buyoutAmount and r.buyoutAmount > 0 then
      local n = math.max(1, r.quantity or 1)
      out[#out + 1] = { each = r.buyoutAmount, total = r.buyoutAmount, n = n, mine = r.containsOwnerItem, id = r.auctionID, link = r.itemLink }
    end
  end
  table.sort(out, function(a, b) return a.each < b.each end)
  return out
end
local function cheapest(rows)
  return rows and rows[1] and rows[1].each
end
-- one item's auctions, then done(rows) (nil: no answer)
function A.search(key, done)
  if not (open and key) then if done then done(nil) end return end
  queue[#queue + 1] = { kind = "search", key = key, done = done,
    send = function() AH.SendSearchQuery(key, SORT, true) end }
  pump()
end
-- the items whose name has the text in it: { { key, each (cheapest), n (on sale), name } }
function A.browse(text, done)
  if not open then if done then done(nil) end return end
  queue[#queue + 1] = { kind = "browse", done = done, send = function()
    AH.SendBrowseQuery({ searchString = text, sorts = SORT, filters = {}, itemClassFilters = {} })
  end }
  pump()
end
local function browseRows()
  local out = {}
  for _, r in ipairs(AH.GetBrowseResults() or {}) do
    if r.itemKey then
      local info = AH.GetItemKeyInfo and AH.GetItemKeyInfo(r.itemKey)
      out[#out + 1] = { key = r.itemKey, each = r.minPrice, n = r.totalQuantity, name = info and info.itemName,
                        commodity = info and info.isCommodity, icon = info and info.iconFileID }
      if r.minPrice and r.minPrice > 0 then A.note(r.itemKey.itemID, r.minPrice) end
    end
  end
  return out
end

-- ------------------------------------------------------------------ the full scan
-- Every auction at once, once every 15 minutes (the server's limit). Read a few hundred a frame; items the game hasn't
-- loaded yet are read again for up to 30 seconds.
local scan
function A.nextScan() return math.max(0, (db().scanAt or 0) + SCAN_GAP - now()) end
function A.fullScan()
  if not (open and AH.ReplicateItems) or scan then return false end
  if A.nextScan() > 0 then return false end
  scan = { t0 = GetTime() }
  db().scanAt = now()
  AH.ReplicateItems()
  log("AH_SCAN", {})
  C_Timer.After(120, function() if scan and not scan.reading then scan = nil A.refresh() end end)
  A.refresh()
  return true
end
local function readScan()
  local s = scan
  if not s or s.reading then return end
  s.reading, s.low, s.i, s.n = true, {}, 0, AH.GetNumReplicateItems() or 0
  local function add(i)
    local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, id = AH.GetReplicateItemInfo(i)
    if not id then return false end
    if buyout and buyout > 0 then
      local each = buyout / math.max(1, count or 1)
      if not s.low[id] or each < s.low[id] then s.low[id] = each end
    end
    return true
  end
  local missing = {}
  local function done()
    for id, each in pairs(s.low) do A.note(id, each) end
    local n = 0
    for _ in pairs(s.low) do n = n + 1 end
    say(("auction house scanned: prices for %d items"):format(n))
    log("AH_SCANNED", { n = n, auctions = s.n })
    scan = nil
    A.refresh()
  end
  local function step()
    if scan ~= s then return end
    local stop = math.min(s.n - 1, s.i + 400)
    for i = s.i, stop do if not add(i) then missing[#missing + 1] = i end end
    s.i = stop + 1
    A.refresh()
    if s.i < s.n then C_Timer.After(0, step) return end
    -- the ones not loaded yet: once more after a moment
    if #missing > 0 and not s.retried then
      s.retried = true
      C_Timer.After(5, function()
        if scan ~= s then return end
        local again = missing
        missing = {}
        for _, i in ipairs(again) do add(i) end
        done()
      end)
      return
    end
    done()
  end
  step()
end
function A.scanText()
  if scan then
    if scan.reading then return ("Scanning: %d of %d auctions"):format(scan.i or 0, scan.n or 0) end
    return "Scanning: waiting for the auction house..."
  end
  local at, wait = db().scanAt, A.nextScan()
  local last = at and ("Last full scan " .. ago(at)) or "No full scan yet"
  return last .. (wait > 0 and (" (next in %d min)"):format(math.ceil(wait / 60)) or "")
end

-- ------------------------------------------------------------------ tooltips
-- "Auction: 1g 20s each (today)", and the usual price when it differs by a quarter or more
-- the item with a price by this name: kept names, the game's cache, then names for prices noted without one (every 30 s
-- at most)
function A.idByName(name)
  local prices = db().prices
  if byName and byName[name] and prices[byName[name]] then return byName[name] end
  local ok, id = pcall(C_Item.GetItemInfoInstant, name)
  if ok and type(id) == "number" and prices[id] then return id end
  if not byName or now() - (namedAt or 0) >= 30 then
    byName, namedAt = {}, now()
    for pid, rec in pairs(prices) do
      rec.n = rec.n or nameOf(pid)
      if rec.n then byName[rec.n] = pid end
    end
  end
  return byName[name]
end
local function tipLine(id)
  local p, t, usual = A.price(id)
  if not p then return nil end
  local text = coins(p) .. " each"
  if usual and math.abs(usual - p) >= p * 0.25 then text = text .. ", usually " .. coins(usual) end
  return "Auction", text .. " |cff999999(" .. ago(t) .. ")|r"
end
A.tipLine = tipLine
-- with Shift held, the history
local function addHistory(tip, id)
  local lo, mid, hi, n = A.history(id)
  if not (n and tip.AddLine) then return end
  if not IsShiftKeyDown() then tip:AddLine("<Shift> Historical", 0.6, 0.6, 0.6) return end
  tip:AddDoubleLine("Historical", ("lowest each day, %d day%s"):format(n, n == 1 and "" or "s"), 1, 0.82, 0, 0.6, 0.6, 0.6)
  tip:AddDoubleLine("  Low", coins(lo), 1, 1, 1, 1, 1, 1)
  tip:AddDoubleLine("  Mid", coins(mid), 1, 1, 1, 1, 1, 1)
  tip:AddDoubleLine("  High", coins(hi), 1, 1, 1, 1, 1, 1)
end
-- a crate's bundles: { { n, name } }. English text only
function A.bundles(text)
  local list = text and text:match("following list:(.*)")
  if not list then return nil end
  list = list:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  local out = {}
  for n, name in list:gmatch("%-%s*(%d+)%s+([^\n]+)") do
    out[#out + 1] = { n = tonumber(n), name = (name:gsub("%s+$", "")) }
  end
  return #out > 0 and out or nil
end
-- the tooltip's text so far: its left lines, else the tooltip data's
local function tipText(tip, data)
  local lines = {}
  local name = tip.GetName and tip:GetName()
  local count = tip.NumLines and tip:NumLines() or 0
  for i = 1, (name and count or 0) do
    local fs = _G[name .. "TextLeft" .. i]
    local t = fs and fs.GetText and fs:GetText()
    if type(t) == "string" then lines[#lines + 1] = t end
  end
  if #lines == 0 and data and type(data.lines) == "table" then
    for _, l in ipairs(data.lines) do if type(l.leftText) == "string" then lines[#lines + 1] = l.leftText end end
  end
  return table.concat(lines, "\n")
end
-- each bundle's cost at the auction house, the cheapest in green; "not seen" for an item without a price
local function addBundles(tip, text)
  local list = A.bundles(text)
  if not (list and tip.AddLine) then return end
  local rows, best = {}, nil
  for _, b in ipairs(list) do
    local id = A.idByName(b.name)
    local each = id and A.price(id)
    local r = { b = b, each = each, total = each and each * b.n }
    if r.total and (not best or r.total < best.total) then best = r end
    rows[#rows + 1] = r
  end
  tip:AddLine("Bundles at auction", 1, 0.82, 0)
  for _, r in ipairs(rows) do
    local left = ("  %d %s"):format(r.b.n, r.b.name)
    if r.total then
      local g = r == best and #rows > 1
      tip:AddDoubleLine(left, coins(r.total) .. " |cff999999(" .. coins(r.each) .. " each)|r",
        g and 0.25 or 1, 1, g and 0.25 or 1, 1, 1, 1)
    else
      tip:AddDoubleLine(left, "not seen at auction", 1, 1, 1, 0.6, 0.6, 0.6)
    end
  end
  tip:AddLine("<Alt-click> shop for a bundle", 0.6, 0.6, 0.6)
end
A.addBundles = addBundles
-- on the slot with the grey frame: what getting rid of it loses
local function addCheap(tip)
  local o = tip.GetOwner and tip:GetOwner()
  local x = o and cheapMarks[o]
  if not (x and x:IsShown() and cheapSlot and tip.AddLine) then return end
  tip:AddLine("Cheapest to get rid of (worth " .. coins(cheapSlot.value) .. ")", 0.7, 0.7, 0.7)
end
A.addCheap = addCheap
local function addTip(tip, id, data)
  if not (A.on() and A.tipsOn() and id and tip and tip.AddDoubleLine) then return end
  local l, r = tipLine(id)
  if l then tip:AddDoubleLine(l, r, 1, 0.82, 0, 1, 1, 1) end
  -- gear: what disenchanting it fetches on average, under the auction line
  local ok, de, unpriced = pcall(A.deValue, id)
  if ok and (de or unpriced) then
    tip:AddDoubleLine("Disenchant", de and ((unpriced and "about " or "") .. coins(de)) or "no prices yet", 1, 0.82, 0, 1, 1, 1)
  end
  if l then addHistory(tip, id) end
  pcall(addBundles, tip, tipText(tip, data))
end
A.addTip = addTip
local function hookTips()
  local function idOf(tip, data)
    if data and type(data.id) == "number" then return data.id end
    local get = tip.GetItem or (TooltipUtil and TooltipUtil.GetDisplayedItem)
    local ok, _, link = pcall(get, tip)
    return ok and link and tonumber(link:match("item:(%d+)")) or nil
  end
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data)
      if tip ~= GameTooltip and tip ~= ItemRefTooltip then return end
      pcall(addTip, tip, idOf(tip, data), data)
      if tip == GameTooltip then pcall(addCheap, tip) end
    end)
  elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetItem", function(self) pcall(addTip, self, idOf(self)) pcall(addCheap, self) end)
  end
end

-- ------------------------------------------------------------------ mail
-- A letter in the inbox: what its items fetch on the auction house in all, and with Shift the history's low, mid and
-- high in all. Items never seen there are counted, not priced
function A.mailWorth(index)
  if not (index and GetInboxItem and GetInboxItemLink) then return nil end
  local w = { total = 0, lo = 0, mid = 0, hi = 0, priced = 0, unseen = 0, items = 0, kinds = 0 }
  for j = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
    local link = GetInboxItemLink(index, j)
    local id = link and tonumber(link:match("item:(%d+)"))
    if id then
      local n = select(4, GetInboxItem(index, j)) or 1
      w.items, w.kinds = w.items + n, w.kinds + 1
      local p = A.price(id)
      if p then
        local lo, mid, hi = A.history(id)
        w.total = w.total + p * n
        w.lo, w.mid, w.hi = w.lo + (lo or p) * n, w.mid + (mid or p) * n, w.hi + (hi or p) * n
        w.priced = w.priced + 1
      else
        w.unseen = w.unseen + 1
      end
    end
  end
  return w.items > 0 and w or nil
end
-- one item alone already has its own price on its tooltip; a stack of one item gets the total only
local function addMailTip(tip, index)
  if not (A.on() and A.tipsOn() and tip and tip.AddDoubleLine) then return end
  local w = A.mailWorth(index)
  if not (w and w.items > 1) then return end
  if w.priced == 0 then
    tip:AddDoubleLine("Auction total", "not seen there yet", 1, 0.82, 0, 0.6, 0.6, 0.6)
  else
    local unseen = w.unseen > 0 and (" |cff999999(%d not seen there)|r"):format(w.unseen) or ""
    tip:AddDoubleLine("Auction total", coins(w.total) .. unseen, 1, 0.82, 0, 1, 1, 1)
    if w.kinds > 1 then
      if not IsShiftKeyDown() then
        tip:AddLine("<Shift> Historical", 0.6, 0.6, 0.6)
      else
        tip:AddDoubleLine("Historical", "in all, lowest each day", 1, 0.82, 0, 0.6, 0.6, 0.6)
        tip:AddDoubleLine("  Low", coins(w.lo), 1, 1, 1, 1, 1, 1)
        tip:AddDoubleLine("  Mid", coins(w.mid), 1, 1, 1, 1, 1, 1)
        tip:AddDoubleLine("  High", coins(w.hi), 1, 1, 1, 1, 1, 1)
      end
    end
  end
  if tip.Show then tip:Show() end
end
A.addMailTip = addMailTip
-- the inbox's letter buttons (HookScript: the game's own OnEnter runs first); the one hovered, so Shift can redo it
local mailHooked, mailHover = {}, nil
local function hookMail()
  for i = 1, INBOXITEMS_TO_DISPLAY or 7 do
    local b = _G["MailItem" .. i .. "Button"]
    if b and b.HookScript and not mailHooked[b] then
      mailHooked[b] = true
      b:HookScript("OnEnter", function(self)
        mailHover = self
        pcall(addMailTip, GameTooltip, self.index)
      end)
      b:HookScript("OnLeave", function(self) if mailHover == self then mailHover = nil end end)
    end
  end
end
A.hookMail = hookMail

-- ------------------------------------------------------------------ bag marks
-- In your bags, a red "V/DE" on what the Sell list marks with its red V: a vendor pays about what the auction house
-- does, so sell it at a vendor or disenchant it. Our own text on the game's bag buttons
local marks = {}   -- bag button -> its "V/DE"
function A.markIDs()
  local set = {}
  if not (A.on() and A.bagMarksOn()) then return set end
  local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  for _, e in ipairs(A.sellable()) do
    if A.vendorClose(A.price(e.id), select(11, get(e.link))) then set[e.id] = true end
  end
  return set
end
-- The stack in your bags worth least, to get rid of when you need room: the higher of the vendor price and the auction
-- price (not for bound items), times the count. Never what the route needs, quest items, ammo, bags or quivers, or an
-- item with no known value (no vendor price and never seen at auction: keys, class items). { bag, slot, value, link }
-- or nil
local NOT_JUNK = { [1] = true, [6] = true, [11] = true, [12] = true }   -- bags, projectiles, quivers, quest items
-- nor tools: any fishing pole (weapon subclass 20), and these, by id from the Codex: Mining Pick, Flint and Tinder (and
-- Forever's Ceremonial ones), Thieves' Tools, the shaman totems (and Forever's Twisted ones), the blacksmith hammers,
-- the enchanting rods, Arclight Spanner, Gyromatic Micro-Adjustor, Philosopher's Stone, the skinning knives
local TOOLS = {}
for _, id in ipairs({ 2901, 4471, 278083, 281044, 5060, 5175, 5176, 5177, 5178, 274044, 274045, 274046, 274047, 5956,
  285279, 285280, 285281, 6218, 6339, 11130, 11145, 16207, 6219, 10498, 9149, 7005, 269716 }) do TOOLS[id] = true end
function A.cheapestSlot()
  if not A.cheapMarkOn() then return nil end
  local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local best
  for _, bag in ipairs(ns.bagIDs()) do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      local link, id = info and info.hyperlink, info and info.itemID
      if link and id then
        local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(link)
        local need = ns.services and ns.services.routeNeeds and ns.services.routeNeeds(id)
        local tool = TOOLS[id] or (classID == 2 and subID == 20)
        if not NOT_JUNK[classID or -1] and not need and not tool then
          local n = info.stackCount or 1
          local vendor = select(11, get(link))
          local value = (type(vendor) == "number" and vendor > 0) and vendor * n or nil
          local ah = not info.isBound and A.price(id)
          if ah and ah * n > (value or 0) then value = ah * n end
          if value and (not best or value < best.value) then best = { bag = bag, slot = slot, value = value, link = link } end
        end
      end
    end
  end
  return best
end
local cheapMarks = {}   -- bag button -> its grey frame
local cheapSlot          -- the slot marked now
local function eachBagButton(fn)
  local frames = {}
  for i = 1, NUM_CONTAINER_FRAMES or 13 do frames[#frames + 1] = _G["ContainerFrame" .. i] end
  frames[#frames + 1] = ContainerFrameCombinedBags
  for _, f in ipairs(frames) do
    if f and f.IsShown and f:IsShown() then
      if f.EnumerateValidItems then
        for _, b in f:EnumerateValidItems() do fn(b, b.GetBagID and b:GetBagID(), b:GetID()) end
      else
        local name = f.GetName and f:GetName()
        for j = 1, 36 do
          local b = name and _G[name .. "Item" .. j]
          if b and b:IsShown() then fn(b, f:GetID(), b:GetID()) end
        end
      end
    end
  end
end
function A.markBags()
  local set   -- worked out at the first open bag's button: nothing while the bags are shut
  local itemID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
  eachBagButton(function(b, bag, slot)
    if not set then set, cheapSlot = A.markIDs(), A.cheapestSlot() end
    local x = cheapMarks[b]
    if cheapSlot and bag == cheapSlot.bag and slot == cheapSlot.slot then
      if not x then
        -- a grey frame round the slot
        x = CreateFrame("Frame", nil, b)
        x:SetAllPoints(b)
        x:SetFrameLevel((b:GetFrameLevel() or 0) + 5)
        local W = 3
        for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, W }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, W },
                             { "TOPLEFT", "BOTTOMLEFT", W, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", W, 0 } }) do
          local t = x:CreateTexture(nil, "OVERLAY")
          t:SetColorTexture(0.8, 0.8, 0.8, 1)
          t:SetPoint(p[1]) t:SetPoint(p[2])
          if p[3] > 0 then t:SetWidth(p[3]) else t:SetHeight(p[4]) end
        end
        cheapMarks[b] = x
      end
      x:Show()
    elseif x then
      x:Hide()
    end
    local id = bag and slot and itemID(bag, slot)
    local fs = marks[b]
    if id and set[id] then
      if not fs then
        fs = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        fs:SetPoint("TOPLEFT", 2, -2)
        fs:SetTextColor(1, 0.13, 0.13)
        fs:SetText("V/DE")
        marks[b] = fs
      end
      fs:Show()
    elseif fs then
      fs:Hide()
    end
  end)
end
-- redone a moment after a bag opens or the game redraws one (its buttons are reused for other slots)
local function hookBagMarks()
  local function soon() A.changed() end
  for i = 1, NUM_CONTAINER_FRAMES or 13 do
    local f = _G["ContainerFrame" .. i]
    if f and f.HookScript then f:HookScript("OnShow", soon) end
    if f and type(f.UpdateItems) == "function" then hooksecurefunc(f, "UpdateItems", soon) end
  end
  local c = ContainerFrameCombinedBags
  if c and c.HookScript then c:HookScript("OnShow", soon) end
  if c and type(c.UpdateItems) == "function" then hooksecurefunc(c, "UpdateItems", soon) end
  if type(ContainerFrame_Update) == "function" then hooksecurefunc("ContainerFrame_Update", soon) end
end

-- ------------------------------------------------------------------ what you could sell
-- In your bags: not bound, not grey, not quest items, not what the route still needs or gear you'd wear. Grouped by
-- item: { { id, link, n, bag, slot, icon } }, by name
-- why the auction house won't take an item: damaged, else it doesn't say
local function refusedWhy(bag, slot)
  local f = (C_Container and C_Container.GetContainerItemDurability) or GetContainerItemDurability
  local ok, cur, max = false, nil, nil
  if f then ok, cur, max = pcall(f, bag, slot) end
  if ok and cur and max and cur < max then
    return ("Damaged (%d / %d): the auction house won't take damaged items. Repair it first"):format(cur, max)
  end
  return "The auction house won't take this item"
end
-- withRefused: also the items the auction house won't take, each with why (the Sell list shows them in grey)
function A.sellable(withRefused)
  local by, out = {}, {}
  for _, bag in ipairs(ns.bagIDs()) do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      local link = info and info.hyperlink
      if link and not info.isBound and (info.quality or 0) >= 1 and info.itemID then
        local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(link)
        local skip = classID == 12 or (ns.services and ns.services.routeNeeds and ns.services.routeNeeds(info.itemID))
          or (ns.auto and ns.auto.wouldWear and ns.auto.wouldWear(link))
        local refused
        if not skip and open and AH.IsSellItemValid and ItemLocation then
          local ok, valid = pcall(AH.IsSellItemValid, ItemLocation:CreateFromBagAndSlot(bag, slot), false)
          if ok and valid == false then
            if withRefused then refused = refusedWhy(bag, slot) else skip = true end
          end
        end
        if not skip then
          local key = refused and (info.itemID .. "r") or info.itemID
          local e = by[key]
          if not e then
            e = { id = info.itemID, link = link, n = 0, bag = bag, slot = slot, icon = info.iconFileID,
                  name = link:match("|h%[(.-)%]|h") or ("item " .. info.itemID), refused = refused }
            by[key] = e
            out[#out + 1] = e
          end
          e.n = e.n + (info.stackCount or 1)
        end
      end
    end
  end
  -- the refused ones last
  table.sort(out, function(a, b)
    if (a.refused and 1 or 0) ~= (b.refused and 1 or 0) then return not a.refused end
    return a.name < b.name
  end)
  return out
end
-- ------------------------------------------------------------------ disenchanting
-- What disenchanting gives (Classic item levels; not checked in Forever). Greens by item level: { up to, dust, its chance, count on
-- average, essence, chance, count, shard, chance } (a shard is 1); weapons swap the dust and essence chances
local GREEN = {
  { 15, 10940, .80, 1.5, 10938, .20, 1.5 },
  { 20, 10940, .75, 2.5, 10939, .20, 1.5, 10978, .05 },
  { 25, 10940, .75, 5, 10998, .15, 1.5, 10978, .10 },
  { 30, 11083, .75, 1.5, 11082, .20, 1.5, 11084, .05 },
  { 35, 11083, .75, 3.5, 11134, .20, 1.5, 11138, .05 },
  { 40, 11137, .75, 1.5, 11135, .20, 1.5, 11139, .05 },
  { 45, 11137, .75, 3.5, 11174, .20, 1.5, 11177, .05 },
  { 50, 11176, .75, 1.5, 11175, .20, 1.5, 11178, .05 },
  { 55, 11176, .75, 3.5, 16202, .20, 1.5, 14343, .05 },
  { 60, 16204, .75, 1.5, 16203, .20, 1.5, 14344, .05 },
  { 65, 16204, .75, 3.5, 16203, .20, 2.5, 14344, .05 },
}
-- weapons: { dust chance, essence chance, shard chance } (the rows not named: .20, .75, .05)
local WEAPON = { [15] = { .20, .80, 0 }, [25] = { .15, .75, .10 }, [55] = { .22, .75, .03 }, [60] = { .22, .75, .03 },
                 [65] = { .22, .75, .03 } }
-- blues and epics: { up to, { item, chance, count }... }
local BLUE = {
  { 25, { 10978, 1, 1 } }, { 30, { 11084, 1, 1 } }, { 35, { 11138, 1, 1 } }, { 40, { 11139, 1, 1 } },
  { 45, { 11177, 1, 1 } }, { 50, { 11178, 1, 1 } }, { 55, { 14343, 1, 1 } }, { 65, { 14344, .995, 1 }, { 20725, .005, 1 } },
}
local EPIC = {
  { 45, { 11177, 1, 3 } }, { 50, { 11178, 1, 3 } }, { 55, { 14343, 1, 3 } }, { 60, { 20725, 1, 1 } }, { 65, { 20725, 1, 1.5 } },
}
local NO_DE = { INVTYPE_BODY = true, INVTYPE_TABARD = true, [""] = true }
-- what an item gives: { { item, chance, count } }, or nil when it can't be disenchanted (or is past the tables)
function A.deYield(quality, ilvl, classID, equipLoc)
  if not (ilvl and (classID == 2 or classID == 4) and not NO_DE[equipLoc or ""]) then return nil end
  local weapon = classID == 2
  if quality == 2 then
    if ilvl < (weapon and 6 or 5) then return nil end
    for _, t in ipairs(GREEN) do
      if ilvl <= t[1] then
        local w = weapon and (WEAPON[t[1]] or { .20, .75, .05 })
        local out = { { t[2], w and w[1] or t[3], t[4] }, { t[5], w and w[2] or t[6], t[7] } }
        if t[8] then out[3] = { t[8], w and w[3] or t[9], 1 } end
        return out
      end
    end
  elseif quality == 3 or quality == 4 then
    if quality == 4 and ilvl < 40 then return nil end
    for _, t in ipairs(quality == 3 and BLUE or EPIC) do
      if ilvl <= t[1] then return { select(2, unpack(t)) } end
    end
  end
  return nil
end
-- what disenchanting it fetches at the auction house, on average; and whether a material had no price (the value is
-- then what the priced ones fetch, or nil when none had one)
function A.deValue(link)
  if not link then return nil end
  local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local _, _, quality, ilvl, _, _, _, _, equipLoc, _, _, classID = get(link)
  local yield = A.deYield(quality, ilvl, classID, equipLoc)
  if not yield then return nil end
  local value, unpriced, any = 0, false, false
  for _, y in ipairs(yield) do
    if y[2] > 0 then
      local p = A.price(y[1])
      if p then value, any = value + p * y[2] * y[3], true else unpriced = true end
    end
  end
  return any and math.floor(value) or nil, unpriced
end

-- a vendor pays within 20% (Settings) of the auction price, or more: not worth posting
function A.vendorClose(price, vendor)
  return (price and vendor and vendor > 0 and vendor >= price * (1 - A.vendorWithin() / 100)) and true or false
end
-- for the reminder: how many items would fetch more at the auction house than at a vendor, and how much more in all
function A.worthSelling()
  local items, gain = 0, 0
  for _, e in ipairs(A.sellable()) do
    local p = A.price(e.id)
    local vendor = select(11, C_Item.GetItemInfo(e.link)) or 0
    -- a price over 10x what a vendor pays is someone's odd listing, not what it sells for; patterns (recipes) are the
    -- exception, they do sell that high
    local recipe = select(6, C_Item.GetItemInfoInstant(e.link)) == 9
    if p and p > vendor * 1.5 and (recipe or p <= vendor * 10) and (p - vendor) * e.n >= 1000 then
      items = items + 1
      gain = gain + (p - vendor) * e.n
    end
  end
  return items, gain
end
function A.remindText()
  if not (A.on() and A.remindOn()) then return nil end
  local items, gain = A.worthSelling()
  if items == 0 or gain < GAIN then return nil end
  return ("Auction house: %d item%s worth about %s more than a vendor pays"):format(items, items == 1 and "" or "s", coins(gain)), items
end

-- ------------------------------------------------------------------ the window
local win
local shownTab = "sell"   -- the page shown
local pages = {}
A.pages = pages   -- (the smoke test)
local function button(parent, text, w, h)
  local b = ns.newFrame("Auction", "Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 90, h or 22)
  b:SetText(text)
  return b
end
local function label(parent, font)
  local f = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  f:SetJustifyH("LEFT")
  return f
end
local function editBox(parent, w)
  local e = ns.newFrame("Auction", "EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(w or 100, 20)
  e:SetAutoFocus(false)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return e
end
-- a price as gold, silver and copper boxes, each with its coin; SetText/GetText take and give "1g 20s 5c" like the one
-- box before it
local COIN = { "Interface\\MoneyFrame\\UI-GoldIcon", "Interface\\MoneyFrame\\UI-SilverIcon", "Interface\\MoneyFrame\\UI-CopperIcon" }
local function moneyBox(parent)
  local m, boxes = {}, {}
  local x = 0
  for i, w in ipairs({ 46, 30, 30 }) do
    local b = editBox(parent, w)
    b:SetNumeric(true)
    b:SetMaxLetters(i == 1 and 6 or 2)
    b:SetJustifyH("RIGHT")
    b.dx = x
    local c = parent:CreateTexture(nil, "ARTWORK")
    c:SetTexture(COIN[i])
    c:SetSize(13, 13)
    c:SetPoint("LEFT", b, "RIGHT", 2, 0)
    b:SetScript("OnTabPressed", function() boxes[i % 3 + 1]:SetFocus() end)
    boxes[i] = b
    x = x + w + 24
  end
  m.boxes = boxes
  function m:SetPoint(point, x0, y0)
    for _, b in ipairs(boxes) do b:SetPoint(point, x0 + b.dx, y0) end
  end
  function m:SetText(text)
    local c = A.parseMoney(text)
    local g, sv, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    boxes[1]:SetText(g > 0 and tostring(g) or "")
    boxes[2]:SetText((sv > 0 or (g > 0 and cp > 0)) and tostring(sv) or "")
    boxes[3]:SetText(cp > 0 and tostring(cp) or "")
  end
  function m:GetText()
    local c = 0
    for i, mult in ipairs({ 10000, 100, 1 }) do c = c + (tonumber(boxes[i]:GetText() or "") or 0) * mult end
    return c > 0 and A.plainMoney(c) or ""
  end
  return m
end
-- "1g 20s 5c", "1.5g", "120s" or plain copper -> copper
function A.parseMoney(text)
  text = (text or ""):lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  local total, found = 0, false
  for n, unit in text:gmatch("([%d%.]+)%s*([gsc])") do
    local v = tonumber(n)
    if v then
      found = true
      total = total + v * (unit == "g" and 10000 or unit == "s" and 100 or 1)
    end
  end
  if not found then total = tonumber(text:match("^%s*(%d+)%s*$") or "") or 0 end
  return math.floor(total + 0.5)
end
local function plainMoney(c)
  c = math.floor(c or 0)
  local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "g" end
  if s > 0 then out[#out + 1] = s .. "s" end
  if k > 0 or #out == 0 then out[#out + 1] = k .. "c" end
  return table.concat(out, " ")
end
A.plainMoney = plainMoney
-- a list of rows with the mouse wheel: rows(page, n, height, make(row), fill(row, item))
local function rowList(parent, x, y, w, n, h, make, fill)
  local L = { items = {}, offset = 0, rows = {} }
  local box = ns.newFrame("Auction", "Frame", nil, parent)
  box:SetPoint("TOPLEFT", x, y)
  box:SetSize(w, n * h)
  box:EnableMouseWheel(true)
  for i = 1, n do
    local r = ns.newFrame("Auction", "Button", nil, box)
    r:SetSize(w, h)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * h)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    make(r)
    L.rows[i] = r
  end
  function L.show(items)
    L.items = items or L.items
    L.offset = math.max(0, math.min(L.offset, #L.items - n))
    for i, r in ipairs(L.rows) do
      local it = L.items[i + L.offset]
      r.item = it
      if it then fill(r, it) r:Show() else r:Hide() end
    end
  end
  box:SetScript("OnMouseWheel", function(_, d) L.offset = L.offset - d L.show() end)
  return L
end

-- Sell: your bags' sellable items; pick one, its cheapest price now is looked up, Post puts it up at that price
local sell = { duration = 3 }
local function stepOf(commodity)
  if commodity and AH.SupportsCopperValues and AH.SupportsCopperValues() then return 1 end
  return 100
end
local function location(id)
  for _, bag in ipairs(ns.bagIDs()) do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID == id and not info.isLocked and ItemLocation then
        return ItemLocation:CreateFromBagAndSlot(bag, slot)
      end
    end
  end
end
local function sellPick(e)
  local p = pages.sell
  sell.item, sell.pending = e, nil
  p.name:SetText(e and (e.link .. (e.n > 1 and (" x" .. e.n) or "")) or "Pick an item from your bags")
  p.qty:SetText(e and tostring(e.n) or "")
  p.price:SetText("")
  p.post:SetText("Post")
  p.post:SetEnabled(e and true or false)
  if not e then p.now:SetText("") return end
  local loc = location(e.id)
  local key = loc and AH.GetItemKeyFromItem and AH.GetItemKeyFromItem(loc)
  sell.commodity = loc and AH.GetItemCommodityStatus and AH.GetItemCommodityStatus(loc) == 2
  local stored = A.price(e.id)
  if stored then p.price:SetText(plainMoney(math.max(stepOf(sell.commodity), math.floor(stored / stepOf(sell.commodity)) * stepOf(sell.commodity)))) end
  p.now:SetText("Looking up the cheapest price now...")
  A.search(key, function(rows)
    if sell.item ~= e then return end
    local best = rows and rows[1]
    if not rows then
      p.now:SetText(stored and ("No answer: the price is from " .. ago(select(2, A.price(e.id)))) or "No answer from the auction house: type a price")
    elseif not best then
      p.now:SetText("None on sale now: you set the price" .. (stored and (" (it was " .. coins(stored) .. ")") or ""))
    else
      -- the newest at a price sells first: match the cheapest
      local step = stepOf(sell.commodity)
      local each = math.max(step, math.floor(best.each / step) * step)
      p.price:SetText(plainMoney(each))
      p.now:SetText(("Cheapest now %s each%s; %d on sale"):format(coins(best.each), best.mine and " (yours)" or "",
        (function() local n = 0 for _, r in ipairs(rows) do n = n + r.n end return n end)()))
    end
  end)
end
-- a post that didn't go up: said on the page and in chat, and logged
local POST_WAIT = 10   -- seconds for the auction house to answer a post
local function postFailed(why)
  local p = pages.sell
  sell.last, sell.pending = nil, nil
  if p then
    p.post:SetText("Post")
    p.now:SetText("|cffff4040Not posted: " .. why .. "|r")
  end
  say("not posted: " .. why)
  log("AH_POST_FAIL", { why = why })
end
A.postFailed = postFailed   -- (the smoke test)
local function sellPost()
  local p, e = pages.sell, sell.item
  if not e then p.now:SetText("Pick an item in the list first") return end
  local loc = location(e.id)
  if not loc then
    -- the game's own Sell tab holds (locks) an item put in it
    p.now:SetText("|cffff4040That item is gone from your bags, or locked (in the game's own Sell tab?)|r")
    say("that item isn't in your bags any more, or it's locked: take it out of the game's own Sell tab")
    return
  end
  -- read again now: an item's kind can be unknown until its data has loaded
  if AH.GetItemCommodityStatus then
    local ok, st = pcall(AH.GetItemCommodityStatus, loc)
    if ok and (st == 1 or st == 2) then sell.commodity = st == 2 end
  end
  local each = A.parseMoney(p.price:GetText())
  local qty = math.max(1, math.min(e.n, tonumber(p.qty:GetText()) or e.n))
  if each <= 0 then p.now:SetText("|cffff4040Type a price first, like 1g 20s|r") say("type a price first, like 1g 20s") return end
  local step = stepOf(sell.commodity)
  each = math.max(step, math.floor(each / step) * step)
  if sell.pending then
    -- the game asked to confirm (a price far under the usual)
    local s = sell.pending
    sell.pending = nil
    if s.commodity then AH.ConfirmPostCommodity(s.loc, s.duration, s.qty, s.each)
    else AH.ConfirmPostItem(s.loc, s.duration, s.qty, nil, s.each) end
    p.post:SetText("Post")
    return
  end
  local s = { loc = loc, duration = sell.duration, qty = qty, each = each, commodity = sell.commodity, id = e.id }
  sell.last, sell.uiError = s, nil
  if s.commodity then AH.PostCommodity(loc, s.duration, qty, each)
  else AH.PostItem(loc, s.duration, qty, nil, each) end
  p.now:SetText(("Posting %d for %s each..."):format(qty, coins(each)))
  log("AH_POST", { id = e.id, n = qty, each = each, commodity = s.commodity or nil })
  -- no answer at all: say so (it may still go up)
  C_Timer.After(POST_WAIT, function()
    if sell.last == s and not sell.pending then
      postFailed(sell.uiError or "no answer from the auction house (it may still go up: look in Your auctions)")
    end
  end)
end
local function sellDeposit()
  local p, e = pages.sell, sell.item
  if not (p and e) then return end
  local loc = location(e.id)
  local qty = math.max(1, math.min(e.n, tonumber(p.qty:GetText()) or e.n))
  local ok, dep
  if sell.commodity then ok, dep = pcall(AH.CalculateCommodityDeposit, e.id, sell.duration, qty)
  elseif loc then ok, dep = pcall(AH.CalculateItemDeposit, loc, sell.duration, qty) end
  p.deposit:SetText(ok and dep and ("Deposit " .. coins(dep)) or "")
end
-- what the Sell list shows: with Hide ticked, not the items a vendor pays about as much for (the red V); and how many
-- are hidden
function A.sellList()
  local out, hidden = {}, 0
  for _, e in ipairs(A.sellable(true)) do
    if AuDHDDB.ahHideClose and not e.refused and A.vendorClose(A.price(e.id), select(11, C_Item.GetItemInfo(e.link))) then
      hidden = hidden + 1
    else
      out[#out + 1] = e
    end
  end
  return out, hidden
end
local function sellPage(page)
  local p = {}
  pages.sell = p
  local head = label(page, "GameFontNormalSmall")
  head:SetPoint("TOPLEFT", 4, 0)
  head:SetText("In your bags (not what the route needs)")
  p.head = head
  p.hide = ns.newFrame("Auction", "CheckButton", nil, page, "UICheckButtonTemplate")
  p.hide:SetSize(22, 22)
  p.hide:SetPoint("TOPRIGHT", page, "TOPRIGHT", -2, 5)
  local hl = label(page, "GameFontNormalSmall")
  hl:SetPoint("RIGHT", p.hide, "LEFT", -2, 0)
  hl:SetText("Hide vendor/DE items")
  p.hide:SetScript("OnClick", guard("hide", function(self)
    AuDHDDB.ahHideClose = self:GetChecked() and true or nil
    p.refresh()
  end))
  p.hide:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Hide vendor/DE items")
    GameTooltip:AddLine("Leave out the items a vendor pays about as much for as the auction house (the red V and line)", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  p.hide:SetScript("OnLeave", function() GameTooltip:Hide() end)
  p.list = rowList(page, 0, -16, 420, 10, 20, function(r)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT", 2, 0)
    -- on the right: "V" (red, when a vendor pays about as much), the auction price (struck through in red then), and
    -- "(V: <what a vendor pays>)"
    r.vend = label(r)
    r.vend:SetPoint("RIGHT", -4, 0)
    r.vend:SetJustifyH("RIGHT")
    r.right = label(r)
    r.right:SetPoint("RIGHT", r.vend, "LEFT", -3, 0)
    r.right:SetJustifyH("RIGHT")
    r.flag = label(r)
    r.flag:SetPoint("RIGHT", r.right, "LEFT", -3, 0)
    r.strike = r:CreateTexture(nil, "OVERLAY")
    r.strike:SetColorTexture(1, 0.1, 0.1, 0.9)
    r.strike:SetHeight(1.5)
    r.strike:SetPoint("LEFT", r.right, "LEFT", -1, 0)
    r.strike:SetPoint("RIGHT", r.right, "RIGHT", 1, 0)
    r.strike:Hide()
    r.left = label(r)
    r.left:SetPoint("LEFT", 24, 0)
    r.left:SetPoint("RIGHT", r.flag, "LEFT", -4, 0)
    r.left:SetWordWrap(false)
    r:SetScript("OnClick", guard("pick an item", function(self)
      if self.item and not self.item.refused then sellPick(self.item) sellDeposit() end
    end))
    r:SetScript("OnEnter", function(self)
      if not self.item then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink(self.item.link:match("|H(item:[^|]+)|h") or self.item.link)
      if self.item.refused then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Can't be posted: " .. self.item.refused, 1, 0.3, 0.3, true)
      end
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end, function(r, e)
    r.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    if r.icon.SetDesaturated then r.icon:SetDesaturated(e.refused and true or false) end
    if e.refused then
      -- the auction house won't take it: grey, why on hover
      r.left:SetText("|cff808080[" .. e.name .. "]" .. (e.n > 1 and (" x" .. e.n) or "") .. "|r")
      r.right:SetText("|cff808080can't post|r")
      r.vend:SetText("")
      r.flag:SetText("")
      r.strike:Hide()
      return
    end
    r.left:SetText(e.link .. (e.n > 1 and (" |cffffffffx" .. e.n .. "|r") or ""))
    local price = A.price(e.id)
    local vendor = select(11, C_Item.GetItemInfo(e.link))
    local close = A.strikeOn() and A.vendorClose(price, vendor)
    -- the whole stack's worth, auction and vendor
    local n = math.max(1, e.n or 1)
    r.right:SetText(price and coins(price * n) or "|cff999999no price yet|r")
    local de, unpriced = A.deValue(e.link)
    local deText = de and (", DE: " .. (unpriced and "about " or "") .. "|r" .. coins(de) .. "|cff999999")
      or (unpriced and ", DE: no prices yet") or ""
    r.vend:SetText(vendor and ("|cff999999(V:|r %s|cff999999%s)|r"):format(vendor > 0 and coins(vendor * n) or "none", deText) or "")
    r.flag:SetText(close and "|cffff2020V|r" or "")
    r.strike:SetShown(close)
  end)
  p.name = label(page, "GameFontHighlight")
  p.name:SetPoint("TOPLEFT", 4, -226)
  p.name:SetWidth(420)
  p.now = label(page, "GameFontDisableSmall")
  p.now:SetPoint("TOPLEFT", 4, -244)
  p.now:SetWidth(420)
  local pl = label(page)
  pl:SetPoint("TOPLEFT", 4, -270)
  pl:SetText("Price each")
  p.price = moneyBox(page)
  p.price:SetPoint("TOPLEFT", 74, -264)
  local ql = label(page)
  ql:SetPoint("TOPLEFT", 280, -270)
  ql:SetText("How many")
  p.qty = editBox(page, 50)
  p.qty:SetPoint("TOPLEFT", 342, -264)
  p.qty:SetScript("OnTextChanged", function() pcall(sellDeposit) end)
  -- the last length used, kept; AuDHDDB.ahDuration, nil = 24 h
  sell.duration = DURATIONS[AuDHDDB.ahDuration or 3] and (AuDHDDB.ahDuration or 3) or 3
  p.dur = button(page, DURATIONS[sell.duration][2], 60)
  p.dur:SetPoint("TOPLEFT", 4, -294)
  p.dur:SetScript("OnClick", function(self)
    sell.duration = sell.duration % 3 + 1
    AuDHDDB.ahDuration = sell.duration ~= 3 and sell.duration or nil
    self:SetText(DURATIONS[sell.duration][2])
    pcall(sellDeposit)
  end)
  p.dur:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("How long it's up for")
    GameTooltip:AddLine("Click for 2, 8 or 24 hours. Longer costs a bigger deposit", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  p.dur:SetScript("OnLeave", function() GameTooltip:Hide() end)
  p.deposit = label(page, "GameFontDisableSmall")
  p.deposit:SetPoint("LEFT", p.dur, "RIGHT", 8, 0)
  p.post = button(page, "Post", 100)
  p.post:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, -294)
  p.post:SetEnabled(false)
  p.post:SetScript("OnClick", guard("post", function() sellPost() end))
  function p.refresh()
    local items, hidden = A.sellList()
    p.hide:SetChecked(AuDHDDB.ahHideClose and true or false)
    p.head:SetText("In your bags (not what the route needs)" .. (hidden > 0 and (" |cff999999" .. hidden .. " hidden|r") or ""))
    p.list.show(items)
    if not sell.item then p.now:SetText(#p.list.items == 0 and "Nothing in your bags the auction house will take" or "") end
    if sell.item then
      local still
      for _, e in ipairs(p.list.items) do if e.id == sell.item.id then still = e end end
      if not still then sellPick(nil) else sell.item.n = still.n end
    else
      p.name:SetText("Pick an item from your bags")
    end
  end
end

-- Your auctions: each with its price and whether someone is cheaper now; Cancel takes one down
local mine = { list = {}, checked = {} }
local function ownedRows()
  local out = {}
  for i = 1, AH.GetNumOwnedAuctions and AH.GetNumOwnedAuctions() or 0 do
    local a = AH.GetOwnedAuctionInfo(i)
    if a then
      out[#out + 1] = { id = a.auctionID, key = a.itemKey, link = a.itemLink, n = a.quantity or 1,
                        each = a.buyoutAmount, sold = a.status == 1, left = a.timeLeftSeconds }
    end
  end
  return out
end
function A.checkUndercuts()
  local seen = {}
  for _, a in ipairs(mine.list) do
    if not a.sold and a.key then
      local k = a.key.itemID .. ":" .. (a.key.itemSuffix or 0)
      if not seen[k] then
        seen[k] = true
        A.search(a.key, function(rows)
          mine.checked[k] = rows and { best = rows[1] } or false
          if pages.mine then pages.mine.refresh() end
        end)
      end
    end
  end
end
local function minePage(page)
  local p = {}
  pages.mine = p
  local head = label(page, "GameFontNormalSmall")
  head:SetPoint("TOPLEFT", 4, 0)
  head:SetText("Your auctions")
  p.list = rowList(page, 0, -16, 420, 13, 22, function(r)
    r.left = label(r)
    r.left:SetPoint("LEFT", 4, 0)
    r.left:SetWidth(150)
    r.left:SetWordWrap(false)
    r.mid = label(r)
    r.mid:SetPoint("LEFT", 158, 0)
    r.mid:SetWidth(110)
    r.mid:SetWordWrap(false)
    r.cancel = button(r, "Cancel", 58, 18)
    r.cancel.row = r
    r.cancel:SetPoint("RIGHT", -2, 0)
    r.cancel:SetScript("OnClick", function(self)
      local a = self.row.item
      if a and a.id then AH.CancelAuction(a.id) log("AH_CANCEL", {}) end
    end)
    r.cancel:SetScript("OnEnter", function(self)
      local a = self.row.item
      local cost = a and AH.GetCancelCost and AH.GetCancelCost(a.id)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText("Cancel this auction")
      if cost and cost > 0 then GameTooltip:AddLine("Costs " .. coins(cost), 1, 1, 1) end
      GameTooltip:AddLine("The item comes back by mail", 1, 1, 1)
      GameTooltip:Show()
    end)
    r.cancel:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end, function(r, a)
    r.left:SetText((a.link or "?") .. (a.n > 1 and (" |cffffffffx" .. a.n .. "|r") or ""))
    local k = a.key and (a.key.itemID .. ":" .. (a.key.itemSuffix or 0))
    local c = k and mine.checked[k]
    local text = a.each and coins(a.each) or "bid only"
    if a.sold then text = "|cff33ff33sold|r"
    elseif c and c.best and a.each and c.best.each < a.each and not c.best.mine then
      text = text .. " |cffff4040(" .. coins(c.best.each) .. " now)|r"
    elseif c and c.best then
      text = text .. " |cff33ff33cheapest|r"
    end
    r.mid:SetText(text)
    r.cancel:SetShown(not a.sold)
  end)
  p.check = button(page, "Check prices", 110)
  p.check:SetPoint("TOPLEFT", 4, -310)
  p.check:SetScript("OnClick", function() A.checkUndercuts() end)
  p.check:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Check prices")
    GameTooltip:AddLine("Looks up each item: red means someone is cheaper now. Cancel and post it again to match", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  p.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
  p.note = label(page, "GameFontDisableSmall")
  p.note:SetPoint("LEFT", p.check, "RIGHT", 8, 0)
  p.note:SetWidth(210)
  function p.refresh()
    p.list.show(mine.list)
    p.note:SetText(#mine.list == 0 and "No auctions up" or (#mine.list .. " up"))
  end
  function p.shown()
    if open and AH.QueryOwnedAuctions then pcall(AH.QueryOwnedAuctions, {}) end
  end
end

-- Shopping: lists of item names; Search all finds each one's cheapest, Buy gets the cheapest
local shop = { found = {} }
local function lists()
  AuDHDDB.ahLists = AuDHDDB.ahLists or { { name = "Shopping", items = {} } }
  if #AuDHDDB.ahLists == 0 then AuDHDDB.ahLists[1] = { name = "Shopping", items = {} } end
  return AuDHDDB.ahLists
end
local function currentList()
  local all = lists()
  shop.index = math.min(shop.index or AuDHDDB.ahList or 1, #all)
  return all[shop.index]
end
-- ------------------------------------------------------------------ the shopping banker
-- One character of the account shops for a crate's bundle: AuDHDDB.shopBanker, else this character's bank alt. Its list
-- in AuDHDDB.ahLists: { name = "<banker>'s shopping", owner = banker, items, want = { [item] = count }, from = { [item]
-- = who asked } }
function A.banker()
  local b = AuDHDDB.shopBanker
  if b and b ~= "" then return b end
  return ns.services and ns.services.bankAlt and ns.services.bankAlt() or nil
end
local function sameChar(a, b)
  local S = ns.services
  if S and S.sameChar then return S.sameChar(a, b) end
  return a == b
end
local function bankerList(who, make)
  if not who then return nil end
  local all = lists()
  for i, l in ipairs(all) do if l.owner and sameChar(l.owner, who) then return l, i end end
  if not make then return nil end
  local l = { name = who .. "'s shopping", owner = who, items = {}, want = {}, from = {} }
  all[#all + 1] = l
  return l, #all
end
-- this character's list as the banker, and its place among the lists
function A.myList()
  local me = ns.services and ns.services.me and ns.services.me()
  return bankerList(me)
end
-- how many of an item are in your bags
local function haveOf(name)
  local f = shop.found[name:lower()]
  local id = f and f.key and f.key.itemID or A.idByName(name)
  local count = (C_Item and C_Item.GetItemCount) or GetItemCount
  local ok, n = pcall(count, id or name)
  return ok and type(n) == "number" and n or 0
end
A.haveOf = haveOf
-- n of an item onto the banker's list (added to what it already wants)
function A.addBundle(n, item, crate)
  local who = A.banker()
  if not who then say("set a shopping banker first: Settings, Auction house") return false end
  local l = bankerList(who, true)
  l.want, l.from = l.want or {}, l.from or {}
  local name
  for _, x in ipairs(l.items) do if x:lower() == item:lower() then name = x break end end
  if not name then
    name = item
    l.items[#l.items + 1] = name
    table.sort(l.items, function(a, b) return a:lower() < b:lower() end)
  end
  l.want[name] = (l.want[name] or 0) + n
  l.from[name] = ns.services and ns.services.me and ns.services.me() or nil
  say(("%d %s added to %s (%d wanted)"):format(n, name, l.name, l.want[name]))
  log("AH_BUNDLE", { n = n, crate = crate })
  if pages.shop then pages.shop.refresh() end
  return true
end
-- on the banker at login: what its list still wants, and from whom
function A.bankerText()
  local l = A.myList()
  if not (l and l.want) then return nil end
  local n, from, seen = 0, {}, {}
  for _, name in ipairs(l.items) do
    local w = l.want[name]
    if w and haveOf(name) < w then
      n = n + 1
      local f = l.from and l.from[name]
      if f and not seen[f] then seen[f] = true from[#from + 1] = f end
    end
  end
  if n == 0 then return nil end
  return ("Shopping list: %d item%s%s"):format(n, n == 1 and "" or "s",
    #from > 0 and (" (from " .. table.concat(from, ", ") .. ")") or "")
end
-- a small menu at the mouse: a title, then rows { text, onClick }, then Cancel
local menu
function A.menu(title, rows)
  if not menu then
    menu = ns.newFrame("Auction", "Frame", "AuDHDBundleMenu", UIParent, "BackdropTemplate")
    if menu.SetBackdrop then
      menu:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                         tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      menu:SetBackdropColor(0, 0, 0, 0.95)
    end
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu.title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    menu.title:SetPoint("TOPLEFT", 10, -8)
    menu.lines = {}
    menu:Hide()
  end
  menu.title:SetText(title)
  local all = {}
  for _, r in ipairs(rows) do all[#all + 1] = r end
  all[#all + 1] = { "|cff999999Cancel|r", function() end }
  for i, it in ipairs(all) do
    local b = menu.lines[i]
    if not b then
      b = ns.newFrame("Auction", "Button", nil, menu)
      b:SetSize(260, 18)
      b:SetPoint("TOPLEFT", 6, -24 - (i - 1) * 18)
      b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      b.text:SetPoint("LEFT", 4, 0)
      menu.lines[i] = b
    end
    b.text:SetText(it[1])
    b:SetScript("OnClick", function() menu:Hide() pcall(it[2]) end)
    b:Show()
  end
  for i = #all + 1, #menu.lines do menu.lines[i]:Hide() end
  menu:SetSize(272, 32 + #all * 18)
  menu:ClearAllPoints()
  local x, y = 0, 0
  if GetCursorPosition then x, y = GetCursorPosition() end
  local s = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
  if not s or s == 0 then s = 1 end
  menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (x or 0) / s, (y or 0) / s)
  menu:Show()
  return menu
end
A.menuFrame = function() return menu end   -- (the smoke test)
-- Alt-click on a crate: pick a bundle for the banker's list
function A.crateClick(link)
  if not (link and ns.auto and ns.auto.tooltipLines) then return false end
  local text = {}
  for _, l in ipairs(ns.auto.tooltipLines(link)) do text[#text + 1] = l.t end
  local list = A.bundles(table.concat(text, "\n"))
  if not list then return false end
  local crate = link:match("|h%[(.-)%]|h") or text[1]
  local rows = {}
  for _, b in ipairs(list) do
    local id = A.idByName(b.name)
    local each = id and A.price(id)
    rows[#rows + 1] = { ("%d %s  %s"):format(b.n, b.name, each and coins(each * b.n) or "|cff999999not seen|r"),
      function() A.addBundle(b.n, b.name, crate) end }
  end
  local who = A.banker()
  A.menu("Shop for a bundle, for " .. (who or "|cffff6060no banker set|r"), rows)
  return true
end
local function hookCrates()
  if not (hooksecurefunc and HandleModifiedItemClick) then return end
  hooksecurefunc("HandleModifiedItemClick", function(link)
    if not (A.on() and IsAltKeyDown and IsAltKeyDown()) then return end
    if (IsShiftKeyDown and IsShiftKeyDown()) or (IsControlKeyDown and IsControlKeyDown()) then return end
    pcall(A.crateClick, link)
  end)
end
function A.addToList(name)
  name = name and (name:match("|h%[(.-)%]|h") or name):gsub("^%s+", ""):gsub("%s+$", "")
  if not name or name == "" then return end
  local l = currentList()
  for _, n in ipairs(l.items) do if n:lower() == name:lower() then return end end
  l.items[#l.items + 1] = name
  table.sort(l.items, function(a, b) return a:lower() < b:lower() end)
end
local function shopFind(name, done)
  A.browse(name, function(rows)
    local exact
    for _, r in ipairs(rows and browseRows() or {}) do
      if r.name and r.name:lower() == name:lower() then exact = r break end
    end
    shop.found[name:lower()] = rows and (exact or false) or nil
    if done then done(exact) end
  end)
end
function A.searchList()
  for _, name in ipairs(currentList().items) do shopFind(name, function() if pages.shop then pages.shop.refresh() end end) end
end
-- Buy: trade goods get a quote first (Buy), then Confirm; other items buy the cheapest auction outright
local function shopPick(name)
  local p = pages.shop
  shop.pick, shop.quote, shop.auction = name, nil, nil
  p.buy:SetText("Buy")
  local f = name and shop.found[name:lower()]
  if not f then
    p.sel:SetText(name and (name .. ": search first, or none on sale") or "Pick an item from the list")
    p.buy:SetEnabled(false)
    return
  end
  p.sel:SetText(("%s: %s each, %d on sale"):format(name, coins(f.each or 0), f.n or 0))
  local w = currentList().want
  w = w and w[name]
  p.qty:SetText(f.commodity and tostring(w and math.max(1, w - haveOf(name)) or 1) or "")
  p.qty:SetShown(f.commodity and true or false)
  p.buy:SetEnabled(true)
  if not f.commodity then
    p.buy:SetEnabled(false)
    A.search(f.key, function(rows)
      if shop.pick ~= name then return end
      local best
      for _, r in ipairs(rows or {}) do if not r.mine then best = r break end end
      shop.auction = best
      if best then
        p.buy:SetText("Buy for " .. plainMoney(best.total or best.each))
        p.buy:SetEnabled(true)
      else
        p.sel:SetText(name .. ": none to buy (only yours, or none)")
      end
    end)
  end
end
local function shopBuy()
  local p, name = pages.shop, shop.pick
  local f = name and shop.found[name:lower()]
  if not f then return end
  if f.commodity then
    local qty = math.max(1, tonumber(p.qty:GetText()) or 1)
    if shop.quote and shop.quote.qty == qty then
      AH.ConfirmCommoditiesPurchase(f.key.itemID, qty)
      shop.quote = nil
      p.buy:SetText("Buying...")
      return
    end
    shop.quote = { qty = qty, asked = true }
    AH.StartCommoditiesPurchase(f.key.itemID, qty)
    p.buy:SetText("Getting a price...")
  elseif shop.auction then
    AH.PlaceBid(shop.auction.id, shop.auction.total or shop.auction.each)
    p.buy:SetText("Buying...")
    log("AH_BUY", { id = f.key.itemID })
  end
end
local listPicker
local function pickList(anchor)
  if not listPicker then
    listPicker = ns.newFrame("Auction", "Frame", "AuDHDAuctionListPick", UIParent, "BackdropTemplate")
    listPicker:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                             tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    listPicker:SetBackdropColor(0, 0, 0, 0.95)
    listPicker:SetFrameStrata("FULLSCREEN_DIALOG")
    listPicker:EnableMouse(true)
    listPicker.lines = {}
    listPicker:Hide()
  end
  if listPicker:IsShown() then listPicker:Hide() return end
  local items = {}
  for i, l in ipairs(lists()) do items[#items + 1] = { l.name .. " |cff999999(" .. #l.items .. ")|r", function() shop.index = i AuDHDDB.ahList = i end } end
  items[#items + 1] = { "New list...", function() StaticPopup_Show("AUDHD_AH_NEWLIST") end }
  if #lists() > 1 then
    items[#items + 1] = { "|cffff6060Delete " .. currentList().name .. "|r", function()
      table.remove(lists(), shop.index)
      shop.index, AuDHDDB.ahList = 1, 1
    end }
  end
  for i, it in ipairs(items) do
    local b = listPicker.lines[i]
    if not b then
      b = ns.newFrame("Auction", "Button", nil, listPicker)
      b:SetSize(200, 18)
      b:SetPoint("TOPLEFT", 8, -6 - (i - 1) * 18)
      b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      b.text:SetPoint("LEFT", 4, 0)
      listPicker.lines[i] = b
    end
    b.text:SetText(it[1])
    b:SetScript("OnClick", function() listPicker:Hide() pcall(it[2]) if pages.shop then pages.shop.refresh() end end)
    b:Show()
  end
  for i = #items + 1, #listPicker.lines do listPicker.lines[i]:Hide() end
  listPicker:SetSize(216, 12 + #items * 18)
  listPicker:ClearAllPoints()
  listPicker:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  listPicker:Show()
end
StaticPopupDialogs.AUDHD_AH_NEWLIST = {
  text = "Name for the new shopping list:", button1 = OKAY or "OK", button2 = CANCEL or "Cancel", hasEditBox = 1,
  OnAccept = function(self)
    local box = self.editBox or self.EditBox
    local name = box and box:GetText() or ""
    if name ~= "" then
      local all = lists()
      all[#all + 1] = { name = name, items = {} }
      shop.index, AuDHDDB.ahList = #all, #all
      if pages.shop then pages.shop.refresh() end
    end
  end,
  timeout = 0, whileDead = 1, hideOnEscape = 1,
}
local function shopPage(page)
  local p = {}
  pages.shop = p
  p.pick = button(page, "Shopping", 150)
  p.pick:SetPoint("TOPLEFT", 0, 2)
  p.pick:SetScript("OnClick", function(self) pickList(self) end)
  p.search = button(page, "Search all", 100)
  p.search:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, 2)
  p.search:SetScript("OnClick", function() A.searchList() end)
  p.list = rowList(page, 0, -26, 420, 10, 20, function(r)
    r.left = label(r)
    r.left:SetPoint("LEFT", 4, 0)
    r.left:SetWidth(240)
    r.left:SetWordWrap(false)
    r.right = label(r)
    r.right:SetPoint("RIGHT", -24, 0)
    r.right:SetJustifyH("RIGHT")
    r.del = ns.newFrame("Auction", "Button", nil, r, "UIPanelCloseButton")
    r.del:SetSize(20, 20)
    r.del.row = r
    r.del:SetPoint("RIGHT", 2, 0)
    r.del:SetScript("OnClick", function(self)
      local name = self.row.item
      local l = currentList()
      for i, n in ipairs(l.items) do if n == name then table.remove(l.items, i) break end end
      if l.want then l.want[name] = nil end
      if l.from then l.from[name] = nil end
      if shop.pick == name then shopPick(nil) end
      p.refresh()
    end)
    r:SetScript("OnClick", function(self) if self.item then shopPick(self.item) end end)
  end, function(r, name)
    local w = currentList().want
    w = w and w[name]
    if w then
      -- a banker's bundle: how many wanted and how many in your bags; green once you have them
      local have = haveOf(name)
      r.left:SetText(("%s%s|r |cffffd200%d|r |cff999999(have %d)|r"):format(have >= w and "|cff40ff40" or "", name, w, have))
    else
      r.left:SetText(name)
    end
    local f = shop.found[name:lower()]
    if f == nil then
      r.right:SetText("|cff999999not searched|r")
    elseif f == false then
      r.right:SetText("|cff999999none on sale|r")
    else
      r.right:SetText(coins(f.each or 0) .. " |cff999999(" .. (f.n or 0) .. ")|r")
    end
  end)
  p.add = editBox(page, 220)
  p.add:SetPoint("TOPLEFT", 8, -232)
  p.add:SetScript("OnEnterPressed", function(self)
    A.addToList(self:GetText())
    self:SetText("")
    p.refresh()
  end)
  local addB = button(page, "Add", 80)
  addB:SetPoint("LEFT", p.add, "RIGHT", 8, 0)
  addB:SetScript("OnClick", function()
    A.addToList(p.add:GetText())
    p.add:SetText("")
    p.add:ClearFocus()
    p.refresh()
  end)
  p.sel = label(page)
  p.sel:SetPoint("TOPLEFT", 4, -262)
  p.sel:SetWidth(420)
  p.qty = editBox(page, 50)
  p.qty:SetPoint("TOPLEFT", 8, -284)
  p.qty:Hide()
  p.buy = button(page, "Buy", 160)
  p.buy:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, -282)
  p.buy:SetEnabled(false)
  p.buy:SetScript("OnClick", function() shopBuy() end)
  function p.refresh()
    local l = currentList()
    ns.dropText(p.pick, l.name)
    p.list.show(l.items)
    if not shop.pick then p.sel:SetText(#l.items == 0 and "Type an item's name below and press Add" or "Pick an item from the list") end
  end
end

local TABS = { { "sell", "Sell", sellPage }, { "mine", "Your auctions", minePage }, { "shop", "Shopping", shopPage } }
local function showTab(key)
  shownTab = key
  for i, t in ipairs(TABS) do
    local on = t[1] == key
    win.pages[t[1]]:SetShown(on)
    if win.realTabs then
      if on then try("tab", PanelTemplates_SetTab, win, i) end
    elseif on then win.tabs[t[1]]:LockHighlight() else win.tabs[t[1]]:UnlockHighlight() end
  end
  local p = pages[key]
  if p and p.shown then try("show " .. key, p.shown) end
  if p and p.refresh then try("fill " .. key, p.refresh) end
end
A.showTab = function(key) if win then showTab(key) end end
-- The pages' tabs hang under the window like the game's own. The game's tab templates, the first this client has; plain
-- buttons if none
local TAB_TEMPLATES = { "PanelTabButtonTemplate", "CharacterFrameTabButtonTemplate" }
local function makeTab(i, text)
  local name = "AuDHDAuctionTab" .. i
  if PanelTemplates_SetTab then
    for _, tpl in ipairs(TAB_TEMPLATES) do
      local ok, b = pcall(ns.newFrame, "Auction", "Button", name, win, tpl)
      if ok and b and (b.Left or b.LeftActive or _G[name .. "Left"]) then
        b:SetID(i)
        b:SetText(text)
        if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, b, 0) end
        return b, true
      end
    end
  end
  return button(win, text, 104, 22), false
end
local function makeWindow()
  win = ns.newFrame("Auction", "Frame", "AuDHDAuction", UIParent, "BackdropTemplate")
  win:SetSize(462, 406)
  win:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                    tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
  win:SetFrameStrata("HIGH")
  win:EnableMouse(true)
  win:SetMovable(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)
  win:SetClampedToScreen(true)
  win:Hide()
  local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", 0, -16)
  title:SetText("AuDHD: auction house")
  local close = ns.newFrame("Auction", "Button", nil, win, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)
  win.status = label(win, "GameFontDisableSmall")
  win.status:SetPoint("TOPLEFT", 20, -38)
  win.status:SetWidth(240)
  win.scanB = button(win, "Full scan", 80, 20)
  win.scanB:SetPoint("TOPRIGHT", -20, -34)
  win.scanB:SetScript("OnClick", function()
    if not A.fullScan() then say(scan and "a scan is running" or ("the auction house allows a full scan once every 15 minutes: " .. math.ceil(A.nextScan() / 60) .. " min to go")) end
  end)
  win.pages, win.tabs, win.Tabs = {}, {}, {}
  local prev
  for i, t in ipairs(TABS) do
    local page = ns.newFrame("Auction", "Frame", nil, win)
    page:SetPoint("TOPLEFT", 20, -62)
    page:SetSize(422, 330)
    page:Hide()
    t[3](page)
    win.pages[t[1]] = page
    local tab, real = makeTab(i, t[2])
    if real then
      win.realTabs = true
      if prev then tab:SetPoint("LEFT", prev, "RIGHT", -15, 0) else tab:SetPoint("TOPLEFT", win, "BOTTOMLEFT", 12, 4) end
    else
      tab:SetPoint("TOPLEFT", win, "BOTTOMLEFT", 18 + (i - 1) * 112, 2)
    end
    tab:SetScript("OnClick", guard("tab " .. t[2], function()
      if PlaySound then pcall(PlaySound, SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB or 841) end
      showTab(t[1])
    end))
    win.tabs[t[1]], win.Tabs[i], prev = tab, tab, tab
  end
  if win.realTabs then try("tabs", PanelTemplates_SetNumTabs, win, #TABS) end
end
function A.refresh()
  if not (win and win:IsShown()) then return end
  win.status:SetText(A.scanText())
  win.scanB:SetEnabled(not scan and A.nextScan() == 0)
  local p = pages[shownTab]
  if p and p.refresh then try("fill " .. tostring(shownTab), p.refresh) end
end
function A.show()
  if not win then makeWindow() end
  win:ClearAllPoints()
  if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
    win:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, 0)
  else
    win:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
  end
  win:Show()
  showTab(shownTab)
  A.refresh()
end
function A.hide() if win then win:Hide() end end
function A.command(rest)
  rest = (rest or ""):lower()
  if rest == "scan" then
    if not open then return "open the auction house first" end
    if not A.fullScan() then return "a full scan is allowed once every 15 minutes: " .. math.ceil(A.nextScan() / 60) .. " min to go" end
    return "full scan started"
  elseif rest == "off" or rest == "on" then
    A.set("ahOff", rest == "on")
    if rest == "off" then A.hide() end
    return "auction house helper " .. rest
  elseif rest:match("^price ") then
    local q = rest:sub(7)
    local id = tonumber(q:match("item:(%d+)") or q)
    if not id then return "/audhd ah price <item id or link>" end
    local l, r = tipLine(id)
    return l and (l .. ": " .. r) or "no price for that item yet"
  end
  if not open then return "open the auction house, or /audhd ah scan|on|off|price <item>" end
  if win and win:IsShown() then A.hide() else A.show() end
end

-- ------------------------------------------------------------------ events
local frame = ns.newFrame("Auction", "Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "REPLICATE_ITEM_LIST_UPDATE",
                     "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
                     "AUCTION_HOUSE_BROWSE_FAILURE", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", "OWNED_AUCTIONS_UPDATED",
                     "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_HOUSE_POST_WARNING", "AUCTION_HOUSE_POST_ERROR", "AUCTION_CANCELED",
                     "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED",
                     "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_PURCHASE_COMPLETED", "BAG_UPDATE_DELAYED",
                     "AUCTION_HOUSE_SHOW_ERROR", "UI_ERROR_MESSAGE", "MODIFIER_STATE_CHANGED", "MAIL_SHOW" }) do
  pcall(frame.RegisterEvent, frame, e)
end
local handlers = {}
handlers.PLAYER_LOGIN = function()
  pcall(hookTips) pcall(hookMail) pcall(hookBagMarks) pcall(hookCrates) A.changed()
  C_Timer.After(12, function()
    local ok, text = pcall(A.bankerText)
    if ok and text then say(text) end
  end)
end
handlers.MAIL_SHOW = function() pcall(hookMail) end
handlers.AUCTION_HOUSE_SHOW = function()
  open = true
  if not A.on() then return end
  -- the banker: its shopping list first
  local ok, _, i = pcall(A.myList)
  if ok and i and A.bankerText() then shop.index = i end
  A.show()
  if A.scanOn() then C_Timer.After(1, function() if open then A.fullScan() end end) end
end
handlers.AUCTION_HOUSE_CLOSED = function()
  open, queue, busy = false, {}, nil
  if listPicker then listPicker:Hide() end
  if scan and not scan.reading then scan = nil end
  A.hide()
end
handlers.REPLICATE_ITEM_LIST_UPDATE = function()
  if not scan or scan.reading or scan.waiting then return end
  -- the list can come in parts: read once it has stopped growing for 2 seconds
  scan.waiting = true
  local last, still = -1, 0
  local function wait()
    if not scan then return end
    local n = AH.GetNumReplicateItems() or 0
    if n == last then still = still + 1 else still, last = 0, n end
    if still >= 4 then readScan() else C_Timer.After(0.5, wait) end
  end
  wait()
end
handlers.COMMODITY_SEARCH_RESULTS_UPDATED = function(id)
  local rows = commodityRows(id)
  if cheapest(rows) then A.note(id, cheapest(rows)) end
  if busy and busy.kind == "search" and busy.key and busy.key.itemID == id then finish(rows) end
end
handlers.ITEM_SEARCH_RESULTS_UPDATED = function(key)
  if type(key) ~= "table" then return end
  local rows = itemRows(key)
  if cheapest(rows) then A.note(key.itemID, cheapest(rows)) end
  if busy and busy.kind == "search" and sameKey(busy.key, key) then finish(rows) end
end
handlers.AUCTION_HOUSE_BROWSE_RESULTS_UPDATED = function()
  if busy and busy.kind == "browse" then finish(true) else pcall(browseRows) end
end
handlers.AUCTION_HOUSE_BROWSE_FAILURE = function() if busy and busy.kind == "browse" then finish(nil) end end
handlers.AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED = function()
  -- the game dropped our search: send it again in a moment
  local job = busy
  if job and not job.resent then
    job.resent = true
    C_Timer.After(1, function() if busy == job then pcall(job.send) end end)
  end
end
handlers.OWNED_AUCTIONS_UPDATED = function()
  mine.list = ownedRows()
  if pages.mine then pages.mine.refresh() end
end
handlers.AUCTION_HOUSE_AUCTION_CREATED = function()
  local s = sell.last
  if s then say(("posted %d for %s each"):format(s.qty, coins(s.each))) end
  sell.last, sell.pending = nil, nil
  if pages.sell then pages.sell.post:SetText("Post") end
  if open and AH.QueryOwnedAuctions then pcall(AH.QueryOwnedAuctions, {}) end
end
handlers.AUCTION_HOUSE_POST_WARNING = function()
  -- the game wants a second click (the price is far under the usual one)
  if sell.last and pages.sell then
    sell.pending = sell.last
    pages.sell.post:SetText("Confirm post")
    say("that price is well under the usual one: click Confirm post to put it up anyway")
  end
end
handlers.AUCTION_HOUSE_POST_ERROR = function()
  if sell.last then postFailed(sell.uiError or "the auction house refused it") end
end
-- while a post waits: the game's red error text (easy to miss at the top of the screen) is kept to say why, and the
-- auction house's own error ends it
handlers.MODIFIER_STATE_CHANGED = function(key)
  if not (key == "LSHIFT" or key == "RSHIFT") then return end
  if not (A.on() and A.tipsOn() and GameTooltip and GameTooltip:IsShown()) then return end
  -- a letter's tooltip is built by its button, not from item data: its OnEnter again (ours included)
  if mailHover and GameTooltip.GetOwner and GameTooltip:GetOwner() == mailHover then
    local enter = mailHover.GetScript and mailHover:GetScript("OnEnter")
    if enter then pcall(enter, mailHover) end
    return
  end
  if GameTooltip.RefreshData then pcall(GameTooltip.RefreshData, GameTooltip) end
end
handlers.UI_ERROR_MESSAGE = function(_, text)
  if sell.last and type(text) == "string" and not (issecretvalue and issecretvalue(text)) then sell.uiError = text end
end
handlers.AUCTION_HOUSE_SHOW_ERROR = function()
  if sell.last and not sell.pending then postFailed(sell.uiError or "the auction house refused it") end
end
handlers.AUCTION_CANCELED = function()
  if open and AH.QueryOwnedAuctions then pcall(AH.QueryOwnedAuctions, {}) end
end
handlers.COMMODITY_PRICE_UPDATED = function(each, total)
  local q = shop.quote
  if not (q and q.asked and pages.shop) then return end
  q.asked = false
  pages.shop.buy:SetText("Confirm: " .. plainMoney(total or 0))
  pages.shop.sel:SetText(("%d for %s in all (%s each): click Confirm to buy"):format(q.qty, coins(total or 0), coins(each or 0)))
end
handlers.COMMODITY_PRICE_UNAVAILABLE = function()
  shop.quote = nil
  if pages.shop then pages.shop.buy:SetText("Buy") pages.shop.sel:SetText("That price is gone: search again") end
end
local function bought(ok)
  if pages.shop then pages.shop.buy:SetText("Buy") end
  if ok then say("bought") else say("the purchase didn't go through") end
  shop.quote, shop.auction = nil, nil
  if shop.pick then local name = shop.pick shopFind(name, function() if pages.shop then pages.shop.refresh() shopPick(name) end end) end
end
handlers.COMMODITY_PURCHASE_SUCCEEDED = function() bought(true) end
handlers.COMMODITY_PURCHASE_FAILED = function() bought(false) end
handlers.AUCTION_HOUSE_PURCHASE_COMPLETED = function() bought(true) end
handlers.BAG_UPDATE_DELAYED = function()
  A.changed()
  if win and win:IsShown() and shownTab == "sell" and pages.sell then try("fill sell", pages.sell.refresh) end
end
frame:SetScript("OnEvent", function(_, event, ...)
  local h = handlers[event]
  if h then
    local ok, err = pcall(h, ...)
    if not ok then failed(event, err) end
  end
end)
