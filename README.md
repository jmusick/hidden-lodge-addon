# HiddenLodge

Repository: [jmusick/hidden-lodge-addon](https://github.com/jmusick/hidden-lodge-addon). Local folder: `C:/Users/JD/source/hidden-lodge-addon`.

This README owns setup and usage; [AGENTS.md](AGENTS.md) owns coding conventions. Companion projects: [website](https://github.com/jmusick/hidden-lodge-website/blob/main/README.md) · [desktop](https://github.com/jmusick/hidden-lodge-desktop/blob/master/README.md) · [sim](https://github.com/jmusick/hidden-lodge-sim/blob/master/README.md). Creative masters and provenance live in `C:/Users/JD/projects/hidden-lodge/README.md`. The Obsidian project note links to these files; implementation and operational instructions belong here.


World of Warcraft addon for the Hidden Lodge guild — surfaces data synced from the HiddenLodge Desktop app and the HiddenLodge website, plus a handful of standalone in-game tools (cauldron tracking, raid invites/organizing, guild note sync).

## Files
- `HiddenLodge.toc`: Addon metadata and load order.
- `HiddenLodge.lua`: Ace3 bootstrap, saved-variable defaults, slash command routing (`/hl`), and the integration registry.
- `HiddenLodge_Style.lua`: Shared UI constants (window/button sizing, colors) and button style helpers.
- `HiddenLodge_Preparedness.lua`: Preparedness tier lookup and display color helpers (desktop-synced).
- `HiddenLodge_GreatVault.lua`: Great Vault score lookup and display color helpers (desktop-synced).
- `HiddenLodge_Attendance.lua`: Attendance score lookup and display color helpers (desktop-synced; surfaced only in the RCLootCouncil column, not on the main window's sync panel).
- `HiddenLodge_RaidSignup.lua`: Raid signup status (Coming/Tentative/Late/Absent/Not Signed) lookup, sort/color helpers, and sync status (desktop-synced).
- `HiddenLodge_Droptimizer.lua`: Per-item upgrade delta/percent lookup from synced Droptimizer data, plus the RCLootCouncil "current item" detection shared by that integration.
- `HiddenLodge_InviteTool.lua`: Raid Invites window — invites online, signed-up guild members not yet in your group.
- `HiddenLodge_RaidComp.lua`: Raid Comp panel — imports a pasted export string from the website's Raid Composition page and uses it to invite missing raiders, organize raid subgroups to match, and whisper downsize notices to raiders cut from the comp.
- `HiddenLodge_AltNoteSync.lua`: Guild public-note sync — auto-applies synced main/nickname notes when you can edit them, plus a "Mismatched Notes" review window.
- `HiddenLodge_CauldronTracker.lua`: Raid cauldron flask/phial tracking (spell-cast + loot detection) and its popup window.
- `HiddenLodge_Integration_RCLootCouncil.lua`: RCLootCouncil integration module that injects the Prep/GV/Att/Signup/Upgrade voting-frame columns.
- `HiddenLodge_UI.lua`: Main window construction, desktop sync status display, and buttons that open the other panels.

## Ace3 dependency
This addon currently expects Ace3 to be installed as a separate addon.

- Easiest path: install Ace3 from CurseForge/Wago like any normal addon.
- The `.toc` includes `OptionalDeps: Ace3, RCLootCouncil`, so load order works when those addons are present.

If Ace3 is missing, HiddenLodge prints a friendly chat warning instead of hard failing.

## Build and workflow
WoW addons are not usually "built" like web apps. The normal workflow is edit -> reload UI in game.

1. Keep the source checkout as `hidden-lodge-addon`; install/symlink it under WoW’s required addon name `HiddenLodge`.
2. Put or symlink this folder into your WoW AddOns directory:
	- `_retail_/Interface/AddOns/HiddenLodge`
3. Launch game, enable `HiddenLodge` and `Ace3` on character select.
4. In game, use `/reload` after code changes.
5. Use `/hl` to verify addon startup.

## Main window
The main window (`/hl` or `/hl show`) shows a sync status panel — one section each for Preparedness, Great Vault, Raid Signup, Droptimizer, and Alt Note Sync, all pushed by the HiddenLodge Desktop app into `HiddenLodgeDB` — plus buttons that open the other panels: **Raid Invites**, **Cauldron Tracker**, **Raid Comp**, and **Show Mismatched Notes**. Each sync section reports its state (Missing/Legacy/Pending Apply/Ready), entry count, and last-synced time.

Attendance data is also desktop-synced but has no section on this panel — it's only surfaced via the RCLootCouncil `Att` column below.

Gem/enchant checks and roster inspection are currently removed from this addon UI.

## Raid Invites panel
Opened via the "Raid Invites" button on the main window (no slash command). Lists online guild members whose synced raid-signup status is Coming/Tentative/Late, with per-row **Invite** buttons and an **Invite All Online** button. Reuses the same invite logic (`InviteRaidSignupCandidate`) that Raid Comp's "Invite Missing" calls.

## Raid Comp panel
Opened via the "Raid Comp" button on the main window or `/hl raidcomp`. Unlike the desktop-synced data above, this is filled by pasting a string directly — no desktop app or `/reload` required, since it needs to be current right before you pull.

1. On the website's `/raid-composition` page, click "Export to Addon" and copy the string (format: `HLRC1|Name-Realm:Group:CLASSTOKEN,...`; a temp/PUG candidate has no realm and is matched by name only).
2. Paste it into the Raid Comp panel's text box and click Import. This is stored in memory (`self.db.raidComp`) and survives `/reload` until you import again.
3. The row list shows every raider from the imported comp, color-coded by class, with their assigned group and whether they're not in the raid yet, in the wrong group, or already correct.
4. **Invite Missing** invites anyone in the comp who isn't in your raid yet (reuses the same invite logic as the Raid Invites panel — requires invite permission).
5. **Organize Groups** moves everyone already in the raid into their assigned subgroup (requires raid leader or assistant). This is best-effort and synchronous per click: it resolves any pair who each want the other's current group (a direct swap, which needs no free slot) plus anyone whose target group already has room, from one snapshot of the raid roster. A longer chain (A → B → C → A) or a move blocked on a full target group is left in place and reported — click Organize Groups again after the first round of moves lands to resolve those.
6. **Whisper Cuts** whispers everyone currently in the raid who isn't among the imported comp's entries, letting them know they can drop group for downsizing and pointing them to the website's Raid Composition page for details (requires raid leader or assistant; confirms with a count before sending).

## Alt Note Sync / Mismatched Notes
The Desktop app syncs each managed character's desired guild public note (main + nickname) into `self.db.altNoteSync`. Two ways this surfaces:

- **Auto-apply**: on `GUILD_ROSTER_UPDATE`/`PLAYER_GUILD_UPDATE` (and once on login), if you're able to edit public notes and there's a newer sync than what was last applied, HiddenLodge silently writes the desired note to any mismatched guild member via `GuildRosterSetPublicNote` and prints a one-line summary to chat.
- **Manual review**: the "Show Mismatched Notes" button on the main window opens a window listing every managed character (Character/Main/Nickname/Desired Note/Current Note), with mismatched rows highlighted red and a per-row **Copy** button (opens a popup with the desired note pre-selected for Ctrl+C).

## RCLootCouncil integration
When RCLootCouncil is installed and loaded, HiddenLodge injects five sortable columns into the voting frame, all populated from desktop-synced (or, for Upgrade, also desktop-synced) data and matched by character + realm with name-only fallback:

- `Prep`: Preparedness tier.
- `GV`: Great Vault score (0-100).
- `Att`: Attendance score (0-100).
- `Signup`: Raid signup status (Coming/Tentative/Late/Absent/Not Signed) plus signed-at time.
- `Upgrade`: Droptimizer upgrade (delta + %) for whichever item is currently up for vote, resolved from the voting frame's current item link/session.

## In-game usage
- `/hl` or `/hl show`: Toggle/show the main window.
- `/hl hide`: Hide the main window.
- `/hl cauldron`: Toggle the cauldron tracker window.
- `/hl raidcomp`: Open the Raid Comp panel.
- Raid Invites and Show Mismatched Notes are button-only (no slash command) — open them from the main window.

## Cauldron tracker
Tracks how many flasks/phials each raider takes from raid cauldrons, ported from the standalone CauldronTracker addon.

- Detects cauldron placement via `UNIT_SPELLCAST_START` (known spell IDs, plus a name-contains-"cauldron" fallback).
- Detects each flask/phial "create" via `CHAT_MSG_LOOT`, counting one charge per create regardless of stack size.
- Falls back to burst detection (3+ different players creating within 30s) if a placement cast is missed.
- Counts are scoped per day and reset at `/reload` only if the active cauldron window has expired.
- **Reset** clears the current day's counts; **Share** posts the current day's counts to chat via `C_ChatInfo.SendChatMessage`.
- Open via the "Cauldron Tracker" button on the main window or `/hl cauldron`.

## CurseForge release automation
This repo includes tag-based release automation in `.github/workflows/release.yml` using `BigWigsMods/packager`, publishing to CurseForge project id `1498420` (set in `.pkgmeta`). Push a tag matching the version in `HiddenLodge.toc` (e.g. `v1.5.0`) to trigger a release — bump `## Version` in the `.toc` first, since there's no separate version file.

`CURSEFORGE_API_TOKEN` must already exist in this repo's GitHub Actions secrets for the workflow to authenticate.
