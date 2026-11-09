-- A profession trainer's recipe tooltip: what the item it makes is worth (vendor, auction, disenchant), what its
-- reagents cost at auction, and the return: the best of the three less the reagents. Prices are the auction scans'
-- (Auction.lua); the reagents are read from the tooltip's own "Reagents:" line. Setting "trainerValueOff".
local _, ns = ...
local T = {}
ns.trainerValue = T

function T.on() return not AuDHDDB.trainerValueOff end
local function coins(c) return ns.services and ns.services.coins and ns.services.coins(c) or tostring(c) end
local isSecret = issecretvalue or function() return false end

-- "Reagents: Elixir of Minor Agility, Medium Leather (6), Fine Thread" -> { { name, count } }
local PREFIX = (SPELL_REAGENTS or "Reagents: "):gsub("%s+$", "")
function T.reagents(text)
  local out = {}
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\n", " ")
  for part in (text .. ","):gmatch("%s*([^,]-)%s*,") do
    if part ~= "" then
      local name, n = part:match("^(.-)%s*%((%d+)%)$")
      out[#out + 1] = { name or part, tonumber(n) or 1 }
    end
  end
  return out
end
-- the reagents on a tooltip: the text after "Reagents:", on its line or the next
local function tooltipReagents(tip)
  local name = tip.GetName and tip:GetName()
  if not name then return nil end
  for i = 1, (tip:NumLines() or 0) do
    local fs = _G[name .. "TextLeft" .. i]
    local t = fs and fs:GetText()
    if t and not isSecret(t) then
      local plain = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
      if plain:sub(1, #PREFIX) == PREFIX then
        local rest = plain:sub(#PREFIX + 1):gsub("^%s+", "")
        if rest == "" then
          local nxt = _G[name .. "TextLeft" .. (i + 1)]
          rest = nxt and nxt:GetText() or ""
        end
        return T.reagents(rest)
      end
    end
  end
end

-- what reagents cost at auction: total, and how many had no price
function T.reagentCost(list)
  local A = ns.auction
  local total, missing = 0, 0
  for _, r in ipairs(list or {}) do
    local id = A and A.idByName(r[1])
    local p = id and A.price(id)
    if p then total = total + p * r[2] else missing = missing + 1 end
  end
  return total, missing
end

-- the lines for the item link made, with reagents: { left, right, r, g, b }
function T.lines(link, reagents)
  local A = ns.auction
  local out = {}
  local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local vendor = select(11, get(link))
  local id = tonumber(link:match("item:(%d+)"))
  local auction = A and id and A.price(id)
  local de, unpriced
  if A then de, unpriced = A.deValue(link) end
  out[#out + 1] = { "Vendor", vendor == nil and "not known yet" or vendor > 0 and coins(vendor) or "won't buy it", 1, 1, 1 }
  out[#out + 1] = { "Auction", auction and coins(auction) or "not seen at auction", 1, 1, 1 }
  if de or unpriced then out[#out + 1] = { "Disenchant", de and ((unpriced and "about " or "") .. coins(de)) or "no prices yet", 1, 1, 1 } end
  local best = math.max(vendor or 0, auction or 0, de or 0)
  if reagents and #reagents > 0 then
    local cost, missing = T.reagentCost(reagents)
    local note = missing > 0 and (" |cff999999(%d not seen at auction)|r"):format(missing) or ""
    out[#out + 1] = { "Reagents at auction", coins(cost) .. note, 1, 1, 1 }
    if best > 0 and missing < #reagents then
      local ret = best - cost
      out[#out + 1] = { "Return", (ret < 0 and "-" or "+") .. coins(math.abs(ret)), ret < 0 and 1 or 0.25, ret < 0 and 0.25 or 1, 0.25 }
    end
  end
  return out
end

local function add(tip, index)
  if not (T.on() and tip and tip.AddDoubleLine and GetTrainerServiceItemLink) then return end
  local link = GetTrainerServiceItemLink(index)
  if not link or isSecret(link) then return end
  for _, l in ipairs(T.lines(link, tooltipReagents(tip))) do
    tip:AddDoubleLine(l[1], l[2], 1, 0.82, 0, l[3], l[4], l[5])
  end
  tip:Show()
end

if GameTooltip and GameTooltip.SetTrainerService then
  hooksecurefunc(GameTooltip, "SetTrainerService", function(tip, index)
    local ok, err = pcall(add, tip, index)
    if not ok and ns.log then ns.log.add("TRAINER_VALUE_ERROR", { err = tostring(err) }) end
  end)
end
