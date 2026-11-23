-- Guild text to copy: in the Guild & Communities window, a click on the Message of the Day or the Guild Information
-- opens a small box with the whole text selected (Ctrl+C), and any link in it (a Discord invite, say) in a field of its
-- own. The game's text can't be selected, and remaking its frames would taint them, so this lies over them, clicks
-- only (the wheel still scrolls them). The text comes from the guild itself, not the window, so none of it is cut off.
-- /audhd motd opens the box too. Settings, User Interface to switch the clicks off
local _, ns = ...
local G = {}
ns.guildCopy = G

local function on() return not AuDHDDB.guildCopyOff end
function G.isOn() return on() end

-- the guild's two texts, "" when there's none (or no guild)
local function clean(v) if v == nil or (issecretvalue and issecretvalue(v)) then return nil end return v end
function G.texts()
  local motd = GetGuildRosterMOTD and clean(GetGuildRosterMOTD()) or ""
  local info = GetGuildInfoText and clean(GetGuildInfoText()) or ""
  return motd, info
end

-- the links in a text, in order: http(s)://..., www...., discord.gg/... (trailing punctuation left off)
function G.links(text)
  local out, seen = {}, {}
  local function add(s, e)
    for _, r in ipairs(seen) do if s >= r[1] and s <= r[2] then return end end
    local l = text:sub(s, e):gsub("[%.,;:!%?%)%]'\"]+$", "")
    seen[#seen + 1] = { s, e }
    out[#out + 1] = { at = s, link = l }
  end
  for _, pat in ipairs({ "https?://[^%s]+", "www%.[^%s]+", "discord%.gg/[^%s]+", "discord%.com/invite/[^%s]+" }) do
    local i = 1
    while true do
      local s, e = text:find(pat, i)
      if not s then break end
      add(s, e)
      i = e + 1
    end
  end
  table.sort(out, function(a, b) return a.at < b.at end)
  local links = {}
  for _, l in ipairs(out) do links[#links + 1] = l.link end
  return links
end

-- the box: the text, selected; the first link under it
local box
local function build()
  local S = ns.share
  box = S.window("AuDHDGuildCopy", 420, 230, "Copy")
  box.hint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  box.hint:SetPoint("TOPLEFT", 16, -30)
  box.hint:SetWidth(388)
  box.hint:SetJustifyH("LEFT")
  box.hint:SetText("It's selected: press Ctrl+C, then Esc to close.")
  local scroll = ns.newFrame("GuildCopy", "ScrollFrame", "AuDHDGuildCopyScroll", box, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 16, -50)
  scroll:SetSize(366, 90)
  box.text = ns.newFrame("GuildCopy", "EditBox", "AuDHDGuildCopyText", scroll)
  box.text:SetMultiLine(true)
  box.text:SetMaxLetters(0)
  box.text:SetFontObject("GameFontHighlight")
  box.text:SetWidth(360)
  S.readOnly(box.text)
  scroll:SetScrollChild(box.text)
  box.linkLabel = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  box.linkLabel:SetPoint("TOPLEFT", 16, -152)
  box.linkLabel:SetText("The link on its own (click it, Ctrl+C):")
  box.link = ns.newFrame("GuildCopy", "EditBox", "AuDHDGuildCopyLink", box, "InputBoxTemplate")
  box.link:SetSize(380, 20)
  box.link:SetPoint("TOPLEFT", 22, -168)
  box.link:SetFontObject("GameFontHighlight")
  S.readOnly(box.link)
  -- (Esc from a box: closed, not only unfocused)
  for _, b in ipairs({ box.text, box.link }) do b:SetScript("OnEscapePressed", function() box:Hide() end) end
end

-- open the box on a text; -> false when there's nothing to copy
function G.open(title, text)
  if not text or text == "" then return false end
  if not box then build() end
  ns.share.setTitle(box, title)
  ns.share.keepText(box.text, text)
  local links = G.links(text)
  local link = links[1]
  box.linkLabel:SetShown(link ~= nil)
  box.link:SetShown(link ~= nil)
  ns.share.keepText(box.link, link or "")
  box:SetHeight(link and 230 or 180)
  box:Show()
  box.text:SetFocus()
  box.text:HighlightText()
  return true
end
G.box = function() return box end   -- (the smoke test)

-- /audhd motd: the message of the day, else the guild information
function G.command()
  if IsInGuild and not IsInGuild() then return "you're not in a guild" end
  local motd, info = G.texts()
  if G.open("Message of the Day", motd) then return nil end
  if G.open("Guild Information", info) then return nil end
  return "your guild has no message of the day or information yet (or the game hasn't sent it: open the guild window once)"
end

-- ------------------------------------------------------------------ the clicks, over the window's two boxes
local overlays = {}
local function overlay(area, title, which)
  if not area or overlays[area] then return end
  local b = ns.newFrame("GuildCopy", "Button", nil, area)
  b:SetAllPoints(area)
  b:SetFrameLevel(area:GetFrameLevel() + 5)
  b:RegisterForClicks("LeftButtonUp")
  b:SetScript("OnClick", function()
    local motd, info = G.texts()
    G.open(title, which == "motd" and motd or info)
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetText("Click to copy", 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetShown(on())
  overlays[area] = b
end
-- the guild page's two boxes (the game's names, as in its other clients); the MOTD's scroll frame, the details' frame
function G.hook()
  local frame = CommunitiesFrame
  local info = frame and frame.GuildDetailsFrame and frame.GuildDetailsFrame.Info
  if not info then return false end
  overlay(info.MOTDScrollFrame, "Message of the Day", "motd")
  overlay(info.DetailsFrame, "Guild Information", "info")
  return info.MOTDScrollFrame ~= nil or info.DetailsFrame ~= nil
end
function G.set(v)
  AuDHDDB.guildCopyOff = not v or nil
  for _, b in pairs(overlays) do b:SetShown(on()) end
end

local told
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name ~= "Blizzard_Communities" then return end
  local ok, hooked = pcall(G.hook)
  -- (the window's first opening: say once in the log when its boxes weren't found)
  if event == "ADDON_LOADED" and not (ok and hooked) and not told and ns.log then
    told = true
    ns.log.add("GUILD_COPY_MISS", { err = not ok and tostring(hooked) or nil })
  end
end)
