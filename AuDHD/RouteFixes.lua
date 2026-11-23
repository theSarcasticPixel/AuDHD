-- Changes to the guides, on top of the engine's guide files: quests they skipped at stops they already make, timers they
-- forgot. Places from the quest data unless a comment says otherwise. Not checked in game.
local _, ns = ...
-- Polestar 0.3.7 took in most of what was here (Hilary's Necklace, Jitters' chain, Teldrassil's last quests, Zinge's
-- delivery, Malaka'jin's quests, Whelgar's and the statuette chains, Hillsbrad's Hoard, the Kodo Roundup steps)
local A = "forever/alliance/06-ashenvale"
local EL = "forever/alliance/human/01-elwynn-forest"
local B, HF, Z = "forever/horde/02-the-barrens", "forever/horde/06-hillsbrad-foothills", "forever/horde/skyborne/01-zephras-isle"

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
  },
  -- a prerequisite the quest data leaves out: [the accept's quest] needs `pre` handed in (the same chain)
  pre = {},
  -- quests out of the route, every goal of them (or only those of kind `t`, or a goto by its `area`)
  drop = {},
  -- a note on a goal that's already there
  notes = {
    { guide = HF, t = "turnin", q = 502, note = "Be ready to fight: Stanley turns on you about 9 seconds after this." },
    -- Raene's Cleansing (1046) takes Dartol's Rod of Transformation, and gives it back as a reward
    { guide = "forever/alliance/06-wetlands", t = "turnin", q = 1046, note = "Safe to hand in: you get the {item:5462} back as a reward and keep it" },
    -- Jungle Secrets (215): Private Thorsen offers it only once saved from the two Kurzen's Agents (775, level 33) who
    -- ambush him on his patrol, about a minute's walk south of the Rebel Camp. Dead, he's back at the camp in 10 minutes
    -- and patrols again 20 minutes later (seen in game). Skipping it skips its five follow-ups, each needing the one before
    { guide = "forever/alliance/30-40/04-stranglethorn-vale", t = "accept", q = 215, note = "{npc:738} only offers this after you save him from two Kurzen's Agents (level 33) who ambush him here on his patrol. If he isn't on the road, wait at the Rebel Camp (38, 3.5) and follow him when he sets off south: the ambush is about a minute down the road. If he dies, he's back at the camp in 10 minutes and sets off again 20 minutes later: about 30 minutes. Skipping it also skips the five quests after it (Bookie Herod to Report to Doren)" },
    -- Noboru the Cudgel (5477), whose cudgel starts his quest (1392): an ordinary mob that wanders the ruins, back about
    -- 5 minutes after he dies (seen in game). By item: the loot goal has no quest
    { guide = "forever/alliance/30-40/05-arathi-highlands", t = "collect", item = 6196, note = "Noboru wanders the ruins. If someone got him first, he's back in about 5 minutes" },
    { guide = "forever/horde/40-50/01-stranglethorn-vale", t = "collect", item = 6196, note = "Noboru wanders the ruins. If someone got him first, he's back in about 5 minutes" },
  },
  -- goals made optional, named by quest (`q`), `item` or mob (`npc`), with a note when there is one. An optional accept
  -- not taken leaves out that quest's later goals too
  optional = {
    -- Assassin's Contract (522) starts from a Shadowy Assassin's loot. They ambush Southshore now and then (an event:
    -- stealthed, level 37-38), so may not be there. The guide has the kill, the loot and the accept optional (Polestar
    -- 0.4); this keeps the fuller note on the kill
    { guide = "forever/alliance/30-40/05-arathi-highlands", t = "kill", npc = 2434, note = "Shadowy Assassins ambush Southshore now and then: stealthed, level 37-38. Kill one if they turn up, don't wait for them" },
  },
  -- new goals, placed straight after the goal named by `after` (t, q) in that guide, or just before the one named by `before`
  add = {
    -- ---------------------------------------------------------------- timers
    { guide = A, after = { "turnin", 1020 }, goals = { wait(24) } },
    { guide = A, after = { "turnin", 1033 }, goals = { wait(17) } },
    { guide = A, after = { "turnin", 1007 }, goals = { wait(22) } },
    { guide = B, after = { "turnin", 95621 }, goals = { wait(67) } },   -- (in the first Barrens guide since 0.3.7)
    { guide = Z, after = { "turnin", 92700 }, goals = { wait(75) } },
    -- the giver's scene after a hand-in, before the same giver's next quest (lengths from another guide's timers)
    { guide = EL, after = { "turnin", 112 }, goals = { wait(9) } },
    { guide = "forever/alliance/dwarf/01-dun-morogh", after = { "turnin", 6661 }, goals = { wait(11) } },
    { guide = "forever/alliance/gnome/01-dun-morogh", after = { "turnin", 6661 }, goals = { wait(11) } },
    { guide = "forever/alliance/03-darkshore-return", after = { "turnin", 950 }, goals = { wait(12) } },
    { guide = "forever/alliance/03-darkshore-return", after = { "turnin", 993 }, goals = { wait(20) } },
    { guide = "forever/alliance/30-40/01-hillsbrad-foothills", after = { "turnin", 637 }, goals = { wait(17) } },
    { guide = "forever/alliance/30-40/05-arathi-highlands", after = { "turnin", 602 }, goals = { wait(6) } },
    { guide = "forever/alliance/30-40/06-badlands", after = { "turnin", 1108 }, goals = { wait(20) } },
    { guide = "forever/alliance/40-50/03-feralas", after = { "turnin", 4129 }, goals = { wait(12) } },
    { guide = "forever/alliance/40-50/03-feralas", after = { "turnin", 4135 }, goals = { wait(19) } },
    { guide = "forever/alliance/40-50/04-tanaris", after = { "turnin", 1452 }, goals = { wait(35) } },
    { guide = "forever/alliance/40-50/06-searing-gorge", after = { "turnin", 3452 }, goals = { wait(28) } },
    { guide = "forever/alliance/50-60/03-winterspring", after = { "turnin", 3908 }, goals = { wait(36) } },
    { guide = "forever/alliance/50-60/04-western-plaguelands", after = { "turnin", 5158 }, goals = { wait(48) } },
    { guide = "forever/alliance/50-60/04-western-plaguelands", after = { "turnin", 3941 }, goals = { wait(25) } },
    -- the last of the three pylons (the Alliance takes them in this guide's Un'Goro part)
    { guide = "forever/alliance/50-60/04-western-plaguelands", after = { "turnin", 4288 }, goals = { wait(12) } },
    { guide = "forever/alliance/50-60/06-silithus", after = { "turnin", 4441 }, goals = { wait(16) } },
    { guide = "forever/horde/tauren/01-mulgore", after = { "turnin", 748 }, goals = { wait(8) } },
    { guide = "forever/horde/tauren/01-mulgore", after = { "turnin", 756 }, goals = { wait(8) } },
    { guide = "forever/horde/tauren/01-mulgore", after = { "turnin", 758 }, goals = { wait(8) } },
    { guide = "forever/horde/30-40/06-badlands", after = { "turnin", 1108 }, goals = { wait(20) } },
    { guide = "forever/horde/40-50/03-feralas", after = { "turnin", 3122 }, goals = { wait(23) } },
    -- the last of the three pylons
    { guide = "forever/horde/50-60/01-un-goro-crater", after = { "turnin", 4288 }, goals = { wait(12) } },
    { guide = "forever/horde/50-60/03-winterspring", after = { "turnin", 3908 }, goals = { wait(36) } },
    { guide = "forever/horde/50-60/04-azshara", after = { "turnin", 5158 }, goals = { wait(48) } },
    { guide = "forever/horde/50-60/06-silithus", after = { "turnin", 3941 }, goals = { wait(25) } },
  },
}
