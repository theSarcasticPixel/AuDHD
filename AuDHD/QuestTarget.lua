-- Target a quest mob: a Target button on the route window, and a key (Key Bindings, AuDHD), that target the nearest mob
-- the step on screen still wants - what it says to kill, and what drops the items it collects. We can't target for you
-- (protected): it's a secure macro button, your click runs "/targetexact <name>" as if you typed it. Its macro and its
-- place can't change in a fight, so a step that changes in one gets its mobs once the fight ends.
-- The button is the game's, not the window's child: a window anchoring a secure button couldn't move or resize in a
-- fight. It sits over the window's top row, placed by the window's position, scale and level.
-- The mouse wheel can do the same (a setting, or right-click Target): only while Target shows, so the rest of the time
-- the wheel zooms the camera as usual, and the rare alert's wheel comes first while it's up.
local _, ns = ...
local T = {}
ns.questTarget = T

_G["BINDING_NAME_CLICK AuDHDTargetMob:LeftButton"] = "Target a quest mob"

local MAXTEXT = 255   -- a macro's length
local button, wheel, dirty
local shown = false   -- what the window's top row makes room for

-- "/cleartarget", then each name in turn while nothing living is targeted; a corpse doesn't count
local function macroOf(names)
  local text, n = "/cleartarget", 0
  for _, name in ipairs(names) do
    local line = ("\n/targetexact [noexists] %s\n/cleartarget [dead]"):format(name)
    if #text + #line > MAXTEXT then break end
    text, n = text .. line, n + 1
  end
  return n > 0 and text or nil, n
end

function T.wheelOn() return AuDHDDB.questWheel and true or false end

-- the wheel's overrides: on while Target shows (and the setting's on), none otherwise
local function applyWheel()
  if not (wheel and ClearOverrideBindings and SetOverrideBindingClick) then return end
  ClearOverrideBindings(wheel)
  if shown and T.wheelOn() then
    SetOverrideBindingClick(wheel, false, "MOUSEWHEELUP", "AuDHDTargetMobWheel")
    SetOverrideBindingClick(wheel, false, "MOUSEWHEELDOWN", "AuDHDTargetMobWheel")
  end
end

local function make()
  if button then return button end
  button = ns.newFrame("QuestTarget", "Button", "AuDHDTargetMob", UIParent, "UIPanelButtonTemplate,SecureActionButtonTemplate")
  button:SetSize(56, 18)
  button:SetText("Target")
  button:RegisterForClicks("AnyUp")
  -- on the release, whatever "cast on key down" is set to (else the game drops the release: nothing happens)
  button:SetAttribute("useOnKeyDown", false)
  -- the left button (and the key) targets; the right one switches the wheel
  button:SetAttribute("type1", "macro")
  button:SetScript("PostClick", function(self, which)
    if which ~= "RightButton" then return end
    T.setWheel(not T.wheelOn())
    if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
  end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Target the nearest mob this step wants", 1, 1, 1)
    for _, name in ipairs(self.names or {}) do GameTooltip:AddLine(name, 1, 0.82, 0) end
    if self.left and self.left > 0 then GameTooltip:AddLine(("and %d more (no room in one macro)"):format(self.left), 0.7, 0.7, 0.7) end
    if T.wheelOn() then
      GameTooltip:AddLine("Mouse wheel: the same. Right-click: the wheel zooms again", 0.25, 1, 0.25, true)
    else
      GameTooltip:AddLine("Right-click: the mouse wheel does the same while this button shows", 0.7, 0.7, 0.7, true)
    end
    GameTooltip:AddLine("A key for it: Key Bindings, AuDHD.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  button:Hide()
  -- what the wheel clicks: shown (a binding clicks only a shown button) but not seen
  wheel = ns.newFrame("QuestTarget", "Button", "AuDHDTargetMobWheel", UIParent, "SecureActionButtonTemplate")
  wheel:SetSize(1, 1)
  wheel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
  wheel:SetAlpha(0)
  wheel:EnableMouse(false)
  wheel:RegisterForClicks("AnyUp", "AnyDown")
  wheel:SetAttribute("type", "macro")
  return button
end

-- right of the title, left of Current (when it shows) and Routes
local function place(frame, off)
  local right, top = frame:GetRight(), frame:GetTop()
  if not (right and top) then return false end
  local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
  button:SetScale(scale)
  button:SetFrameStrata(frame:GetFrameStrata())
  button:SetFrameLevel(frame:GetFrameLevel() + 10)
  button:ClearAllPoints()
  button:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right - (off and 136 or 70), top - 6)
  return true
end

-- off: the Current button shows too. Returns whether Target shows (the title makes room for it).
function T.update(off)
  local frame = _G.AuDHDFrame
  if not frame then return false end
  make()
  if InCombatLockdown() then dirty = true return shown end
  dirty = nil
  local names = frame:IsShown() and ns.core.route() and ns.core.stepMobs() or {}
  local text, n = macroOf(names)
  button:SetAttribute("macrotext", text)
  wheel:SetAttribute("macrotext", text)
  button.names = { unpack(names, 1, n) }
  button.left = #names - n
  shown = text ~= nil and place(frame, off)
  button:SetShown(shown)
  applyWheel()
  return shown
end
T.macroOf = macroOf   -- (the smoke test)

-- the setting (Settings, User Interface; or right-click Target). In a fight it takes effect once the fight ends.
function T.setWheel(on)
  AuDHDDB.questWheel = on or nil
  if InCombatLockdown() then dirty = true else applyWheel() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function()
  if dirty and ns.ui and ns.ui.refresh then ns.ui.refresh() end
end)

-- the window moves, shows or hides: the button follows (a fight: once it ends)
function T.hook(frame)
  local function again() T.update(ns.core.offLive()) end
  frame:HookScript("OnShow", again)
  frame:HookScript("OnHide", again)
  frame:HookScript("OnDragStop", again)
end
