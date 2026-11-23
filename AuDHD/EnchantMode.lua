-- Enchant levelling: a button in the Enchanting window. On, the game's "Do you want to replace ... with ...?" opens with
-- its Yes over the Enchant button, so a double click there enchants one practice item again and again. The game lets
-- only your own click say Yes (ReplaceTradeskillEnchant is blocked from an addon), so this only moves the question. Only
-- while the profession window is open, never the trade window's (someone else's item). Off at each login: not saved
local _, ns = ...
local E = {}
ns.enchantMode = E

local ENCHANTING = 333   -- the Enchanting skill line
local active = false
local button

local function log(e, f) if ns.log then ns.log.add(e, f) end end
local function windowOpen() return ProfessionsFrame and ProfessionsFrame:IsShown() and true or false end

-- the profession the window shows is Enchanting
function E.isEnchanting()
  local T = C_TradeSkillUI
  for _, get in ipairs({ T and T.GetBaseProfessionInfo, T and T.GetChildProfessionInfo }) do
    local ok, info = pcall(get)
    if ok and type(info) == "table" then
      if info.professionID == ENCHANTING or info.parentProfessionID == ENCHANTING then return true end
      if info.professionName == "Enchanting" or info.parentProfessionName == "Enchanting" then return true end
    end
  end
  return false
end

function E.on() return active end
local function label()
  if not button then return end
  button:SetText(active and "Enchant levelling: |cff40ff40On|r" or "Enchant levelling: Off")
end
function E.set(on)
  active = on and true or false
  label()
  log("ENCHANT_MODE", { on = active })
end

local function tip(b)
  if not GameTooltip then return end
  GameTooltip:SetOwner(b, "ANCHOR_TOP")
  GameTooltip:SetText("Enchant levelling", 1, 1, 1)
  GameTooltip:AddLine("On: when an enchant would replace the one already on your item, the question opens with its "
    .. "Yes over the Enchant button, so a double click there enchants your practice item again. The game only lets "
    .. "you say Yes yourself. Only while this window is open; the trade window is left alone. Off again when you log "
    .. "out.", nil, nil, nil, true)
  GameTooltip:Show()
end

-- made once, left of the Enchant button; shown for Enchanting only
function E.place()
  local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
  if not page then return end
  if not button then
    button = ns.newFrame("EnchantMode", "Button", "AuDHDEnchantMode", page, "UIPanelButtonTemplate")
    button:SetSize(170, 22)
    button:SetScript("OnClick", function() E.set(not active) end)
    button:SetScript("OnEnter", tip)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    label()
  end
  button:ClearAllPoints()
  local create = page.CreateButton
  if create then
    button:SetPoint("RIGHT", create, "LEFT", -8, 0)
  else
    button:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -140, 8)
  end
  button:SetShown(E.isEnchanting())
end
E.widget = function() return button end   -- (the smoke test)

-- the game's question: Forever's is REPLACE_TRADESKILL_ENCHANT (the window's Enchant on an item already enchanted),
-- REPLACE_ENCHANT the older one. Never TRADE_REPLACE_ENCHANT (the trade window)
local WHICH = { REPLACE_TRADESKILL_ENCHANT = true, REPLACE_ENCHANT = true }
local function shownQuestion()
  for i = 1, 4 do
    local d = _G["StaticPopup" .. i]
    if d and d.IsShown and d:IsShown() and WHICH[d.which] then return d end
  end
end
local function yesOf(d)
  local ok, b = pcall(function() return d.GetButton1 and d:GetButton1() end)
  b = ok and b or d.button1
  return b and b.Click and b or nil
end
-- a frame's centre in another frame's units
local function centreIn(f, to)
  local x, y = f:GetCenter()
  if not (x and y) then return nil end
  local k = (f:GetEffectiveScale() or 1) / (to:GetEffectiveScale() or 1)
  return x * k, y * k
end
-- moved so its Yes is over the Enchant button, while on, the window open and it's Enchanting. -> true when moved
local movedAt, told = 0, false
function E.answer()
  if not (active and windowOpen() and E.isEnchanting()) then return false end
  local d = shownQuestion()
  local yes = d and yesOf(d)
  local page = ProfessionsFrame.CraftingPage
  local create = page and page.CreateButton
  local cx, cy, yx, yy, dx, dy
  if yes and create and d.SetPoint then
    cx, cy = centreIn(create, d)
    yx, yy = centreIn(yes, d)
    dx, dy = centreIn(d, d)
  end
  if not (cx and yx and dx) then
    -- (the question and the hook can both ask: only a miss with no move just now is said, once)
    if not told and GetTime() - movedAt > 1 then
      told = true
      print("|cff66ccffAuDHD|r: Enchant levelling couldn't move the replace question over the Enchant button")
      log("ENCHANT_MODE_MISS", { which = d and d.which })
    end
    return false
  end
  d:ClearAllPoints()
  d:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx - (yx - dx), cy - (yy - dy))
  movedAt = GetTime()
  log("ENCHANT_MOVED", { which = d.which })
  return true
end

-- a frame later, so the question is up
local function soon()
  if not active then return end
  local function go()
    local ok, err = pcall(E.answer)
    if not ok then log("ENCHANT_MODE_ERROR", { err = tostring(err) }) end
  end
  if C_Timer and C_Timer.After then C_Timer.After(0, go) else go() end
end

local hooked
local function hook()
  if hooked or not (hooksecurefunc and StaticPopup_Show) then return end
  hooked = true
  hooksecurefunc("StaticPopup_Show", function(which) if WHICH[which] then soon() end end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("TRADE_SKILL_SHOW")
for _, ev in ipairs({ "TRADE_SKILL_LIST_UPDATE", "REPLACE_TRADESKILL_ENCHANT", "REPLACE_ENCHANT" }) do
  pcall(frame.RegisterEvent, frame, ev)
end
frame:SetScript("OnEvent", function(_, event, name)
  if WHICH[event] then soon() return end
  if event == "ADDON_LOADED" and name ~= "Blizzard_Professions" then return end
  pcall(hook)
  pcall(E.place)
end)
