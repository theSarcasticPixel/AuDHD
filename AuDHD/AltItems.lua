-- What your characters carry: bags, the bank (as it was when you last closed it) and mail (in their mailbox, or on the
-- way to them), shown on item tooltips and in a search window. Equipped gear is left out. Only your characters on this
-- realm, the ones AuDHD has seen log in (ns.services). Saved by item id: AuDHDDB.items[realm][name] = { bags = {[id] =
-- n}, bank = {}, mail = {}, transit = { { id, n, t, from } }, class, bankSeen }, and every slot in order for the bag
-- windows: bagSlots / bankSlots = { { link, n } or false (empty), ... }
local _, ns = ...
local A = {}
ns.altItems = A

local BANK = BANK_CONTAINER or -1
local ARRIVED = 65 * 60   -- mail with items takes an hour: after that, what isn't in the mailbox has been collected
local MAX_FOUND = 40

local function realm() return GetRealmName and GetRealmName() end
local function me() return ns.services and ns.services.me and ns.services.me() end
local function same(a, b) return ns.services and ns.services.sameChar and ns.services.sameChar(a, b) end
local function chars()
  local r = realm()
  return r and AuDHDDB.chars and AuDHDDB.chars[r] or {}
end
-- the saved name of one of your characters, from a name typed or shown by the game ("Bankie", "Bankie Smith")
local function known(name)
  if not name or name == "" then return nil end
  if chars()[name] then return name end
  for n in pairs(chars()) do if same(n, name) then return n end end
end
local function store()
  local r = realm()
  if not r then return nil end
  AuDHDDB.items = AuDHDDB.items or {}
  AuDHDDB.items[r] = AuDHDDB.items[r] or {}
  return AuDHDDB.items[r]
end
local function record(name)
  local s = store()
  if not (s and name) then return nil end
  s[name] = s[name] or {}
  return s[name]
end
local function mine()
  local n = me()
  local rec = record(n)
  if rec and UnitClass then rec.class = select(2, UnitClass("player")) end
  return rec, n
end

-- item names, for the search window: kept from the links seen, since the game only knows names of items it has loaded
local function remember(id, link)
  local name = link and link:match("|h%[(.-)%]|h")
  if id and name then
    AuDHDDB.itemNames = AuDHDDB.itemNames or {}
    AuDHDDB.itemNames[id] = name
  end
end
local function idOf(link) return link and tonumber(link:match("item:(%d+)")) end

