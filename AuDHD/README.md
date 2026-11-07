# AuDHD

An addon for **WoW Forever** built for players with ADHD, autism or both, and anyone who gets distracted easily.

WoW asks you to keep a lot in your head: which buffs have dropped, whether you have arrows or soul shards, what to ask
your group for, where the next quest is. AuDHD remembers that for you and puts the next thing right in front of you, one
at a time, as a button you can click or an arrow you can follow.

What it does:

- **Keeps your character ready.** Buttons for missing weapon imbues, oils and self buffs; ammo restocking; a soul shard
  counter; selling, repairing and training reminders.
- **Makes groups easier.** One-click buff requests that know who can buff you and with what, click-cast healing frames,
  party quest progress and quest-complete messages.
- **Shows what's next.** Step-by-step levelling routes with an arrow that follows real walking paths.
- **Cuts down surprises.** Range and threat on nameplates, rare alerts and drop chances on tooltips.
- **Makes fishing one click.** Cast and reel in with one mouse button, lures put on for you, a splash you can hear,
  and each zone's fishing level coloured by your skill.
- **Shows the whole world.** A detailed map of both continents that zooms from the game's painted map down to single
  buildings.

Every part can be turned on or off, so you only get the parts that help you.

## Buttons that save a click

- **Weapon imbues and oils.** No imbue, oil or sharpening stone on your weapon? A small button appears with each one
  you know. Click to put it on. The oil button shows how many uses are left.
- **Self buffs.** Lightning Shield, Demon Skin, Inner Fire, aspects and the like: a button when one drops off.
- **Well Fed.** Not Well Fed, with food in your bags that does it? A button appears. Click to eat it, or pick another food from the list under it. Settings > Reminders: the food you prefer comes first.
- **Buff scrolls.** A scroll in your bags (Stamina, Agility and the like) whose buff isn't on you? A button to read it, with the scrolls for your other missing buffs under it. Quiet while the class buff it won't stack with is on.
- **Quest items.** When a step needs you to use an item (a rod, a potion, a totem), a button for it appears next to
  the route window.

All buttons can be dragged anywhere, and each has a small close button.

## Warlocks: soul shards

- A **soul shard counter** of its own, separate from the route window, so it works whether or not you follow a route.
- **Warns you when low** (red number, a sound and a message), so you don't start a fight without a shard.
- **Keeps you at your max.** Past the max you set, the extras are deleted so Drain Soul keeps working. The game only lets
  an addon delete an item during a key press or click of yours, so one goes with each key you press or click in the
  world, or click the counter.
- Set your **max** and **low** numbers in the settings, or with the mouse wheel on the counter (Shift + wheel for low).

## Done for you

Hold **Shift** while talking to an NPC to pause all of these.

- **Accepts and hands in** your guide's quests.
- **Picks your quest reward**: an upgrade for your spec if there is one, otherwise the one that sells for the most.
  `/audhd spec <name>` sets which spec rewards are scored for. A Mining, Herbalism or Skinning book is always left for
  you to choose.
- **Sells grey items and repairs** at vendors.
- **Hunters: buys ammo** to keep you stocked, leaving enough gold for your next training.
- **Sell and train nudges.** Bags nearly full near a vendor, new skills to learn near your class trainer, or a
  profession near the cap of its rank with its trainer close by? A reminder pops up once per visit, for Alliance and
  Horde. Hunters near an ammo vendor get one when running low, and in a group whenever the quiver isn't full. **Go to** points the arrow there; **Snooze** quiets it for 10, 20 or
  30 minutes.
- **Alt mail.** In the settings (Alt mail tab), name your bank character, first and last name, or pick an alt for
  each kind of item: herbs to your alchemist, ore to your blacksmith, green BoE gear to your enchanter, the rest to a
  catch-all. Each character has its own alt mail settings and starts with them off. Near a mailbox with gear you wouldn't wear or trade goods the route doesn't need, a reminder pops up, and
  the mail window gets a **Send all** button: it asks once, then sends them alt by alt, 12 items a mail. Mail only goes
  to characters that have logged in with AuDHD on your account, so a typo doesn't send your herbs to a stranger. For
  an alt on another account, tick **Other account**. The game can't tell an addon when you delete a character, so
  **Your characters...** lists them with when each was last played: remove ones you've deleted, so a new player who
  takes the name never gets your mail.
- **What your alts carry.** Item tooltips list which of your characters on this realm have that item, and where: bags,
  bank (as it was when they last closed it), their mailbox, or mail on the way to them. Worn gear isn't counted.
  **Find an item...** (Alt mail tab, or `/audhd find <name>`) searches them all by part of the name. Each character
  is added once you log in on it.
  The **Alts** button on top of your backpack opens another character's bags, bank or mail as if they were yours, or
  **Show all** of them side by side (also `/audhd bags`).
