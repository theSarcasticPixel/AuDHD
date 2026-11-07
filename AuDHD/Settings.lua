-- The settings window (the minimap button's right-click, /audhd settings, and a button in the game's Options under
-- AddOns): the switches the /audhd commands have, as checkboxes. Each one reads and writes the same saved setting its
-- command does, so the two never disagree. One tab per part of the addon; the tabs down the left, the open one's
-- switches on the right.
local _, ns = ...
local S = {}
ns.settings = S

local frame
local COL, ROW = 330, 24                -- the page's width, a checkbox row
-- the tab list is as wide as its longest name needs; set in create
local SIDE, PAGE_X                      -- the tab list's width, where a page's switches start

local function sub(key) return AuDHDDB[key] or {} end
local function autoOn(key)
  local v = AuDHDDB.auto and AuDHDDB.auto[key]
  if v == nil then return ns.auto and ns.auto.DEFAULTS[key] end
  return v
end

-- each tab: its name and its rows, { section }, { label, get, set, tip }, { slider = name } or { note = text }; extra(page, y) adds
-- sliders or number boxes under them
-- the Dungeons tab: the heads-up, then a switch per dungeon the leveling guides have steps for (per character)
local function dungeonRows()
  local out = {
    { "Tell me when a dungeon opens up", function() return AuDHDDB.dungeonHeadsUp and true or false end,
      function(on) AuDHDDB.dungeonHeadsUp = on or nil end,
      "After a level-up that opens a dungeon's quests to you, once per dungeon on each character: how many to pick up and what they're worth, with a button that picks them up" },
    { "Dungeons in the leveling guides (this character)" },
    { note = "Off: the guides keep to the solo route. On: they take you through that dungeon where they have steps for it. The dungeon quests window: /audhd dungeons, or Alt-click the minimap button" },
  }
  for _, d in ipairs(ns.dungeons and ns.dungeons.ROUTE or {}) do
    local map = d[1]
    out[#out + 1] = { d[2] .. (d[3] and (" |cffaaaaaa(" .. d[3] .. ")|r") or ""), function() return ns.dungeons.chosen(map) end,
      function(on) ns.dungeons.choose(map, on) end }
  end
  return out