-- one container's items, added to counts
local function slotInfo(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local i = C_Container.GetContainerItemInfo(bag, slot)
    if i then return i.itemID or idOf(i.hyperlink), i.stackCount or 1, i.hyperlink end
    return nil
  end
  if GetContainerItemInfo then
    local _, n, _, _, _, _, link, _, _, id = GetContainerItemInfo(bag, slot)
    if link then return id or idOf(link), n or 1, link end
  end
end
local function numSlots(bag)
  local f = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
  return f and f(bag) or 0
end
local function scan(bags)
  local counts, slots = {}, {}
  for _, bag in ipairs(bags) do
    for slot = 1, numSlots(bag) do
      local id, n, link = slotInfo(bag, slot)
      if id then
        counts[id] = (counts[id] or 0) + n
        remember(id, link)
        slots[#slots + 1] = { link or ("item:" .. id), n }
      else
        slots[#slots + 1] = false
      end
    end
  end
  return counts, slots
end

function A.scanBags()
  local rec = mine()
  if not rec then return end
  rec.bags, rec.bagSlots = scan(ns.bagIDs())
end
-- only while the bank is open: the game can't read it otherwise
local bankOpen = false
function A.scanBank()
  local rec = mine()
  if not (rec and bankOpen) or numSlots(BANK) == 0 then return end
  rec.bank, rec.bankSlots = scan(ns.bankBagIDs())
  rec.bankSeen = time and time() or nil
end

-- mail you send to your characters: "on the way" until they open their mailbox. The attachments are read when the mail
-- goes, and kept once the game says it went
local pending
function A.sending(to)
  pending = nil
  local name = known(to and to:gsub("%-.*", ""))
  if not (name and GetSendMailItem) then return end
  local items = {}
  for i = 1, ATTACHMENTS_MAX_SEND or 12 do
    local link = GetSendMailItemLink and GetSendMailItemLink(i)
    local id = idOf(link) or select(2, GetSendMailItem(i))
    local n = select(4, GetSendMailItem(i))
    if type(id) == "number" then
      items[#items + 1] = { id = id, n = n or 1 }
      remember(id, link)
    end
  end
  if #items > 0 then pending = { to = name, items = items } end
end
function A.sent()
  local p = pending
  pending = nil
  local rec = p and record(p.to)
  if not rec then return end
  rec.transit = rec.transit or {}
  local now, from = time and time() or 0, me()
  for _, it in ipairs(p.items) do
    rec.transit[#rec.transit + 1] = { id = it.id, n = it.n, t = now, from = from }
  end
end
function A.mailFailed() pending = nil end

-- your own mailbox, read while it's open. Mail on the way that is now in it stops being "on the way"
function A.scanInbox()
  local rec = mine()
  if not (rec and GetInboxNumItems) then return end
  local counts, fromCounts = {}, {}
  for i = 1, GetInboxNumItems() do
    local sender = select(3, GetInboxHeaderInfo(i))
    for j = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
      local link = GetInboxItemLink and GetInboxItemLink(i, j)
      local id = idOf(link)
      if id then
        local n = select(4, GetInboxItem(i, j)) or 1
        counts[id] = (counts[id] or 0) + n
        remember(id, link)
        if sender then
          fromCounts[sender] = fromCounts[sender] or {}
          fromCounts[sender][id] = (fromCounts[sender][id] or 0) + n
        end
      end
    end
  end
  rec.mail = counts
  local now, keep = time and time() or 0, {}
  for _, e in ipairs(rec.transit or {}) do
    local found = false
    for sender, c in pairs(fromCounts) do
      if (not e.from or same(sender, e.from)) and (c[e.id] or 0) >= e.n then
        c[e.id] = c[e.id] - e.n
        found = true
        break
      end
    end
    if not found and now - (e.t or 0) < ARRIVED then keep[#keep + 1] = e end
  end
  rec.transit = #keep > 0 and keep or nil
end

-- characters removed from the list (Services.forget) or renamed (a surname learned late) take their items along
function A.forget(name)
  local s = store()
  if s and name then s[name] = nil end
end
function A.tidy()
  local s = store()
  if not s then return end
  local list = chars()
  for name, rec in pairs(s) do
    if not list[name] then
      local to = known(name)
      if to and not s[to] then s[to] = rec end
      s[name] = nil
    end
  end
end

-- who has an item, and where: { { name, class, bags, bank, mail, transit, total }, ... }, most first
function A.who(id)
  local out = {}
  local s = store()
  if not (s and id) then return out end
  for name, rec in pairs(s) do
    if chars()[name] then
      local e = { name = name, class = rec.class, bags = rec.bags and rec.bags[id] or 0, bank = rec.bank and rec.bank[id] or 0,
                  mail = rec.mail and rec.mail[id] or 0, transit = 0 }
      for _, t in ipairs(rec.transit or {}) do if t.id == id then e.transit = e.transit + t.n end end
      e.total = e.bags + e.bank + e.mail + e.transit
      if e.total > 0 then out[#out + 1] = e end
    end
  end
  table.sort(out, function(a, b) if a.total ~= b.total then return a.total > b.total end return a.name < b.name end)
  return out
end
function A.where(e)
  local parts = {}
  if e.bags > 0 then parts[#parts + 1] = e.bags .. " bags" end
  if e.bank > 0 then parts[#parts + 1] = e.bank .. " bank" end
  if e.mail > 0 then parts[#parts + 1] = e.mail .. " mailbox" end
  if e.transit > 0 then parts[#parts + 1] = e.transit .. " on the way" end
  return table.concat(parts, ", ")
end
local function color(class)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then return c.r, c.g, c.b end
  return 1, 0.82, 0
end
-- the tooltip lines: one for each character that has it, then a total
function A.lines(id)
  local out, total = {}, 0
  for _, e in ipairs(A.who(id)) do
    local r, g, b = color(e.class)
    out[#out + 1] = { left = e.name, right = A.where(e), r = r, g = g, b = b }
    total = total + e.total
  end
  if #out > 1 then out[#out + 1] = { left = "Total", right = tostring(total), r = 1, g = 0.82, b = 0 } end
  return out
end

-- ------------------------------------------------------------------ tooltips
function A.on() return not AuDHDDB.altItemsOff end
function A.setOn(on) AuDHDDB.altItemsOff = not on or nil end
local function addLines(tip, id)
  if not (A.on() and id and tip and tip.AddDoubleLine) then return end
  local lines = A.lines(id)
  if #lines == 0 then return end
  for _, l in ipairs(lines) do tip:AddDoubleLine(l.left, l.right, l.r, l.g, l.b, 1, 1, 1) end
  if tip.Show then tip:Show() end
end
A.addLines = addLines
local function itemOf(tip)
  local get = tip.GetItem or (TooltipUtil and TooltipUtil.GetDisplayedItem)
  if not get then return nil end
  local ok, _, link = pcall(get, tip)
  return ok and idOf(link) or nil
end
local hooked = false
local function hookTooltips()
  if hooked then return end
  hooked = true
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data)
      if tip ~= GameTooltip and tip ~= ItemRefTooltip then return end
      pcall(addLines, tip, (data and type(data.id) == "number" and data.id) or itemOf(tip))
    end)
    return
  end
  for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tip and tip.HookScript then
      tip:HookScript("OnTooltipSetItem", function(self) pcall(addLines, self, itemOf(self)) end)
    end
  end
end

-- ------------------------------------------------------------------ search
-- items whose name has the text in it, with who has them: { { id, name, who = A.who(id) }, ... }, by name
function A.find(text)
  local out = {}
  text = text and text:lower():gsub("^%s+", ""):gsub("%s+$", "")
  if not text or #text < 2 then return out end
  local seen = {}
  local s = store() or {}
  for name, rec in pairs(s) do
    if chars()[name] then
      local function add(id)
        if seen[id] then return end
        local n = AuDHDDB.itemNames and AuDHDDB.itemNames[id] or (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id))
        if n and n:lower():find(text, 1, true) then
          seen[id] = true
          out[#out + 1] = { id = id, name = n, who = A.who(id) }
        end
      end
      for _, k in ipairs({ "bags", "bank", "mail" }) do for id in pairs(rec[k] or {}) do add(id) end end
      for _, t in ipairs(rec.transit or {}) do add(t.id) end
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

local win
local function showFound()
  local text = win.box:GetText()
  local found = A.find(text)
  local rows, y = {}, 0
  for i, it in ipairs(found) do
    if i > MAX_FOUND then break end
    rows[#rows + 1] = { item = it }
    for _, e in ipairs(it.who) do rows[#rows + 1] = { who = e } end
  end
  for i, r in ipairs(rows) do
    local row = win.rows[i]
    if not row then
      row = ns.newFrame("AltItems", "Button", nil, win.list)
      row:SetSize(330, 16)
      row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      row.left:SetPoint("LEFT", 2, 0)
      row.left:SetWidth(180)
      row.left:SetJustifyH("LEFT")
      row.left:SetWordWrap(false)
      row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      row.right:SetPoint("RIGHT", -2, 0)
      row.right:SetJustifyH("RIGHT")
      row:SetScript("OnLeave", function() GameTooltip:Hide() end)
      win.rows[i] = row
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", win.list, "TOPLEFT", 0, -y)
    if r.item then
      local total = 0
      for _, e in ipairs(r.item.who) do total = total + e.total end
      row.left:SetText("|cffffd100" .. r.item.name .. "|r")
      row.left:SetTextColor(1, 1, 1)
      row.right:SetText(total)
      local id = r.item.id
      row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. id)
        GameTooltip:Show()
      end)
      y = y + (i > 1 and 4 or 0)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", win.list, "TOPLEFT", 0, -y)
    else
      row.left:SetText("    " .. r.who.name)
      row.left:SetTextColor(color(r.who.class))
      row.right:SetText(A.where(r.who))
      row:SetScript("OnEnter", nil)
    end
    row:Show()
    y = y + 16
  end
  for i = #rows + 1, #win.rows do win.rows[i]:Hide() end
  win.list:SetHeight(math.max(y, 1))
  local more = #found > MAX_FOUND and (" (the first " .. MAX_FOUND .. ")") or ""
  if #(text or "") < 2 then
    win.status:SetText("Type part of an item's name")
  elseif #found == 0 then
    win.status:SetText("None of your characters has one (bags, bank and mail; worn gear isn't counted)")
  else
    win.status:SetText(#found .. " item" .. (#found == 1 and "" or "s") .. more)
  end
end
function A.show(text)
  if not win then
    win = ns.newFrame("AltItems", "Frame", "AuDHDFind", UIParent, "BackdropTemplate")
    win:SetSize(380, 420)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                      tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetClampedToScreen(true)
    if UISpecialFrames then table.insert(UISpecialFrames, "AuDHDFind") end
    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Find an item on your characters")
    local close = ns.newFrame("AltItems", "Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    win.box = ns.newFrame("AltItems", "EditBox", nil, win, "InputBoxTemplate")
    win.box:SetSize(320, 20)
    win.box:SetPoint("TOPLEFT", 28, -42)
    win.box:SetAutoFocus(false)
    win.box:SetScript("OnTextChanged", function() pcall(showFound) end)
    win.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    win.box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    win.status = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.status:SetPoint("TOPLEFT", 24, -68)
    win.status:SetWidth(330)
    win.status:SetJustifyH("LEFT")
    local scroll = ns.newFrame("AltItems", "ScrollFrame", "AuDHDFindScroll", win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -86)
    scroll:SetPoint("BOTTOMRIGHT", -36, 34)
    win.list = ns.newFrame("AltItems", "Frame", nil, scroll)
    win.list:SetSize(330, 1)
    scroll:SetScrollChild(win.list)
    win.rows = {}
    local note = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", 22, 16)
    note:SetWidth(336)
    note:SetJustifyH("LEFT")
    note:SetText("Banks as they were when each character last closed theirs. Log in on a character once to add it")
  end
  win:Show()
  if text and text ~= "" then win.box:SetText(text) end
  win.box:SetFocus()
  pcall(showFound)
end
function A.command(rest)
  A.show(rest)
end

-- ------------------------------------------------------------------ alt bag windows
-- One window per character, their bags, bank or mail drawn as slots, picked from an Alts button on the backpack
local COLS, SLOT, GAP = 10, 37, 4
local WIDTH = 32 + COLS * (SLOT + GAP) - GAP
local bagWins, winCount = {}, 0
local VIEWS = { { "bags", "Bags" }, { "bank", "Bank" }, { "mail", "Mail" } }

function A.bagsButtonOn() return not AuDHDDB.altBagsButtonOff end
function A.setBagsButton(on)
  AuDHDDB.altBagsButtonOff = not on or nil
  if A.bagButton then A.bagButton:SetShown(on and true or false) end
  if A.bankButton then A.bankButton:SetShown(on and true or false) end
end
local function ago(t)
  local days = math.floor(((time and time() or t) - t) / 86400)
  if days <= 0 then return "today" elseif days == 1 then return "yesterday" end
  return days .. " days ago"
end
local function iconOf(id)
  if C_Item and C_Item.GetItemIconByID then
    local ok, t = pcall(C_Item.GetItemIconByID, id)
    if ok and t then return t end
  end
  if GetItemIcon then return GetItemIcon(id) end
end
-- the border colour: from the link's colour, else the item's quality; white and grey items get none
local function qualityColor(link, id)
  local hex = link and link:match("|cff(%x%x%x%x%x%x)")
  if hex then
    if hex == "ffffff" or hex == "9d9d9d" then return nil end
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, true
  end
  local q = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
  local c = q and q >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if c then return c.r, c.g, c.b, true end
end
-- what one view holds: slots { { link, n, onTheWay } or false }, and a line under them
local function viewOf(name, view)
  local rec = (store() or {})[name]
  if view == "bags" then
    if not (rec and rec.bagSlots) then return {}, "Log in on " .. name .. " once to see their bags here" end
    return rec.bagSlots, nil
  elseif view == "bank" then
    if not (rec and rec.bankSlots) then return {}, "Open the bank on " .. name .. " once to see it here" end
    return rec.bankSlots, "The bank as it was " .. (rec.bankSeen and ago(rec.bankSeen) or "last seen")
  end
  local slots, ids = {}, {}
  for id in pairs(rec and rec.mail or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do slots[#slots + 1] = { "item:" .. id, rec.mail[id] } end
  for _, t in ipairs(rec and rec.transit or {}) do slots[#slots + 1] = { "item:" .. t.id, t.n, true } end
  if #slots == 0 then return slots, "Nothing in the mail (as of the last time " .. name .. " opened the mailbox)" end
  return slots, "In the mailbox when " .. name .. " last opened it. Faded: mail on the way"
end
local function slotButton(w, i)
  local b = w.slots[i]
  if b then return b end
  b = ns.newFrame("AltItems", "Button", nil, w)
  b:SetSize(SLOT, SLOT)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
  b.bg:SetTexCoord(0.140625, 0.859375, 0.140625, 0.859375)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.glow = b:CreateTexture(nil, "OVERLAY")
  b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  b.glow:SetBlendMode("ADD")
  b.glow:SetSize(SLOT * 1.8, SLOT * 1.8)
  b.glow:SetPoint("CENTER")
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.count:SetPoint("BOTTOMRIGHT", -3, 3)
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:RegisterForClicks("AnyUp")
  b:SetScript("OnEnter", function(self)
    if not self.link then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(self.link:match("|H(item:[^|]+)|h") or self.link)
    if self.onTheWay then GameTooltip:AddLine("On the way by mail", 0.6, 0.6, 0.6) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- shift-click puts the item's link in chat, as in your own bags
  b:SetScript("OnClick", function(self)
    if not (self.link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink) then return end
    local link = self.link:find("|H") and self.link or select(2, GetItemInfo(self.link))
    if link then ChatEdit_InsertLink(link) end
  end)
  w.slots[i] = b
  return b
end
local function draw(w)
  local slots, note = viewOf(w.char, w.view)
  for i, s in ipairs(slots) do
    local b = slotButton(w, i)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 16 + ((i - 1) % COLS) * (SLOT + GAP), -40 - math.floor((i - 1) / COLS) * (SLOT + GAP))
    if s then
      local id = idOf(s[1])
      b.link, b.onTheWay = s[1], s[3]
      b.icon:SetTexture(id and iconOf(id) or "Interface\\Icons\\INV_Misc_QuestionMark")
      b.icon:SetDesaturated(s[3] and true or false)
      b.icon:SetAlpha(s[3] and 0.5 or 1)
      b.icon:Show()
      b.count:SetText((s[2] or 1) > 1 and s[2] or "")
      local r, g, bl, show = qualityColor(s[1], id)
      if show then b.glow:SetVertexColor(r, g, bl) b.glow:Show() else b.glow:Hide() end
    else
      b.link, b.onTheWay = nil, nil
      b.icon:Hide() b.glow:Hide()
      b.count:SetText("")
    end
    b:Show()
  end
  for i = #slots + 1, #w.slots do w.slots[i]:Hide() end
  local rows = math.max(1, math.ceil(#slots / COLS))
  local y = 40 + rows * (SLOT + GAP) + 4
  w.note:ClearAllPoints()
  w.note:SetPoint("TOPLEFT", 18, -y)
  w.note:SetText(note or "")
  y = y + (note and (w.note:GetStringHeight() or 12) + 6 or 0)
  for _, t in ipairs(w.tabs) do
    if t.view == w.view then t:LockHighlight() else t:UnlockHighlight() end
  end
  w:SetSize(WIDTH, y + 44)
end
local function bagWindow(name)
  local w = bagWins[name]
  if w then return w end
  winCount = winCount + 1
  local global = "AuDHDAltBag" .. winCount
  w = ns.newFrame("AltItems", "Frame", global, UIParent, "BackdropTemplate")
  w:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                  tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
  w:SetFrameStrata("HIGH")
  w:EnableMouse(true)
  w:SetMovable(true)
  w:RegisterForDrag("LeftButton")
  w:SetScript("OnDragStart", w.StartMoving)
  w:SetScript("OnDragStop", w.StopMovingOrSizing)
  w:SetClampedToScreen(true)
  if UISpecialFrames then table.insert(UISpecialFrames, global) end
  w.char, w.view, w.slots, w.tabs = name, "bags", {}, {}
  w.title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  w.title:SetPoint("TOP", 0, -16)
  local close = ns.newFrame("AltItems", "Button", nil, w, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)
  w.note = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  w.note:SetWidth(WIDTH - 36)
  w.note:SetJustifyH("LEFT")
  for i, v in ipairs(VIEWS) do
    local t = ns.newFrame("AltItems", "Button", nil, w, "UIPanelButtonTemplate")
    t:SetSize(70, 22)
    t:SetPoint("BOTTOMLEFT", 16 + (i - 1) * 74, 16)
    t:SetText(v[2])
    t.view = v[1]
    t:SetScript("OnClick", function() w.view = v[1] pcall(draw, w) end)
    w.tabs[i] = t
  end
  bagWins[name] = w
  return w
end
-- the characters there's something to show for: { name, class, me }, you last
function A.bagChars()
  local out, myName = {}, me()
  for name, rec in pairs(store() or {}) do
    if chars()[name] then out[#out + 1] = { name = name, class = rec.class, me = name == myName } end
  end
  table.sort(out, function(a, b) if a.me ~= b.me then return b.me end return a.name < b.name end)
  return out
end
function A.openBags(name, x, y)
  local w = bagWindow(name)
  local rec = (store() or {})[name]
  w.title:SetText(name)
  w.title:SetTextColor(color(rec and rec.class))
  pcall(draw, w)
  w:ClearAllPoints()
  if x then w:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y) else w:SetPoint("RIGHT", UIParent, "CENTER", -40, 40) end
  w:Show()
  return w
end
-- every other character's bags, side by side, wrapping onto a second row
function A.showAll()
  local x, y, rowH = 20, -80, 0
  local maxW = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 1920
  local n = 0
  for _, c in ipairs(A.bagChars()) do
    if not c.me then
      if x + WIDTH > maxW and x > 20 then x, y, rowH = 20, y - rowH - 8, 0 end
      local w = A.openBags(c.name, x, y)
      x = x + WIDTH + 8
      rowH = math.max(rowH, w:GetHeight() or 0)
      n = n + 1
    end
  end
  return n
end
function A.closeAll() for _, w in pairs(bagWins) do w:Hide() end end
-- your own bank, as it was when you last closed it. With toggle, a second go closes it (then false)
function A.openBank(toggle)
  local name = me()
  if not name then return nil end
  local w = bagWins[name]
  if toggle and w and w:IsShown() and w.view == "bank" then w:Hide() return false end
  bagWindow(name).view = "bank"
  A.openBags(name)
  return true
end
-- after the game's open-all-bags with Shift held (Shift-B): your bank window opens and closes with the bags. Only ever
-- after the game's own code has run, so its bag frames are never opened from here
function A.allBagsToggled()
  if not (IsShiftKeyDown and IsShiftKeyDown()) then return end
  local name = me()
  if not name then return end
  if IsBagOpen and IsBagOpen(0) then
    A.openBank()
  else
    local w = bagWins[name]
    if w and w:IsShown() and w.view == "bank" then w:Hide() end
  end
end
local function redraw() for _, w in pairs(bagWins) do if w:IsShown() then pcall(draw, w) end end end
A.redraw = redraw

-- the Alts list: each character, Show all, Close all, Find an item
local picker
function A.pick(anchor)
  if not picker then
    picker = ns.newFrame("AltItems", "Frame", "AuDHDAltBagPick", UIParent, "BackdropTemplate")
    picker:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                         tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    picker:SetBackdropColor(0, 0, 0, 0.95)
    picker:SetFrameStrata("FULLSCREEN_DIALOG")
    picker:EnableMouse(true)
    picker.lines = {}
    picker:Hide()   -- (a new frame starts shown: the first click would only hide it)
  end
  if picker:IsShown() then picker:Hide() return end
  local items = {}
  for _, c in ipairs(A.bagChars()) do
    local r, g, b = color(c.class)
    items[#items + 1] = { ("|cff%02x%02x%02x%s|r%s"):format(r * 255, g * 255, b * 255, c.name, c.me and " |cff999999(you: bank and mail)|r" or ""),
                          function() A.openBags(c.name) end }
  end
  if #items == 0 then items[1] = { "|cff999999Log in on each character once to see their bags|r" } end
  items[#items + 1] = { "Show all", function() A.showAll() end }
  items[#items + 1] = { "Close all", function() A.closeAll() end }
  items[#items + 1] = { "Find an item...", function() A.show() end }
  for i, it in ipairs(items) do
    local b = picker.lines[i]
    if not b then
      b = ns.newFrame("AltItems", "Button", nil, picker)
      b:SetSize(240, 18)
      b:SetPoint("TOPLEFT", 8, -6 - (i - 1) * 18)
      b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      b.text:SetPoint("LEFT", 4, 0)
      picker.lines[i] = b
    end
    b.text:SetText(it[1])
    b:SetScript("OnClick", it[2] and function() picker:Hide() pcall(it[2]) end or nil)
    b:Show()
  end
  for i = #items + 1, #picker.lines do picker.lines[i]:Hide() end
  picker:SetSize(256, 12 + #items * 18)
  picker:ClearAllPoints()
  if anchor == UIParent then picker:SetPoint("CENTER") else picker:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 2) end
  picker:Show()
end

-- the Alts button, sitting on top of the game's backpack, and the Bank button beside it
local function placeBankButton(bag)
  local b = A.bankButton
  if not b then
    b = ns.newFrame("AltItems", "Button", "AuDHDBankBagsButton", UIParent, "UIPanelButtonTemplate")
    b:SetSize(60, 20)
    b:SetText("Bank")
    b:SetScript("OnClick", function() pcall(A.openBank, true) end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetText("Your bank")
      GameTooltip:AddLine("What's in your bank, as it was when you last closed it", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    A.bankButton = b
  end
  b:SetParent(bag)
  b:ClearAllPoints()
  b:SetPoint("RIGHT", A.bagButton, "LEFT", -4, 0)
  b:SetShown(A.bagsButtonOn())
end
local function placeBagButton(bag)
  local b = A.bagButton
  if not b then
    b = ns.newFrame("AltItems", "Button", "AuDHDAltBagsButton", UIParent, "UIPanelButtonTemplate")
    b:SetSize(70, 20)
    b:SetText("Alts")
    b:SetScript("OnClick", function(self) pcall(A.pick, self) end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetText("Your characters' bags")
      GameTooltip:AddLine("See another character's bags, bank or mail, or all of them at once", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    A.bagButton = b
  end
  b:SetParent(bag)
  b:ClearAllPoints()
  b:SetPoint("BOTTOMRIGHT", bag, "TOPRIGHT", -8, -2)
  b:SetShown(A.bagsButtonOn())
  placeBankButton(bag)
end
-- the reagent bag with the backpack: B runs the game's own open-all-bags (bindKeys), which opens it too. Never opened
-- or closed from here: the game's bag frames keep that taint, and the bank's purchase reads it
function A.reagentOn() return not AuDHDDB.reagentWithBagsOff end
function A.setReagent(on)
  AuDHDDB.reagentWithBagsOff = not on or nil
  A.bindKeys()
end
local function reagentBag()
  local r = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
  if not r or not C_Container or (C_Container.GetContainerNumSlots(r) or 0) == 0 then return nil end
  return r
end
local function hookBags()
  for i = 1, NUM_CONTAINER_FRAMES or 13 do
    local f = _G["ContainerFrame" .. i]
    if f and f.HookScript then
      f:HookScript("OnShow", function(self)
        if self.GetID and self:GetID() == 0 then pcall(placeBagButton, self) end
      end)
    end
  end
  if ContainerFrameCombinedBags and ContainerFrameCombinedBags.HookScript then
    ContainerFrameCombinedBags:HookScript("OnShow", function(self) pcall(placeBagButton, self) end)
  end
  if hooksecurefunc and ToggleAllBags then hooksecurefunc("ToggleAllBags", function() pcall(A.allBagsToggled) end) end
end
-- /audhd bags [all|close|<name>]
function A.bagsCommand(rest)
  rest = rest and rest:gsub("^%s+", ""):gsub("%s+$", "") or ""
  if rest == "all" then
    if A.showAll() == 0 then return "no other characters yet: log in on each once" end
    return nil
  elseif rest == "close" then A.closeAll() return nil
  elseif rest == "" then
    A.pick(A.bagButton and A.bagButton:IsVisible() and A.bagButton or UIParent)
    return nil
  end
  local name = known(rest)
  if not name or not (store() or {})[name] then return "no saved bags for " .. rest .. " (log in on them once)" end
  A.openBags(name)
end

-- ------------------------------------------------------------------ events
local frame = ns.newFrame("AltItems", "Frame")
-- Shift-B runs the game's own open-all-bags, as an override (your saved key bindings stay as they are), and the bank
-- window follows (A.allBagsToggled). B does too while you have a reagent bag and the setting is on, so it opens with
-- the backpack. Neither key when it's bound to something other than your bags. Out of combat only (waits for it)
local hadReagent
local function bindKeys()
  if not (GetBindingAction and SetOverrideBinding and ClearOverrideBindings) then return end
  if InCombatLockdown and InCombatLockdown() then
    pcall(frame.RegisterEvent, frame, "PLAYER_REGEN_ENABLED")
    return
  end
  local function bagKey(key)
    local now = GetBindingAction(key) or ""
    return now == "" or now:find("BAG") or now:find("BACKPACK")
  end
  hadReagent = reagentBag() ~= nil
  ClearOverrideBindings(frame)
  if bagKey("SHIFT-B") then SetOverrideBinding(frame, false, "SHIFT-B", "OPENALLBAGS") end
  if hadReagent and A.reagentOn() and bagKey("B") then SetOverrideBinding(frame, false, "B", "OPENALLBAGS") end
end
A.bindKeys = bindKeys
for _, e in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED",
                     "MAIL_INBOX_UPDATE", "MAIL_SEND_SUCCESS", "MAIL_FAILED" }) do
  pcall(frame.RegisterEvent, frame, e)
end
frame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    pcall(hookTooltips)
    pcall(hookBags)
    pcall(bindKeys)
    if hooksecurefunc and SendMail then hooksecurefunc("SendMail", function(to) pcall(A.sending, to) end) end
    -- after Services has noted this character (the surname can come late)
    C_Timer.After(6, function() pcall(A.tidy) pcall(A.scanBags) end)
  elseif event == "BAG_UPDATE_DELAYED" then
    pcall(A.scanBags)
    pcall(A.scanBank)
    -- a reagent bag put on or taken off (the bag's size can come after login)
    if (reagentBag() ~= nil) ~= hadReagent then pcall(bindKeys) end
  elseif event == "BANKFRAME_OPENED" then
    bankOpen = true
    pcall(A.scanBank)
  elseif event == "PLAYERBANKSLOTS_CHANGED" then
    pcall(A.scanBank)
  elseif event == "BANKFRAME_CLOSED" then
    pcall(A.scanBank)
    bankOpen = false
  elseif event == "MAIL_INBOX_UPDATE" then
    pcall(A.scanInbox)
  elseif event == "MAIL_SEND_SUCCESS" then
    pcall(A.sent)
    redraw()
  elseif event == "MAIL_FAILED" then
    pcall(A.mailFailed)
  elseif event == "PLAYER_REGEN_ENABLED" then
    frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    pcall(bindKeys)
  end
end)
