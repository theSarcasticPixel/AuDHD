-- Reminders when you pass a service (the user, 2026-10-17): bags full or nearly full within 100 yards of a vendor -
-- sell; class skills to learn within 100 yards of your class trainer - train. Once per visit: it comes back after you've
-- been 200 yards away (or when it changes: bags filling up again, a new level's skills).
-- And a mailbox within 100 yards with BoEs or materials in your bags: mail them to your bank alt (the user, 2026-10-28:
-- "make a bank alt and have it sit in a city and have prompts to send excess materials and BoEs to the bank alt when
-- we are going to be running by a mailbox").
local _, ns = ...
local M = {}
ns.services = M
local log = function(e, f) if ns.log then ns.log.add(e, f) end end
local isSecret = issecretvalue or function() return false end

local NEAR, AWAY = 100, 200
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
function M.bankAlt()
  local a = AuDHDDB.bankAlt
  if not a or a == "" then return nil end
  local me = UnitName and UnitName("player")
  if me and a:lower() == me:lower() then return nil end   -- you are the bank alt
  return a
end
-- the route needs it: an item named in one of its steps (Linen Cloth for a quest; done steps too, kept simple)
local function routeNeeds(name)
  local r = ns.core and ns.core.route and ns.core.route()
  if not (r and r.steps and name) then return false end
  for _, st in pairs(r.steps) do
    if st.t and st.t:find(name, 1, true) then return true end
  end
  return false
end
-- what to mail the bank alt: BoE gear you wouldn't wear (green or better, not bound yet) and materials (Trade Goods),
-- not bound and not needed by the route. A list of { bag, slot, kind = "boe" | "mat" }
function M.mailables()
  local out = {}
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      local link = info and info.hyperlink
      if link and not info.isBound and not info.isLocked then
        local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(link)
        local name = C_Item.GetItemInfo(link)
        if (classID == 2 or classID == 4) and equipLoc and equipLoc ~= "" and (info.quality or 0) >= 2
            and not (ns.auto and ns.auto.wouldWear and ns.auto.wouldWear(link)) then
          out[#out + 1] = { bag = bag, slot = slot, kind = "boe" }
        elseif classID == 7 and not routeNeeds(name) then
          out[#out + 1] = { bag = bag, slot = slot, kind = "mat" }
        end
      end
    end
  end
  return out
end
local function mailText(list, box, d)
  local boe, mat = 0, 0
  for _, it in ipairs(list) do if it.kind == "boe" then boe = boe + 1 else mat = mat + 1 end end
  local parts = {}
  if boe > 0 then parts[#parts + 1] = boe .. " BoE" end
  if mat > 0 then parts[#parts + 1] = mat .. " materials" end
  return ("%s %d yd: mail %s to %s"):format(box.n, math.floor(d), table.concat(parts, " + "), M.bankAlt())
end

-- ------------------------------------------------------------------ the pop-ups
-- a pop-up per kind, with Go to (your /way arrow to it) and Snooze 10 / 20 / 30 minutes. Said once per visit; passing
-- from one vendor to the next only changes its text (the user, 2026-10-17: "have it be a pop-up that you can click go
-- to > ignore"; 2026-10-28: "it was very annoying getting the pop up, telling it no, then running a few more steps and
-- getting another pop up. we should be able to snooze the alerts for 10,20,30 mins")
local SNOOZE = { 10, 20, 30 }   -- minutes
local shown = {}     -- kind -> { e = the service, key = what was said }
local snoozed = {}   -- kind -> GetTime() until which it stays quiet
local pops = {}      -- kind -> its pop-up frame
local SLOT = { vendor = 0, trainer = 1, mail = 2, banktip = 2 }
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
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
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
  local function close() f.open = false f:Hide() end
  if kind == "banktip" then
    -- said once ever: OK puts it away for good
    f:SetHeight(92)
    f.ok = button("OK", -50, 90, function() AuDHDDB.bankAltTipped = true log("BANKALT_TIP_OK", {}) close() end)
    f.settings = button("Settings", 50, 90, function()
      AuDHDDB.bankAltTipped = true
      if ns.settings and ns.settings.show then ns.settings.show() end
      close()
    end)
  else
    f.go = button("Go to", -108, 72, function()
      local s = shown[kind]
      if s and ns.way then ns.way.set(s.e.m, s.e.x, s.e.y, s.e.n) end
      log("SERVICE_GOTO", { kind = kind, npc = s and s.e.n })
      close()
    end)
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
    if pops[kind] then pops[kind].msg = text pops[kind].text:SetText(text) end
    return
  end
  shown[kind] = { e = e, key = key }
  local f = popup(kind)
  f.msg, f.open = text, true
  f.text:SetText(text)
  f:Show()
  PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
  log("SERVICE_NEAR", { kind = kind, npc = e.n, yd = math.floor(d), key = key })
end
local function drop(kind)
  shown[kind] = nil
  if pops[kind] then pops[kind].open = false pops[kind]:Hide() end
end
local function forget(kind, P)
  local s = shown[kind]
  if not s then return end
  local w = placeOf(s.e)
  if not w or w.c ~= P.c or math.sqrt((w.wx - P.wx) ^ 2 + (w.wy - P.wy) ^ 2) > AWAY then drop(kind) end
end
-- the smoke test: what a pop-up says (nil when it's not up), and its buttons
function M.popupText(kind) local f = pops[kind] return f and f.open and f.msg or nil end
function M.click(kind, which)
  local b = pops[kind] and pops[kind][which]
  local fn = b and (b.scripts and b.scripts.OnClick or b:GetScript("OnClick"))
  if fn then fn(b) end
end

local KINDS = { "vendor", "trainer", "mail", "banktip" }
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
  if not AuDHDDB.mailOff then
    local box, d = nearest(ns.mailboxes, P)
    if box and d <= NEAR then
      local list = M.mailables()
      if #list >= MAIL_MIN then
        if M.bankAlt() then
          remind("mail", box, d, "mail", mailText(list, box, d))
        elseif not AuDHDDB.bankAltTipped and UnitLevel("player") >= 10 then
          -- no bank alt yet: say once what it's for
          remind("banktip", box, d, "tip", "Tip: make a bank alt and park it in a city. Set its name in Settings"
            .. " (or /wfn bankalt <name>) and I'll remind you to mail it your BoEs and materials at mailboxes on the way.")
        end
      end
    end
  end
end

-- ------------------------------------------------------------------ at the mailbox: one click fills the mail
-- A button on the mail window: switches to Send Mail, puts the bank alt's name in and attaches what's to go (12 at
-- most, the game's limit); you check it and press Send.
local mailButton
function M.fillMail()
  local alt = M.bankAlt()
  if not alt then return 0 end
  if MailFrameTab_OnClick then pcall(MailFrameTab_OnClick, nil, 2) end
  if SendMailNameEditBox then SendMailNameEditBox:SetText(alt) end
  if SendMailSubjectEditBox and SendMailSubjectEditBox:GetText() == "" then SendMailSubjectEditBox:SetText("For the bank") end
  local n, max = 0, ATTACHMENTS_MAX_SEND or 12
  for _, it in ipairs(M.mailables()) do
    if n >= max then break end
    ClearCursor()
    C_Container.PickupContainerItem(it.bag, it.slot)
    n = n + 1
    ClickSendMailItemButton(n)
  end
  ClearCursor()
  log("BANKALT_FILL", { n = n })
  return n
end
local function mailShown()
  if AuDHDDB.mailOff or not M.bankAlt() or not MailFrame then return end
  if not mailButton then
    mailButton = ns.newFrame("Services", "Button", "AuDHDMailFill", MailFrame, "UIPanelButtonTemplate")
    mailButton:SetSize(170, 22)
    mailButton:SetPoint("TOPRIGHT", MailFrame, "BOTTOMRIGHT", 0, -2)
    mailButton:SetScript("OnClick", function() pcall(M.fillMail) end)
  end
  local n = #M.mailables()
  mailButton:SetText(("Fill mail to %s (%d)"):format(M.bankAlt(), n))
  mailButton:SetShown(n > 0)
  drop("mail")
end

function M.command(rest)
  if rest == "" then
    print("|cff66ccffAuDHD|r: bank alt " .. (AuDHDDB.bankAlt or "not set") .. (AuDHDDB.mailOff and " (reminders off)" or "")
      .. ". /wfn bankalt <name>, /wfn bankalt off|on, /wfn bankalt clear")
  elseif rest == "off" then AuDHDDB.mailOff = true drop("mail")
  elseif rest == "on" then AuDHDDB.mailOff = nil
  elseif rest == "clear" then AuDHDDB.bankAlt = nil drop("mail")
  else
    AuDHDDB.bankAlt = rest:gsub("^%l", string.upper)
    AuDHDDB.bankAltTipped = true
    drop("banktip")
    print("|cff66ccffAuDHD|r: bank alt set to " .. AuDHDDB.bankAlt)
  end
end

local frame = ns.newFrame("Services", "Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("MAIL_SHOW")
frame:SetScript("OnEvent", function(_, event)
  if event == "MAIL_SHOW" then pcall(mailShown) return end
  C_Timer.NewTicker(2, function() pcall(M.check) end)
end)
