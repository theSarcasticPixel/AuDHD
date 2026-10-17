-- Soul shards, for warlocks (the user, 2026-10-17: "deleting soul shards once you're at max so you can continue to use
-- drain soul", "have it warn when running low on shards and show the number in your bag"):
--   a counter by the window (red when low, orange over your max), a warning as you drop to your low mark, and the
--   extras deleted once you're over your max, or your bags have no room left for the next one (Drain Soul makes none
--   then). Out of combat only. If the game won't let an addon delete on its own, a click on the counter does it.
-- /wfn shards [on | off | max <n> | low <n>]
local _, ns = ...
local S = {}
ns.shards = S

local SHARD = 6265
local DEF_MAX, DEF_LOW = 5, 2

local function db()
  AuDHDDB.shards = AuDHDDB.shards or {}
  local d = AuDHDDB.shards
  d.max, d.low = d.max or DEF_MAX, d.low or DEF_LOW
  return d
end
local function isWarlock()
  local _, class = UnitClass("player")
  return class == "WARLOCK"
end
local function log(e, t) if ns.log then ns.log.add(e, t) end end
local function count() return C_Item.GetItemCount(SHARD) or 0 end

-- bag room a shard can go in: plain bags and soul bags (bag family bit 4)
local function roomForShard()
  local free = 0
  for bag = 0, 4 do
    local n, fam = C_Container.GetContainerNumFreeSlots(bag)
    if n and (fam == 0 or (fam and fam % 8 >= 4)) then free = free + n end
  end
  return free
end
-- where the shards are, last bag and slot first (the newest stack up there as a rule)
local function shardSlots()
  local out = {}
  for bag = 4, 0, -1 do
    for slot = C_Container.GetContainerNumSlots(bag) or 0, 1, -1 do
      if C_Container.GetContainerItemID(bag, slot) == SHARD then out[#out + 1] = { bag, slot } end
    end
  end
  return out
end

-- how many to delete now: down to your max, or one to make room for the next when the bags are full
function S.extra()
  local d, n = db(), count()
  local cut = math.max(0, n - d.max)
  if cut == 0 and n > d.low and roomForShard() == 0 then cut = 1 end
  return cut
end

local button, warned, blocked

local function refresh()
  if not button then return end
  local d = db()
  if d.off or not isWarlock() then button:Hide() return end
  local n = count()
  local colour = n <= d.low and "|cffff4040" or n > d.max and "|cffff9900" or "|cffffffff"
  button.text:SetText(colour .. n .. "|r")
  button:Show()
end

-- delete the extras (from a click, or on its own when the game allows it)
function S.trim(fromClick)
  if InCombatLockdown() or GetCursorInfo() then return 0 end
  if blocked and not fromClick then return 0 end
  local cut, done = S.extra(), 0
  for _, bs in ipairs(shardSlots()) do
    if done >= cut then break end
    C_Container.PickupContainerItem(bs[1], bs[2])
    local kind, id = GetCursorInfo()
    if kind == "item" and id == SHARD then
      DeleteCursorItem()
      done = done + 1
    else
      ClearCursor()
      break
    end
  end
  if done > 0 then log("SHARDS_DELETED", { n = done, left = count() - done, click = fromClick or nil }) end
  return done
end

local function make()
  button = ns.newFrame("Shards", "Button", "AuDHDShards", UIParent, "BackdropTemplate")
  button:SetSize(32, 32)
  local d = db()
  if d.p then button:SetPoint(d.p, UIParent, d.rp, d.x, d.y)
  elseif _G.AuDHDFrame then button:SetPoint("TOPRIGHT", _G.AuDHDFrame, "TOPLEFT", -4, -46)
  else button:SetPoint("CENTER", UIParent, "CENTER", -200, -120) end
  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetAllPoints()
  button.icon:SetTexture(C_Item.GetItemIconByID(SHARD) or 134075)
  button.text = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
  button.text:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
  button:SetMovable(true)
  button:RegisterForDrag("LeftButton")
  button:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
  button:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    d.p, d.rp, d.x, d.y = p, rp, x, y
  end)
  button:RegisterForClicks("LeftButtonUp")
  button:SetScript("OnClick", function() S.trim(true) end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(("Soul Shards: %d"):format(count()))
    GameTooltip:AddLine(("Kept to %d; warns at %d or fewer. /wfn shards max <n> | low <n> | off"):format(d.max, d.low), 1, 1, 1, true)
    local cut = S.extra()
    if cut > 0 then GameTooltip:AddLine(("Click: delete %d to make room for Drain Soul"):format(cut), 1, 0.6, 0)
    else GameTooltip:AddLine("Shift-drag to move", 0.7, 0.7, 0.7) end
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function S.check()
  if not isWarlock() then return end
  if not button then make() end
  local d, n = db(), count()
  -- the warning, once each time you drop to your low mark
  if n <= d.low and not d.off then
    if not warned then
      warned = true
      local msg = n == 0 and "Out of Soul Shards: Drain Soul a mob as it dies" or ("Low on Soul Shards: %d left"):format(n)
      if UIErrorsFrame then UIErrorsFrame:AddMessage(msg, 1, 0.3, 0.3) end
      print("|cff66ccffAuDHD|r: " .. msg)
      if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
      log("SHARDS_LOW", { n = n })
    end
  elseif n > d.low then
    warned = false
  end
  if not d.off and S.extra() > 0 then S.trim(false) end
  refresh()
end

function S.command(rest)
  local d = db()
  local cmd, val = (rest or ""):match("^(%S*)%s*(%S*)")
  local v = tonumber(val)
  if cmd == "off" then d.off = true
  elseif cmd == "on" then d.off = nil
  elseif cmd == "max" and v and v >= 1 then d.max = math.floor(v)
  elseif cmd == "low" and v and v >= 0 then d.low = math.floor(v)
  end
  S.check()
  refresh()
  return ("soul shards: %s, %d in your bags, kept to %d, warns at %d (/wfn shards on | off | max <n> | low <n>)")
    :format(d.off and "off" or "on", count(), d.max, d.low)
end

local frame = ns.newFrame("Shards", "Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("ADDON_ACTION_BLOCKED")
frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
frame:SetScript("OnEvent", function(_, e, addon, fn)
  if e == "ADDON_ACTION_BLOCKED" or e == "ADDON_ACTION_FORBIDDEN" then
    -- the game won't let us delete on our own: from a click on the counter only, from now on
    if addon == "AuDHD" and fn and tostring(fn):find("DeleteCursorItem") then
      blocked = true
      ClearCursor()
      log("SHARDS_BLOCKED", { fn = tostring(fn) })
      print("|cff66ccffAuDHD|r: the game won't let addons delete items on their own: click the shard counter to delete the extras")
    end
    return
  end
  S.check()
end)
