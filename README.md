# Raukin GDKP

A GDKP bidding addon for WoW 3.3.5a (Wrath of the Lich King). When the raid lead puts loot up for auction, a window opens with every item, the current bid and a countdown. You bid with one click, and the addon tells you when you have been outbid or have won.

## Installation

1. Download the zip from **Releases** (or **Code → Download ZIP**).
2. Copy the `RaukinGDKP` folder into `World of Warcraft\Interface\AddOns\`.
   If you used *Download ZIP*, copy the folder *inside* `RaukinGDKPClient-main`, not `RaukinGDKPClient-main` itself.
3. Restart the game, or `/reload` if it was already running.

The bidding window opens by itself when bidding starts. You can also open it with `/rgdkp` (or `/wgdkp`), or by clicking the minimap button.

## Features

### Bidding
- **One window for the whole raid's loot.** Every item shows its icon, current bid, top bidder and a countdown bar.
- **Bid with one click.** The bid box is pre-filled with the lowest valid bid (current bid + increment, or the minimum bid).
- **"Outbid!" and "You won!" alerts** in the middle of your screen.
- **Off-spec rounds.** Items nobody wanted come back at half price, marked **[OS]**.
- **Pause and anti-snipe extensions** from the raid lead update your timers live.

### Finding your items
- **Search** by item name.
- **Usable: On** shows only items your class can use.
- **Watched** shows only items you bid on or marked as watched.
- **Active** hides sold items and shows only pending and running auctions.

### Gold
- **Total pot and cut per raider** at the bottom of the window. Both update with every sale. Hover over them for the maths.
- **Top spender** of the raid at the top.
- **"You Owe: Xg"** appears on your trade window when you trade the raid lead for the items you won.

### Joining late or reconnecting
Joining the raid or reloading UI fetches the current list from the raid lead automatically.

### Looks
- The **ElvUI / AddOnSkins look** is applied automatically when either is installed. Turn it off with `/rgdkp skin`.
- An **opacity slider** sits at the top of the window.
- **Drag the bottom edge** of the window to choose how many rows show before it scrolls.

### Update check
When someone in your guild or group runs a newer version, a window opens with the download link to copy. `/rgdkp version` shows your version, and the link when an update is out.

## Slash commands

| Command | What it does |
|---|---|
| `/rgdkp` | Show or hide the bidding window |
| `/rgdkp center` | Move the window back to the middle of the screen |
| `/rgdkp rows N` | Number of items shown before the list scrolls |
| `/rgdkp opacity 10-100` | Window background opacity |
| `/rgdkp skin` | ElvUI / AddOnSkins look on or off (needs `/reload`) |
| `/rgdkp autoopen` | Stop or resume the window opening by itself when bidding starts |
| `/rgdkp version` | Your version, and the download link if a newer one is out |
| `/rgdkp help` | List all commands |

`/wgdkp` works everywhere `/rgdkp` does.

## Requirements

- WoW 3.3.5a (Interface 30300)
