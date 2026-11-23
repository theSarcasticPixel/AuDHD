-- The profession window: what a recipe's materials cost and the profit on what it makes, sold at auction (A) and to a
-- vendor (V), under the made item's tooltip and after each recipe's name in the list; and on the tooltip of any item
-- that teaches a recipe (RecipeItemData.lua), for the recipe it teaches. A material costs its latest
-- auction price or, when cheaper or never seen there, what a vendor charges: what this character was charged at a
-- vendor, else the usual price (VendorPriceData.lua). At auction the made
-- item fetches its price less the house's cut (nothing when it binds when picked up). Follows the auction tooltip
-- setting.
local _, ns = ...
local C = {}
ns.craft = C

local CUT = 0.95   -- what the seller keeps of an auction's price
local function coins(c) return ns.services and ns.services.coins and ns.services.coins(c) or tostring(c) end
local function log(e, f) if ns.log then ns.log.add(e, f) end end
local function on() local A = ns.auction return A and A.on() and A.tipsOn() end
local function say(msg) print("|cff66ccffAuDHD|r: " .. msg) end

-- what a vendor charges this character (reputation takes some off): learned at each vendor's window, the lowest price
-- each of unlimited trade goods, reagents and the usual table's items, in AuDHDDB.vendorSeen["Name-Realm"][itemID];
-- else the usual price
local function me() return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?") end
function C.vendorPrice(id)
  local mine = AuDHDDB and AuDHDDB.vendorSeen and AuDHDDB.vendorSeen[me()]
  return (mine and mine[id]) or (ns.vendorBuy and ns.vendorBuy[id])
end
local function wanted(id)
  if ns.vendorBuy and ns.vendorBuy[id] then return true end
  local get = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
  local classID = get and select(6, get(id))
  return classID == 7 or classID == 5
end
function C.learnVendor()
  if not (AuDHDDB and GetMerchantNumItems) then return end
  AuDHDDB.vendorSeen = AuDHDDB.vendorSeen or {}
  local key = me()
  local t = AuDHDDB.vendorSeen[key] or {}
  for i = 1, GetMerchantNumItems() or 0 do
    local link = GetMerchantItemLink and GetMerchantItemLink(i)
    local id = (GetMerchantItemID and GetMerchantItemID(i)) or (link and tonumber(link:match("item:(%d+)")))
    local price, stack, avail, extended
    local info = C_MerchantFrame and C_MerchantFrame.GetItemInfo and C_MerchantFrame.GetItemInfo(i)
    if info then
      price, stack, avail, extended = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
    elseif GetMerchantItemInfo then
      local _
      _, _, price, stack, avail, _, _, extended = GetMerchantItemInfo(i)
    end
    if id and price and price > 0 and avail == -1 and not extended and wanted(id) then
      local each = price / math.max(1, stack or 1)
      if not t[id] or each < t[id] then t[id] = each end
    end
  end
  if next(t) then AuDHDDB.vendorSeen[key] = t end
end
-- one of a material: its price and where (auction or vendor), the cheaper
function C.materialEach(id)
  local A = ns.auction
  local p = A and A.price(id)
  local v = C.vendorPrice(id)
  if p and not (v and v < p) then return p, "auction" end
  if v then return v, "vendor" end
end
-- one of the made item: at auction less the cut (not when it binds when picked up), and what a vendor pays
function C.madeEach(id)
  local A = ns.auction
  local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local info = { get(id) }
  local sell, bind = info[11], info[14]
  local p = A and A.price(id)
  return p and bind ~= 1 and math.floor(p * CUT) or nil, sell and sell > 0 and sell or nil
end

local schematics = {}
local function schematic(recipeID)
  if schematics[recipeID] == nil then
    local get = C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic
    local ok, s = pcall(get, recipeID, false)
    schematics[recipeID] = ok and s or false
  end
  return schematics[recipeID] or nil
end
local function required(slot)
  if slot.required ~= nil then return slot.required end
  local T = Enum and Enum.CraftingReagentType
  return not (T and T.Basic and slot.reagentType) or slot.reagentType == T.Basic