- **Reagent bag.** Opens and closes with your backpack (Settings > User Interface).
- **Auction house.** A window beside the auction house:
  - **Sell** lists what is in your bags that can go up (not what the route still needs, or gear you would wear). Pick
    one and it finds the cheapest price on sale and matches it, since the newest auction at a price sells first. Set
    how many and for how long (2, 8 or 24 hours), see the deposit, and click Post.
  - **Your auctions** shows what you have up. **Check prices** marks in red the ones someone is now cheaper than.
  - **Shopping** keeps lists of item names. **Search all** finds the cheapest of each, and **Buy** gets it.
  - When it opens, a full scan reads every price (at most once every 15 minutes, the game's limit). Item tooltips
    then show the cheapest price each and when it was seen.
  - Near an auctioneer in a city, with things in your bags worth at least 50s more there than at a vendor, a
    reminder says so. A price over 10 times what a vendor pays is ignored as an odd listing, except on
    patterns. Never a detour. All of it can be switched off in Settings, Auction house.
  - The Sell list shows what a vendor pays (V) and what disenchanting gives (DE) next to each price, and marks the
    items a vendor pays about as much for. Hold **Shift** on an item tooltip for its price history.
  - A grey frame marks the stack in your bags that loses you least if you need room.
  - Crate tooltips price each bundle. Alt-click a crate to add a bundle to your shopping banker's list.
- **Quest complete message.** When a quest's objectives are all done, it says so in your chat, and (if you like) to your party when
  you're in one.

## Party

- **Ask for buffs.** In a group with a priest, mage, druid or paladin, a button appears for each buff you're missing
  that someone there can give. One click asks them in party chat, politely and by name. You don't need to know which
  class gives what.
- **Click-cast healing.** Your party (you first) as health bars in a row near the bottom of the screen. Click someone to
  cast on them:
  - Pick a spell and rank for each mouse button, and for Shift + click and Ctrl + click too. Choose from your spellbook
    or drag a spell in. Right-click a slot to clear it. Spells are saved per character.
  - Damaging spells work too: they go to whoever that person is targeting. Click the tank to hit the tank's target.
  - While you cast a heal, the bar shows how far it will fill them and how much it heals ("+340").
  - Your own heals over time and buffs show along the bottom of each bar, with a timer sweep, so you can see who still
    has your Rejuvenation or Renew. Everyone else's buffs show in a row above the bar.
  - Bars show health missing, Dead or Offline, and fade when someone is out of range.
  - Works in combat. Turn it on in the settings, or just pick a spell (`/audhd heal setup`).
- **Party quest progress.** See how far your group has got on quests you share ("Bob 3/7, Amy done"). Only party
  members who also run AuDHD show up.

## The guide window

- **Guides for every race and class**, from Polestar: levelling for every starting area, plus class, reputation,
  collectible and other guides. Pick one with the Routes button or `/audhd guides`.
- **One step at a time.** "Take this quest", "kill 8 of these", "hand that in". Progress counts update as you play.
- **It knows where you are.** Your place comes from your quest log and what you've done, not from a counter. Reloads,
  disconnects and quests done out of order don't lose your place, and you can start anywhere.
- **Back on track.** Wander off and stay away and you get one plain message: your step, how far it is, and the arrow
  pointing back. `/audhd where` says the same whenever you ask, and you get it when you log back in.
- **Extra quests.** Want a quest the guide doesn't have? `/audhd extra add <name>`, or take it and say yes to the pop-up.
  It goes where it adds the least time, not before you're the level for it, and you're told about what it costs.
- **Timed quests** are never picked up on the way somewhere. With one in your log, finishing and handing it in comes
  before everything else.
- **Missing data.** If we don't know where something is, the addon says so and asks you to log the quest, then gives
  you text to post on GitHub or CurseForge. To log any quest yourself, click its **Log** button in the route window
  (**Logging** while it does; click again to stop).
- **One task at a time.** A step with several things to do shows a **Done** button on each row.
- **Class quests.** When a class quest for you opens up, a pop-up offers to swap to its guide now, after the route, or
  later. Finish it and you're back on your route.

## Dungeons

`/audhd dungeons`, or Alt-click the minimap button. The dungeons for your level, what their quests are worth and where
each quest stands. **Pick up quests** and **Hand in** run as a guide in the route window and take you back to your
route when done; **Go to entrance** points the arrow there. A heads-up after a level-up when a dungeon's quests are ready is
off by default (Settings > Dungeons), where you can also choose which dungeons the levelling guides send you to.

## Getting there

- **Arrow.** Green when you're facing the right way, red when you're facing away. Drag it anywhere, resize it in the
  settings, or lock it so clicks go through.
- **Walking paths, not straight lines.** Routes go around cliffs, trees, water and buildings, using a path map of each
  zone. Caves and mines lead you to the entrance first.
- **Smoother paths.** The walking path is pulled straight wherever the ground allows, so it doesn't zigzag. Prefer
  plain straight lines on the map? Switch them on in the settings (Windows) or with `/audhd paths`.
- **Blocked?** `/audhd blocked` tells it the way ahead is closed and it finds another; `/audhd unblock` resets that.
- **Flight paths.** Passing a flight master you don't have yet? It sends you to learn it first (talking to them is
  enough). Long trips use flights
  you know, and the Deeprun Tram between Ironforge and Stormwind when that's quicker.