end
local TABS = {
  { "User Interface", {
    { "Route window", function() local f = _G.AuDHDFrame return f and f:IsShown() end,
      function(on) local f = _G.AuDHDFrame if f and f:IsShown() ~= on then ns.ui.toggle() end end },
    { "Hide the game's quest list with the route window", function() return AuDHDDB.hideTracker end,
      function(on) AuDHDDB.hideTracker = on or nil if ns.ui then ns.ui.applyTracker() end end,
      "All Objectives goes away while the route window is showing, and comes back when you hide the window" },
    { "Arrow", function() return not sub("arrow").hidden end, function(on) ns.arrow.command(on and "show" or "hide") end },
    { slider = "arrow" },
    { "Lock the arrow", function() return sub("arrow").locked end, function(on) ns.arrow.command(on and "lock" or "unlock") end,
      "Locked: clicks go through it, and it can't be dragged" },
    { "Range guide", function() return not sub("range").hidden end,
      function(on) if ns.range then ns.range.command(on and "show" or "hide") end end },
    { slider = "range" },
    { "Lock the range guide", function() return sub("range").locked end,
      function(on) if ns.range then ns.range.command(on and "lock" or "unlock") end end },
    { "Minimap button", function() return not sub("minimap").hide end,
      function(on) AuDHDDB.minimap = AuDHDDB.minimap or { angle = 200 }; AuDHDDB.minimap.hide = not on or nil
        if ns.minimap then ns.minimap.apply() end end, "Off: /audhd minimap brings it back" },
    { "Threat on nameplates", function() return not AuDHDDB.threatHidden end,
      function(on) if ns.threat then ns.threat.command(on and "on" or "off") end end },
    { "Listen button (with Chronicle)", function() return not AuDHDDB.chronicleOff end,
      function(on) AuDHDDB.chronicleOff = not on or nil if ns.ui then ns.ui.refresh() end end,
      "When the Chronicle addon is installed: a button on the route window that has Chronicle read the current step's quest out. AuDHD has no voices of its own" },
    { "Welcome-back message in chat", function() return not AuDHDDB.welcomeOff end,
      function(on) AuDHDDB.welcomeOff = not on or nil end,
      "At login, a line in chat saying which step you're on and how far away it is" },
    { "Reagent bag opens with the backpack", function() return not ns.altItems or ns.altItems.reagentOn() end,
      function(on) if ns.altItems then ns.altItems.setReagent(on) end end,
      "Opening your bags opens the reagent bag too, and closing them closes it" },
  } },
  { "Gold and XP bar", {
    { "Show the bar", function() return ns.stats and ns.stats.isShown() end,
      function(on) if ns.stats then ns.stats.command(on and "show" or "hide") end end,
      "At the top of the screen: your gold, gold an hour (net), XP an hour, the time to your next level, bag space, gear durability and volume. Right-click it for a new session" },
    { "Lock the bar", function() return ns.stats and ns.stats.isLocked() end,
      function(on) if ns.stats then ns.stats.command(on and "lock" or "unlock") end end },
    { "  ...free bag slots", function() return ns.stats and ns.stats.partShown("bags") end,
      function(on) if ns.stats then ns.stats.setPart("bags", on) end end, "Click it to open your bags" },
    { "    ...as slots used (off: slots free)", function() return ns.stats and ns.stats.bagsUsed() end,
      function(on) if ns.stats then ns.stats.setBagsUsed(on) end end,
      "On: 37/40 when 37 of your 40 slots are full. Off: 3/40, the slots still free" },
    { "  ...gold of all my characters", function() return ns.stats and ns.stats.allOn() end,
      function(on) if ns.stats then ns.stats.setAll(on) end end,
      "\"All:\" and the total of your characters on this realm, as each was when you last logged it in. Hover for each one's" },
    { "  ...gear durability", function() return ns.stats and ns.stats.partShown("repair") end,
      function(on) if ns.stats then ns.stats.setPart("repair", on) end end, "Your most worn piece; hover for the rest" },
    { "  ...volume", function() return ns.stats and ns.stats.partShown("volume") end,
      function(on) if ns.stats then ns.stats.setPart("volume", on) end end, "Mouse wheel on it: louder / quieter. Click: sound on / off" },
    { "Gold of all my characters in the backpack", function() return ns.stats and ns.stats.bagGoldOn() end,
      function(on) if ns.stats then ns.stats.setBagGold(on) end end,
      "\"All:\" and the total, left of this character's own money at the bottom of your backpack" },
  } },
  { "Maps", {
    { "Joined-up world map (work in progress)", function() return ns.atlas and ns.atlas.isOn() end,
      function(on) if ns.atlas then print("AuDHD: " .. ns.atlas.command(on and "on" or "off")) end end,
      "The game's world map with every zone's painting joined into one: zoom from the whole world down to the minimap's pictures with the wheel, drag past a map's edge into the next. The quest log and everything else on the map stay.\n\n|cffff9933Work in progress: not tested in game yet.|r It may show errors or look wrong; untick this (or /audhd atlas off) to go back to the normal map." },
    { "Detailed map (the minimap's pictures)", function() return ns.bigmap and ns.bigmap.isOn() end,
      function(on) if ns.bigmap then ns.bigmap.set(on) end end,
      "A big map of the open world drawn from the game's own minimap pictures, with you and your route on it. Open it with /audhd bigmap or a key in Key Bindings (AuDHD: Detailed map). Drag to move around, scroll to zoom" },
    { "  ...instead of the world map", function() return ns.bigmap and ns.bigmap.replaces() end,
      function(on) if ns.bigmap then ns.bigmap.setReplace(on) end end,
      "Your world map key (M) opens the detailed map; its Game map button opens the game's own" },
    { "  ...the game's painted map when zoomed out", function() return ns.bigmap and ns.bigmap.artOn() end,
      function(on) if ns.bigmap then ns.bigmap.setArt(on) end end,
      "Zoomed out, the detailed map shows the game's painted continent map, fading into the minimap's pictures as you zoom in; zoomed in, the cities the minimap's pictures don't show (Ironforge, Undercity, Stormwind, Orgrimmar) come from the game's city maps" },
    { "Route on the world map and minimap", function() return not AuDHDDB.mapHidden end,
      function(on) AuDHDDB.mapHidden = not on or nil if ns.routemap then pcall(ns.routemap.refresh) end end },
    -- detailed walking paths, or a straight line to the next spot
    { "  ...walking paths (off: straight lines)", function() return AuDHDDB.pathStyle ~= "straight" end,
      function(on) if ns.walk then ns.walk.setStyle(on and "detailed" or "straight") end end,
      "On: the way over the ground, round hills and water. Off: a straight line to each spot (the arrow too); flights still used" },
    -- one of three
    { "Where the step's mobs are: a ring per camp", function() return ns.routemap and ns.routemap.spawnMode() == "camps" end,
      function() if ns.routemap then ns.routemap.setSpawnMode("camps") end end,
      "On the world map and minimap, in each objective's colour from the guide window: a ring for each place a group of them stands" },
    { "Where the step's mobs are: a dot per spawn", function() return ns.routemap and ns.routemap.spawnMode() == "each" end,
      function(on) if ns.routemap then ns.routemap.setSpawnMode(on and "each" or "camps") end end,
      "A dot for every single spawn of the step's mobs and objects (busy places get crowded)" },
    { "Where the step's mobs are: none", function() return ns.routemap and ns.routemap.spawnMode() == "off" end,
      function(on) if ns.routemap then ns.routemap.setSpawnMode(on and "off" or "camps") end end },
  } },
  { "Automation", {
    { note = "Hold Shift to pause it (at a quest giver, a vendor)." },
    { "Accept quests", function() return autoOn("accept") end, function(on) AuDHDDB.auto.accept = on end },
    { "Turn in quests", function() return autoOn("complete") end, function(on) AuDHDDB.auto.complete = on end },
    { "Pick quest rewards", function() return autoOn("reward") ~= "manual" end,
      function(on) AuDHDDB.auto.reward = on and "value" or "manual" end,
      "On: an upgrade for your spec if one of the choices is, else the one that sells for most. Off: you choose" },
    { "Sell grey items", function() return autoOn("junk") end, function(on) AuDHDDB.auto.junk = on end },
    { "Repair", function() return autoOn("repair") end, function(on) AuDHDDB.auto.repair = on end },
    { "Buy ammo", function() return autoOn("ammo") end, function(on) AuDHDDB.auto.ammo = on end },
  } },
  -- every part of the addon can be switched off
  { "Reminders", {
    { "Weapon imbue and oil buttons", function() return not (AuDHDDB.buffOff and AuDHDDB.buffOff.weapon) end,
      function(on) if ns.imbue then ns.imbue.command(on and "on" or "off", "weapon") end end,
      "A button when your weapon has no imbue, oil or stone on it" },
    { "Self-buff buttons", function() return not (AuDHDDB.buffOff and ns.imbue and ns.imbue.anyBuffOff()) end,
      function(on) if ns.imbue then ns.imbue.command(on and "on" or "off", "buffs") end end,
      "A button when a buff of your own (Lightning Shield, Demon Skin, an aspect) has dropped off" },
    { "Food buff button", function() return not (AuDHDDB.buffOff and AuDHDDB.buffOff.food) end,
      function(on) if ns.imbue then ns.imbue.command(on and "on" or "off", "food") end end,
      "A button when you're not Well Fed and have food in your bags that does it" },
    { "Scroll buff button", function() return not (AuDHDDB.buffOff and AuDHDDB.buffOff.scroll) end,
      function(on) if ns.imbue then ns.imbue.command(on and "on" or "off", "scrolls") end end,
      "A button when a buff scroll in your bags (Stamina, Agility...) has a buff that isn't on you, the others missing under it. Not while the class buff it won't stack with is on" },
    { "Sell and train reminders", function() return not AuDHDDB.servicesOff end,
      function(on) AuDHDDB.servicesOff = not on or nil if ns.services then ns.services.check() end end,
      "Near a vendor with full bags, or your trainer with new skills to learn" },
    { "Profession trainer reminder", function() return not AuDHDDB.profTrainOff end,
      function(on) AuDHDDB.profTrainOff = not on or nil if ns.services then ns.services.check() end end,
      "Within 500 yards of a trainer who teaches the next rank of a profession you have, once your skill and level are high enough" },
    { "Quest item button", function() return not AuDHDDB.useItemOff end,
      function(on) AuDHDDB.useItemOff = not on or nil if ns.useItem then ns.useItem.refresh() end end,
      "A button for the item the current step needs you to use" },
    { "Quest complete message", function() return not AuDHDDB.announceOff end,
      function(on) if ns.questDone then ns.questDone.command(on and "on" or "off") end end,
      "In your own chat" },
    { "  ...and tell my party", function() return not AuDHDDB.announcePartyOff end,
      function(on) if ns.questDone then ns.questDone.command("party " .. (on and "on" or "off")) end end,
      "Also sends it to party chat when you're in a group" },
    { "Class quest reminder", function() return not AuDHDDB.classQuestOff end,
      function(on) AuDHDDB.classQuestOff = not on or nil if ns.classQuest then ns.classQuest.check() end end,
      "Reaching the level of a class quest the leveling routes leave out: swap to its guide, put it off, or say no to it. Your route waits where you left it" },
    { "Drop chances on mob tooltips", function() return not AuDHDDB.dropsOff end,
      function(on) AuDHDDB.dropsOff = not on or nil end },
    { "Reminder sound" },
    { "Play a sound with reminders", function() return ns.sound.on() end,
      function(on) AuDHDDB.alertSoundOff = not on or nil if not on and AuDHDSoundPick then AuDHDSoundPick:Hide() end end,
      "Pop-ups, buff buttons, low ammo and shards, and rares. Pick the sound below" },
  }, extra = { "sound", "food", "scrolls" } },
  -- BoEs and materials to your alts: one bank alt, or an alt for each kind of item
  { "Alt mail", {
    { "Mail BoEs and materials to my alts", function() return not ns.services.cfg().mailOff end,
      function(on) ns.services.cfg().mailOff = not on or nil if ns.services then ns.services.check() end end,
      "Passing a mailbox with BoE gear you wouldn't wear and materials in your bags: a reminder, and a button on the mail window that sends them. Items the route still needs stay in your bags" },
    { "  ...only remind me with a full stack", function() return ns.services.cfg().mailFullStack and true or false end,
      function(on) ns.services.cfg().mailFullStack = on or nil if ns.services then ns.services.check() end end,
      "The reminder waits for a BoE, or a material you'd send that makes a whole stack (20 Copper Ore, say), so you don't pay postage for one ore. Send all still sends everything" },
    { "Basic: everything to one bank alt", function() return not (ns.services.cfg().altMail and ns.services.cfg().altMail.mode == "prof") end,
      function() ns.services.cfg().altMail = ns.services.cfg().altMail or {} ns.services.cfg().altMail.mode = nil end },
    { "Professions: each kind of item to its own alt", function() return ns.services.cfg().altMail and ns.services.cfg().altMail.mode == "prof" end,
      function(on) ns.services.cfg().altMail = ns.services.cfg().altMail or {} ns.services.cfg().altMail.mode = on and "prof" or nil end,
      "Herbs to your alchemist, ore to your blacksmith and so on. What no row takes, and rows left empty, go to Everything else; with that empty too, they stay in your bags" },
    { "Show what my characters carry on item tooltips", function() return not ns.altItems or ns.altItems.on() end,
      function(on) if ns.altItems then ns.altItems.setOn(on) end end,
      "Item tooltips list which of your characters on this realm have one, in their bags, bank or mail (not worn gear). Find an item... searches them all" },
    { "Alts button on the backpack", function() return not ns.altItems or ns.altItems.bagsButtonOn() end,
      function(on) if ns.altItems then ns.altItems.setBagsButton(on) end end,
      "Pick one of your characters and see their bags, bank or mail as if they were yours, or Show all. Also /audhd bags" },
  }, extra = "altmail" },
  -- the auction house
  { "Auction house", {
    { "Helper window beside the auction house", function() return not ns.auction or ns.auction.on() end,
      function(on) if ns.auction then ns.auction.set("ahOff", on) if not on then ns.auction.hide() end end end,
      "Sell what is in your bags at the cheapest price on sale, see your auctions and whether someone is cheaper, and shopping lists. Also /audhd ah" },
    { "Full scan when it opens", function() return not ns.auction or ns.auction.scanOn() end,
      function(on) if ns.auction then ns.auction.set("ahScanOff", on) end end,
      "Reads every auction's price when you open the auction house, at most once every 15 minutes (the game's limit)" },
    { "Auction prices on item tooltips", function() return not ns.auction or ns.auction.tipsOn() end,
      function(on) if ns.auction then ns.auction.set("ahTipsOff", on) end end,
      "The cheapest price each from your last scan or search, and when it was seen" },
    { "Remind me to sell near an auctioneer", function() return not ns.auction or ns.auction.remindOn() end,
      function(on) if ns.auction then ns.auction.set("ahRemindOff", on) end end,
      "Only when you are already by an auctioneer in a city, and your bags hold things worth at least 50s more there than a vendor pays. Never a detour" },
    { "Red V and line on prices a vendor matches", function() return not ns.auction or ns.auction.strikeOn() end,
      function(on) if ns.auction then ns.auction.set("ahStrikeOff", on) ns.auction.changed() end end,
      "In the helper's Sell list: a red V and a red line through the auction price when a vendor pays about as much (the % below), so it isn't worth posting" },
    { "V/DE on those items in my bags", function() return not ns.auction or ns.auction.bagMarksOn() end,
      function(on) if ns.auction then ns.auction.set("ahBagMarksOff", on) ns.auction.changed() end end,
      "A red V/DE on their bag slots, so at a vendor you can see what to sell there or disenchant. Only items your scans have seen on the auction house" },
    { "Grey frame round the item worth least in my bags", function() return not ns.auction or ns.auction.cheapMarkOn() end,
      function(on) if ns.auction then ns.auction.set("ahCheapOff", on) ns.auction.changed() end end,
      "When you need room: the stack that loses you least, by the higher of what a vendor pays and the auction price. Never what your route needs, quest items, ammo, bags, or items with no known value" },
  }, extra = { "ahVendor", "shopBanker" } },
  { "Dungeons", dungeonRows() },
  { "Rares", {
    { "Alerts for every rare", function() return (AuDHDDB.rares or "all") == "all" end,
      function() ns.rare.command("all") end, "A pop-up and the /tar button near any rare's spawn point" },
    { "Alerts only for the route's rares", function() return AuDHDDB.rares == "route" end,
      function(on) ns.rare.command(on and "route" or "all") end },
    { "No rare alerts", function() return AuDHDDB.rares == "off" end, function(on) ns.rare.command(on and "off" or "all") end },
    { "Mouse wheel targets rares", function() return AuDHDDB.rareWheel end,
      function(on) AuDHDDB.rareWheel = on or nil if ns.rare then ns.rare.applyWheel() end end,
      "While the rare button shows, scrolling the mouse wheel clicks it (cycles /tar through nearby rares)" },
  } },
  { "Party", {
    { "Buttons to ask the party for buffs", function() return not (AuDHDDB.buffAsk and AuDHDDB.buffAsk.off) end,
      function(on) if ns.buffAsk then ns.buffAsk.command(on and "on" or "off") end end,
      "In a group with a priest, mage, druid or paladin: a click asks them in party chat for a buff you don't have" },
    { "Click-cast healing frames", function() return ns.heal and ns.heal.isOn() end,
      function(on) if ns.heal then ns.heal.command(on and "on" or "off") end end,
      "Your party in a row near the bottom of the screen: click one with a mouse button to cast that button's spell on them. Set the spells with the Click-cast spells button below" },
    { "Party quest progress", function() return not AuDHDDB.partyOff end,
      function(on) AuDHDDB.partyOff = not on or nil end,
      "What your group (with AuDHD) has done on quests you share" },
  } },
  { "Fishing", {
    { "One-click fishing", function() return ns.fishing and ns.fishing.isOn() end,
      function(on) if ns.fishing then ns.fishing.command(on and "on" or "off") end end,
      "With a fishing pole equipped: one click on the world casts, the same click reels in, the catch looted" },
    { "The button to fish with" },
    { "Right button", function() return ns.fishing and ns.fishing.button() == "BUTTON2" end,
      function() if ns.fishing then ns.fishing.command("right") end end,
      "Holding it still turns the camera; right-clicking a mob, NPC or chest works as always" },
    { "Middle button", function() return ns.fishing and ns.fishing.button() == "BUTTON3" end,
      function() if ns.fishing then ns.fishing.command("middle") end end },
    { "Mouse button 4", function() return ns.fishing and ns.fishing.button() == "BUTTON4" end,
      function() if ns.fishing then ns.fishing.command("4") end end },
    { "Mouse button 5", function() return ns.fishing and ns.fishing.button() == "BUTTON5" end,
      function() if ns.fishing then ns.fishing.command("5") end end },
    { "Put on a lure first", function() return ns.fishing and ns.fishing.lureOn() end,
      function(on) if ns.fishing then ns.fishing.command("lure " .. (on and "on" or "off")) end end,
      "No lure on the pole and one in your bags: the click puts the best one your skill can use on, the next click casts" },
    { "Fishing level" },
    { "Under the minimap (with a pole)", function() return ns.fishing and ns.fishing.zoneOn() end,
      function(on) if ns.fishing then ns.fishing.command("zone " .. (on and "on" or "off")) end end,
      "The skill this zone needs before fish stop getting away, and yours (red: too low)" },
    { "On the world map", function() return ns.fishing and ns.fishing.mapOn() end,
      function(on) if ns.fishing then ns.fishing.command("map " .. (on and "on" or "off")) end end,
      "In the top right corner, for the zone the map shows, pole or not" },
    { note = "One-click fishing works only while a fishing pole is equipped and you're out of combat. A key for it: Key Bindings, AuDHD, Fish." },
    { "Sound" },
    { "Louder splash while a pole is equipped", function() return ns.fishing and ns.fishing.isLoud() end,
      function(on) if ns.fishing then ns.fishing.command("loud " .. (on and "on" or "off")) end end,
      "Sound effects at the volume below, music and ambience down to a third, sound on with the game in the background. All put back when the pole comes off" },
  }, extra = "splash" },
  { "Warlock", {
    { "Soul shard counter", function() return ns.shards and ns.shards.isOn() end,
      function(on) if ns.shards then ns.shards.command(on and "on" or "off") end end,
      "Your shards in your bags, a warning when low, extras deleted past your max so Drain Soul keeps working. Mouse wheel on it sets the max, Shift + wheel the low mark" },
    { "Lock the shard counter", function() return ns.shards and ns.shards.isLocked() end,
      function(on) if ns.shards then ns.shards.command(on and "lock" or "unlock") end end },
  }, extra = "shards" },
  -- how to log things and where to send the logs
  { "Help/Info", {
    { "Something went wrong?" },
    { note = "Press Report a problem below (or Ctrl-click the minimap button, or /audhd report). Say what went wrong, press Make report, then Select all and Ctrl+C, and paste it into a new GitHub issue or a CurseForge comment. It holds the last 30 minutes of what AuDHD saw, without character names, realm or account." },
    { "Logging a quest" },
    { note = "When AuDHD doesn't know where a quest's mob or objective is, it asks you to log that quest while you do it. A drop chance that says \"Unsure, please upload logged data\" needs the same." },
    { note = "To log one yourself: click [log] after the quest in the route window (it says [logging] while it does: click again to stop). It records your kills, loot and objective progress, and where each happened, until you turn the quest in or abandon it." },
    { note = "/audhd share list: the quests you've logged.  /audhd share stop: stop logging.  /audhd share show <quest ID>: the log as text to copy." },
    { "Sending a log" },
    { note = "Open /audhd share show, press Select all, then Ctrl+C. Paste it into a new issue on GitHub, or a comment on the CurseForge page (links below). The text has no character names, realm or account: only race, class, level and build." },
    { note = "Or attach the saved file, written when you /reload or log out: WTF/Account/<account>/SavedVariables/AuDHD.lua. It has your drop counts from mob tooltips too, but also your character names and realms." },
  }, extra = "help" },
}

