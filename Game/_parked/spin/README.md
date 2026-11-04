# Parked: spin system

Taken out of the game for now; to bring it back:

1. Move `SpinService.luau` and `ZoneService.luau` back to `src/server/Services/`,
   and `SpinController.luau` back to `src/client/Controllers/`.
2. Add `"ZoneService"`, `"SpinService"` (after `RemoteGuard`) to ORDER in `src/server/init.server.luau`,
   and `"SpinController"` (after `HUDController`) to ORDER in `src/client/init.client.luau`.
3. Add back to `src/shared/Remotes.luau`:
   - EVENTS client → server: `SetAutoSpin`
   - EVENTS server → client: `SpinResult`, `Announcement`, `AreaUnlocked`
   - FUNCTIONS: `RequestSpin`, `ChooseResult`

Still in place (spin-related but shared): `shared/Odds.luau`, `Config/Rarities.luau`,
`Config/Areas.luau`, `Server/Tests/OddsTest.luau`, and the pity/TotalSpins fields in DataService
(kept so saved data stays compatible).