- **Map pins.** The route's next steps are numbered on your world map and minimap. The **Route** tick box in the world map's bottom-left corner hides the numbers and lines on the world map only.
- **Your own waypoint.** `/way 42 54` (or `/way <zone> 42 54`) points the arrow anywhere.

## In combat

- **Range guide** on the enemy's nameplate: too close, in range, too far. Useful for hunters and casters.
- **Threat** on nameplates, so you can see what's about to turn on you.
- **Rare alerts.** A pop-up and a `/tar` button (with the rare's face) near any rare's spawn point, louder when a quest
  of yours needs it.
  Choose all rares, only the route's rares, or none. Optionally, the mouse wheel cycles through nearby rares.
- **Drop chances on mob tooltips.** Hover a mob to see what quest items it drops, the known (or estimated) chance, and
  how lucky you've been so far: `Dewy Lasher Frond 25% · you 2/9 (22%)`.

## Info bar

A bar along the top of the screen, one button per part: your money, gold an hour, XP an hour, time to the next level
at that pace, bag slots free or in use, your choice (click to open your bags), your most worn gear (hover for every piece), and the master
volume (mouse wheel to change it, click to mute). Hover for more: money in and out, XP from kills and from quests,
your rested bonus, kills to level. The session starts when you log in; right-click or `/audhd stats reset` starts it again.
Show it, lock it, and pick its parts in the settings (Windows).

## Fishing

- **One-click fishing.** With a fishing pole in your hands, one click of a mouse button you choose (right, middle,
  button 4 or 5) casts, and the same click reels in when the bobber splashes. Holding the button still turns the camera
  as usual.
- **Lures for you.** No lure on your pole? The click puts the best one from your bags on first.
- **A louder splash.** While a pole is equipped the splash is turned up and the music and ambience down, so the bite
  is easy to hear. Set the volume in the settings. Everything goes back when you take the pole off.
- **Fishing level of the zone**, under the minimap while you hold a pole and on the world map, coloured like quest
  difficulty: red is too high even with your lures, orange needs a lure you have, yellow is about your skill, green
  gives fewer skill-ups and grey none.

## Detailed map

A big map of the whole open world, both continents side by side, drawn from the game's own pictures.

- **Zoom all the way.** Zoomed out it's the game's painted continent map; zoom in with the mouse wheel and it blends
  into the detailed minimap pictures, down to single buildings. Ironforge, Undercity, Stormwind and Orgrimmar fade in
  from their city maps.
- **You, your group and your route on it.** Your arrow, a class-coloured dot for each party or raid member (hover for
  who it is), the walking path to your step, and the next steps as numbered dots.
- **Drag to move around**, or **Center on me** to follow you again.
- Open it with `/audhd bigmap` or a key (Key Bindings → AuDHD → Detailed map). It can also take over your world map key,
  with a button to the game's own map. Off until you switch it on in the settings.
- **Joined-up world map (work in progress, not yet tried in game).** The game's own world map with every zone's
  painting joined into one, quest log and all: zoom from the whole world down to the minimap's pictures, drag past a
  map's edge into the next. Off unless you tick it in the settings' Maps tab.

## Settings

`/audhd settings`, a right-click on the minimap button, or **Options → AddOns → AuDHD**. The settings are in tabs:
Windows, Automation, Reminders, Rares, Party, Fishing and Warlock.

Every part of the addon can be switched on or off: the route window, arrow, range guide, minimap button, map pins,
threat, each automation, rare alerts, imbue and buff buttons, sell and train reminders, the quest item button, quest
complete messages, drop chances, party progress, click-cast healing, the soul shard counter, each fishing helper and
the detailed map.

## Commands

`/audhd` and `/wfn` both work.

| Command | What it does |
| --- | --- |
| `/audhd` | Show or hide the guide window |
| `/audhd settings` | Open the settings |
| `/audhd done` · `later` · `back` | Mark the step done, push it later, or go back one |
| `/audhd goto <n>` | Jump to step n |
| `/audhd note <text>` | Add a note to the log (for bug reports) |
| `/audhd report` | Make a problem report to paste on GitHub or CurseForge |
| `/audhd dungeons [name]` | The Dungeons window |
| `/audhd arrow` | Arrow options (show, hide, lock, unlock, scale) |
| `/audhd map on\|off` | Route pins on the world map and minimap |
| `/audhd threat on\|off` | Threat on nameplates |
| `/audhd rares all\|route\|off` | Which rares to alert for |
| `/audhd auto` | Automation switches (accept, complete, junk, repair on or off; reward value or manual) |
| `/audhd ammo [off\|<count>]` | Hunter ammo restocking |
| `/audhd spec [name]` | The spec rewards are scored for |
| `/audhd imbue [off\|on]` | Weapon imbue and oil buttons |
| `/audhd buffs [off\|on]` | Self-buff buttons |
| `/audhd food [off\|on]` | The Well Fed button |
| `/audhd scrolls [off\|on]` | The buff scroll button |
| `/audhd askbuffs [off\|on]` | Ask-the-party buff buttons |
| `/audhd announce [off\|on]` | Quest complete messages |
| `/audhd announce party off\|on` | Whether they also go to party chat |
| `/audhd heal [on\|off\|setup]` | Click-cast healing frames, or pick their spells |
| `/audhd shards [on\|off\|max <n>\|low <n>\|lock\|unlock\|reset]` | Soul shard counter |
| `/audhd fish [on\|off\|right\|middle\|4\|5]` | One-click fishing, and which mouse button |
| `/audhd fish loud on\|off` · `volume <10-100>` | The louder splash, and its volume |
| `/audhd fish lure on\|off` · `zone on\|off` · `map on\|off` | Lures, the zone's fishing level under the minimap, on the world map |
| `/audhd fish status` | What one-click fishing sees right now |
| `/audhd bigmap [on\|off\|replace on\|off]` | Open the detailed map, switch it on or off, or let it take the world map key |
| `/audhd minimap on\|off` | Minimap button |
| `/audhd blocked` · `unblock` | Route around a blocked path, or reset |
| `/audhd paths [straight\|detailed]` | Walking paths on the map as straight lines or the detailed way |
| `/audhd stats reset` | Start a new info bar session |
| `/audhd bankalt <name>` | Your bank character's first and last name, for Basic alt mail |
| `/audhd find <item>` | Search your characters' bags, banks and mail for an item |
| `/audhd bags [all\|close\|<name>]` | Open a character's bags, all of them, or close them |
| `/audhd ah [scan\|on\|off\|price <item>]` | The auction house window, a full scan, the helper on or off, an item's price |
| `/audhd perf` | Measure the addon's frame time (for lag reports) |
| `/audhd where` | Your guide, your step and how far it is |
| `/audhd guides` | Pick a guide |
| `/audhd extra add <quest name or id>` · `remove <id>` | Fit a quest of your own into the guide, where it adds the least time |
| `/audhd share` | Log a quest we have no data for, and hand the log over |
| `/audhd log` | Show the log |

## Install

1. Download the latest release (or the repository as a zip).
2. Put every folder from the zip (`AuDHD`, `AuDHDEngine`, the `AuDHD_` ones) in the `Interface\AddOns` folder of your
   WoW Forever install. Don't rename them.
3. Restart the game, or `/reload` if it's running.

## Reporting a problem

AuDHD keeps a log of what it saw and decided (steps, positions, pop-ups, frame time). If something goes wrong:

1. Press **Report a problem**: Ctrl-click the minimap button, or Settings > Help/Info, or type `/audhd report`.
2. Say what went wrong and press **Make report**.
3. Press **Select all**, then Ctrl+C, and paste it into a [new issue](https://github.com/theSarcasticPixel/AuDHD/issues)
   or a comment on the CurseForge page.

The report holds the last 30 minutes of the log, packed into one code, with your race, class and level but no
character names, realm or account. An addon can't send anything out of the game itself, so the copy and paste is the
one step left to you.

## Credits

- [Polestar](https://github.com/fitzforge/polestar)
- Blizzard Entertainment
- [CMaNGOS](https://github.com/cmangos/classic-db)
- [pfQuest](https://github.com/shagu/pfQuest)
- Leffe's navigation maps

## License

[GPL-3.0](LICENSE)
