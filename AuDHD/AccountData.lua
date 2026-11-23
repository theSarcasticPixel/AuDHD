-- What your characters know, for every character on the account whichever of the two addons (this one or its
-- route-free twin) it runs: auction prices, each character's money, bags, bank and mail, your character list, item
-- names, drop counts, the herb and ore nodes you gathered and the shopping lists. The game reads only the saved files of addons switched on for the character you play, so
-- these live in the AuDHD_Shared folder's own file (AuDHDSharedDB), which both addons ship. Settings (the
-- shopping list last open too) and each character's own progress stay in this addon's file.
-- AuDHDDB keeps these fields by name: they are read and written straight through to the shared file and are never in
-- this addon's own file. What this addon saved there before (or while the shared folder was missing) is merged in.
local _, ns = ...
local S = {}
ns.accountData = S

S.FOLDER = "AuDHD_Shared"
-- (charSeen last: the others are merged by when each character was last seen)
local KEYS = { "ah", "gold", "items", "itemNames", "chars", "drops", "nodes", "ahLists", "charSeen" }
local SHARED = {}
for _, k in ipairs(KEYS) do SHARED[k] = true end
S.SHARED = SHARED

local function tbl(t) return type(t) == "table" and t or nil end

-- when a character was last logged in on, in one saved copy (charSeen is by full name, money by first name)
local function seenIn(db, realm, name)
  local seen = tbl(db.charSeen) and tbl(db.charSeen[realm])
  local best = 0
  if not (seen and type(name) == "string") then return best end
  for n, t in pairs(seen) do
    if type(n) == "string" and type(t) == "number" and (n == name or n:sub(1, #name + 1) == name .. " ") and t > best then
      best = t
    end
  end
  return best
end

-- realm -> character -> record: the copy of whichever addon saw that character last
local function byCharacter(to, from, toDB, fromDB)
  for realm, f in pairs(from) do
    if tbl(f) then
      to[realm] = tbl(to[realm]) or {}
      for name, v in pairs(f) do
        if to[realm][name] == nil or seenIn(fromDB, realm, name) > seenIn(toDB, realm, name) then to[realm][name] = v end
      end
    end
  end
end

-- each field: how a second copy goes into the shared one
local MERGE = {
  -- prices by realm: the newer price of each item, every day's cheapest from both, the later scan
  ah = function(to, from)
    for realm, f in pairs(from) do
      local t = tbl(to[realm])
      if not t then
        to[realm] = f
      elseif tbl(f) then
        t.prices = tbl(t.prices) or {}
        for id, p in pairs(tbl(f.prices) or {}) do
          local q = tbl(t.prices[id])
          if not q then
            t.prices[id] = p
          elseif tbl(p) then
            local keep, other = q, p
            if (tonumber(p.t) or 0) > (tonumber(q.t) or 0) then keep, other = p, q end
            keep.n = keep.n or other.n
            keep.d = tbl(keep.d) or {}
            for day, c in pairs(tbl(other.d) or {}) do keep.d[day] = math.min(keep.d[day] or c, c) end
            t.prices[id] = keep
          end
        end
        t.scanAt = math.max(tonumber(t.scanAt) or 0, tonumber(f.scanAt) or 0)
      end
    end
  end,
  gold = byCharacter,
  items = byCharacter,
  itemNames = function(to, from)
    for id, n in pairs(from) do if to[id] == nil then to[id] = n end end
  end,
  -- your characters by realm: all of them, with their side where either copy knows it
  chars = function(to, from)
    for realm, f in pairs(from) do
      if tbl(f) then
        to[realm] = tbl(to[realm]) or {}
        for name, side in pairs(f) do
          if to[realm][name] == nil or to[realm][name] == true then to[realm][name] = side end
        end
      end
    end
  end,
  -- kills and drops counted under each addon are different kills: added up
  drops = function(to, from)
    for npc, f in pairs(from) do
      if tbl(f) then
        to[npc] = tbl(to[npc]) or {}
        for item, c in pairs(f) do
          local t = tbl(to[npc][item])
          if not t then
            to[npc][item] = c
          elseif tbl(c) then
            t.k, t.d = (t.k or 0) + (c.k or 0), (t.d or 0) + (c.d or 0)
          end
        end
      end
    end
  end,
  -- gathered nodes by map (Gather.lua): the other copy's, less those already kept at the same spot
  nodes = function(to, from)
    for m, f in pairs(from) do
      if tbl(f) then
        to[m] = tbl(to[m]) or {}
        for _, r in ipairs(f) do
          local dup = false
          for _, q in ipairs(to[m]) do
            if tbl(r) and tbl(q) and q.p == r.p and math.abs((q.x or 0) - (r.x or 0)) < 0.005 and math.abs((q.y or 0) - (r.y or 0)) < 0.005 then dup = true break end
          end
          if tbl(r) and not dup then table.insert(to[m], r) end
        end
      end
    end
  end,
  -- shopping lists (Auction.lua): the other copy's lists added, one of the same name merged into it: its items too, and
  -- each item's count, price and where from where this copy has none
  ahLists = function(to, from)
    for _, f in ipairs(from) do
      if tbl(f) and type(f.name) == "string" then
        local t
        for _, l in ipairs(to) do if tbl(l) and l.name == f.name then t = l break end end
        if not t then
          table.insert(to, f)
        else
          t.items = tbl(t.items) or {}
          local has = {}
          for _, n in ipairs(t.items) do has[n] = true end
          for _, n in ipairs(tbl(f.items) or {}) do if not has[n] then has[n] = true table.insert(t.items, n) end end
          for _, k in ipairs({ "want", "est", "from" }) do
            if tbl(f[k]) then
              t[k] = tbl(t[k]) or {}
              for item, v in pairs(f[k]) do if t[k][item] == nil then t[k][item] = v end end
            end
          end
          t.owner = t.owner or f.owner
        end
      end
    end
  end,
  charSeen = function(to, from)
    for realm, f in pairs(from) do
      if tbl(f) then
        to[realm] = tbl(to[realm]) or {}
        for name, t in pairs(f) do
          if type(t) == "number" and t > (tonumber(to[realm][name]) or 0) then to[realm][name] = t end
        end
      end
    end
  end,
}
S.merge = MERGE

local function folderLoaded()
  local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  return loaded and loaded(S.FOLDER) and true or false
end

-- once AuDHDDB is loaded: move its copies into the shared file and send the fields there from now on. Without the
-- shared folder, everything stays in AuDHDDB as before
function S.adopt()
  if not (tbl(AuDHDDB) and folderLoaded()) then return false end
  AuDHDSharedDB = tbl(AuDHDSharedDB) or {}
  local store = AuDHDSharedDB
  for _, k in ipairs(KEYS) do
    local mine = tbl(rawget(AuDHDDB, k))
    if mine then
      if tbl(store[k]) then
        local ok = pcall(MERGE[k], store[k], mine, store, AuDHDDB)
        if not ok then return false end   -- (a broken copy: left where it is)
      else
        store[k] = mine
      end
    end
  end
  for _, k in ipairs(KEYS) do rawset(AuDHDDB, k, nil) end
  -- (the game saves a table's own fields, not what its metatable gives)
  setmetatable(AuDHDDB, {
    __index = function(_, k) if SHARED[k] then return store[k] end end,
    __newindex = function(t, k, v) if SHARED[k] then store[k] = v else rawset(t, k, v) end end,
  })
  return true
end
function S.on() return getmetatable(AuDHDDB or {}) ~= nil and folderLoaded() end
