-- ============================================================
--  frcp_vipgarage  |  config.lua
--  🔧 CUSTOM INPUTS — everything marked !! CHANGE ME !!
-- ============================================================

Config = {}

-- How far away a player must be before the parked vehicle
-- entity is created in the world (metres)
Config.SpawnRadius            = 50.0

-- How often (milliseconds) the server checks who is near
-- and spawns vehicles for them
Config.StreamInterval         = 5000

-- How often (ms) the server checks and despawns vehicles
-- when no players are nearby
Config.DespawnInterval        = 5000

-- Radius of the ox_target interaction sphere on each slot
Config.TargetRadius           = 2.5

-- Distance at which the Park / Retrieve prompt appears
Config.SlotInteractDistance   = 5.0

-- Maximum parking slots one player can be assigned by admins
Config.MaxSlotsPerOwner       = 10

-- Maximum number of other players one owner can give access to
Config.MaxAccessGrantsPerOwner = 4

-- !! CHANGE ME !! The permission group that can use admin commands
-- This must match the permission group name in your Qbox/ACE setup
Config.AdminGroup             = 'admin'

-- Set to true to print extra info in server console while testing
Config.Debug                  = false
