-- How far a dungeon's quests take this character: every page quest for them
-- still to do, turned in in level order, from the lowest level they open at
-- when the character is below it (Core/Levels.lua does the sums; kills are
-- not counted here). The dungeon page's level chip and its tooltip read it
-- (UI/Dungeons.lua, UI/LevelTip.lua).
--
--   Dungeons.QuestXP(key[, p]) -> summary | nil (unknown dungeon)
--   Dungeons.ChainXP(key, id[, p]) -> summary | nil   -- a page quest with
--       the chain before it: the chain's quests oldest first, then the quest;
--       nil without a chain
--     p and summary: Levels.Run's

local ADDON, ns = ...
local Dungeons = ns.Dungeons

local ipairs, min = ipairs, math.min

local SIDE = { Alliance = "A", Horde = "H" }

function Dungeons.QuestXP(key, p)
	if not Dungeons.Get(key) then return nil end
	local Levels, C = ns.Levels, ns.Compat
	p = p or Levels.Player()
	local quests, start = {}, nil
	for _, q in ipairs(Dungeons.Quests(key, SIDE[p.faction or ""])) do
		quests[#quests + 1] = { id = q.id, level = q.level, xp = q.rewards and q.rewards.xp, classes = q.classes }
		local open = not (C and C.IsQuestCompleted and C.IsQuestCompleted(q.id))
		if open and q.minLevel then start = start and min(start, q.minLevel) or q.minLevel end
	end
	return Levels.Run(quests, p, start)
end

function Dungeons.ChainXP(key, id, p)
	local q = Dungeons.Quest(key, id)
	if not (q and type(q.chain) == "table" and #q.chain > 0) then return nil end
	local Levels, C = ns.Levels, ns.Compat
	p = p or Levels.Player()
	local quests, start = {}, nil
	local function add(cq)
		quests[#quests + 1] = { id = cq.id, level = cq.level, xp = cq.rewards and cq.rewards.xp, classes = cq.classes }
		local open = not (C and C.IsQuestCompleted and C.IsQuestCompleted(cq.id))
		if open and cq.minLevel then start = start and min(start, cq.minLevel) or cq.minLevel end
	end
	for _, cid in ipairs(q.chain) do add(Dungeons.Quest(key, cid) or { id = cid }) end
	add(q)
	return Levels.Run(quests, p, start)
end