end
-- a recipe's materials { { id, n, each, from } }, their cost, how many have no price; with an item made: made, n (an
-- average when it makes a range), auction and vendor (one made), and profitA and profitV (one craft). From the
-- materials { { id, n } } and the item made
local function valueOf(list, made, lo, hi)
  local out = { parts = {}, cost = 0, unpriced = 0 }
  for _, r in ipairs(list) do
    local each, from = C.materialEach(r[1])
    out.parts[#out.parts + 1] = { id = r[1], n = r[2], each = each, from = from }
    if each then out.cost = out.cost + each * r[2] else out.unpriced = out.unpriced + 1 end
  end
  if made then
    lo = lo or 1
    out.made, out.n = made, (lo + (hi or lo)) / 2
    out.auction, out.vendor = C.madeEach(made)
    if out.auction then out.profitA = math.floor(out.auction * out.n - out.cost + 0.5) end
    if out.vendor then out.profitV = math.floor(out.vendor * out.n - out.cost + 0.5) end
  end
  return out
end
-- a recipe in the profession window, by its id
function C.value(recipeID)
  local s = recipeID and schematic(recipeID)
  if not s then return nil end
  local list = {}
  for _, slot in ipairs(s.reagentSlotSchematics or {}) do
    local r = slot.reagents and slot.reagents[1]
    if r and r.itemID and required(slot) then list[#list + 1] = { r.itemID, slot.quantityRequired or 1 } end
  end
  return valueOf(list, s.outputItemID, s.quantityMin, s.quantityMax)
end
-- the recipe an item teaches (a pattern, plans, a formula...), from RecipeItemData.lua
function C.patternValue(id)
  local d = id and ns.recipeItems and ns.recipeItems[id]
  if not d then return nil end
  local made, n, rest = d:match("^(%d+):(%d+):(.*)$")
  if not made then return nil end
  local list = {}
  for rid, rn in rest:gmatch("(%d+):(%d+)") do list[#list + 1] = { tonumber(rid), tonumber(rn) } end
  return valueOf(list, tonumber(made), tonumber(n), tonumber(n))
end

-- "+32s", "-5s 20c", "+1g 2s": gold and silver, copper only under a silver
function C.short(c)
  local a = math.abs(c)
  local g, s, cp = math.floor(a / 10000), math.floor(a / 100) % 100, a % 100
  local t
  if g > 0 then t = g .. "g" .. (s > 0 and (" " .. s .. "s") or "")
  elseif s > 0 then t = s .. "s" .. (cp > 0 and (" " .. cp .. "c") or "")
  else t = cp .. "c" end
  return (c < 0 and "-" or "+") .. t
end

-- the recipe a frame in the profession window is about: a list row's, or the recipe page's
local function form()
  local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
  return page and page.SchematicForm
end
local function recipeOf(owner)
  local f, sf = owner, form()
  for _ = 1, 8 do
    if not f then return nil end
    if f.GetElementData then
      local ok, node = pcall(f.GetElementData, f)
      local data = ok and type(node) == "table" and node.GetData and node:GetData()
      if type(data) == "table" and data.recipeInfo then return data.recipeInfo.recipeID end
    end
    if sf and f == sf then
      local info = (sf.GetRecipeInfo and sf:GetRecipeInfo()) or sf.currentRecipeInfo
      return info and info.recipeID
    end
    f = f.GetParent and f:GetParent()
  end
end

local function itemName(id)
  local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
  if not name then
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    name = get and get(id)
  end
  return name or ("item " .. id)
end
-- Materials, Profit (A) and (V), and with Shift each material
local function addLines(tip, v)
  local grey = "|cff999999%s|r"
  local missing = v.unpriced > 0 and (" " .. grey:format(("(%d not priced)"):format(v.unpriced))) or ""
  tip:AddDoubleLine("Materials", (v.unpriced == #v.parts and "not priced" or coins(v.cost)) .. missing, 1, 0.82, 0, 1, 1, 1)
  local made = v.n ~= 1 and (" " .. grey:format(("(%s made)"):format(v.n))) or ""
  local function profit(label, c)
    local text = (v.unpriced > 0 and "about " or "") .. (c < 0 and "-" or "+") .. coins(math.abs(c)) .. made
    tip:AddDoubleLine(label, text, 1, 0.82, 0, c < 0 and 1 or 0.25, c < 0 and 0.25 or 1, 0.25)
  end
  if v.profitA then profit("Profit (A)", v.profitA)
  else tip:AddDoubleLine("Profit (A)", "not seen at auction", 1, 0.82, 0, 0.6, 0.6, 0.6) end
  if v.profitV then profit("Profit (V)", v.profitV)
  else tip:AddDoubleLine("Profit (V)", "a vendor won't buy it", 1, 0.82, 0, 0.6, 0.6, 0.6) end
  if not IsShiftKeyDown() then tip:AddLine("<Shift> each material", 0.6, 0.6, 0.6) return end
  for _, p in ipairs(v.parts) do
    local right = p.each and (coins(p.each * p.n) .. (p.from == "vendor" and (" " .. grey:format("(vendor)")) or ""))
      or grey:format("not priced")
    tip:AddDoubleLine(("  %d %s"):format(p.n, itemName(p.id)), right, 1, 1, 1, 1, 1, 1)
  end
end
-- Auction.lua's item tooltip lines call this. An item that teaches a recipe: "Crafting <item>" and its lines, anywhere.
-- In the profession window: the made item's lines, on the recipe's own item (a list row's or the recipe page's)
function C.addTip(tip, id)
  if not (on() and tip and tip.AddDoubleLine and id) then return end
  local v = C.patternValue(id)
  if v and #v.parts > 0 then
    tip:AddLine("Crafting " .. itemName(v.made), 1, 0.82, 0)
    addLines(tip, v)
    return
  end
  if not (tip == GameTooltip and ProfessionsFrame and ProfessionsFrame:IsShown()) then return end
  v = C.value(recipeOf(tip.GetOwner and tip:GetOwner()))
  if v and v.made == id and #v.parts > 0 then addLines(tip, v) end
end

-- the recipe list: "[7] Thick Leather (A) +32s  (V) -5s". The count of how many you can make goes in front of the name,
-- in the name's own text (the game writes the name again each time it reuses a row; its count is hidden), the name's
-- box widened when that would cut it short; the profits after the name, when every material is priced (a side with no
-- price left out). Nothing is moved: reused rows can't gather gaps
local BLUE = "|cff66ccff%s|r"
local function colored(c) return (c < 0 and "|cffff4d4d" or "|cff40ff40") .. C.short(c) .. "|r" end
local function countFirst(frame, move)
  local label, count = frame.Label, frame.Count
  if not (label and count and label.GetText and count.SetAlpha) then return end
  local text = count:IsShown() and count:GetText() or ""
  text = text:match("^%s*(.-)%s*$")
  if not (move and text ~= "") then count:SetAlpha(1) return end
  local name = label:GetText() or ""
  if name:sub(1, #text + 1) ~= text .. " " then label:SetText(text .. " " .. name) end
  count:SetAlpha(0)
  local full = (label.GetUnboundedStringWidth and label:GetUnboundedStringWidth()) or label:GetStringWidth() or 0
  local box = label:GetWidth() or 0
  if box > 0 and box < full then label:SetWidth(full + 1) end
end
local function mark(frame, node)
  if type(frame) ~= "table" then return end
  local data = type(node) == "table" and node.GetData and node:GetData()
  local info = type(data) == "table" and data.recipeInfo
  local fs = frame.audhdProfit
  local v = on() and info and info.recipeID and C.value(info.recipeID)
  countFirst(frame, on() and info and true)
  local after = frame.Label
  if not (v and (v.profitA or v.profitV) and v.unpriced == 0 and after) then
    if fs then fs:Hide() end
    return
  end
  if not fs then
    fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local font = after.GetFontObject and after:GetFontObject()
    if font then fs:SetFontObject(font) end
    frame.audhdProfit = fs
  end
  local w = after:GetStringWidth() or 0
  local box = after:GetWidth() or 0
  if box > 0 and box < w then w = box end
  fs:ClearAllPoints()
  fs:SetPoint("LEFT", after, "LEFT", w + 6, 0)
  local parts = {}
  if v.profitA then parts[#parts + 1] = BLUE:format("(A)") .. " " .. colored(v.profitA) end
  if v.profitV then parts[#parts + 1] = BLUE:format("(V)") .. " " .. colored(v.profitV) end
  fs:SetText(table.concat(parts, "  "))
  fs:Show()
end
local function listBox()
  local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
  return page and page.RecipeList and page.RecipeList.ScrollBox
end
-- frame, node from either way of calling: (frame, node) or (owner, frame, node)
local function each(a, b, c)
  if type(a) == "table" and a.GetObjectType then return mark(a, b) end
  return mark(b, c)
end
-- the recipe list made wider, and the window with it, so the profits fit after long names. Only while the recipe page
-- hangs off the list's right side (it moves over with it); the game setting the window's width gets the extra too
local WIDER = 120
local widened, baseList, busy = 0, nil, false
local function frameWide(f, w)
  busy = true
  pcall(f.SetWidth, f, w)
  busy = false
end
function C.widen()
  local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
  local list, sf = page and page.RecipeList, page and page.SchematicForm
  if not (list and sf and sf.GetNumPoints and list.SetWidth and ProfessionsFrame.SetWidth) then return end
  local beside = false
  for i = 1, sf:GetNumPoints() or 0 do
    local _, rel = sf:GetPoint(i)
    if rel == list then beside = true end
  end
  local want = (beside and on()) and WIDER or 0
  if want == widened then return end
  baseList = baseList or list:GetWidth()
  list:SetWidth(baseList + want)
  frameWide(ProfessionsFrame, ProfessionsFrame:GetWidth() + want - widened)
  widened = want
end
C.wider = function() return widened end   -- (the smoke test)
local sizeHooked
local function hookSize()
  if sizeHooked or not (ProfessionsFrame and hooksecurefunc) then return end
  sizeHooked = true
  hooksecurefunc(ProfessionsFrame, "SetWidth", function(f, w)
    if not busy and widened > 0 and type(w) == "number" then frameWide(f, w + widened) end
  end)
  hooksecurefunc(ProfessionsFrame, "SetSize", function(f, w)
    if not busy and widened > 0 and type(w) == "number" then frameWide(f, w + widened) end
  end)
end

-- ------------------------------------------------------------------ materials onto the shopping list
-- the recipe page's box and button: how many crafts, then their materials onto the auction helper's "Crafting" list
-- (Buy then offers what you want less what you carry). Not the ones a vendor sells cheaper: chat names those. Follows
-- the auction helper, and "craftShopOff"
function C.shopOn() local A = ns.auction return A and A.on() and not AuDHDDB.craftShopOff end
-- count crafts of a recipe: what went on the list { { name, n, each } } and what a vendor sells cheaper, or nil
function C.shopFor(recipeID, count)
  local A = ns.auction
  local v = A and A.shopForCrafting and recipeID and C.value(recipeID)
  if not v then say("can't read that recipe's materials") return nil end
  count = math.max(1, math.floor(tonumber(count) or 1))
  local buy, vendor = {}, {}
  for _, p in ipairs(v.parts) do
    local name, n = itemName(p.id), p.n * count
    if p.from == "vendor" then vendor[#vendor + 1] = n .. " " .. name else buy[#buy + 1] = { name, n, p.each } end
  end
  local made = v.made and itemName(v.made) or "that recipe"
  if #buy > 0 then
    A.shopForCrafting(buy)
    local t = {}
    for _, b in ipairs(buy) do t[#t + 1] = b[2] .. " " .. b[1] end
    say(("for %d x %s, on your Crafting list: %s"):format(count, made, table.concat(t, ", ")))
  end
  if #vendor > 0 then
    say(("left off, cheaper from a vendor: %s"):format(table.concat(vendor, ", ")))
  end
  if #buy == 0 and #vendor == 0 then say(made .. " needs no materials") end
  log("CRAFT_SHOP", { recipe = recipeID, count = count, buy = #buy, vendor = #vendor })
  return buy, vendor
end
local shopBox, shopButton
local function shopTip(b)
  if not GameTooltip then return end
  GameTooltip:SetOwner(b, "ANCHOR_TOP")
  GameTooltip:SetText("Add to shopping", 1, 1, 1)
  GameTooltip:AddLine("Puts the materials for that many crafts on the auction helper's Crafting list. Buy offers "
    .. "what the list wants less what you carry. Materials cheaper from a vendor are left off: chat names them.", nil, nil, nil, true)
  GameTooltip:Show()
end
local function shopClick()
  if shopBox then shopBox:ClearFocus() end
  C.shopFor(recipeOf(form()), shopBox and shopBox:GetNumber())
end
-- the recipe page's "Reagents:" heading: the form's Reagents.Label, else a text on the form (or its frames, two deep)
-- that starts "Reagents"
local function reagentsLabel(sf)
  local r = rawget(sf, "Reagents")
  local l = type(r) == "table" and rawget(r, "Label")
  if type(l) == "table" and l.GetText then return l end
  local function find(f, depth)
    if not (f.GetRegions and f.GetChildren) then return nil end
    for _, x in ipairs({ f:GetRegions() }) do
      if x.GetObjectType and x:GetObjectType() == "FontString" then
        local t = x:GetText()
        if type(t) == "string" and t:find("^Reagents") then return x end
      end
    end
    if depth > 0 then
      for _, c in ipairs({ f:GetChildren() }) do
        local hit = find(c, depth - 1)
        if hit then return hit end
      end
    end
  end
  return find(sf, 2)
end
-- made once: the count box and button right of the "Reagents:" heading, else at the recipe's bottom left
function C.shopButtons()
  local sf = form()
  if not sf then return end
  if not shopButton then
    shopButton = ns.newFrame("CraftValue", "Button", "AuDHDCraftShop", sf, "UIPanelButtonTemplate")
    shopButton:SetText("Add to shopping")
    shopButton:SetSize(120, 22)
    shopButton:SetScript("OnClick", shopClick)
    shopButton:SetScript("OnEnter", shopTip)
    shopButton:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    shopBox = ns.newFrame("CraftValue", "EditBox", "AuDHDCraftShopCount", sf, "InputBoxTemplate")
    shopBox:SetSize(32, 20)
    shopBox:SetAutoFocus(false)
    shopBox:SetNumeric(true)
    shopBox:SetMaxLetters(3)
    shopBox:SetNumber(1)
    shopBox:SetScript("OnEnterPressed", shopClick)
    shopBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  end
  shopBox:ClearAllPoints()
  local label = reagentsLabel(sf)
  if label then
    -- after the word, not the label's box (it can run the panel's width)
    local w = label.GetStringWidth and label:GetStringWidth()
    if type(w) ~= "number" or w <= 0 then w = 70 end
    shopBox:SetPoint("LEFT", label, "LEFT", w + 14, 0)
  else
    shopBox:SetPoint("BOTTOMLEFT", sf, "BOTTOMLEFT", 24, 40)
  end
  shopButton:ClearAllPoints()
  shopButton:SetPoint("LEFT", shopBox, "RIGHT", 6, 0)
  local show = C.shopOn() and true or false
  shopButton:SetShown(show)
  shopBox:SetShown(show)
end
C.shopWidgets = function() return shopBox, shopButton end   -- (the smoke test)

local hooked
function C.hook()
  if ProfessionsFrame then pcall(hookSize) pcall(C.widen) pcall(C.shopButtons) end
  local box = listBox()
  if hooked or not box then return end
  hooked = true
  local function safe(...)
    local ok, err = pcall(each, ...)
    if not ok and not C.failed then C.failed = true log("CRAFT_VALUE_ERROR", { err = tostring(err) }) end
  end
  if ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
    ScrollUtil.AddInitializedFrameCallback(box, safe, C, true)
  elseif box.RegisterCallback then
    box:RegisterCallback("OnInitializedFrame", safe, C)
  end
end
-- prices changed: the rows shown again
function C.redraw()
  local box = listBox()
  if not (hooked and box and box.ForEachFrame and ProfessionsFrame:IsShown()) then return end
  box:ForEachFrame(function(frame, node) pcall(mark, frame, node) end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("TRADE_SKILL_SHOW")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_UPDATE")
frame:SetScript("OnEvent", function(_, event, name)
  if event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then pcall(C.learnVendor) return end
  if event == "ADDON_LOADED" and name ~= "Blizzard_Professions" then return end
  pcall(C.hook)
  if event == "TRADE_SKILL_SHOW" then pcall(C.widen) pcall(C.redraw) end
end)
