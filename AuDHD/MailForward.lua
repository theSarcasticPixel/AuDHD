-- Forward to alt: a Forward button on an opened mail (one with items or money, not Cash on Delivery) and a list of
-- your alts (your characters on this realm and side, and the alt mail names ticked Other account). Picking one takes
-- the items and money into your bags, then sends them on, "Fwd: <subject>", 12 items a mail: the same items and
-- counts (a stack that joined one already in your bags is split back off). Postage is yours. When the game keeps mail
-- sending to itself, the mail is filled and you press Send (as Send all does). Settings, Alt mail
local _, ns = ...
local F = {}
ns.mailForward = F

local function log(e, t) if ns.log then ns.log.add(e, t) end end
local function say(msg) print("|cff66ccffAuDHD|r: " .. msg) end
local function sv() return ns.services end

function F.on() return not AuDHDDB.mailForwardOff end
function F.set(v)
  AuDHDDB.mailForwardOff = not v or nil
  if F.button then F.update() end
end

-- the alts mail may go to, sorted
function F.alts()
  local S = sv()
  if not S then return {} end
  local out, seen = {}, {}
  local function add(name, other)
    name = S.cleanName(name)
    if not name or seen[name:lower()] or S.whyNot(name, other) then return end
    seen[name:lower()] = true
    out[#out + 1] = name
  end
  for _, n in ipairs(S.myChars()) do add(n) end
  local c = S.cfg()
  if c.bankAltOther then add(c.bankAlt, true) end
  for _, r in pairs(c.altMail and c.altMail.rows or {}) do if r.other then add(r.name, true) end end
  table.sort(out)
  return out
end

-- what an inbox mail holds: { sender, subject, body, money, cod, items = { { a = slot, id, count } } }
local MAX_IN = ATTACHMENTS_MAX_RECEIVE or 16
function F.read(index)
  if not (index and GetInboxHeaderInfo) then return nil end
  local _, _, sender, subject, money, cod = GetInboxHeaderInfo(index)
  local m = { sender = sender, subject = subject or "", money = money or 0, cod = cod or 0, items = {} }
  m.body = GetInboxText and GetInboxText(index) or ""
  for a = 1, MAX_IN do
    local _, id, _, count = GetInboxItem(index, a)
    if id then m.items[#m.items + 1] = { a = a, id = id, count = count or 1 } end
  end
  return m
end
local function worth(m) return m and m.cod == 0 and (#m.items > 0 or m.money > 0) end

-- ------------------------------------------------------------------ the forwarding
local job   -- { to, m, index, step, before, wait, look, tries, mails, money0, token }
local function stop(why)
  if job and why then say("forwarding stopped: " .. why) log("MAIL_FORWARD_STOP", { why = why }) end
  job = nil
end
-- whether the mail at the index is still the one being forwarded (taking the last thing can delete it and move the rest)
local function same(m)
  if not GetInboxHeaderInfo then return false end
  local _, _, sender, subject = GetInboxHeaderInfo(job.index)
  return sender == m.sender and (subject or "") == m.subject
end
-- the attachment slot holding this item and count now (taking one can move the rest along)
local function slotOf(it)
  for a = 1, MAX_IN do
    local _, id, _, n = GetInboxItem(job.index, a)
    if id == it.id and (n or 1) == it.count then return a end
  end
end
-- how many of an item your bags hold (the reagent bag too), locked stacks counted
local function have(id)
  local n = 0
  for _, b in ipairs(ns.bagIDs()) do
    for sl = 1, C_Container.GetContainerNumSlots(b) or 0 do
      local info = C_Container.GetContainerItemInfo(b, sl)
      if info and info.itemID == id then n = n + (info.stackCount or 1) end
    end
  end
  return n
end

-- the bag slots that make up the items again: each item's count from its stacks, the last one split (the reagent bag
-- too: materials go there by themselves)
function F.slots(items)
  local out, used = {}, {}
  for _, it in ipairs(items) do
    local need = it.count
    -- a stack of the exact size first, then any
    for pass = 1, 2 do
      for _, b in ipairs(ns.bagIDs()) do
        for s = 1, C_Container.GetContainerNumSlots(b) or 0 do
          local info = need > 0 and not used[b * 100 + s] and C_Container.GetContainerItemInfo(b, s)
          if info and info.itemID == it.id and not info.isLocked and (pass == 2 or info.stackCount == need) then
            local take = math.min(need, info.stackCount)
            used[b * 100 + s] = true
            out[#out + 1] = { bag = b, slot = s, split = take < info.stackCount and take or nil }
            need = need - take
          end
        end
      end
    end
    if need > 0 then return nil, it.id end
  end
  return out
end

local function sendMail(list, money)
  local S = sv()
  local m = job.m
  local subject = ("Fwd: " .. m.subject):sub(1, 64)
  S.fillMail(list, job.to)
  if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText(subject) end
  if money > 0 and SetSendMailMoney then SetSendMailMoney(money) end
  if S.cfg().mailManual then
    say(("the mail to %s is filled: press Send.%s"):format(job.to, #job.mails > 0 and " The rest of the items are in your bags." or ""))
    job = nil
    return
  end
  job.token = (job.token or 0) + 1
  local token = job.token
  local ok = pcall(SendMail, job.to, subject, m.body or "")
  if not ok then return stop("the game wouldn't send it") end
  C_Timer.After(15, function() if job and job.token == token then stop("no answer from the mailbox") end end)
end
local function sendNext()
  local list = table.remove(job.mails, 1)
  if not list then
    say(("forwarded to %s."):format(job.to))
    log("MAIL_FORWARD_DONE", {})
    job = nil
    -- back to the inbox, for the next one
    if MailFrameTab_OnClick then pcall(MailFrameTab_OnClick, nil, 1) end
    return
  end
  local money = job.sendMoney or 0
  job.sendMoney = 0
  sendMail(list, money)
end

-- the items and money are in the bags: make them up into mails (a stack just arrived can be locked a moment: looked for
-- again for 5 seconds)
local function attachAll()
  local m = job.m
  local slots, missing = F.slots(m.items)
  if not slots then
    job.tries = (job.tries or 0) + 1
    if job.tries < 17 then C_Timer.After(0.3, function() if job then attachAll() end end) return end
    return stop("item " .. missing .. " isn't in your bags")
  end
  job.mails = {}
  local max = ATTACHMENTS_MAX_SEND or 12
  for i, sl in ipairs(slots) do
    local k = math.floor((i - 1) / max) + 1
    job.mails[k] = job.mails[k] or {}
    table.insert(job.mails[k], sl)
  end
  if #job.mails == 0 then job.mails[1] = {} end
  local postage = (GetSendMailPrice and GetSendMailPrice() or 30) * #slots
  if (GetMoney and GetMoney() or 0) < m.money + math.max(postage, 30) then return stop("not enough money for the postage") end
  job.sendMoney = m.money
  sendNext()
end

-- take the next attachment out of the mail, done once your bags hold that many more of it (the mail can look empty
-- before they do, and the game ignores a take while the last one is still going); once everything is in, send it on
local function step()
  if not job then return end
  local m = job.m
  local it = m.items[job.step]
  if it then
    if job.wait then
      if have(it.id) >= job.before + it.count then
        job.step, job.wait = job.step + 1, nil
        return step()
      end
      if GetTime() - job.wait > 6 then return stop("an item didn't come out of the mail") end
    else
      -- (the mail can look empty a moment after a take: looked for again for 3 seconds)
      local a = same(m) and slotOf(it)
      if not a then
        job.look = job.look or GetTime()
        if GetTime() - job.look > 3 then return stop("the mail changed") end
        C_Timer.After(0.2, step)
        return
      end
      job.before, job.wait, job.look = have(it.id), GetTime(), nil
      TakeInboxItem(job.index, a)
    end
    C_Timer.After(0.2, step)
    return
  end
  if m.money > 0 and not job.gotMoney then
    if job.wait and (not same(m) or (GetMoney() or 0) >= job.money0 + m.money) then
      job.gotMoney, job.wait = true, nil
      return step()
    end
    if not job.wait then
      if not same(m) then return stop("the mail changed") end
      job.money0, job.wait = GetMoney() or 0, GetTime()
      TakeInboxMoney(job.index)
    elseif GetTime() - job.wait > 6 then
      return stop("the money didn't come out of the mail")
    end
    C_Timer.After(0.2, step)
    return
  end
  -- (the bags settle a moment after the last item lands)
  C_Timer.After(0.3, function() if job then attachAll() end end)
end

-- forward the mail at index to an alt; nil, or why not
function F.forward(index, to)
  if job then return "already forwarding a mail" end
  local m = F.read(index)
  if not m then return "no mail open" end
  if m.cod > 0 then return "Cash on Delivery mail can't be forwarded" end
  if not worth(m) then return "nothing to forward: no items or money" end
  local S = sv()
  local free = S and S.bagSpace and select(1, S.bagSpace()) or 0
  if free < #m.items then return ("%d free bag slots needed, you have %d"):format(#m.items, free) end
  job = { to = to, m = m, index = index, step = 1 }
  log("MAIL_FORWARD", { items = #m.items })
  step()
  return nil
end
function F.busy() return job ~= nil end
function F.mailEvent(event, a1, a2)
  if not job then return end
  if event == "MAIL_SEND_SUCCESS" and job.mails then
    job.token = nil
    C_Timer.After(0.5, function() if job then sendNext() end end)
  elseif event == "MAIL_FAILED" and job.mails then
    stop("a mail didn't go (the game said why)")
  elseif event == "MAIL_CLOSED" then
    stop("the mailbox closed (what was taken is in your bags)")
  elseif (event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN") and a1 == "AuDHD" then
    job = nil   -- (Services says it and fills from now on)
  end
end

-- ------------------------------------------------------------------ the button and the list
local function openIndex() return InboxFrame and InboxFrame.openMailID end
local menu
local function showList(owner)
  local alts = F.alts()
  if #alts == 0 then
    say("no alts to forward to: log in once on each with AuDHD, or tick Other account in Settings, Alt mail")
    return
  end
  local function pick(name)
    local why = F.forward(openIndex(), name)
    if why then say(why) end
  end
  if MenuUtil and MenuUtil.CreateContextMenu then
    MenuUtil.CreateContextMenu(owner, function(_, root)
      root:CreateTitle("Forward to")
      for _, n in ipairs(alts) do root:CreateButton(n, function() pick(n) end) end
    end)
    return
  end
  if not (UIDropDownMenu_Initialize and ToggleDropDownMenu) then return end
  menu = menu or CreateFrame("Frame", "AuDHDForwardMenu", UIParent, "UIDropDownMenuTemplate")
  UIDropDownMenu_Initialize(menu, function()
    local t = UIDropDownMenu_CreateInfo()
    t.text, t.isTitle, t.notCheckable = "Forward to", true, true
    UIDropDownMenu_AddButton(t)
    for _, n in ipairs(alts) do
      t = UIDropDownMenu_CreateInfo()
      t.text, t.notCheckable, t.func = n, true, function() pick(n) end
      UIDropDownMenu_AddButton(t)
    end
  end, "MENU")
  ToggleDropDownMenu(1, nil, menu, owner, 0, 0)
end
F.showList = showList

function F.update()
  local b = F.button
  if not b then return end
  b:SetShown(F.on() and worth(F.read(openIndex())) or false)
end
function F.hook()
  if F.button or not OpenMailFrame then return F.button ~= nil end
  local b = ns.newFrame("MailForward", "Button", "AuDHDForwardButton", OpenMailFrame, "UIPanelButtonTemplate")
  b:SetSize(80, 20)
  b:SetText("Forward")
  if OpenMailAttachmentText then
    b:SetPoint("TOP", OpenMailAttachmentText, "TOP", 0, 3)
    b:SetPoint("RIGHT", OpenMailFrame, "RIGHT", -14, 0)
  else
    b:SetPoint("BOTTOMRIGHT", OpenMailFrame, "BOTTOMRIGHT", -14, 110)
  end
  b:SetScript("OnClick", function(self) showList(self) end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Forward to an alt", 1, 1, 1)
    GameTooltip:AddLine("Takes the items and money and mails them on. Postage is yours.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  F.button = b
  OpenMailFrame:HookScript("OnShow", function() pcall(F.update) end)
  F.update()
  return true
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "MAIL_INBOX_UPDATE", "MAIL_SEND_SUCCESS", "MAIL_FAILED", "MAIL_CLOSED",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then pcall(F.hook) return end
  if event == "MAIL_INBOX_UPDATE" then pcall(F.update) return end
  pcall(F.mailEvent, event, ...)
end)
