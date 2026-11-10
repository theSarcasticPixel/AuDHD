-- Reminders when you pass a service: bags full or nearly full within 100 yards of a vendor - sell; class skills to
-- learn within 100 yards of your class trainer - train. Once per visit: it comes back after you've been 200 yards away
-- (or when it changes: bags filling up again, a new level's skills).
-- And a mailbox within 100 yards with BoEs or materials in your bags: mail them to your bank alt.
-- And a vendor that sells your arrows or bullets within 100 yards while you carry fewer than 800. And a profession's
-- next rank to learn within 500 yards of a trainer who teaches it.
local _, ns = ...
local M = {}
ns.services = M
local log = function(e, f) if ns.log then ns.log.add(e, f) end end
local isSecret = issecretvalue or function() return false end

local NEAR, AWAY = 100, 200
local PROF_NEAR, PROF_AWAY = 500, 700   -- profession trainers
local MAIL_MIN = 3   -- items worth a stop at the mailbox

-- world positions (yards), cached per entry
local function worldPos(m, x, y)
  local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, m, CreateVector2D(x, y))
  if not ok or not pos then return nil end
  local wx, wy = pos:GetXY()
  return cont, wx, wy
end
local function placeOf(e)
  if e.c == nil then
    local c, wx, wy = worldPos(e.m, e.x / 100, e.y / 100)
    e.c, e.wx, e.wy = c or false, wx, wy
  end
  return e.c and e
end
local function player()
  local m = C_Map.GetBestMapForUnit("player")
  if not m or isSecret(m) then return nil end
  local p = C_Map.GetPlayerMapPosition(m, "player")
  if not p then return nil end
  local px, py = p:GetXY()
  if isSecret(px) then return nil end
  local c, wx, wy = worldPos(m, px, py)
  return c and { c = c, wx = wx, wy = wy }
end
-- your side's letter ("A" / "H"): the other side's vendors, trainers and mailboxes are skipped
local function mySide()
  local f = UnitFactionGroup and UnitFactionGroup("player")
  return f == "Horde" and "H" or f == "Alliance" and "A" or nil
end
local function nearest(list, P)
  local best, bd
  local side = mySide()
  for _, e in ipairs(list or {}) do
    local w = (not e.f or not side or e.f == side) and placeOf(e)
    if w and w.c == P.c then
      local dx, dy = w.wx - P.wx, w.wy - P.wy
      local d = math.sqrt(dx * dx + dy * dy)
      if not bd or d < bd then best, bd = e, d end
    end
  end
  return best, bd
end

-- plain bags only (no quivers or ammo pouches): free slots and all slots
function M.bagSpace()
  local free, total = 0, 0
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    local n = C_Container.GetContainerNumSlots(bag) or 0
    local f, fam = C_Container.GetContainerNumFreeSlots(bag)
    if n > 0 and (not fam or fam == 0) then free, total = free + (f or 0), total + n end
  end
  return free, total
end
-- nearly full: 2 slots or a tenth of your bags left, whichever is more
function M.bagsFull()
  local free, total = M.bagSpace()
  return total > 0 and free <= math.max(2, math.floor(total / 10)), free
end

-- skills to learn now: what the Ammo module keeps back for them, when it's for your level
function M.skillsOwed()
  if not (ns.ammo and ns.ammo.trainReserve) then return false end
  local ok, cost, forLevel = pcall(ns.ammo.trainReserve)
  return ok and cost and cost > 0 and forLevel == UnitLevel("player") or false
end

