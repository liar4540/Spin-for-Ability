# Spin for Abilities

Roblox RNG ability spinner + battlegrounds PvP. Spinning is free and unlimited; players earn and buy **luck**.
The full game plan lives in the Obsidian vault next to this folder (`../Spin for Abilities Vault`).

## Setup (once)

1. Install [Aftman](https://github.com/LPGhatguy/aftman), then in this folder run:
   ```
   aftman install
   ```
   This installs Rojo 7.7.1 (pinned in `aftman.toml`).
2. Install the **Rojo** plugin in Roblox Studio (Plugins → Manage Plugins, or `rojo plugin install`).
3. Build the place file and open it in Studio:
   ```
   rojo build -o "Spin for Abilities.rbxlx"
   ```

## Every day

1. Run `rojo serve` in this folder.
2. In Studio, open the place and click **Connect** in the Rojo plugin.
3. Edit code in `src/`. Changes sync into Studio live.
4. Press Play. In Studio the Odds tests run automatically; check the Output for
   `[OddsTest] N passed, 0 failed`.

Maps, UI, VFX and dummies are built in Studio and saved in the place file (Rojo doesn't touch them).
The place file is git-ignored, so **publish often** to back it up.

## Where code lives

| Folder | Shows up in Studio as | What's in it |
|---|---|---|
| `src/server/` | `ServerScriptService.Server` | `init.server.luau` (starts everything), `Services/`, `Config/Codes.luau`, `Tests/` |
| `src/shared/` | `ReplicatedStorage.Shared` | `Odds.luau`, `Remotes.luau`, `Types.luau`, `Config/` (rarities, abilities, areas, economy, combat, product IDs) |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` | `init.client.luau` (starts everything), `Controllers/` |

**Golden rule:** the server decides everything important (spins, damage, money). The client only asks and shows.

## Odds

All spin chances come from `src/shared/Odds.luau`, which reads the "1 in N" numbers in
`src/shared/Config/Rarities.luau`. The server roll and the odds screen use the same function, so
the shown odds always match the real ones (required by Roblox for paid luck). Never type odds anywhere else.

## Testing spins (Studio)

Press Play. A **Studio-only test panel** appears at the bottom of the screen (it never shows in the live game):

- **SPIN** asks the server to spin and shows the result, its real chance, your luck and the reveal time.
- **Keep / Equip / Skip** answer the waiting result.
- Things to try: spin twice quickly (`TooSoon`), get an Epic+ and press SPIN again (`ChooseFirst`),
  keep 15 abilities then Keep again (`StorageFull`). The very first spin is always Rare+.

With no `SpinMachine`-tagged parts in the place, Studio lets you spin anywhere as the Starter area.
To test real machines: tag a Part `SpinMachine` and give it a string attribute `AreaId` (e.g. `Starter`).
