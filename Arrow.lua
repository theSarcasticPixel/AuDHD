-- The direction arrow (TomTom-style): its own window, big, movable and scalable. Green when you face the step,
-- yellow when it's to the side, red when it's behind you; the distance and the step under it. Our own frame and
-- texture only: nothing protected, so it works in combat. /wfn arrow lock | unlock | scale <n> | reset | hide | show
local _, ns = ...
local A = {}
ns.arrow = A

local SIZE = 96
local frame, tex, distText, labelText, thenTex, thenText
local closeBtn

local function settings()
  AuDHDDB.arrow = AuDHDDB.arrow or { scale = 1, locked = false }
  return AuDHDDB.arrow
end

-- green (on course) -> yellow (90 degrees off) -> red (behind you)
local function colourFor(turn)
  local off = math.abs(turn)
  while off > math.pi do off = math.abs(off - 2 * math.pi) end
  local f = off / math.pi              -- 0 on course .. 1 behind
  if f < 0.5 then return f * 2, 1, 0 end
  return 1, 1 - (f - 0.5) * 2, 0
end

function A.create()
  if frame then return end
  local s = settings()
  frame = CreateFrame("Frame", "AuDHDArrow", UIParent)
  frame:SetSize(SIZE, SIZE + 70)
  frame:SetScale(s.scale or 1)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(not s.locked)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) if not settings().locked then self:StartMoving() end end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    local st = settings()
    st.p, st.rp, st.x, st.y = p, rp, x, y
  end)
  if s.p then frame:SetPoint(s.p, UIParent, s.rp, s.x, s.y) else frame:SetPoint("TOP", UIParent, "TOP", 0, -140) end

  tex = frame:CreateTexture(nil, "ARTWORK")
  tex:SetSize(SIZE, SIZE)
  tex:SetPoint("TOP")
  tex:SetTexture("Interface\\AddOns\\AuDHD\\Media\\arrow")

  distText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  distText:SetPoint("TOP", tex, "BOTTOM", 0, -2)
  labelText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  labelText:SetPoint("TOP", distText, "BOTTOM", 0, -2)
  labelText:SetWidth(220)
  labelText:SetWordWrap(false)

  -- "then": a small grey arrow to the step after this one, so you can work your way towards it
  thenTex = frame:CreateTexture(nil, "ARTWORK")
  thenTex:SetSize(26, 26)
  thenTex:SetPoint("TOPRIGHT", labelText, "BOTTOM", -4, -4)
  thenTex:SetTexture("Interface\\AddOns\\AuDHD\\Media\\arrow")
  thenTex:SetVertexColor(0.75, 0.75, 0.75, 0.9)
  thenText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  thenText:SetPoint("LEFT", thenTex, "RIGHT", 4, 0)

  -- X while the arrow is sent somewhere off the route (an ammo vendor): back to the route (the user, 2026-10-17: "the
  -- ability to x/close the vendor arrows for when you decide to keep going instead of going to the vendor")
  closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  closeBtn:SetSize(22, 22)
  closeBtn:SetPoint("TOPRIGHT", tex, "TOPRIGHT", 14, 4)
  closeBtn:SetScript("OnClick", function()
    local o = ns.core.override
    ns.core.override = nil
    if ns.log then ns.log.add("ARROW_CLOSED", { t = o and o.t }) end
    closeBtn:Hide()
  end)
  closeBtn:Hide()
  A.closeBtn = closeBtn

  local acc = 0
  frame:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.03 then return end
    acc = 0
    A.update()
  end)
  if s.hidden then frame:Hide() end
end

-- a short name for where the arrow points: the step's NPC or objective, from its text
local function shortLabel(step)
  local t = ns.core.text(step)
  return (t:gsub("^Together here: ", ""):gsub("%s*%(.-%)", ""):sub(1, 60))
end

local function updateThen(step)
  local nxt = ns.core.peek(1)
  local d, turn
  if nxt and nxt.m and nxt.x then d, turn = ns.core.bearing(nxt) end
  -- only when the next step is somewhere else (not the same NPC or camp)
  local same = nxt and step and nxt.m == step.m and math.abs((nxt.x or 0) - (step.x or 0)) + math.abs((nxt.y or 0) - (step.y or 0)) < 0.6
  if d and turn and not same then
    thenTex:Show()
    thenTex:SetRotation(turn)
    thenText:SetText(("then %d yd"):format(math.floor(d)))
  else
    thenTex:Hide()
    thenText:SetText("")
  end
end

function A.update()
  if not frame then return end
  local step = ns.core.override or ns.core.target   -- an override (an ammo vendor) wins while it's set
  if closeBtn then if ns.core.override then closeBtn:Show() else closeBtn:Hide() end end
  updateThen(step)
  if not step then
    tex:Hide(); distText:SetText(""); labelText:SetText("")
    return
  end
  local d, turn = ns.core.bearing(step)
  -- along the walking way (Walk.lua) when there is one: point at the path a little ahead, count the yards to walk
  local ride
  if d and d >= 10 and ns.walk then
    local ax, ay, left, r = ns.walk.aim(step)
    if ax then
      local _, t2 = ns.walk.bearing(ax, ay)
      if t2 then turn = t2 end
      d, ride = left, r
    elseif r then
      ride = r .. (left and (", then %d yd"):format(math.floor(left)) or "")   -- in the air: where you land
    end
  end
  labelText:SetText(shortLabel(step) .. (ride and ("  |cffaaaaaa(" .. ride .. ")|r") or ""))
  if not d then
    tex:Hide()
    distText:SetText(step.esc and "|cffaaaaaafollow the escort|r" or "|cffaaaaaaanother zone or continent|r")
    return
  end
  if d < 10 then
    tex:Show()
    tex:SetRotation(0)
    tex:SetVertexColor(0.3, 1, 0.3)
    distText:SetText("|cff40ff40Arrived|r")
    return
  end
  distText:SetText(("%d yd"):format(math.floor(d)))
  tex:Show()
  if turn then
    tex:SetRotation(turn)
    tex:SetVertexColor(colourFor(turn))
  else
    tex:SetRotation(0)
    tex:SetVertexColor(0.8, 0.8, 0.8)   -- the game won't say which way you face (rare): grey, pointing up
  end
end

function A.command(rest)
  local s = settings()
  local cmd, val = (rest or ""):match("^(%S*)%s*(%S*)")
  if cmd == "lock" then s.locked = true; frame:EnableMouse(false)
  elseif cmd == "unlock" then s.locked = false; frame:EnableMouse(true)
  elseif cmd == "scale" and tonumber(val) then s.scale = math.max(0.4, math.min(3, tonumber(val))); frame:SetScale(s.scale)
  elseif cmd == "reset" then
    s.p, s.rp, s.x, s.y, s.scale = nil, nil, nil, nil, 1
    frame:SetScale(1); frame:ClearAllPoints(); frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
  elseif cmd == "hide" then s.hidden = true; frame:Hide()
  elseif cmd == "show" then s.hidden = nil; frame:Show()
  else
    return ("arrow: %s, scale %.1f%s (/wfn arrow lock | unlock | scale <0.4-3> | reset | hide | show)")
      :format(s.locked and "locked" or "unlocked (drag to move)", s.scale or 1, s.hidden and ", hidden" or "")
  end
  return ("arrow: %s"):format(cmd)
end