-- ------------------------------------------------------------------ the bank alt
-- Each character's own alt mail settings: the mode, the bank alt, the rows, and the switches; all off for a character
-- until set. AuDHDDB.mailChars["Name-Realm"]
local cfgKey   -- (worked out once: the character doesn't change in a session)
local spare = { mailOff = true }   -- (before the game says who you are)
function M.cfg()
  AuDHDDB.mailChars = AuDHDDB.mailChars or {}
  if not cfgKey then
    local n, r = UnitName("player"), GetRealmName and GetRealmName()
    if not (n and r) then return spare end
    cfgKey = n .. "-" .. r
  end
  local key = cfgKey
  local c = AuDHDDB.mailChars[key]
  if not c then c = { mailOff = true } AuDHDDB.mailChars[key] = c end
  return c
end
-- Forever's characters are "Name Surname", and the real game's mail needs both. The offline server finds a character by
-- the first name alone, so a one-word name still works there.
local function firstName(n) return type(n) == "string" and n:match("^%s*([^%s]+)") or nil end
M.firstName = firstName
-- spaces tidied, each word capitalised: " bankie  smith " is "Bankie Smith"
local function cleanName(n)
  if type(n) ~= "string" then return nil end
  local words = {}
  for w in n:gmatch("%S+") do words[#words + 1] = (w:gsub("^%l", string.upper)) end
  return #words > 0 and table.concat(words, " ") or nil
end
M.cleanName = cleanName
-- your own first name and surname. Forever's UnitFullName gives the surname where Classic gives the realm
-- (seen in game); a realm name there isn't taken for one
local function myName()
  local first, surname
  if UnitFullName then first, surname = UnitFullName("player") end
  first = firstName(first or (UnitName and UnitName("player")))
  local realm = GetRealmName and GetRealmName()
  if surname == "" or (realm and surname == realm) then surname = nil end
  return first, surname
end
-- the same character: the full names match, or the first names when either has no surname
local function sameChar(a, b)
  if not (a and b) then return false end
  if a:find(" ") and b:find(" ") then return a:lower() == b:lower() end
  return firstName(a):lower() == firstName(b):lower()
end
local function myFullName()
  local first, surname = myName()
  return first and (surname and (first .. " " .. surname) or first)
end
local function isMe(name) return sameChar(name, myFullName()) end
M.me, M.sameChar = myFullName, sameChar
function M.bankAlt()
  local a = cleanName(M.cfg().bankAlt)
  if not a or isMe(a) then return nil end   -- (you are the bank alt)
  return a
end

-- ------------------------------------------------------------------ your characters
-- Every character that logs in with AuDHD, by realm, with its side. Mail goes only to these, unless the name is marked
-- as on another account. AuDHDDB is the account's own file, so this is the characters of this account.
function M.remember()
  local me, realm = myFullName(), GetRealmName and GetRealmName()
  if not (me and realm) then return end
  AuDHDDB.chars = AuDHDDB.chars or {}
  AuDHDDB.chars[realm] = AuDHDDB.chars[realm] or {}
  local list = AuDHDDB.chars[realm]
  for name in pairs(list) do if sameChar(name, me) and name ~= me then list[name] = nil end end   -- (a surname learned)
  list[me] = mySide() or true
  -- when each was last logged in on, for the list in Settings (AuDHDDB.charSeen[realm][name] = time())
  AuDHDDB.charSeen = AuDHDDB.charSeen or {}
  AuDHDDB.charSeen[realm] = AuDHDDB.charSeen[realm] or {}
  local seen = AuDHDDB.charSeen[realm]
  for name in pairs(seen) do if not list[name] then seen[name] = nil end end
  seen[me] = time and time() or nil
end
-- Every character on this realm, for Settings: { name, side ("A"/"H"/nil), seen (time or nil), me }, sorted. The game
-- can't tell an addon a character was deleted, and a deleted name can be taken by someone else, so the player removes
-- old ones here
function M.charList()
  local realm = GetRealmName and GetRealmName()
  local list = realm and AuDHDDB.chars and AuDHDDB.chars[realm] or {}
  local seen = realm and AuDHDDB.charSeen and AuDHDDB.charSeen[realm] or {}
  local out = {}
  for name, s in pairs(list) do
    out[#out + 1] = { name = name, side = s ~= true and s or nil, seen = seen[name], me = isMe(name) }
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end
function M.forget(name)
  local realm = GetRealmName and GetRealmName()
  if not (realm and name and AuDHDDB.chars and AuDHDDB.chars[realm]) then return end
  AuDHDDB.chars[realm][name] = nil
  if AuDHDDB.charSeen and AuDHDDB.charSeen[realm] then AuDHDDB.charSeen[realm][name] = nil end
  if ns.altItems then pcall(ns.altItems.forget, name) end
  log("CHAR_FORGOTTEN", {})
end
-- your other characters on this realm and side, sorted
function M.myChars()
  local realm = GetRealmName and GetRealmName()
  local side, out = mySide(), {}
  for name, s in pairs(realm and AuDHDDB.chars and AuDHDDB.chars[realm] or {}) do
    if (s == true or not side or s == side) and not isMe(name) then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end
local function onAccount(name)
  for _, n in ipairs(M.myChars()) do if sameChar(n, name) then return true end end
  return false
end
-- whether mail may go to this name: nil when it may, else why not
function M.whyNot(name, other)
  if not name then return "no name" end
  if isMe(name) then return "that's you" end
  if not other and not onAccount(name) then
    return name .. " hasn't logged in with AuDHD on this account (log in on it once, or tick Other account)"
  end
end

-- ------------------------------------------------------------------ who gets what
-- Basic: everything to the bank alt. Professions: each kind of item to its own alt, by the game's item type, and the
-- rest to the catch-all; a row left empty goes to the catch-all, an empty catch-all keeps them in your bags. Trade
-- Goods subtypes: 1 Parts, 2 Explosives, 3 Devices, 5 Cloth, 6 Leather, 7 Metal & Stone, 8 Meat, 9 Herb, 10 Elemental,
-- 12 Enchanting (Classic's numbers; not yet seen in Forever's client).
M.GROUPS = {
  { key = "herb", label = "Herbs", prof = "Alchemy", sub = { [9] = true } },
  { key = "metal", label = "Ore and stone", prof = "Blacksmithing, Engineering", sub = { [7] = true } },
  { key = "parts", label = "Parts", prof = "Engineering", sub = { [1] = true, [2] = true, [3] = true } },
  { key = "cloth", label = "Cloth", prof = "Tailoring", sub = { [5] = true } },
  { key = "leather", label = "Leather", prof = "Leatherworking", sub = { [6] = true } },
  { key = "meat", label = "Meat and fish", prof = "Cooking", sub = { [8] = true } },
  { key = "enchant", label = "Dust, essences", prof = "Enchanting", sub = { [12] = true } },
  { key = "greens", label = "Green BoE gear", prof = "Enchanting, to disenchant" },
  { key = "elemental", label = "Elemental", prof = "several professions", sub = { [10] = true } },
  { key = "scrolls", label = "Mage scrolls", prof = "your mage (the Comprehension scrolls)" },
  { key = "catch", label = "Everything else", prof = "the catch-all: what no row above takes, and rows left empty" },
}
local ORDER = {}
for i, g in ipairs(M.GROUPS) do ORDER[g.key] = i end
local function groupOf(it)
  if it.kind == "boe" then return it.q == 2 and "greens" or "catch" end
  if it.kind == "scroll" then return "scrolls" end
  for _, g in ipairs(M.GROUPS) do if g.sub and g.sub[it.sub or -1] then return g.key end end
  return "catch"
end
function M.profMode() return M.cfg().altMail and M.cfg().altMail.mode == "prof" end
function M.row(key)
  local c = M.cfg()
  c.altMail = c.altMail or {}
  c.altMail.rows = c.altMail.rows or {}
  c.altMail.rows[key] = c.altMail.rows[key] or {}
  return c.altMail.rows[key]
end
-- an item's alt: its name, whether it's on another account, and the row it came from
local function recipient(it)
  if not M.profMode() then return cleanName(M.cfg().bankAlt), M.cfg().bankAltOther, "bank alt" end
  local key = groupOf(it)
  local r = M.row(key)
  if not cleanName(r.name) then key, r = "catch", M.row("catch") end
  return cleanName(r.name), r.other, key
end
-- any alt set up at all
function M.configured()
  if not M.profMode() then return cleanName(M.cfg().bankAlt) ~= nil end
  for _, g in ipairs(M.GROUPS) do if cleanName(M.row(g.key).name) then return true end end
  return false
end
-- what goes where now: { sends = { { to, items }, ... } in the rows' order, count, held = { { to, n, why } } }
function M.plan()
  local by, sends, held, heldBy, count = {}, {}, {}, {}, 0
  local list, kept = M.mailables()
  for _, it in ipairs(list) do
    local to, other, key = recipient(it)
    local why = to and M.whyNot(to, other)
    if to and not why then
      local k = to:lower()
      if not by[k] then by[k] = { to = to, items = {}, order = ORDER[key] or 0 } sends[#sends + 1] = by[k] end
      table.insert(by[k].items, it)
      count = count + 1
    elseif to and why ~= "that's you" then
      local k = to:lower()
      if not heldBy[k] then heldBy[k] = { to = to, n = 0, why = why } held[#held + 1] = heldBy[k] end
      heldBy[k].n = heldBy[k].n + 1
    end
  end
  table.sort(sends, function(a, b) return a.order < b.order end)
  return { sends = sends, count = count, held = held, kept = kept or {} }
end
-- the items the route still needs, by item id: the guide's collect and buy goals not done for real, and the item
-- objectives of the quests in your log and your extra quests. Not done for real: a quest's item until the quest is
-- handed in (a collect goal reads done as soon as the items are in your bags, which is just when they mustn't go), any
-- other item until the route has passed its step. Worked out again every few seconds at most.
-- Each item: { n = how many to keep (nil: all of them), why = the quest it's for }; a quest counted once, its guide goal
-- and its quest log entry being the same need. A quest in your log or on your extra list keeps all of its items: a
-- spare may be for the next quest of its chain. A guide goal alone keeps the count it says
local NEEDS_EVERY = 5
local needs, needsAt = {}, nil
local function questTitle(q)
  local t = q and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(q)
  local db = AuDHDEngine and AuDHDEngine.QuestDB
  if not t and q and db and db.GetQuestTitle then t = db.GetQuestTitle(q) end
  return t or (q and ("quest " .. q)) or "your guide"
end
local function addNeed(out, id, key, n, why)
  local e = out[id]
  if not e then e = { by = {}, why = why } out[id] = e end
  local had = e.by[key]
  if had == nil then e.by[key] = n or false
  elseif had and n then e.by[key] = math.max(had, n)
  elseif not n then e.by[key] = false end
end
-- the quests each item is for, turned round: quest -> { item ids }. From ns.questItems, which is always there, for
-- while the quest data isn't loaded
local itemsOfQuest
local function questItemsBuiltIn(q)
  if not itemsOfQuest then
    itemsOfQuest = {}
    for id, qs in pairs(ns.questItems or {}) do
      for _, qq in ipairs(qs) do
        local l = itemsOfQuest[qq] or {}
        itemsOfQuest[qq] = l
        l[#l + 1] = id
      end
    end
  end
  return itemsOfQuest[q]
end
local function questItems(db, q, out)
  local r = db and db.IsLoaded and db.IsLoaded() and db.QuestRecord and db.F and db.QuestRecord(q)
  if not r then
    for _, id in ipairs(questItemsBuiltIn(q) or {}) do addNeed(out, id, "q" .. q, nil, questTitle(q)) end
    return
  end
  local obj = r[db.F.OBJ]
  for i = 1, #(obj or {}), 3 do
    -- (2: an item objective)
    if obj[i] == 2 and obj[i + 1] then addNeed(out, obj[i + 1], "q" .. q, nil, questTitle(q)) end
  end
  local v = r[db.F.ITEMS]
  if type(v) == "number" then addNeed(out, v, "i" .. q, nil, questTitle(q)) end
  if type(v) == "table" then for _, id in ipairs(v) do addNeed(out, id, "i" .. q, nil, questTitle(q)) end end
end
local function handedIn(q)
  return C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(q)
end
local function routeItems()
  if needsAt and GetTime() - needsAt < NEEDS_EVERY then return needs end
  needsAt = GetTime()
  local out = {}
  local A = AuDHDEngine
  local E, db = A and A.Engine, A and A.QuestDB
  -- (the quest data loads at login, but not in combat: loaded here then, out of combat, when a quest feature wants it)
  if db and db.Load and db.IsLoaded and not db.IsLoaded() then pcall(db.Load) end
  local guide = E and E.GetGuide and E.GetGuide()
  local live = E and E.GetLiveStep and E.GetLiveStep() or math.huge   -- (nil: the guide is finished)
  for i, st in ipairs(guide and guide.steps or {}) do
    local items
    for g, goal in ipairs(st.goals or {}) do
      if (goal.t == "collect" or goal.t == "buy") and goal.item then items = items or {} items[g] = goal end
    end
    local v = items and E.GetStepView(i)
    if v and v.status ~= "na" then
      for _, gv in ipairs(v.goals or {}) do
        local goal = items[gv.index]
        if goal and gv.status ~= "na" then
          local need
          if goal.quest then need = not handedIn(goal.quest) else need = not (i < live and v.status == "done") end
          if need then
            addNeed(out, goal.item, goal.quest and ("q" .. goal.quest) or ("s" .. i .. "." .. gv.index), tonumber(goal.count),
              goal.quest and questTitle(goal.quest) or "your guide")
          end
        end
      end
    end
  end
  local ok, n = pcall(C_QuestLog.GetNumQuestLogEntries)
  for li = 1, (ok and n or 0) do
    local info = C_QuestLog.GetInfo(li)
    if info and not info.isHeader and info.questID then questItems(db, info.questID, out) end
  end
  for q in pairs(ns.extra and ns.extra.list and ns.extra.list() or {}) do questItems(db, q, out) end
  for _, e in pairs(out) do
    local n = 0
    for _, c in pairs(e.by) do if c == false then n = nil break end n = n + c end
    e.n = n
  end
  needs = out
  return out
end
local function routeNeeds(id) return id and routeItems()[id] or false end
M.routeItems = routeItems   -- (the smoke test)
M.routeNeeds = routeNeeds   -- (the auction house: not offered for sale)
-- a mage's Comprehension scroll: its tooltip says "Requires Comprehension". By the tooltip, not a list, so new ones
-- count too. Item id -> true / false once its tooltip has loaded
local scrolls = {}
local function isScroll(id)
  if scrolls[id] ~= nil then return scrolls[id] end
  local data = C_TooltipInfo and C_TooltipInfo.GetItemByID and select(2, pcall(C_TooltipInfo.GetItemByID, id))
  if type(data) ~= "table" or not data.lines or #data.lines == 0 then return false end   -- not loaded: asked again
  local yes = false
  for _, l in ipairs(data.lines) do
    local t = l.leftText
    if type(t) == "string" and not isSecret(t) and t:find("Requires Comprehension", 1, true) then yes = true break end
  end
  scrolls[id] = yes
  return yes
end
local function amMage() return select(2, UnitClass("player")) == "MAGE" end
-- what to mail your alts: BoE gear you wouldn't wear (green or better, not bound yet), materials (Trade Goods) and a
-- mage's scrolls, not bound. Never your tools (Auction.lua's: fishing poles, Flint and Tinder, Simple Wood, Mining
-- Pick and the like) or fishing lures. A list of { bag, slot, kind = "boe" | "mat" | "scroll", q = gear's quality, sub = Trade
-- Goods subtype, split = how many of the stack (the rest kept) }. Then what's kept for the route: { { id, n, why } }.
-- What a quest needs stays: all of them, or as many as a guide goal says when only the guide asks (the rest of the stack goes)
function M.mailables()
  local out, kept, keptBy, left = {}, {}, {}, {}
  local function keep(id, n, why)
    local k = keptBy[id]
    if not k then k = { id = id, n = 0, why = why } keptBy[id] = k kept[#kept + 1] = k end
    k.n = k.n + n
  end
  for _, bag in ipairs(ns.bagIDs()) do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      local link = info and info.hyperlink
      if link and not info.isBound and not info.isLocked then
        local itemID, _, _, equipLoc, _, classID, subID = C_Item.GetItemInfoInstant(link)
        local id0 = info.itemID or itemID
        if (ns.auction and ns.auction.isTool and ns.auction.isTool(id0, classID, subID))
            or (ns.fishing and ns.fishing.isLure and ns.fishing.isLure(id0)) then
          -- yours to use: stays in your bags
        elseif (classID == 2 or classID == 4) and equipLoc and equipLoc ~= "" and (info.quality or 0) >= 2
            and not (ns.auto and ns.auto.keepForMe and ns.auto.keepForMe(link)) then
          out[#out + 1] = { bag = bag, slot = slot, kind = "boe", q = info.quality }
        elseif classID == 7 or (classID ~= 2 and classID ~= 4 and not amMage() and isScroll(info.itemID or itemID)) then
          local id, stack = info.itemID or itemID, info.stackCount or 1
          local it = { bag = bag, slot = slot, kind = classID == 7 and "mat" or "scroll", sub = subID }
          local need = M.routeNeeds(id)
          if not need then
            out[#out + 1] = it
          elseif not need.n then
            keep(id, stack, need.why)
          else
            local still = left[id] or need.n
            if still >= stack then
              left[id] = still - stack
              keep(id, stack, need.why)
            else
              left[id] = 0
              if still > 0 then it.split = stack - still keep(id, still, need.why) end
              out[#out + 1] = it
            end
          end
        end
      end
    end
  end
  return out, kept
end
-- the setting "only remind me with a full stack": a BoE going, or a material whose stacks going out add up to a full
-- stack of it, counted over all your bags
local function fullStackGoing(p)
  local have = {}
  local info = C_Item and C_Item.GetItemInfo or GetItemInfo
  for _, send in ipairs(p.sends) do
    for _, it in ipairs(send.items) do
      if it.kind ~= "mat" then return true end
      local slot = C_Container.GetContainerItemInfo(it.bag, it.slot)
      local id = slot and slot.itemID
      if id then
        have[id] = (have[id] or 0) + (it.split or slot.stackCount or 1)
        local max = info and select(8, info(id))
        if type(max) == "number" and not isSecret(max) and have[id] >= max then return true end
      end
    end
  end
  return false
end
M.fullStackGoing = fullStackGoing   -- (the smoke test)
local function mailText(p, box, d)
  local boe, mat, scroll = 0, 0, 0
  for _, s in ipairs(p.sends) do
    for _, it in ipairs(s.items) do
      if it.kind == "boe" then boe = boe + 1 elseif it.kind == "scroll" then scroll = scroll + 1 else mat = mat + 1 end
    end
  end
  local parts = {}
  if boe > 0 then parts[#parts + 1] = boe .. " BoE" end
  if mat > 0 then parts[#parts + 1] = mat .. " materials" end
  if scroll > 0 then parts[#parts + 1] = scroll .. " mage scroll" .. (scroll == 1 and "" or "s") end
  local to = #p.sends == 1 and p.sends[1].to or (#p.sends .. " alts")
  return ("%s %d yd: mail %s to %s"):format(box.n, math.floor(d), table.concat(parts, " + "), to)
end

-- ------------------------------------------------------------------ the pop-ups
-- a pop-up per kind, with Go to (your /way arrow to it) and Snooze 10 / 20 / 30 minutes. Said once per visit; passing
-- from one vendor to the next only changes its text
local SNOOZE = { 10, 20, 30 }   -- minutes
local shown = {}     -- kind -> { e = the service, key = what was said }
local snoozed = {}   -- kind -> GetTime() until which it stays quiet
local pops = {}      -- kind -> its pop-up frame
local SLOT = { vendor = 0, trainer = 1, mail = 2, banktip = 2, auction = 3, ammo = 4, prof = 5 }
-- the open pop-ups stacked down from the top in SLOT order, each under the one above, so a tall one never covers the
-- next. One you dragged stays put
local function stack()
  local order = {}
  for kind, f in pairs(pops) do
    if f.open and not f.moved then order[#order + 1] = kind end
  end
  table.sort(order, function(a, b) return (SLOT[a] or 9) < (SLOT[b] or 9) end)
  local y = -230
  for _, kind in ipairs(order) do
    local f = pops[kind]
    f:ClearAllPoints()
    f:SetPoint("TOP", UIParent, "TOP", 0, y)
    y = y - (f:GetHeight() or 64) - 6
  end
end
-- the text, and the pop-up sized to fit it above the buttons (and the "Snooze:" label)
local function setText(f, text)
  f.text:SetText(text)
  local h = f.text:GetStringHeight() or 14
  f:SetHeight(math.max(f.minH, math.ceil(h) + f.under))
  stack()
end
local function popup(kind)
  if pops[kind] then return pops[kind] end
  local f = ns.newFrame("Services", "Frame", "AuDHDService_" .. kind, UIParent, "BackdropTemplate")
  f:SetSize(310, 64)
  f:SetPoint("TOP", UIParent, "TOP", 0, -230 - 70 * (SLOT[kind] or 0))
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() self.moved = true end)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.05, 0.05, 0.1, 0.92)
  end
  f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.text:SetPoint("TOP", 0, -10)
  f.text:SetWidth(294)
  local function button(label, x, w, onClick)
    local b = ns.newFrame("Services", "Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(w, 20)
    b:SetPoint("BOTTOM", f, "BOTTOM", x, 8)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
  end
  local function close() f.open = false f:Hide() stack() end
  f.minH, f.under = 64, 55   -- 10 above the text; Snooze label, buttons and 8 below
  if kind == "banktip" then
    -- said once ever: OK puts it away for good
    f.minH, f.under = 92, 44   -- no Snooze label
    f:SetHeight(92)
    f.ok = button("OK", -50, 90, function() AuDHDDB.bankAltTipped = true log("BANKALT_TIP_OK", {}) close() end)
    f.settings = button("Settings", 50, 90, function()
      AuDHDDB.bankAltTipped = true
      if ns.settings and ns.settings.show then ns.settings.show() end
      close()
    end)
  else
    -- (only with an arrow to point)
    if ns.way then
      f.go = button("Go to", -108, 72, function()
        local s = shown[kind]
        if s then ns.way.set(s.e.m, s.e.x, s.e.y, s.e.n) end
        log("SERVICE_GOTO", { kind = kind, npc = s and s.e.n })
        close()
      end)
    end
    for i, mins in ipairs(SNOOZE) do
      f["snooze" .. mins] = button(mins .. " min", -34 + 68 * (i - 1), 64, function()
        snoozed[kind] = GetTime() + 60 * mins
        log("SERVICE_SNOOZE", { kind = kind, mins = mins })
        close()
      end)
    end
    f.zz = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.zz:SetPoint("BOTTOMLEFT", f["snooze" .. SNOOZE[1]], "TOPLEFT", 0, 1)
    f.zz:SetText("Snooze:")
  end
  f:Hide()
  pops[kind] = f
  return f
end
local function remind(kind, e, d, key, text)
  if snoozed[kind] and GetTime() < snoozed[kind] then return end
  local s = shown[kind]
  if s and s.key == key then
    -- the same thing to say: only the nearest place and the yards change, quietly
    s.e = e
    if pops[kind] then pops[kind].msg = text setText(pops[kind], text) end
    return
  end
  shown[kind] = { e = e, key = key }
  local f = popup(kind)
  f.msg, f.open = text, true
  f:Show()
  setText(f, text)
  ns.playAlert()
  log("SERVICE_NEAR", { kind = kind, npc = e.n, yd = math.floor(d), key = key })
end
local function drop(kind)
  shown[kind] = nil
  if pops[kind] then pops[kind].open = false pops[kind]:Hide() stack() end
end
local function forget(kind, P)
  local s = shown[kind]
  if not s then return end
  local w = placeOf(s.e)
  local away = kind == "prof" and PROF_AWAY or AWAY
  if not w or w.c ~= P.c or math.sqrt((w.wx - P.wx) ^ 2 + (w.wy - P.wy) ^ 2) > away then drop(kind) end
end
-- the smoke test: what a pop-up says (nil when it's not up), and its buttons
function M.popupText(kind) local f = pops[kind] return f and f.open and f.msg or nil end
function M.click(kind, which)
  local b = pops[kind] and pops[kind][which]
  local fn = b and (b.scripts and b.scripts.OnClick or b:GetScript("OnClick"))
  if fn then fn(b) end
end

local KINDS = { "vendor", "trainer", "mail", "banktip", "auction", "ammo", "prof" }

-- ------------------------------------------------------------------ profession trainers
-- A rank of a profession you have, to learn now: your skill near its cap and your level enough, within PROF_NEAR yards
-- of a trainer of your side who teaches it. Never a profession you don't have. Ranks (Classic; not checked in Forever):
-- cap 75 -> Journeyman at skill 50 and level 10,
-- 150 -> Expert at 125 and level 20, 225 -> Artisan at 200 and level 35. Cooking, First Aid and Fishing: Journeyman
-- only (their Expert and Artisan are books and quests in Classic). Trainers: ProfTrainerData.lua; one whose title gives
-- a lower cap is skipped, and one whose window had nothing of that rank for you isn't sent to again for it (Forever's
-- trainers can teach less: Fanorran Stilloak in Shadowglen, Apprentice Mining only)
local RANKS = { [75] = { "Journeyman", 10 }, [150] = { "Expert", 20 }, [225] = { "Artisan", 35 } }
local SECONDARY = { Cooking = true, ["First Aid"] = true, Fishing = true }
local profs, profsAt
-- your professions: { { name, rank, max } }, read at most every 15 s
function M.professions()
  local now = GetTime()
  if profs and now - profsAt < 15 then return profs end
  profs, profsAt = {}, now
  local known = ns.profTrainers or {}
  if GetProfessions and GetProfessionInfo then
    local t = table.pack(GetProfessions())
    for i = 1, t.n do
      if t[i] then
        local name, _, rank, max = GetProfessionInfo(t[i])
        if name and known[name] and rank and max then profs[#profs + 1] = { name = name, rank = rank, max = max } end
      end
    end
  elseif GetNumSkillLines and GetSkillLineInfo then
    -- (lines under a header you've folded in the skills pane aren't seen)
    for i = 1, GetNumSkillLines() do
      local name, header, _, rank, _, _, max = GetSkillLineInfo(i)
      if not header and name and known[name] and rank and max then profs[#profs + 1] = { name = name, rank = rank, max = max } end
    end
  end
  return profs
end
-- the ranks due now: { { name, rank, max, next = rank name, want = the new cap } }
function M.profDue()
  local out, lv = {}, UnitLevel("player") or 1
  for _, p in ipairs(M.professions()) do
    local r = RANKS[p.max]
    if r and not (SECONDARY[p.name] and p.max > 75) and p.rank >= p.max - 25 and lv >= r[2] then
      out[#out + 1] = { name = p.name, rank = p.rank, max = p.max, next = r[1], want = p.max + 75 }
    end
  end
  return out
end
local function noneKey(n, p) return ("%s:%s:%d"):format(n, p.name, p.max) end
-- the nearest trainer for any rank due, and that rank
local function profTrainer(P)
  local best, bd, what
  local none = AuDHDDB.profNone or {}
  for _, p in ipairs(M.profDue()) do
    local list = {}
    for _, t in ipairs(ns.profTrainers and ns.profTrainers[p.name] or {}) do
      if (not t.cap or t.cap >= p.want) and not none[noneKey(t.n, p)] then list[#list + 1] = t end
    end
    local t, d = nearest(list, P)
    if t and (not bd or d < bd) then best, bd, what = t, d, p end
  end
  return best, bd, what
end
-- at a profession trainer: nothing of a due rank in its list (learnable or not yet) means it doesn't teach that rank
function M.trainerSeen()
  if not (GetNumTrainerServices and GetTrainerServiceInfo) then return end
  if IsTradeskillTrainer and not IsTradeskillTrainer() then return end
  local npc = UnitName("npc")
  if not npc then return end
  local text = {}
  for i = 1, (GetNumTrainerServices() or 0) do
    local name, sub = GetTrainerServiceInfo(i)
    text[#text + 1] = (name or "") .. " " .. (sub or "")
  end
  local all = table.concat(text, " | ")
  for _, p in ipairs(M.profDue()) do
    local theirs = false
    for _, t in ipairs(ns.profTrainers and ns.profTrainers[p.name] or {}) do if t.n == npc then theirs = true break end end
    if theirs and #text > 0 and not all:find(p.next, 1, true) then
      AuDHDDB.profNone = AuDHDDB.profNone or {}
      AuDHDDB.profNone[noneKey(npc, p)] = true
      log("PROF_TRAINER_NONE", { npc = npc, prof = p.name, rank = p.next })
      if shown.prof and shown.prof.e.n == npc then drop("prof") end
    end
  end
end
-- ammo: fewer than this (or than you can carry: Ammo.lua's target, a full quiver) by a vendor of your kind; not while
-- your money is all kept back for your class skills (Ammo.lua buys nothing then)
local AMMO_LOW = 800
local sideOf   -- vendor name -> its side ("A" / "H") or false, from the vendor list: AmmoData has no sides
local function ammoVendors(kind)
  if not sideOf then
    sideOf = {}
    for _, v in ipairs(ns.vendors or {}) do if sideOf[v.n] == nil then sideOf[v.n] = v.f or false end end
  end
  local out = {}
  for _, v in ipairs(ns.ammoVendors or {}) do
    if (kind == "arrow" and v.a) or (kind == "bullet" and v.b) then
      if v.f == nil then v.f = sideOf[v.n] or nil end
      out[#out + 1] = v
    end
  end
  return out
end
local function ammoText(P)
  local A = ns.ammo
  local kind = A and A.kind()
  local n = kind and A.count(kind)
  local full = n and (A.target(kind) or AMMO_LOW)
  -- in a group, anything short of full
  local group = IsInGroup and IsInGroup()
  if not n or n >= (group and full or math.min(AMMO_LOW, full)) then return nil end
  if GetMoney() <= ((A.trainReserve and A.trainReserve()) or 0) then return nil end
  local v, d = nearest(ammoVendors(kind), P)
  if not (v and d <= NEAR) then return nil end
  local what = kind == "arrow" and "Arrows" or "Bullets"
  if group and n >= math.min(AMMO_LOW, full) then
    return ("%s: %d of %d. You're in a group: fill up at %s, %d yd"):format(what, n, full, v.n, math.floor(d)), v, d
  end
  return ("%s: %d left: buy more at %s, %d yd"):format(what, n, v.n, math.floor(d)), v, d
end
M.ammoText = ammoText   -- (the smoke test)
function M.check()
  if AuDHDDB.servicesOff then for _, k in ipairs(KINDS) do drop(k) end return end
  if UnitOnTaxi and UnitOnTaxi("player") then return end
  local P = player()
  if not P then return end
  for _, k in ipairs(KINDS) do forget(k, P) end
  local full, free = M.bagsFull()
  if full then
    local v, d = nearest(ns.vendors, P)
    if v and d <= NEAR then
      remind("vendor", v, d, "full", ("Bags %s (%d free): sell at %s, %d yd"):format(free == 0 and "full" or "nearly full", free, v.n, math.floor(d)))
    end
  elseif shown.vendor then
    drop("vendor")
  end
  if M.skillsOwed() then
    local _, class = UnitClass("player")
    local cur = ns.core and ns.core.current and ns.core.current()
    local t, d = nearest(ns.classTrainers and ns.classTrainers[class], P)
    -- the route's own "Train at" step says it already
    if t and d <= NEAR and not (cur and cur.k == "train") then
      remind("trainer", t, d, "lv" .. UnitLevel("player"), ("Skills to learn: %s is %d yd away"):format(t.n, math.floor(d)))
    end
  elseif shown.trainer then
    drop("trainer")
  end
  if not M.cfg().mailOff then
    local box, d = nearest(ns.mailboxes, P)
    if box and d <= NEAR and MailFrame and MailFrame:IsShown() then
      -- at the mailbox: this visit is said, nothing again until you've gone
      if not shown.mail then shown.mail = { e = box, key = "mail" } end
      if pops.mail then pops.mail.open = false pops.mail:Hide() stack() end
    elseif box and d <= NEAR then
      local p = M.configured() and M.plan()
      if p then
        local worth
        if M.cfg().mailFullStack then worth = fullStackGoing(p) else worth = p.count >= MAIL_MIN end
        if worth then remind("mail", box, d, "mail", mailText(p, box, d)) end
      elseif #M.mailables() >= MAIL_MIN and not AuDHDDB.bankAltTipped and UnitLevel("player") >= 10 then
        -- no alt yet: say once what it's for
        remind("banktip", box, d, "tip", "Tip: make a bank alt and park it in a city. Set its first and last name in Settings,"
          .. " Alt mail, and I'll remind you to mail it your BoEs and materials at mailboxes on the way.")
      end
    end
  end
  -- the auction house, only when you're already by it
  local ah, d = nearest(ns.auctioneers, P)
  local text = ah and d <= NEAR and ns.auction and ns.auction.remindText and ns.auction.remindText()
  if text then
    remind("auction", ah, d, "ah", text .. (": %s, %d yd"):format(ah.n, math.floor(d)))
  elseif shown.auction and not text then
    drop("auction")
  end
  local at, av, ad = ammoText(P)
  if at then
    remind("ammo", av, ad, "low", at)
  elseif shown.ammo then
    drop("ammo")
  end
  local pt, pd, pw = nil, nil, nil
  if not AuDHDDB.profTrainOff then pt, pd, pw = profTrainer(P) end
  -- (once up, it stays and counts the yards until you're PROF_AWAY off)
  local up = pt and shown.prof and shown.prof.key == pw.name .. pw.max
  if pt and (pd <= PROF_NEAR or (up and pd <= PROF_AWAY)) then
    remind("prof", pt, pd, pw.name .. pw.max, ("%s %s to learn (skill %d/%d): %s is %d yd away"):format(pw.next, pw.name,
      pw.rank, pw.max, pt.n, math.floor(pd)))
  elseif shown.prof and (not pt or shown.prof.key ~= pw.name .. pw.max) then
    drop("prof")   -- (what it said isn't due now; the same rank out of reach goes once you're PROF_AWAY off)
  end
end

-- ------------------------------------------------------------------ at the mailbox: send it all
-- A button on the mail window sends everything that's to go, 12 items a mail (the game's limit), one mail after the
-- other. It asks once first: on the real game a mistyped name could be someone else's character. It stops when a mail
-- fails, the mailbox closes, or a mail went and nothing left the bags; what's left stays in your bags. If the game
-- won't let an addon send mail, the button goes back to filling the mail for you to press Send. Several alts
-- (Professions): their mails one after the other, in the rows' order.
local POSTAGE = 30   -- copper a mail item (the server's MailHandler: 30 an item, 30 for a mail without)
local SUBJECT = "For the bank"
local mailButton, run, mailShown   -- run: the sending in progress { sent = { [to] = items }, mails, before, n, to, token }
-- why the last run stopped early, shown on the button until the mailbox closes; and the kept-back lines already said in
-- chat this visit
local stopped, told
local function maxItems() return ATTACHMENTS_MAX_SEND or 12 end
-- 870 -> 8s 70c, every coin that isn't 0, coloured like the info bar
local function money(c)
  c = math.floor(c or 0)
  local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local out = {}
  if g > 0 then out[#out + 1] = ("|cffffd700%dg|r"):format(g) end
  if s > 0 then out[#out + 1] = ("|cffc7c7cf%ds|r"):format(s) end
  if k > 0 or #out == 0 then out[#out + 1] = ("|cffeda55f%dc|r"):format(k) end
  return table.concat(out, " ")
end
M.coins = money
local function say(msg) print("|cff66ccffAuDHD|r: " .. msg) end

-- switches to Send Mail, puts the alt's name in and attaches the first 12 of its items. Without a list: the first alt's
-- items. Returns how many
function M.fillMail(list, alt)
  if not list then
    local s = M.plan().sends[1]
    if not s then return 0 end
    list, alt = s.items, s.to
  end
  if not alt then return 0 end
  if MailFrameTab_OnClick then pcall(MailFrameTab_OnClick, nil, 2) end
  if SendMailNameEditBox then SendMailNameEditBox:SetText(alt) end
  if SendMailSubjectEditBox and SendMailSubjectEditBox:GetText() == "" then SendMailSubjectEditBox:SetText(SUBJECT) end
  local n = 0
  for _, it in ipairs(list) do
    if n >= maxItems() then break end
    ClearCursor()
    if it.split and C_Container.SplitContainerItem then
      C_Container.SplitContainerItem(it.bag, it.slot, it.split)   -- the part of the stack that goes; the rest stays
    else
      C_Container.PickupContainerItem(it.bag, it.slot)
    end
    n = n + 1
    ClickSendMailItemButton(n)
  end
  ClearCursor()
  log("BANKALT_FILL", { n = n })
  return n
end

local function finish(why)
  local r = run
  if not r then return end
  run = nil
  local parts = {}
  for _, to in ipairs(r.order) do parts[#parts + 1] = r.sent[to] .. " to " .. to end
  say(("%d mail%s sent%s%s"):format(r.mails, r.mails == 1 and "" or "s", #parts > 0 and (": " .. table.concat(parts, ", ")) or "",
    why and (". Stopped: " .. why) or ""))
  log("BANKALT_SENT", { mails = r.mails, why = why })
  stopped = why
  if mailShown then pcall(mailShown) end
end
local function sendNext()
  local r = run
  if not r then return end
  local p = M.plan()
  local s = p.sends[1]
  if not s then return finish() end
  if r.before and p.count >= r.before then
    -- the bags may not have caught up with the mail yet: look once more a second later
    if not r.waited then r.waited = true C_Timer.After(1, sendNext) return end
    return finish("a mail went but nothing left your bags")
  end
  r.waited = nil
  local n = math.min(#s.items, maxItems())
  if GetMoney and GetMoney() < n * POSTAGE then return finish("not enough money for the postage") end
  M.fillMail(s.items, s.to)
  r.before, r.n, r.to = p.count, n, s.to
  r.token = (r.token or 0) + 1
  local token = r.token
  local ok = pcall(SendMail, s.to, SUBJECT, "")
  if not ok then return finish("the game wouldn't send it") end
  -- no answer at all: don't wait for ever
  C_Timer.After(15, function() if run == r and r.token == token and r.n then finish("no answer from the mailbox") end end)
end
function M.sendAll()
  if run or #M.plan().sends == 0 then return end
  run = { sent = {}, order = {}, mails = 0 }
  stopped = nil
  log("BANKALT_SEND_ALL", {})
  sendNext()
end
-- the game answers each mail
function M.mailEvent(event, a1, a2)
  if event == "MAIL_SEND_SUCCESS" and run and run.n then
    if not run.sent[run.to] then run.sent[run.to] = 0 table.insert(run.order, run.to) end
    run.sent[run.to] = run.sent[run.to] + run.n
    run.mails, run.n = run.mails + 1, nil
    C_Timer.After(0.5, sendNext)
  elseif event == "MAIL_FAILED" and run then
    finish("a mail didn't go (the game said why)")
  elseif event == "MAIL_CLOSED" and run then
    finish("the mailbox closed")
  elseif (event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN") and a1 == "AuDHD"
      and tostring(a2):find("SendMail") then
    -- the game keeps mail sending to itself: fill the mail, you press Send
    M.cfg().mailManual = true
    run = nil
    say("the game won't let an addon send mail, so the items are attached: press Send. The button fills the mail from now on.")
    if mailShown then pcall(mailShown) end
  end
end

StaticPopupDialogs.AUDHD_MAIL_ALL = {
  text = "%s", button1 = "Send", button2 = CANCEL or "Cancel",
  OnAccept = function() pcall(M.sendAll) end,
  timeout = 0, whileDead = 1, hideOnEscape = 1,
}
-- what's held back and why: names not seen on this account, and what your quests need ("4 Light Leather kept for Kodo
-- Hide Bag")
local function heldText(p)
  local out = {}
  for _, h in ipairs(p.held) do out[#out + 1] = ("%d item%s kept: %s"):format(h.n, h.n == 1 and "" or "s", h.why) end
  local name = C_Item and C_Item.GetItemNameByID
  for _, k in ipairs(p.kept or {}) do
    out[#out + 1] = ("%d %s kept for %s"):format(k.n, (name and name(k.id)) or ("item " .. k.id), k.why)
  end
  return table.concat(out, "\n")
end
M.heldText = heldText   -- (the smoke test)
function M.stoppedWhy() return stopped end
function M.askText()
  local p = M.plan()
  if p.count == 0 then return nil end
  local lines, mails = {}, 0
  for _, s in ipairs(p.sends) do
    local m = math.ceil(#s.items / maxItems())
    mails = mails + m
    lines[#lines + 1] = ("%d item%s to %s"):format(#s.items, #s.items == 1 and "" or "s", s.to)
  end
  local held = heldText(p)
  return ("Send %d mail%s?\n%s\nPostage: %s%s"):format(mails, mails == 1 and "" or "s", table.concat(lines, "\n"),
    money(p.count * POSTAGE), held ~= "" and ("\n\n" .. held) or "")
end
local function askSendAll()
  local text = M.askText()
  if text then StaticPopup_Show("AUDHD_MAIL_ALL", text) end
end

mailShown = function()
  if M.cfg().mailOff or not M.configured() or not MailFrame then return end
  if not mailButton then
    mailButton = ns.newFrame("Services", "Button", "AuDHDMailFill", MailFrame, "UIPanelButtonTemplate")
    mailButton:SetHeight(22)
    mailButton:SetPoint("TOPRIGHT", MailFrame, "BOTTOMRIGHT", 0, -2)
    mailButton:SetScript("OnClick", function()
      if M.cfg().mailManual then pcall(M.fillMail) else pcall(askSendAll) end
    end)
  end
  local p = M.plan()
  local first = p.sends[1]
  if M.cfg().mailManual then
    mailButton:SetText(first and ("Fill mail to %s (%d)"):format(first.to, #first.items) or "")
  elseif #p.sends == 1 then
    mailButton:SetText(("Send all to %s (%d)"):format(first.to, p.count))
  else
    mailButton:SetText(("Send all to %d alts (%d)"):format(#p.sends, p.count))
  end
  -- a run that stopped early: why, in red under the button, and the button sends the rest
  if stopped and p.count > 0 and not M.cfg().mailManual then mailButton:SetText(("Send the rest (%d)"):format(p.count)) end
  if not mailButton.why then
    mailButton.why = mailButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mailButton.why:SetPoint("TOPRIGHT", mailButton, "BOTTOMRIGHT", 0, -2)
    mailButton.why:SetTextColor(1, 0.25, 0.25)
  end
  mailButton.why:SetText(stopped and ("Stopped: " .. stopped) or "")
  mailButton:SetWidth(math.max(170, (mailButton:GetTextWidth() or 0) + 28))
  mailButton:SetShown(p.count > 0 and not run)
  -- kept back: said once a mailbox visit (again only when it changes)
  local held = heldText(p)
  if held ~= "" and not run and held ~= told then say((held:gsub("\n", ". "))) end
  told = held
  -- the pop-up away, but still said for this visit (forgotten once you're AWAY yards off)
  if pops.mail then pops.mail.open = false pops.mail:Hide() stack() end
end

-- once for each character: alt mail is off here, and where to set it up
local tip
function M.mailTip()
  local c = M.cfg()
  if c.told then return false end
  if InCombatLockdown and InCombatLockdown() then C_Timer.After(10, function() pcall(M.mailTip) end) return false end
  if not tip then
    tip = ns.newFrame("Services", "Frame", "AuDHDMailTip", UIParent, "BackdropTemplate")
    tip:SetSize(340, 104)
    tip:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    tip:SetFrameStrata("DIALOG")
    tip:EnableMouse(true)
    if tip.SetBackdrop then
      tip:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    end
    tip.text = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    tip.text:SetPoint("TOP", 0, -18)
    tip.text:SetWidth(300)
    local function done() M.cfg().told = true log("MAIL_TIP", {}) tip:Hide() end
    local function button(label, x, onClick)
      local b = ns.newFrame("Services", "Button", nil, tip, "UIPanelButtonTemplate")
      b:SetSize(120, 22)
      b:SetPoint("BOTTOM", tip, "BOTTOM", x, 16)
      b:SetText(label)
      b:SetScript("OnClick", onClick)
      return b
    end
    tip.open = button("Open settings", -64, function() done() if ns.settings and ns.settings.show then ns.settings.show("Alt mail") end end)
    tip.ok = button("OK", 64, done)
  end
  tip.text:SetText(("Alt mail is off for %s. To have your BoEs and materials mailed to your alts, set it up in Settings, Alt mail. Each character has its own."):format(UnitName("player") or "this character"))
  tip:Show()
  return true
end
M.mailTipFrame = function() return tip end   -- (the smoke test)

function M.command(rest)
  if rest == "" then
    print("|cff66ccffAuDHD|r: bank alt " .. (M.cfg().bankAlt or "not set") .. (M.cfg().mailOff and " (reminders off)" or "")
      .. ". /audhd bankalt <name>, /audhd bankalt off|on, /audhd bankalt clear")
  elseif rest == "off" then M.cfg().mailOff = true drop("mail")
  elseif rest == "on" then M.cfg().mailOff = nil
  elseif rest == "clear" then M.cfg().bankAlt = nil drop("mail")
  else
    M.cfg().bankAlt = cleanName(rest)
    AuDHDDB.bankAltTipped = true
    drop("banktip")
    print("|cff66ccffAuDHD|r: bank alt set to " .. M.cfg().bankAlt
      .. (M.cfg().bankAlt:find(" ") and "" or " (mail needs the first and last name, like /audhd bankalt Bankie Smith)"))
    local why = M.whyNot(M.cfg().bankAlt, M.cfg().bankAltOther)
    if why then say("nothing will be mailed: " .. why) end
  end
end

local frame = ns.newFrame("Services", "Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("MAIL_SHOW")
pcall(frame.RegisterEvent, frame, "TRAINER_SHOW")
for _, e in ipairs({ "MAIL_SEND_SUCCESS", "MAIL_FAILED", "MAIL_CLOSED", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
  pcall(frame.RegisterEvent, frame, e)
end
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "MAIL_SHOW" then stopped, told = nil, nil pcall(mailShown) return end
  if event == "TRAINER_SHOW" then C_Timer.After(0.5, function() pcall(M.trainerSeen) end) return end
  if event ~= "PLAYER_LOGIN" then pcall(M.mailEvent, event, ...) return end
  -- again a little later: the surname may come late
  pcall(M.remember)
  C_Timer.After(8, function() pcall(M.mailTip) end)
  C_Timer.After(5, function() pcall(M.remember) end)
  C_Timer.NewTicker(2, function() pcall(M.check) end)
end)
