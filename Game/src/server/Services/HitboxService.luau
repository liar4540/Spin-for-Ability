--!strict
-- HitboxService: spatial queries per move + 1 s position history for lag-compensated reach checks.
-- Status: empty stub. Planned in Milestone 1 (vault: 07 Tech Plan, 08 Roadmap).

local HitboxService = {}

-- Called once at startup, before any Start(). Create state, read config. Don't yield.
function HitboxService.Init() end

-- Called once after every Init(). Connect events, start loops.
function HitboxService.Start() end

return HitboxService
