# AuDHD

An addon for **WoW Forever** built for players with ADHD, autism or both, and anyone who gets distracted easily.

WoW asks you to keep a lot in your head: which buffs have dropped, whether you have arrows or soul shards, what to ask
your group for, where the next quest is. AuDHD remembers that for you and puts the next thing right in front of you, one
at a time, as a button you can click or an arrow you can follow.

It does four things:

- **Keeps your character ready.** Buttons for missing weapon imbues, oils and self buffs; ammo restocking; a soul shard
  counter; selling, repairing and training reminders.
- **Makes groups easier.** One-click buff requests that know who can buff you and with what, click-cast healing frames,
  party quest progress and quest-complete messages.
- **Shows what's next.** Step-by-step levelling routes with an arrow that follows real walking paths.
- **Cuts down surprises.** Range and threat on nameplates, rare alerts and drop chances on tooltips.

Every part can be turned on or off, so you only get the parts that help you.

## Buttons that save a click

- **Weapon imbues and oils.** No imbue, oil or sharpening stone on your weapon? A small button appears with each one
  you know. Click to put it on. The oil button shows how many uses are left.
- **Self buffs.** Lightning Shield, Demon Skin, Inner Fire, aspects and the like: a button when one drops off.
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

- **Accepts and hands in** route quests.
- **Picks your quest reward**: an upgrade for your spec if there is one, otherwise the one that sells for the most.
  `/audhd spec <name>` sets which spec rewards are scored for.
- **Sells grey items and repairs** at vendors.
- **Hunters: buys ammo** to keep you stocked, leaving enough gold for your next training.
- **Sell and train nudges.** Bags nearly full near a vendor, or new skills to learn near your class trainer? A reminder
  pops up once per visit.
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

## The route window

- **One step at a time.** "Take this quest", "kill 8 of these", "hand that in". Progress counts update as you play.
- **It knows where you are.** Your place comes from your quest log and what you've done, not from a counter. Reloads,
  disconnects and quests done out of order don't lose your place.
- **Done, later, back.** Mark a step done yourself, push it to later, or step back if you need to.
- **Side quests are optional.** Quests already in your log are a head start, never a requirement. Pick one up that the
  route doesn't use and a pop-up asks whether to keep it (it's added where it fits) or skip it (it's abandoned).
- **Elites and hard quests** on the way show up as optional pop-ups, not forced steps.
- **Timed quests** are never picked up early, so the timer doesn't run out while you're doing something else.

## Getting there

- **Arrow.** Green when you're facing the right way, red when you're facing away. Drag it anywhere, resize it in the
  settings, or lock it so clicks go through.
- **Walking paths, not straight lines.** Routes go around cliffs, trees, water and buildings, using a path map of each
  zone. Caves and mines lead you to the entrance first.
- **Blocked?** `/audhd blocked` tells it the way ahead is closed and it finds another; `/audhd unblock` resets that.
- **Flight paths.** Passing a flight master you don't have yet? It sends you to learn it first (talking to them is
  enough). Long trips use flights
  you know, and the Deeprun Tram between Ironforge and Stormwind when that's quicker.
- **Map pins.** The route's next steps are numbered on your world map and minimap.
- **Your own waypoint.** `/way 42 54` (or `/way <zone> 42 54`) points the arrow anywhere.

## In combat

- **Range guide** on the enemy's nameplate: too close, in range, too far. Useful for hunters and casters.
- **Threat** on nameplates, so you can see what's about to turn on you.
- **Rare alerts.** A pop-up and a `/tar` button (with the rare's face) near any rare's spawn point, louder when a quest
  of yours needs it.
  Choose all rares, only the route's rares, or none. Optionally, the mouse wheel cycles through nearby rares.
- **Drop chances on mob tooltips.** Hover a mob to see what quest items it drops, the known (or estimated) chance, and
  how lucky you've been so far: `Dewy Lasher Frond 25% · you 2/9 (22%)`.

## Settings

`/audhd settings`, a right-click on the minimap button, or **Options → AddOns → AuDHD**.

Every part of the addon can be switched on or off: the route window, arrow, range guide, minimap button, map pins,
threat, each automation, rare alerts, imbue and buff buttons, sell and train reminders, the quest item button, quest
complete messages, drop chances, party progress, click-cast healing and the soul shard counter.

## Commands

`/audhd` and `/wfn` both work.

| Command | What it does |
| --- | --- |
| `/audhd` | Show or hide the route window |
| `/audhd settings` | Open the settings |
| `/audhd routes` | Pick a route |
| `/audhd done` · `later` · `back` | Mark the step done, push it later, or go back one |
| `/audhd goto <n>` | Jump to step n |
| `/audhd note <text>` | Add a note to the log (for bug reports) |
| `/audhd arrow` | Arrow options (show, hide, lock, unlock, scale) |
| `/audhd map on\|off` | Route pins on the world map and minimap |
| `/audhd threat on\|off` | Threat on nameplates |
| `/audhd rares all\|route\|off` | Which rares to alert for |
| `/audhd auto` | Automation switches (accept, complete, junk, repair on or off; reward value or manual) |
| `/audhd ammo [off\|<count>]` | Hunter ammo restocking |
| `/audhd spec [name]` | The spec rewards are scored for |
| `/audhd imbue [off\|on]` | Weapon imbue and oil buttons |
| `/audhd buffs [off\|on]` | Self-buff buttons |
| `/audhd askbuffs [off\|on]` | Ask-the-party buff buttons |
| `/audhd announce [off\|on]` | Quest complete messages |
| `/audhd announce party off\|on` | Whether they also go to party chat |
| `/audhd heal [on\|off\|setup]` | Click-cast healing frames, or pick their spells |
| `/audhd shards [on\|off\|max <n>\|low <n>\|lock\|unlock\|reset]` | Soul shard counter |
| `/audhd minimap on\|off` | Minimap button |
| `/audhd blocked` · `unblock` | Route around a blocked path, or reset |
| `/audhd perf` | Measure the addon's frame time (for lag reports) |
| `/audhd log` · `reset` | Show the log, or reset your progress |

## Install

1. Download the latest release (or the repository as a zip).
2. Put the `AuDHD` folder in the `Interface\AddOns` folder of your WoW Forever install. The folder must be named
   `AuDHD` and contain `AuDHD.toc`.
3. Restart the game, or `/reload` if it's running.

## Reporting a problem

AuDHD keeps a log of what it saw and decided (steps, positions, pop-ups, frame time). If something goes wrong:

1. Type `/audhd note what happened` right away.
2. `/reload` so the log is saved.
3. Find the log file: `WTF\Account\<your account>\SavedVariables\AuDHD.lua` in your WoW Forever folder.
4. [Open an issue](https://github.com/theSarcasticPixel/AuDHD/issues), say what went wrong, and attach the file.

The log contains your character's name and route progress, nothing else.

## Credits

Quest and map data based in part on [Questie](https://github.com/Questie/Questie) and the
[ForeverDB](https://foreverdb.net) community, with many corrections from in-game testing.

## License

[GPL-3.0](LICENSE)
