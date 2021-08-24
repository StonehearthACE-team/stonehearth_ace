local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3
local build_util = require 'stonehearth.lib.build_util'
local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'

local AceDigAdjacent = class()
local log = radiant.log.create_logger('mining')

function AceDigAdjacent:start_thinking(ai, entity, args)
   if ai.CURRENT.carrying then
      return
   end

   local mining_zone = args.mining_zone
   local adjacent_location = args.adjacent_location

   -- resolve which block we are going to mine first
   self._block, self._reserved_region_for_block = stonehearth.mining:get_block_to_mine(adjacent_location, mining_zone)
   if self._block then
      -- ACE: determine if we should build a ladder (there aren't already ladders, but they're needed for this zone)
      local mining_zone_component = mining_zone:get_component('stonehearth:mining_zone')
      if not mining_zone_component:get_ladders_region() and mining_zone_component:should_have_ladders() then
         self._build_ladder = true
      else
         self._build_ladder = nil
      end
      ai:set_think_output()
   end
end

function AceDigAdjacent:_mine_block(ai, entity, mining_zone, block)
   if not mining_zone:is_valid() then
      return false
   end

   local worker_location = radiant.entities.get_world_grid_location(entity)

   radiant.entities.turn_to_face(entity, block)
   ai:execute('stonehearth:run_effect', { effect = 'mine' })

   -- check after yielding
   if not mining_zone:is_valid() then
      return false
   end

   -- The reserved region may include support blocks. We must release it before looking
   -- for the next block to mine so that they will be included as candidates.
   -- Also release it on any failure conditions.
   self:_release_blocks(mining_zone)

   -- any time we yield, check to make sure we're still in the same location
   if radiant.entities.get_world_grid_location(entity) ~= worker_location then
      return false
   end

   local mining_zone_component = mining_zone:get_component('stonehearth:mining_zone')
   local loot = mining_zone_component:mine_point(block)
   local work_player_id = radiant.entities.get_work_player_id(entity)
   local options = {
      owner = work_player_id,
      add_spilled_to_inventory = true,
      inputs = entity,
      output = mining_zone,
      spill_fail_items = true,
      quality = self:_get_quality_chances(entity, mining_zone, block),
   }
   radiant.entities.output_items(loot, worker_location, 1, 3, options)

   -- apply quality to mined items if relevant
   --self:_apply_quality(entity, work_player_id, items, mining_zone, block)
   -- for the autotest
   radiant.events.trigger(entity, 'stonehearth:mined_location', { location = block })

   -- TODO: do another check here for whether we need a ladder based on overall height at this point

   -- if we should build a ladder here, set that up now
   if self._build_ladder then
      self._build_ladder = nil
      local normal = build_util.rotation_to_normal(radiant.entities.get_facing(entity) + 180)
      mining_zone_component:create_ladder_handle(block, normal)
   end

   return true
end

-- not using mining_zone or block, but maybe someone wants to override this function to take that into account
-- e.g., higher/lower chances based on altitude
function AceDigAdjacent:_get_quality_chances(entity, mining_zone, block)
   local buffs_component = entity:get_component('stonehearth:buffs')
   return buffs_component and buffs_component:get_managed_property('stonehearth_ace:mining_quality')
end

-- ACE: if there isn't an immediately reachable block, check for a reachable ladder that could be built
function AceDigAdjacent:_move_to_next_available_block(ai, entity, mining_zone, current_adjacent_location, harvest_range)
   if not mining_zone:is_valid() then
      return nil, nil
   end

   -- Current_adjacent_location is a point in the adjacent region of the mining_zone.
   -- Worker_location is where the worker is actually in the world. This is often different than the
   -- adjacent location becuase we stop short in follow path to allow space for the mining animation.
   local worker_location = radiant.entities.get_world_grid_location(entity)
   if not worker_location then  --  The entity is not in world (e.g. suspended)
      return nil, nil
   end
   local next_block, next_adjacent_location, reserved_region_for_block

   -- check to see if there are more reachable blocks from our current_adjacent_location
   next_block, reserved_region_for_block = stonehearth.mining:get_block_to_mine(current_adjacent_location, mining_zone)
   if self:_is_eligible_block(next_block, worker_location) then
      next_adjacent_location = current_adjacent_location
      self:_reserve_blocks(reserved_region_for_block, mining_zone)
      return next_block, next_adjacent_location
   end

   -- check for ladder before checking for pathable block
   local mining_zone_component = mining_zone:get_component('stonehearth:mining_zone')
   local ladder_handle = mining_zone_component:get_closest_ladder_handle(worker_location)
   local builder = ladder_handle and ladder_handle:get_builder()
   if builder then
      local proxy = builder:get_ladder_proxy()
      -- local ladder_location = radiant.entities.get_world_grid_location(proxy)
      ai:execute('stonehearth:build_ladder_adjacent', {
         ladder_builder_entity = proxy,
      })
   end

   -- no more work at current_adjacent_location, move to another
   local path = entity:get_component('stonehearth:pathfinder')
                           :find_path_to_entity_sync('find another block to mine', mining_zone, 8)

   if not path then
      return nil, nil
   end

   next_adjacent_location = path:get_finish_point()
   next_block, reserved_region_for_block = stonehearth.mining:get_block_to_mine(next_adjacent_location, mining_zone)
   if not next_block then
      return nil, nil
   end

   -- reserve the block and any supporting blocks before yielding
   self:_reserve_blocks(reserved_region_for_block, mining_zone)

   ai:execute('stonehearth:follow_path', {
      path = path,
      stop_distance = harvest_range,
   })

   return next_block, next_adjacent_location
end

return AceDigAdjacent
