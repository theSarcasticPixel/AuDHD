-- Changes to the guides, on top of the engine's guide files: quests they skipped at stops they already make, timers they
-- forgot. Places from the quest data unless a comment says otherwise. Not checked in game.
local _, ns = ...
local R, D, A = "forever/alliance/04-redridge-mountains", "forever/alliance/05-duskwood", "forever/alliance/06-ashenvale"
local T = "forever/alliance/nightelf/01-teldrassil"
local EL = "forever/alliance/human/01-elwynn-forest"
local TN = "forever/alliance/07-thousand-needles"
local S, B, ST, HF, Z = "forever/horde/03-silverpine-forest", "forever/horde/04-the-barrens", "forever/horde/05-stonetalon-mountains", "forever/horde/06-hillsbrad-foothills", "forever/horde/skyborne/01-zephras-isle"

local SCENE = "Wait for the scene to finish"
local function wait(secs) return { t = "wait", seconds = secs, text = SCENE } end

ns.routeFixes = {
  -- quests the guide keeps from some races that those races can in fact take: [guide] = { quests }
  lift = {},
  -- a goal moved to straight after another (t, q) in the same guide: the goal named by t and its item
  move = {
    -- Shhh! We're Hunting Kobolds (91772) handed in to Marshal Dughan before taking The Fargodeep Mine (62) from him:
    -- another guide always does it in that order (not seen in game). Its own step is left with a note
    { guide = EL, t = "turnin", q = 91772, before = { "accept", 62 }, note = "Shhh! We're Hunting Kobolds was handed in with The Fargodeep Mine" },
    -- (by quest, `q`) Forever's statuette chain in game goes 279 > 281 > 284 > 285 > 286 > 98189 > 98190 > 98191; the
    -- guide had 98189 and 98190 on the first Menethil visit. Now: 98189 from Karl Boran as you hand him 286, then
    -- Stoutfist's hand-in and 98190 on the Menethil round after it
    { guide = A, t = "accept", q = 98189, after = { "turnin", 286 } },
    { guide = A, t = "turnin", q = 98189, before = { "turnin", 484 } },
    { guide = A, t = "accept", q = 98190, after = { "turnin", 98189 } },
    -- Whelgar's chain: Understanding Our Present (98216) once Uncovering the Past (299) is handed in, then Gleaning Our
    -- Future (98310), then For Further Study (98313) once 98310 is handed in. In game Whelgar offered none of the three
    -- with 299, nor 98313 with 98310 in the log. That 98310 follows 98216 is a guess from their titles. The Keystone's
    -- Goaz Warders are just west of his camp: there and back from the 299 hand-in, then hand 98216 in (its accepts are
    -- in `add`, the first visit's in `drop`)
    { guide = TN, t = "collect", q = 98216, after = { "turnin", 299 } },
    { guide = TN, t = "turnin", q = 98216, after = { "collect", 98216 } },
    -- Kurzen's Mystery (207) needs The Second Rebellion (203) and Bad Medicine (204) handed in: taken at the Rebel Camp
    -- once both are, not on the first visit
    { guide = "forever/alliance/30-40/04-stranglethorn-vale", t = "accept", q = 207, after = { "turnin", 204 },
      note = "Kurzen's Mystery is taken once The Second Rebellion and Bad Medicine are handed in" },
    -- Sara Balloo's Plea (683) needs Sully Balloo's Letter (637) handed in, to Sara Balloo herself: the letter first,
    -- then her quest. Without the letter the hand-in is passed and her quest isn't offered
    { guide = "forever/alliance/30-40/01-hillsbrad-foothills", t = "turnin", q = 637, before = { "accept", 683 },
      note = "Sully Balloo's Letter was handed in to Sara Balloo with her quest" },
    -- Hillsbrad's Hoard (98059): the letter is placed in Hillsbrad's town hall first (see `add`), so it's handed in to
    -- Captain McManus on the next Southshore visit, not straight after it's taken
    { guide = "forever/alliance/30-40/01-hillsbrad-foothills", t = "turnin", q = 98059, before = { "turnin", 510 } },
  },
  -- a prerequisite the quest data leaves out: [the accept's quest] needs `pre` handed in (the same chain)
  pre = {
    { guide = A, q = 98189, pre = 286, title = "Return the Statuette" },
    { guide = A, q = 98190, pre = 98189, title = "Return the Statuette" },
    { guide = A, q = 98191, pre = 98190, title = "A Friend of the Family" },
  },
  -- quests out of the route, every goal of them (or only those of kind `t`). Lightforge Ingots (526) is a side branch
  -- of Sven's chain in game, not offered on the first Menethil visit; the route does that branch later anyway (321 >
  -- 324 > 322, the same five ingots for Glorin Steelbrow)
  drop = {
    { guide = A, q = 526 },
    { guide = "forever/alliance/07-thousand-needles", q = 526, note = "Lightforge Ingots is left out: the route does that branch later" },
    -- Crimson Crate Delivery (98240) follows Crocs of the Sky (98072), which needs Apprentice's Duties (471) handed in.
    -- Polestar 0.3.4 moved Crocs' accept to that hand-in itself (our fix did the same until then); Crimson Crate's
    -- hand-in, Howin Kindfeather mid-Wetlands, comes before Crocs is handed in at Menethil and the boat out, so it
    -- can't fit: left out
    { guide = A, q = 98240 },
    { guide = "forever/alliance/30-40/01-hillsbrad-foothills", q = 98240 },
    -- This Land Was Their Land (98230) isn't offered until Nek'rosh's Gambit (465) is handed in, which the route does
    -- after 98230's own hand-in, and it never returns to Howin Kindfeather after that. Howin's quests don't need it:
    -- left out, with the walk to Menethil Keep that was only for it
    { guide = "forever/alliance/30-40/01-hillsbrad-foothills", q = 98230 },
    { guide = "forever/alliance/30-40/01-hillsbrad-foothills", t = "goto", area = 2104 },
    -- Hearts of the Lost (87318): Comar Villard doesn't offer it in game, it looks removed. Its pick-up and hand-in go
    { guide = "forever/alliance/30-40/01-hillsbrad-foothills", q = 87318 },
    { guide = A, q = 98216, t = "accept" },
    { guide = A, q = 98310, t = "accept" },
    { guide = A, q = 98313, t = "accept" },
  },
  -- a note on a goal that's already there
  notes = {
    { guide = HF, t = "turnin", q = 502, note = "Be ready to fight: Stanley turns on you about 9 seconds after this." },
  },
  -- new goals, placed straight after the goal named by `after` (t, q) in that guide, or just before the one named by `before`
  add = {
    -- Whelgar's chain (see `move`)
    { guide = TN, before = { "collect", 98216 }, goals = {
      { t = "accept", quest = 98216, title = "Understanding Our Present", npc = 1077, npcName = "Prospector Whelgar", minLevel = 23, qlvl = 31, pre = { 299 }, preTitles = { [299] = "Uncovering the Past" }, map = 1437, x = 38.81, y = 52.39, z = 117, f = "e", note = "Then out to the Goaz Warders just west of his camp: use the Goaz Stone beside one, and back to him" },
    } },
    { guide = TN, after = { "turnin", 98216 }, goals = {
      { t = "accept", quest = 98310, title = "Gleaning Our Future", npc = 1077, npcName = "Prospector Whelgar", minLevel = 24, qlvl = 32, pre = { 98216 }, preTitles = { [98216] = "Understanding Our Present" }, map = 1437, x = 38.81, y = 52.39, z = 117, f = "e", note = "A new Goaz Stone, for the four titan watchers around the Wetlands" },
    } },
    -- For Further Study as Gleaning Our Future is handed in to Whelgar (the Hillsbrad guide hands it in to Karnik later)
    { guide = "forever/alliance/30-40/01-hillsbrad-foothills", after = { "turnin", 98310 }, goals = {
      { t = "accept", quest = 98313, title = "For Further Study", npc = 1077, npcName = "Prospector Whelgar", minLevel = 24, qlvl = 32, pre = { 98310 }, preTitles = { [98310] = "Gleaning Our Future" }, map = 1437, x = 38.81, y = 52.39, z = 117, f = "e", note = "For Historian Karnik in Ironforge, later in the route" },
    } },
    -- Hillsbrad's Hoard (98059): its quest data has no objective, only the text (place the letter on the bookkeeping
    -- table in Hillsbrad's town hall), with no place: 30.0, 42.8 is where that table stands
    { guide = "forever/alliance/30-40/01-hillsbrad-foothills", after = { "accept", 98059 }, goals = {
      { t = "complete", quest = 98059, title = "Hillsbrad's Hoard", map = 1424, x = 30.0, y = 42.8, f = "e", note = "Place the {item:279386} on the bookkeeping table in the town hall", objs = { { text = "Place the Sealed Company Request", count = 1 } } },
    } },
    -- ---------------------------------------------------------------- timers
    { guide = A, after = { "turnin", 1020 }, goals = { wait(24) } },
    { guide = A, after = { "turnin", 1033 }, goals = { wait(17) } },
    { guide = A, after = { "turnin", 1007 }, goals = { wait(22) } },
    { guide = B, after = { "turnin", 95621 }, goals = { wait(67) } },
    { guide = Z, after = { "turnin", 92700 }, goals = { wait(75) } },

    -- ---------------------------------------------------------------- Redridge: Hilary's Necklace, by the bridge into Lakeshire
    -- the lake places are from comparing with another guide; the quest data has none
    { guide = R, after = { "accept", 128 }, goals = {
      { t = "accept", quest = 3741, title = "Hilary's Necklace", npc = 8965, npcName = "Shawn", minLevel = 12, qlvl = 15, map = 1433, x = 24.2, y = 53.6 },
      { t = "collect", quest = 3741, title = "Hilary's Necklace", item = 10958, itemName = "Hilary's Necklace", count = 1, oi = 1, map = 1433, x = 31.12, y = 54.21, note = "In the Glinting Mud on the lake bed: swim along and look, it has several spots" },
      { t = "turnin", quest = 3741, title = "Hilary's Necklace", npc = 8962, npcName = "Hilary", map = 1433, x = 24.2, y = 53.6 },
    } },

    -- ---------------------------------------------------------------- Duskwood: Jitters' chain, all at stops already on the way
    { guide = D, after = { "accept", 165 }, goals = {
      { t = "accept", quest = 163, title = "Raven Hill", npc = 633, npcName = "Elaine Carevin", minLevel = 17, qlvl = 20, map = 1431, x = 75.34, y = 48.75, f = "e" },
    } },
    { guide = D, after = { "collect", 96139 }, goals = {
      { t = "turnin", quest = 163, title = "Raven Hill", npc = 288, npcName = "Jitters", map = 1431, x = 18.38, y = 56.37, f = "e" },
      { t = "accept", quest = 5, title = "Jitters' Growling Gut", npc = 288, npcName = "Jitters", minLevel = 17, qlvl = 20, pre = { 163 }, preTitles = { [163] = "Raven Hill" }, map = 1431, x = 18.38, y = 56.37, f = "e" },
    } },
    { guide = D, after = { "accept", 149 }, goals = {
      { t = "turnin", quest = 5, title = "Jitters' Growling Gut", npc = 272, npcName = "Chef Grual", map = 1431, x = 73.8, y = 43.5, f = "e" },
      { t = "accept", quest = 93, title = "Dusky Crab Cakes", npc = 272, npcName = "Chef Grual", minLevel = 17, qlvl = 20, pre = { 5 }, preTitles = { [5] = "Jitters' Growling Gut" }, map = 1431, x = 73.8, y = 43.5, f = "e" },
    } },
    { guide = D, after = { "accept", 158 }, goals = {
      { t = "collect", quest = 93, title = "Dusky Crab Cakes", item = 2251, itemName = "Gooey Spider Leg", count = 6, oi = 1, map = 1431, x = 18.1, y = 43.7, f = "e", note = "Carrion Recluses around Raven Hill Cemetery" },
    } },
    { guide = D, after = { "accept", 156 }, goals = {
      { t = "turnin", quest = 93, title = "Dusky Crab Cakes", npc = 272, npcName = "Chef Grual", map = 1431, x = 73.8, y = 43.5, f = "e" },
      { t = "accept", quest = 240, title = "Return to Jitters", npc = 272, npcName = "Chef Grual", minLevel = 17, qlvl = 20, pre = { 93 }, preTitles = { [93] = "Dusky Crab Cakes" }, map = 1431, x = 73.8, y = 43.5, f = "e" },
    } },
    { guide = D, after = { "accept", 268 }, goals = {
      { t = "turnin", quest = 240, title = "Return to Jitters", npc = 288, npcName = "Jitters", map = 1431, x = 18.38, y = 56.37, f = "e" },
    } },

    -- ---------------------------------------------------------------- Teldrassil: don't leave without these
    { guide = T, after = { "turnin", 922 }, goals = {
      { t = "accept", quest = 923, title = "Tumors", npc = 3517, npcName = "Rellian Greenspyre", minLevel = 4, qlvl = 9, pre = { 922 }, preTitles = { [922] = "Rellian Greenspyre" }, map = 1457, x = 38.18, y = 21.64 },
    } },
    { guide = T, after = { "turnin", 98046 }, goals = {
      { t = "accept", quest = 2518, title = "Tears of the Moon", npc = 7313, npcName = "Priestess A'moora", minLevel = 5, qlvl = 12, map = 1457, x = 36.7, y = 85.9, f = "e" },
      { t = "accept", quest = 98067, title = "Eyes of the Sentinels", npc = 8396, npcName = "Sentinel Dalia Sunblade", minLevel = 1, qlvl = 11, map = 1457, x = 39.7, y = 89.5, f = "e" },
    } },
    { guide = T, after = { "turnin", 5629 }, goals = {
      { t = "collect", quest = 923, title = "Tumors", item = 5170, itemName = "Mossy Tumor", count = 5, oi = 1, map = 1438, x = 42.5, y = 33.8, f = "e", note = "Timberlings on the way north" },
      { t = "collect", quest = 2518, title = "Tears of the Moon", item = 8344, itemName = "Silvery Spinnerets", count = 1, oi = 1, map = 1438, x = 41.5, y = 25.4, f = "e", note = "Lady Sathrah: she moves between a few spots" },
      { t = "turnin", quest = 923, title = "Tumors", npc = 3517, npcName = "Rellian Greenspyre", map = 1457, x = 38.18, y = 21.64 },
      { t = "kill", quest = 98067, title = "Eyes of the Sentinels", target = "First lookout", npc = 270418, count = 1, oi = 1, map = 1457, x = 33.4, y = 16.8, f = "e", note = "Use the Lunar Pendant here" },
      { t = "kill", quest = 98067, title = "Eyes of the Sentinels", target = "Second lookout", npc = 270419, count = 1, oi = 2, map = 1457, x = 41, y = 43.6, f = "e", note = "Use the Lunar Pendant here" },
      { t = "kill", quest = 98067, title = "Eyes of the Sentinels", target = "Third lookout", npc = 270420, count = 1, oi = 3, map = 1457, x = 66.5, y = 15.4, f = "e", note = "Use the Lunar Pendant here" },
      { t = "kill", quest = 98067, title = "Eyes of the Sentinels", target = "The gates", npc = 270421, count = 1, oi = 4, map = 1457, x = 89.1, y = 34.8, f = "e", note = "Use the Lunar Pendant here" },
      { t = "turnin", quest = 98067, title = "Eyes of the Sentinels", npc = 8396, npcName = "Sentinel Dalia Sunblade", map = 1457, x = 39.7, y = 89.5, f = "e" },
      { t = "turnin", quest = 2518, title = "Tears of the Moon", npc = 7313, npcName = "Priestess A'moora", map = 1457, x = 36.7, y = 85.9, f = "e" },
      { t = "accept", quest = 2520, title = "Sathrah's Sacrifice", npc = 7313, npcName = "Priestess A'moora", minLevel = 5, qlvl = 12, pre = { 2518 }, preTitles = { [2518] = "Tears of the Moon" }, map = 1457, x = 36.7, y = 85.9, f = "e" },
      { t = "complete", quest = 2520, title = "Sathrah's Sacrifice", map = 1457, x = 39.2, y = 85.6, f = "e", note = "At the fountain in the temple, right beside her" },
      { t = "turnin", quest = 2520, title = "Sathrah's Sacrifice", npc = 7313, npcName = "Priestess A'moora", map = 1457, x = 36.7, y = 85.9, f = "e" },
    } },

    -- ---------------------------------------------------------------- Horde: a delivery on the way through the Undercity
    { guide = S, after = { "accept", 493 }, goals = {
      { t = "accept", quest = 1359, title = "Zinge's Delivery", npc = 1937, npcName = "Apothecary Renferrel", minLevel = 10, qlvl = 15, pre = { 3221 }, preTitles = { [3221] = "Speak with Renferrel" }, map = 1421, x = 42.8, y = 40.86, f = "e" },
    } },
    { guide = S, after = { "accept", 441 }, goals = {
      { t = "turnin", quest = 1359, title = "Zinge's Delivery", npc = 5204, npcName = "Apothecary Zinge", map = 1458, x = 50.1, y = 68, f = "e", note = "In the Undercity, before the zeppelin" },
      { t = "accept", quest = 1358, title = "Sample for Helbrim", npc = 5204, npcName = "Apothecary Zinge", minLevel = 10, qlvl = 15, pre = { 1359 }, preTitles = { [1359] = "Zinge's Delivery" }, map = 1458, x = 50.1, y = 68, f = "e" },
    } },
    { guide = B, after = { "accept", 868 }, goals = {
      { t = "turnin", quest = 1358, title = "Sample for Helbrim", npc = 3390, npcName = "Apothecary Helbrim", map = 1413, x = 51.4, y = 30.2, f = "e" },
    } },

    -- ---------------------------------------------------------------- Stonetalon: Malaka'jin's quests, on the way in and out
    { guide = ST, after = { "turnin", 1061 }, goals = {
      { t = "accept", quest = 1062, title = "Goblin Invaders", npc = 4049, npcName = "Seereth Stonebreak", minLevel = 13, qlvl = 19, map = 1413, x = 35.26, y = 27.88, f = "e" },
      { t = "accept", quest = 6548, title = "Avenge My Village", npc = 11857, npcName = "Makaba Flathoof", minLevel = 12, qlvl = 18, map = 1413, x = 35.2, y = 27.8, f = "e" },
      { t = "kill", quest = 6548, title = "Avenge My Village", target = "Grimtotem Ruffian", npc = 11910, count = 8, oi = 1, map = 1413, x = 33.3, y = 22.6, f = "e" },
      { t = "kill", quest = 6548, title = "Avenge My Village", target = "Grimtotem Mercenary", npc = 11911, count = 6, oi = 2, map = 1413, x = 33.4, y = 22.7, f = "e" },
      { t = "turnin", quest = 6548, title = "Avenge My Village", npc = 11857, npcName = "Makaba Flathoof", map = 1413, x = 35.2, y = 27.8, f = "e" },
      { t = "accept", quest = 6629, title = "Kill Grundig Darkcloud", npc = 11857, npcName = "Makaba Flathoof", minLevel = 12, qlvl = 18, pre = { 6548 }, preTitles = { [6548] = "Avenge My Village" }, map = 1413, x = 35.2, y = 27.8, f = "e" },
      { t = "kill", quest = 6629, title = "Kill Grundig Darkcloud", target = "Grimtotem Brute", npc = 11912, count = 6, oi = 2, map = 1413, x = 31.5, y = 22, f = "e" },
    } },
    { guide = ST, after = { "accept", 1058 }, goals = {
      { t = "accept", quest = 6461, title = "Blood Feeders", npc = 12816, npcName = "Xen'Zilla", minLevel = 13, qlvl = 19, map = 1442, x = 71.3, y = 95, f = "e" },
    } },
    { guide = ST, after = { "collect", 1093 }, goals = {
      { t = "kill", quest = 1062, title = "Goblin Invaders", target = "Venture Co. Logger", npc = 3989, count = 15, oi = 1, map = 1442, x = 63.1, y = 55.1, f = "e" },
    } },
    { guide = ST, before = { "turnin", 1058 }, goals = {
      { t = "kill", quest = 6461, title = "Blood Feeders", target = "Deepmoss Creeper", npc = 4005, count = 10, oi = 1, map = 1442, x = 56.1, y = 76.3, f = "e", note = "On the Webwinder Path" },
      { t = "kill", quest = 6461, title = "Blood Feeders", target = "Deepmoss Venomspitter", npc = 4007, count = 7, oi = 2, map = 1442, x = 53.1, y = 72.9, f = "e", note = "On the Webwinder Path" },
      { t = "kill", quest = 6629, title = "Kill Grundig Darkcloud", target = "Grundig Darkcloud", npc = 11858, count = 1, oi = 1, map = 1442, x = 73.7, y = 86.1, f = "e" },
    } },
    { guide = ST, after = { "turnin", 1058 }, goals = {
      { t = "turnin", quest = 6461, title = "Blood Feeders", npc = 12816, npcName = "Xen'Zilla", map = 1442, x = 71.3, y = 95, f = "e" },
      { t = "turnin", quest = 1062, title = "Goblin Invaders", npc = 4049, npcName = "Seereth Stonebreak", map = 1413, x = 35.26, y = 27.88, f = "e" },
      { t = "turnin", quest = 6629, title = "Kill Grundig Darkcloud", npc = 11857, npcName = "Makaba Flathoof", map = 1413, x = 35.2, y = 27.8, f = "e" },
    } },
  },
}