local checks = {}
local function refresh()
  for _, c in ipairs(checks) do c:SetChecked(c.get() and true or false) end
  if frame and frame.arrowScale then
    -- the saved size (moving the slider here mustn't write it back)
    frame.syncing = true
    frame.arrowScale:SetValue((AuDHDDB.arrow and AuDHDDB.arrow.scale) or 1)
    if frame.rangeGap and ns.range then frame.rangeGap:SetValue(sub("range").gap or ns.range.PLATE_GAP) end
    if frame.splash and ns.fishing then frame.splash:SetValue(ns.fishing.volume()) end
    if frame.shardMax and ns.shards then
      local mx, lo = ns.shards.values()
      if not frame.shardMax:HasFocus() then frame.shardMax:SetText(tostring(mx)) end
      if not frame.shardLow:HasFocus() then frame.shardLow:SetText(tostring(lo)) end
    end
    if frame.ahVendor and ns.auction and not frame.ahVendor:HasFocus() then
      frame.ahVendor:SetText(tostring(ns.auction.vendorWithin()))
    end
    if frame.altMail then frame.altMail() end
    if frame.sound then frame.sound() end
    if frame.food then frame.food() end
    if frame.shopBanker then frame.shopBanker() end
    if frame.scrolls then frame.scrolls() end
    frame.syncing = nil
  end
end

local function heading(page, text, y)
  local h = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  h:SetPoint("TOPLEFT", PAGE_X, y - 6)
  h:SetText(text)
  return y - 26
end

local SLIDERS = {}   -- { slider = name } rows: below, with the slider itself
local function rows(page, items, y)
  for _, it in ipairs(items) do
    if it.note then
      local n = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      n:SetPoint("TOPLEFT", PAGE_X, y - 4)
      n:SetWidth(COL - 10)
      n:SetJustifyH("LEFT")
      n:SetText(it.note)
      y = y - math.max(ROW, n:GetStringHeight() + 12)
    elseif it.slider then
      y = SLIDERS[it.slider](page, y)
    elseif not it[2] then
      y = heading(page, it[1], y - 4)
    else
      local c = ns.newFrame("Settings", "CheckButton", nil, page, "UICheckButtonTemplate")
      c:SetSize(22, 22)
      c:SetPoint("TOPLEFT", PAGE_X - 2, y)
      local label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      label:SetPoint("LEFT", c, "RIGHT", 2, 0)
      label:SetWidth(COL - 34)
      label:SetJustifyH("LEFT")
      label:SetWordWrap(false)
      label:SetText(it[1])
      c.get, c.set = it[2], it[3]
      c:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT and (self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF) or 856)
        AuDHDDB.auto = AuDHDDB.auto or {}
        self.set(self:GetChecked() and true or false)
        refresh()   -- the rare and fishing-button choices are one of several: the others change too
      end)
      if it[4] then
        c:SetScript("OnEnter", function(self)
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          GameTooltip:SetText(it[1])
          GameTooltip:AddLine(it[4], 1, 1, 1, true)
          GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
      end
      checks[#checks + 1] = c
      y = y - ROW
    end
  end
  return y
end

-- the arrow's size (the same as /audhd arrow scale, 0.4 to 3; here 0.5 to 2.5) and the range guide's height over the
-- target's nameplate
local function slider(page, y, title, name, lo, hi, step, ends, show, set)
  local label = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("TOPLEFT", PAGE_X, y - 8)
  label:SetText(title)
  local value = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  value:SetPoint("LEFT", label, "RIGHT", 8, 0)
  local s = ns.newFrame("Settings", "Slider", name, page, "OptionsSliderTemplate")
  s:SetPoint("TOPLEFT", PAGE_X + 4, y - 30)
  s:SetWidth(COL - 60)
  s:SetMinMaxValues(lo, hi)
  s:SetValueStep(step)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  for suffix, text in pairs({ Low = ends[1], High = ends[2], Text = "" }) do
    local f = _G[name .. suffix]
    if f then f:SetText(text) end
  end
  s:SetScript("OnValueChanged", function(_, v)
    v = math.floor(v / step + 0.5) * step
    value:SetText(show(v))
    if frame.syncing then return end
    set(v)
  end)
  return s, y - 60
end

local EXTRA = {}
function SLIDERS.arrow(page, y)
  frame.arrowScale, y = slider(page, y - 2, "Arrow size", "AuDHDArrowScale", 0.5, 2.5, 0.1, { "small", "big" },
    function(v) return ("%.1fx"):format(v) end,
    function(v) if ns.arrow then ns.arrow.command(("scale %.1f"):format(v)) end end)
  return y
end
function SLIDERS.range(page, y)
  frame.rangeGap, y = slider(page, y - 2, "Range guide height", "AuDHDRangeGap", -60, 80, 2, { "lower", "higher" },
    function(v) return ("%+d"):format(v) end,
    function(v) if ns.range then ns.range.setGap(v) end end)
  return y
end
-- the splash's volume (sound effects) while the pole is out
function EXTRA.splash(page, y)
  frame.splash, y = slider(page, y, "Splash volume", "AuDHDSplashVolume", 10, 100, 5, { "quiet", "loud" },
    function(v) return ("%d%%"):format(v) end,
    function(v) if ns.fishing then ns.fishing.command("volume " .. v) end end)
  return y
end
-- soul shards: how many to keep, and how few is low
function EXTRA.shards(page, y)
  local function numberBox(text, x, cmd)
    local l = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l:SetPoint("TOPLEFT", x, y - 12)
    l:SetText(text)
    local b = ns.newFrame("Settings", "EditBox", nil, page, "InputBoxTemplate")
    b:SetSize(32, 20)
    b:SetPoint("LEFT", l, "RIGHT", 10, 0)
    b:SetAutoFocus(false)
    b:SetNumeric(true)
    b:SetMaxLetters(2)
    local function apply(self)
      local v = tonumber(self:GetText())
      if v and ns.shards then ns.shards.command(cmd .. " " .. v) end
      refresh()
    end
    b:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    b:SetScript("OnEditFocusLost", apply)
    return b
  end
  y = heading(page, "Soul shards", y - 4)
  frame.shardMax = numberBox("Keep at most", PAGE_X + 4, "max")
  frame.shardLow = numberBox("Low at", PAGE_X + 124, "low")
  return y - 34
end

-- how close a vendor's price must be to the auction price for the red V
function EXTRA.ahVendor(page, y)
  local l = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  l:SetPoint("TOPLEFT", PAGE_X + 4, y - 12)
  l:SetText("A vendor pays within")
  local b = ns.newFrame("Settings", "EditBox", nil, page, "InputBoxTemplate")
  b:SetSize(32, 20)
  b:SetPoint("LEFT", l, "RIGHT", 10, 0)
  b:SetAutoFocus(false)
  b:SetNumeric(true)
  b:SetMaxLetters(3)
  local r = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r:SetPoint("LEFT", b, "RIGHT", 6, 0)
  r:SetText("% of the auction price, or more")
  b:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  b:SetScript("OnEditFocusLost", function(self)
    if ns.auction then ns.auction.setVendorWithin(self:GetText()) end
    refresh()
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("When the red V shows")
    GameTooltip:AddLine("20 means a vendor paying 80% of the auction price or more. 0: only when a vendor pays the same or more", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  frame.ahVendor = b
  return y - 34
end

-- the alts' names. Each row: the name, a list of your characters to pick from, and Other account (mail goes only to
-- names seen on this account unless that's ticked). The mode not in use is dimmed
local picker
local function pickAlt(anchor, set)
  if not picker then
    picker = ns.newFrame("Settings", "Frame", "AuDHDAltPick", frame, "BackdropTemplate")
    picker:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                         tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    picker:SetBackdropColor(0, 0, 0, 0.95)
    picker:SetFrameStrata("FULLSCREEN_DIALOG")
    picker:EnableMouse(true)
    picker.lines = {}
  end
  local names = ns.services and ns.services.myChars() or {}
  local items = {}
  for _, n in ipairs(names) do items[#items + 1] = { n, n } end
  items[#items + 1] = { "(none)", false }
  if #names == 0 then table.insert(items, 1, { "|cff999999No other characters yet: log in on each alt once|r" }) end
  for i, it in ipairs(items) do
    local b = picker.lines[i]
    if not b then
      b = ns.newFrame("Settings", "Button", nil, picker)
      b:SetSize(260, 18)
      b:SetPoint("TOPLEFT", 8, -6 - (i - 1) * 18)
      b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      b.text:SetPoint("LEFT", 4, 0)
      picker.lines[i] = b
    end
    b.text:SetText(it[1])
    b:SetScript("OnClick", it[2] ~= nil and function() picker:Hide() set(it[2] or nil) end or nil)
    b:Show()
  end
  for i = #items + 1, #picker.lines do picker.lines[i]:Hide() end
  picker:SetSize(276, 12 + #items * 18)
  picker:ClearAllPoints()
  picker:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
  picker:Show()
end

-- the reminder sound: a list to pick from (the suggested ones, then every sound the game names, A to Z, with a search
-- box), clicking one plays it, and Preview plays the one chosen
local soundPick
local SOUND_ROWS = 14
local function soundPicker(anchor, done)
  local S = ns.sound
  if not soundPick then
    local p = ns.newFrame("Settings", "Frame", "AuDHDSoundPick", frame, "BackdropTemplate")
    soundPick = p
    p:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    p:SetBackdropColor(0, 0, 0, 0.95)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:EnableMouse(true)
    p:SetSize(300, 52 + SOUND_ROWS * 18)
    p.offset = 0
    p.find = ns.newFrame("Settings", "EditBox", nil, p, "InputBoxTemplate")
    p.find:SetSize(200, 18)
    p.find:SetPoint("TOPLEFT", 14, -8)
    p.find:SetAutoFocus(false)
    p.find:SetFontObject("GameFontHighlightSmall")
    p.find:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    p.find:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    p.hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.hint:SetPoint("LEFT", p.find, "LEFT", 2, 0)
    p.hint:SetText("Search")
    p.close = ns.newFrame("Settings", "Button", nil, p, "UIPanelButtonTemplate")
    p.close:SetSize(60, 20)
    p.close:SetPoint("TOPRIGHT", -8, -7)
    p.close:SetText("Done")
    p.close:SetScript("OnClick", function() p:Hide() end)
    p:SetScript("OnHide", function() S.stop() end)
    p.lines = {}
    for i = 1, SOUND_ROWS do
      local b = ns.newFrame("Settings", "Button", nil, p)
      b:SetSize(262, 18)
      b:SetPoint("TOPLEFT", 8, -32 - (i - 1) * 18)
      b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      b.text:SetPoint("LEFT", 4, 0)
      b.text:SetWidth(254)
      b.text:SetJustifyH("LEFT")
      b.text:SetWordWrap(false)
      p.lines[i] = b
    end
    p.count = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.count:SetPoint("BOTTOMLEFT", 12, 8)
    -- the scroll bar beside the rows; the mouse wheel works without it
    local ok, bar = pcall(ns.newFrame, "Settings", "Slider", "AuDHDSoundPickBar", p, "UIPanelScrollBarTemplate")
    if ok and bar then
      bar:SetPoint("TOPRIGHT", -8, -48)
      bar:SetPoint("BOTTOMRIGHT", -8, 38)
      bar:SetValueStep(1)
      bar.scrollStep = 3
      bar:SetScript("OnValueChanged", function(_, v) if not p.syncing then p.offset = math.floor(v + 0.5) p.fill() end end)
      p.bar = bar
    end
    function p.fill()
      local want = (p.find:GetText() or ""):lower()
      p.hint:SetShown(want == "")
      local all, first = S.list()
      local shown = {}
      for i, k in ipairs(all) do
        local label = S.label(k)
        if want == "" or label:lower():find(want, 1, true) or k:lower():find(want, 1, true) then
          shown[#shown + 1] = { k = k, label = label, suggested = i < first }
        end
      end
      local most = math.max(0, #shown - SOUND_ROWS)
      p.offset = math.max(0, math.min(p.offset, most))
      if p.bar then
        p.syncing = true
        p.bar:SetMinMaxValues(0, most)
        p.bar:SetValue(p.offset)
        p.syncing = nil
      end
      local chosen = S.chosen()
      for i, b in ipairs(p.lines) do
        local it = shown[i + p.offset]
        if it then
          local mark = it.k == chosen and "|cff00ff00> |r" or ""
          b.text:SetText(mark .. (it.suggested and ("|cffffd100" .. it.label .. "|r") or it.label))
          b:SetScript("OnClick", function()
            AuDHDDB.alertSound = it.k ~= "RAID_WARNING" and it.k or nil
            S.play(it.k)
            p.fill()
            if p.done then p.done() end
          end)
          b:Show()
        else
          b:Hide()
        end
      end
      p.count:SetText(("%d sounds%s: click one to hear it and pick it"):format(#shown, want ~= "" and " found" or ""))
    end
    p.find:SetScript("OnTextChanged", function() p.offset = 0 p.fill() end)
    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel", function(_, d) p.offset = p.offset - d * 3 p.fill() end)
  end
  soundPick.done = done
  soundPick.find:SetText("")
  soundPick.offset = 0
  -- open on the chosen one
  local all = S.list()
  for i, k in ipairs(all) do if k == S.chosen() then soundPick.offset = math.max(0, i - 3) break end end
  soundPick.fill()
  soundPick:ClearAllPoints()
  soundPick:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  soundPick:Show()
end
function EXTRA.sound(page, y)
  local S = ns.sound
  local l = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  l:SetPoint("TOPLEFT", PAGE_X + 4, y - 8)
  l:SetText("Sound")
  local pick = ns.newFrame("Settings", "Button", nil, page, "UIPanelButtonTemplate")
  pick:SetSize(190, 22)
  pick:SetPoint("TOPLEFT", PAGE_X + 50, y - 3)
  local preview = ns.newFrame("Settings", "Button", nil, page, "UIPanelButtonTemplate")
  preview:SetSize(80, 22)
  preview:SetPoint("LEFT", pick, "RIGHT", 6, 0)
  preview:SetText("Preview")
  preview:SetScript("OnClick", function() S.play() end)
  local function show()
    ns.dropText(pick, S.label(S.chosen()))
    pick:SetEnabled(S.on())
    preview:SetEnabled(S.on())
  end
  pick:SetScript("OnClick", function()
    if soundPick and soundPick:IsShown() then soundPick:Hide() return end
    soundPicker(pick, show)
  end)
  frame.sound = show
  show()
  return y - 34
end

-- the food you prefer: a list of the Well Fed food in your bags to tick, the ticked ones first on the food button
-- (and the scrolls to be reminded of: the same list, its own words)
local PICKS = {
  food = { title = "Tick the food you'd rather eat", none = "No food that makes you Well Fed in your bags",
           choices = function() return ns.imbue.foodChoices() end, set = function(id, on) ns.imbue.setFoodPref(id, on) end },
  scrolls = { title = "Tick the scrolls to be reminded of", none = "No buff scrolls in your bags",
              choices = function() return ns.imbue.scrollChoices() end, set = function(id, on) ns.imbue.setScrollOn(id, on) end },
}
local foodPick
local FOOD_ROWS = 12
local function foodPicker(anchor, done, which)
  local spec = PICKS[which or "food"]
  if not foodPick then
    local p = ns.newFrame("Settings", "Frame", "AuDHDFoodPick", frame, "BackdropTemplate")
    foodPick = p
    p:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    p:SetBackdropColor(0, 0, 0, 0.95)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:EnableMouse(true)
    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.title:SetPoint("TOPLEFT", 12, -12)

    p.close = ns.newFrame("Settings", "Button", nil, p, "UIPanelButtonTemplate")
    p.close:SetSize(60, 20)
    p.close:SetPoint("TOPRIGHT", -8, -7)
    p.close:SetText("Done")
    p.close:SetScript("OnClick", function() p:Hide() end)
    p.none = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.none:SetPoint("TOPLEFT", 12, -38)
    p.none:SetWidth(256)
    p.none:SetJustifyH("LEFT")

    p.lines = {}
    for i = 1, FOOD_ROWS do
      local c = ns.newFrame("Settings", "CheckButton", nil, p, "UICheckButtonTemplate")
      c:SetSize(22, 22)
      c:SetPoint("TOPLEFT", 8, -32 - (i - 1) * 22)
      c.icon = c:CreateTexture(nil, "ARTWORK")
      c.icon:SetSize(18, 18)
      c.icon:SetPoint("LEFT", c, "RIGHT", 2, 0)
      c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      c.text:SetPoint("LEFT", c.icon, "RIGHT", 6, 0)
      c.text:SetWidth(210)
      c.text:SetJustifyH("LEFT")
      c.text:SetWordWrap(false)
      c:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT and (self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF) or 856)
        if self.id then p.spec.set(self.id, self:GetChecked()) end
        p.fill()
        if p.done then p.done() end
      end)
      c:SetScript("OnEnter", function(self)
        if not self.id then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.id) end
        GameTooltip:Show()
      end)
      c:SetScript("OnLeave", function() GameTooltip:Hide() end)
      p.lines[i] = c
    end
    function p.fill()
      local list = p.spec.choices()
      for i, c in ipairs(p.lines) do
        local f = list[i]
        c.id = f and f.id
        if f then
          c:SetChecked(f.pref)
          local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(f.id)
          c.icon:SetTexture(icon or 134400)
          c.text:SetText(f.n > 0 and ("%s |cff999999(%d)|r"):format(f.name, f.n) or ("|cff999999%s (none in your bags)|r"):format(f.name))
          c:Show()
        else
          c:Hide()
        end
      end
      p.none:SetShown(#list == 0)
      p:SetSize(290, 46 + math.max(1, math.min(#list, FOOD_ROWS)) * 22)
    end
  end
  foodPick.done, foodPick.spec, foodPick.which = done, spec, which or "food"
  foodPick.title:SetText(spec.title)
  foodPick.none:SetText(spec.none)
  foodPick.fill()
  foodPick:ClearAllPoints()
  foodPick:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  foodPick:Show()
end
-- the account's shopping banker: a crate's bundle goes on its list
function EXTRA.shopBanker(page, y)
  local l = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  l:SetPoint("TOPLEFT", PAGE_X + 4, y - 8)
  l:SetText("Shopping banker")
  local pick = ns.newFrame("Settings", "Button", nil, page, "UIPanelButtonTemplate")
  pick:SetSize(190, 22)
  pick:SetPoint("LEFT", l, "RIGHT", 10, 0)
  pick:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Shopping banker")
    GameTooltip:AddLine("Alt-click a Waylaid Crate in your bags and pick a bundle: it goes on this character's shopping list, shown when it opens the auction house. One for the whole account; until you pick one, this character's bank alt", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  pick:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local function show()
    local b = AuDHDDB.shopBanker
    local alt = ns.auction and ns.auction.banker()
    ns.dropText(pick, b or (alt and ("Bank alt (" .. alt .. ")")) or "Not set")
  end
  pick:SetScript("OnClick", function()
    if not ns.auction then return end
    local rows = { { "Bank alt (from Alt mail)", function() AuDHDDB.shopBanker = nil show() end } }
    for _, c in ipairs(ns.services and ns.services.charList() or {}) do
      rows[#rows + 1] = { c.name, function() AuDHDDB.shopBanker = c.name show() end }
    end
    ns.auction.menu("Shopping banker", rows)
  end)
  frame.shopBanker = show
  show()
  return y - 34
end
function EXTRA.food(page, y)
  local l = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  l:SetPoint("TOPLEFT", PAGE_X + 4, y - 8)
  l:SetText("Preferred food")
  local pick = ns.newFrame("Settings", "Button", nil, page, "UIPanelButtonTemplate")
  pick:SetSize(190, 22)
  pick:SetPoint("LEFT", l, "RIGHT", 10, 0)
  pick:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Preferred food")
    GameTooltip:AddLine("Tick the Well Fed food you'd rather eat: it goes first on the food button, the rest in the list under it", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  pick:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local function show()
    if not ns.imbue then return end
    local names = {}
    for _, f in ipairs(ns.imbue.foodChoices()) do if f.pref then names[#names + 1] = f.name end end
    ns.dropText(pick, #names == 0 and "None ticked" or #names == 1 and names[1] or (#names .. " ticked"))
  end
  pick:SetScript("OnClick", function()
    if foodPick and foodPick:IsShown() and foodPick.which == "food" then foodPick:Hide() return end
    foodPicker(pick, show, "food")
  end)
  frame.food = show
  show()
  return y - 34
end
-- the buff scrolls to be reminded of: all of them ticked until you untick one
function EXTRA.scrolls(page, y)
  local l = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  l:SetPoint("TOPLEFT", PAGE_X + 4, y - 8)
  l:SetText("Buff scrolls")
  local pick = ns.newFrame("Settings", "Button", nil, page, "UIPanelButtonTemplate")
  pick:SetSize(190, 22)
  pick:SetPoint("LEFT", l, "RIGHT", 10, 0)
  pick:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Buff scrolls")
    GameTooltip:AddLine("The buff scrolls in your bags: untick one to never be reminded of it", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  pick:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local function show()
    if not ns.imbue then return end
    local on, off = 0, 0
    for _, s in ipairs(ns.imbue.scrollChoices()) do if s.pref then on = on + 1 else off = off + 1 end end
    ns.dropText(pick, off == 0 and "All reminded" or (on .. " reminded, " .. off .. " not"))
  end
  pick:SetScript("OnClick", function()
    if foodPick and foodPick:IsShown() and foodPick.which == "scrolls" then foodPick:Hide() return end
    foodPicker(pick, show, "scrolls")
  end)
  frame.scrolls = show
  show()
  return y - 34
end

function EXTRA.altmail(page, y)
  local sv = ns.services
  local boxes, sections = {}, {}
  local BOX_X, PICK_X, OTHER_X = 112, 252, 290
  local function section() local s = ns.newFrame("Settings", "Frame", nil, page) s:SetAllPoints(page) return s end
  -- one row: name in the box, the pick button, the Other account check. get/set: the name; other/setOther: the tick
  local function altRow(parent, label, tip, get, set, other, setOther)
    local l = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l:SetPoint("TOPLEFT", PAGE_X + 4, y - 5)
    l:SetText(label)
    local b = ns.newFrame("Settings", "EditBox", nil, parent, "InputBoxTemplate")
    b:SetSize(130, 18)
    b:SetPoint("TOPLEFT", PAGE_X + BOX_X + 6, y - 2)
    b:SetAutoFocus(false)
    b:SetMaxLetters(40)   -- (Forever's "Name Surname", Services.lua)
    b:SetFontObject("GameFontHighlightSmall")
    b:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    b:SetScript("OnEditFocusLost", function(self)
      if frame.syncing then return end
      set(sv and sv.cleanName(self:GetText() or ""))
      refresh()
    end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(label)
      GameTooltip:AddLine(tip, 1, 1, 1, true)
      local why = sv and get() and sv.whyNot(get(), other())
      if why and why ~= "that's you" then GameTooltip:AddLine("Not mailed: " .. why, 1, 0.3, 0.3, true) end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local p = ns.newFrame("Settings", "Button", nil, parent)
    p:SetSize(20, 20)
    p:SetPoint("TOPLEFT", PAGE_X + PICK_X, y - 1)
    p:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    p:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
    p:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    p:SetScript("OnClick", function(self)
      if picker and picker:IsShown() and picker.owner == self then picker:Hide() return end
      pickAlt(self, function(name) set(name) refresh() end)
      picker.owner = self
    end)
    local c = ns.newFrame("Settings", "CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(22, 22)
    c:SetPoint("TOPLEFT", PAGE_X + OTHER_X, y)
    c.get = other
    c:SetScript("OnClick", function(self)
      PlaySound(SOUNDKIT and (self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF) or 856)
      setOther(self:GetChecked() or nil)
      refresh()
    end)
    c:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText("Lives on another account")
      GameTooltip:AddLine("AuDHD can't see that account's characters, so the name is mailed as you typed it. Check the spelling", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    checks[#checks + 1] = c
    boxes[#boxes + 1] = { box = b, get = get, other = other }
    y = y - 22
  end

  local h1 = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  h1:SetPoint("TOPLEFT", PAGE_X + BOX_X + 2, y - 6)
  h1:SetText("Alt (first and last name)")
  local h2 = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  h2:SetPoint("TOPRIGHT", page, "TOPLEFT", PAGE_X + COL - 4, y - 6)
  h2:SetText("Other account")
  y = y - 22

  sections.basic = section()
  altRow(sections.basic, "Bank alt", "Everything mailable goes to this character",
    function() return ns.services.cfg().bankAlt end,
    function(v) if sv then sv.command(v or "clear") end end,
    function() return ns.services.cfg().bankAltOther end, function(v) ns.services.cfg().bankAltOther = v end)

  sections.prof = section()
  y = heading(sections.prof, "By profession", y - 4)
  for _, g in ipairs(sv and sv.GROUPS or {}) do
    local key = g.key
    altRow(sections.prof, g.label, "For " .. g.prof,
      function() return sv.row(key).name end, function(v) sv.row(key).name = v end,
      function() return sv.row(key).other end, function(v) sv.row(key).other = v end)
  end

  local note = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  note:SetPoint("TOPLEFT", PAGE_X, y - 8)
  note:SetWidth(COL - 10)
  note:SetJustifyH("LEFT")
  note:SetText("Mail only goes to your characters on this realm and side that have logged in with AuDHD. Tick Other account for an alt on another account.")
  y = y - note:GetStringHeight() - 14
  local warn = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  warn:SetPoint("TOPLEFT", PAGE_X, y)
  warn:SetWidth(COL - 10)
  warn:SetJustifyH("LEFT")
  warn:SetTextColor(1, 0.3, 0.3)
  warn:SetText("Red names haven't logged in with AuDHD on this account: nothing is mailed to them. Log in on each once, or tick Other account.")
  y = y - warn:GetStringHeight() - 8
  local list = ns.newFrame("Settings", "Button", nil, page, "UIPanelButtonTemplate")
  list:SetSize(150, 22)
  list:SetPoint("TOPLEFT", PAGE_X, y - 2)
  list:SetText("Your characters...")
  list:SetScript("OnClick", function() S.charList() end)
  list:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Your characters")
    GameTooltip:AddLine("The characters AuDHD has seen on this realm, and when you last played each. Remove ones you've deleted: someone else could take the name", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  list:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local find = ns.newFrame("Settings", "Button", nil, page, "UIPanelButtonTemplate")
  find:SetSize(150, 22)
  find:SetPoint("LEFT", list, "RIGHT", 8, 0)
  find:SetText("Find an item...")
  find:SetScript("OnClick", function() if ns.altItems then ns.altItems.show() end end)
  find:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Find an item")
    GameTooltip:AddLine("Search the bags, banks and mail of your characters on this realm. Also /audhd find <name>", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  find:SetScript("OnLeave", function() GameTooltip:Hide() end)
  y = y - 30

  frame.altMail = function()
    local prof = sv and sv.profMode()
    sections.basic:SetAlpha(prof and 0.4 or 1)
    sections.prof:SetAlpha(prof and 1 or 0.4)
    local bad = false
    for _, r in ipairs(boxes) do
      local name = r.get()
      if not r.box:HasFocus() then r.box:SetText(name or "") end
      local why = sv and name and sv.whyNot(name, r.other())
      local red = why and why ~= "that's you"
      if red then r.box:SetTextColor(1, 0.3, 0.3) else r.box:SetTextColor(1, 1, 1) end
      -- only the mode in use counts for the warning
      if red and ((r.box:GetParent() == sections.prof) == (prof and true or false)) then bad = true end
    end
    warn:SetShown(bad)
  end
  return y
end

-- the characters mail may go to, and when each was last played: the game can't tell an addon a character was deleted,
-- so the player removes old ones. Logging in on one adds it again
local charFrame
local function ago(t)
  if not t then return "not recorded" end
  local days = math.floor(((time and time() or t) - t) / 86400)
  if days <= 0 then return "today" elseif days == 1 then return "yesterday" end
  return days .. " days ago"
end
function S.charList()
  local sv = ns.services
  if not sv then return end
  if not charFrame then
    charFrame = ns.newFrame("Settings", "Frame", "AuDHDCharList", frame, "BackdropTemplate")
    charFrame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                            tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    charFrame:SetBackdropColor(0, 0, 0, 0.95)
    charFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    charFrame:EnableMouse(true)
    charFrame:SetPoint("CENTER", frame, "CENTER", 0, 0)
    local title = charFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Your characters on this realm")
    local close = ns.newFrame("Settings", "Button", nil, charFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() charFrame:Hide() end)
    charFrame.note = charFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    charFrame.note:SetWidth(336)
    charFrame.note:SetJustifyH("LEFT")
    charFrame.note:SetText("AuDHD can't tell when a character is deleted. Remove ones you've deleted, so a new player who takes the name never gets your mail. Logging in on a character adds it back.")
    charFrame.rows = {}
  end
  local chars = sv.charList()
  for i, c in ipairs(chars) do
    local r = charFrame.rows[i]
    if not r then
      r = {}
      r.name = charFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      r.name:SetPoint("TOPLEFT", 14, -34 - (i - 1) * 22)
      r.name:SetWidth(150)
      r.name:SetJustifyH("LEFT")
      r.name:SetWordWrap(false)
      r.info = charFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      r.info:SetPoint("TOPLEFT", 168, -34 - (i - 1) * 22)
      r.remove = ns.newFrame("Settings", "Button", nil, charFrame, "UIPanelButtonTemplate")
      r.remove:SetSize(70, 20)
      r.remove:SetPoint("TOPRIGHT", charFrame, "TOPRIGHT", -12, -30 - (i - 1) * 22)
      r.remove:SetText("Remove")
      charFrame.rows[i] = r
    end
    r.name:SetText(c.name .. (c.me and " |cff999999(you)|r" or ""))
    r.info:SetText((c.side == "A" and "Alliance, " or c.side == "H" and "Horde, " or "") .. ago(c.seen))
    r.remove:SetShown(not c.me)
    r.remove:SetScript("OnClick", function()
      PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or 857)
      sv.forget(c.name)
      S.charList()
      refresh()
    end)
    r.name:Show() r.info:Show()
  end
  for i = #chars + 1, #charFrame.rows do
    local r = charFrame.rows[i]
    r.name:Hide() r.info:Hide() r.remove:Hide()
  end
  local bottom = -34 - #chars * 22 - 6
  charFrame.note:ClearAllPoints()
  charFrame.note:SetPoint("TOPLEFT", 12, bottom)
  charFrame:SetSize(360, -bottom + charFrame.note:GetStringHeight() + 16)
  charFrame:Show()
end

-- where to send logs: links in boxes to copy (addons can't open links), the text put back if you type in them
local CURSEFORGE_URL = ns.share and ns.share.CURSEFORGE_URL or "https://www.curseforge.com/projects/1749872"
function EXTRA.help(page, y)
  local function link(text, url)
    local l = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l:SetPoint("TOPLEFT", PAGE_X + 4, y - 8)
    l:SetText(text)
    local b = ns.newFrame("Settings", "EditBox", nil, page, "InputBoxTemplate")
    b:SetSize(COL - 24, 20)
    b:SetPoint("TOPLEFT", PAGE_X + 10, y - 22)
    b:SetFontObject("GameFontHighlightSmall")
    b:SetAutoFocus(false)
    b:SetText(url)
    b:SetCursorPosition(0)
    b:SetScript("OnTextChanged", function(self, user) if user then self:SetText(url) self:HighlightText() end end)
    b:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    b:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    y = y - 50
  end
  local rb = ns.newFrame("Settings", "Button", nil, page, "UIPanelButtonTemplate")
  rb:SetSize(160, 22)
  rb:SetPoint("TOPLEFT", PAGE_X + 4, y - 8)
  rb:SetText("Report a problem")
  rb:SetScript("OnClick", function() if ns.share then ns.share.showReport() end end)
  y = y - 34
  y = heading(page, "Links (click, Ctrl+A, Ctrl+C)", y - 4)
  link("GitHub: a new issue", ns.share and ns.share.ISSUE_URL or "https://github.com/theSarcasticPixel/AuDHD/issues/new")
  link("CurseForge: the AuDHD page", CURSEFORGE_URL)
  return y
end

local function pick(i)
  for j, t in ipairs(frame.tabs) do
    t.page:SetShown(j == i)
    if j == i then t.button:LockHighlight() else t.button:UnlockHighlight() end
  end
  AuDHDDB.settingsTab = i ~= 1 and i or nil
end

local function create()
  frame = ns.newFrame("Settings", "Frame", "AuDHDSettings", UIParent, "BackdropTemplate")
  frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                      tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  frame:SetBackdropColor(0, 0, 0, 0.92)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  frame:SetFrameStrata("DIALOG")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetScript("OnShow", refresh)
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("AuDHD settings")
  local close = ns.newFrame("Settings", "Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function() frame:Hide() end)
  -- the tab buttons first: their names' width sets the list's
  frame.tabs = {}
  local widest = 0
  for i, tab in ipairs(TABS) do
    local b = ns.newFrame("Settings", "Button", nil, frame, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", 14, -44 - (i - 1) * 28)
    b:SetText(tab[1])
    b:SetScript("OnClick", function()
      PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
      pick(i)
    end)
    local fs = b:GetFontString()
    widest = math.max(widest, fs and fs:GetStringWidth() or 70)
    frame.tabs[i] = { button = b }
  end
  SIDE = math.ceil(widest) + 24
  PAGE_X = 14 + SIDE + 12
  for _, t in ipairs(frame.tabs) do t.button:SetSize(SIDE, 24) end
  -- a line between the tabs and the page
  local line = frame:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(1, 1, 1, 0.15)
  line:SetPoint("TOPLEFT", 14 + SIDE + 6, -44)
  line:SetPoint("BOTTOMLEFT", 14 + SIDE + 6, 44)
  line:SetWidth(1)
  local bottom = -44
  for i, tab in ipairs(TABS) do
    local page = ns.newFrame("Settings", "Frame", nil, frame)
    page:SetAllPoints(frame)
    local y = heading(page, tab[1], -38)
    y = rows(page, tab[2], y)
    for _, e in ipairs(type(tab.extra) == "table" and tab.extra or { tab.extra }) do y = EXTRA[e](page, y) end
    bottom = math.min(bottom, y)
    frame.tabs[i].page = page
  end
  bottom = math.min(bottom, -44 - #TABS * 28) - 8
  local routes = ns.newFrame("Settings", "Button", nil, frame, "UIPanelButtonTemplate")
  routes:SetSize(110, 22)
  routes:SetPoint("TOPLEFT", 12, bottom)
  routes:SetText("Pick a route")
  routes:SetScript("OnClick", function()
    if not ns.picker then return end
    frame:Hide()
    ns.picker.show(function() S.show() end)
  end)
  local heals = ns.newFrame("Settings", "Button", nil, frame, "UIPanelButtonTemplate")
  heals:SetSize(130, 22)
  heals:SetPoint("LEFT", routes, "RIGHT", 8, 0)
  heals:SetText("Click-cast spells")
  heals:SetScript("OnClick", function()
    if not ns.heal then return end
    frame:Hide()
    ns.heal.setup(function() S.show() end)
  end)
  frame:SetSize(PAGE_X + COL + 10, -bottom + 34)
  pick(TABS[AuDHDDB.settingsTab or 1] and AuDHDDB.settingsTab or 1)
  -- Escape closes it
  if UISpecialFrames then table.insert(UISpecialFrames, "AuDHDSettings") end
  frame:Hide()
end

function S.show(tab)   -- tab: a tab's name to open on ("Alt mail"), else the last one
  if not frame then create() end
  frame:Show()
  if tab then for i, t in ipairs(TABS) do if t[1] == tab then pick(i) break end end end
  refresh()
end
function S.toggle()
  if frame and frame:IsShown() then frame:Hide() else S.show() end
end

-- the game's Options > AddOns: a page with a button that opens this window (where the Settings API is there)
function S.register()
  if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
  local panel = ns.newFrame("Settings", "Frame")
  local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("TOPLEFT", 16, -16)
  text:SetText("AuDHD's settings have their own window (also: right-click the minimap button, or /audhd settings).")
  local b = ns.newFrame("Settings", "Button", nil, panel, "UIPanelButtonTemplate")
  b:SetSize(160, 24)
  b:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -12)
  b:SetText("Open the settings")
  b:SetScript("OnClick", function()
    if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
    S.show()
  end)
  local category = Settings.RegisterCanvasLayoutCategory(panel, "AuDHD")
  Settings.RegisterAddOnCategory(category)
end
