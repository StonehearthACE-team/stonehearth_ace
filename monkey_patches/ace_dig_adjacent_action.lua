local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3
local build_util = require 'stonehearth.lib.build_util'
local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'

local AceDigAdjacent = class()
local log = radiant.log.create_logger('mining')

-- function AceDigAdjacent:start_thinking(ai, entity, args)
--    if ai.CURRENT.carrying then
--       return
--    end

--    local mining_zone = args.mining_zone
--    local adjacent_location = args.adjacent_location

--    -- resolve which block we are going to mine first
--    self._block, self._reserved_region_for_block = stonehearth.mining:get_block_to_mine(adjacent_location, mining_zone)
--    if self._block then
--       -- ACE: determine if we should build a ladder (there aren't already ladders, but they're needed for this zone)
--       local mining_zone_component = mining_zone:get_component('stonehearth:mining_zone')
--       if not mining_zone_component:has_ladders() and mining_zone_component:should_have_ladders() then
--          self._build_ladder = true
--       else
--          self._build_ladder = nil
--       end
--       ai:set_think_output()
--    end
-- end

function AceDigAdjacent:start_thinking(ai, entity, args)
   if ai.CURRENT.carrying then
      return
   end

   self._entity = entity
   self._mining_zone = args.mining_zone
   self._path = nil

   -- resolve which block we are going to mine first
   self._block, self._adjacent_location, self._reserved_region_for_block = self:_get_block_to_mine(args.adjacent_location)
   log:spam('%s start_thinking block to mine from %s: %s', entity, args.adjacent_location, tostring(self._block))
   if self._block then
      ai:set_think_output()
   end
end

function AceDigAdjacent:start(ai, entity, args)
   -- ACE: now that we're actually at the adjacent location, try to find the closest place we can mine
   -- if not self._block then
   --    self._block, self._reserved_region_for_block = stonehearth.mining:get_block_to_mine(self._adjacent_location, mining_zone)
   -- end

   -- reserve the block and any supporting blocks
   -- local reserved = self:_reserve_blocks(self._reserved_region_for_block, self._mining_zone)
   -- self._reserved_region_for_block = nil

   -- if not reserved then
   --    ai:abort('could not reserve mining region')
   -- end

   -- if the enable bit is toggled while we're running the action, go ahead and abort.
   self._zone_enabled_trace = radiant.events.listen(self._mining_zone, 'stonehearth:mining:enable_changed', function()
         local enabled = mining_zone:get_component('stonehearth:mining_zone')
                                       :get_enabled()
         if not enabled then
            ai:abort('mining zone not enabled')
         end
      end)
end

function AceDigAdjacent:run(ai, entity, args)
   local mining_zone = self._mining_zone
   local adjacent_location = self._adjacent_location
   local reserved = self._reserved_region_for_block
   local block = self._block
   self._block = nil

   ai:unprotect_argument(mining_zone)

   repeat
      reserved = self:_reserve_blocks(reserved, mining_zone)
      if not reserved then
         log:spam('%s failed to reserve any blocks', entity)
         break
      end
      if self._path then
         log:spam('%s following path to %s', entity, self._path:get_finish_point())
         ai:execute('stonehearth:follow_path', {
            path = self._path,
            stop_distance = args.harvest_range,
         })
      end
      self:_mine_block(ai, entity, mining_zone, block)
      block, adjacent_location, reserved = self:_get_block_to_mine(adjacent_location, ai)
   until not block
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
   log:spam('outputting mining loot %s', radiant.util.table_tostring(loot))
   radiant.entities.output_items(loot, worker_location, 1, 3, options)

   -- apply quality to mined items if relevant
   --self:_apply_quality(entity, work_player_id, items, mining_zone, block)
   -- for the autotest
   radiant.events.trigger(entity, 'stonehearth:mined_location', { location = block })

   -- do a check here for whether we need a ladder based on overall height at this point
   --log:debug('%s checking if mining ladder should be built at %s', entity, block)
   if mining_zone_component:should_have_ladders() and mining_zone_component:should_build_ladder_at(block) then
      local normal = -build_util.rotation_to_normal(radiant.math.quantize(radiant.entities.get_facing(entity), 90) + 180)
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

function AceDigAdjacent:_get_block_to_mine(adjacent_location, ai)
   self._path = nil
   
   if not self._mining_zone:is_valid() then
      return nil, nil, nil
   end

   -- Current_adjacent_location is a point in the adjacent region of the mining_zone.
   -- Worker_location is where the worker is actually in the world. This is often different than the
   -- adjacent location becuase we stop short in follow path to allow space for the mining animation.
   local worker_location = radiant.entities.get_world_grid_location(self._entity)
   if not worker_location then  --  The entity is not in world (e.g. suspended)
      return nil, nil, nil
   end

   log:spam('%s at %s getting block to mine from %s', self._entity, worker_location, adjacent_location)
   local block, reserved = stonehearth.mining:get_block_to_mine(adjacent_location, self._mining_zone, worker_location)
   if self:_is_eligible_block(block, worker_location) then
      log:spam('%s found block to mine: %s', self._entity, block)
      return block, worker_location, reserved
   end

   -- check for ladder before checking for pathable block
   if ai then
      local mining_zone_component = self._mining_zone:get_component('stonehearth:mining_zone')
      local ladder_handle = mining_zone_component:get_closest_ladder_handle(worker_location)
      local builder = ladder_handle and ladder_handle:get_builder()
      if builder then
         local proxy = builder:get_ladder_proxy()
         -- local ladder_location = radiant.entities.get_world_grid_location(proxy)
         ai:execute('stonehearth:build_ladder_adjacent', {
            ladder_builder_entity = proxy,
         })
      end
   end

   -- no more work at current_adjacent_location, move to another
   log:spam('%s not close enough to mining zone; finding path for more work', self._entity)
   self._path = self._entity:get_component('stonehearth:pathfinder')
                           :find_path_to_entity_sync('find another block to mine', self._mining_zone, 8)

   if not self._path then
      log:spam('%s could not find path to mining zone from %s', self._entity, worker_location)
      return nil, nil, nil
   end

   local next_adjacent_location = self._path:get_finish_point()
   block, reserved = stonehearth.mining:get_block_to_mine(next_adjacent_location, self._mining_zone, worker_location)
   log:spam('%s found block to mine from %s: %s', self._entity, next_adjacent_location, tostring(block))
   if not block then
      return nil, nil, nil
   end

   return block, next_adjacent_location, reserved
end

-- ACE: if there isn't an immediately reachable block, check for a reachable ladder that could be built
-- function AceDigAdjacent:_move_to_next_available_block(ai, entity, mining_zone, current_adjacent_location, harvest_range)
--    if not mining_zone:is_valid() then
--       return nil, nil
--    end

--    -- Current_adjacent_location is a point in the adjacent region of the mining_zone.
--    -- Worker_location is where the worker is actually in the world. This is often different than the
--    -- adjacent location becuase we stop short in follow path to allow space for the mining animation.
--    local worker_location = radiant.entities.get_world_grid_location(entity)
--    if not worker_location then  --  The entity is not in world (e.g. suspended)
--       return nil, nil
--    end
--    local next_block, next_adjacent_location, reserved_region_for_block

--    -- check to see if there are more reachable blocks from our current_adjacent_location
--    next_block, reserved_region_for_block = stonehearth.mining:get_block_to_mine(current_adjacent_location, mining_zone)
--    if self:_is_eligible_block(next_block, worker_location) then
--       next_adjacent_location = current_adjacent_location
--       self:_reserve_blocks(reserved_region_for_block, mining_zone)
--       return next_block, next_adjacent_location
--    end

--    -- check for ladder before checking for pathable block
--    local mining_zone_component = mining_zone:get_component('stonehearth:mining_zone')
--    local ladder_handle = mining_zone_component:get_closest_ladder_handle(worker_location)
--    local builder = ladder_handle and ladder_handle:get_builder()
--    if builder then
--       local proxy = builder:get_ladder_proxy()
--       -- local ladder_location = radiant.entities.get_world_grid_location(proxy)
--       ai:execute('stonehearth:build_ladder_adjacent', {
--          ladder_builder_entity = proxy,
--       })
--    end

--    -- no more work at current_adjacent_location, move to another
--    local path = entity:get_component('stonehearth:pathfinder')
--                            :find_path_to_entity_sync('find another block to mine', mining_zone, 8)

--    if not path then
--       return nil, nil
--    end

--    next_adjacent_location = path:get_finish_point()
--    next_block, reserved_region_for_block = stonehearth.mining:get_block_to_mine(next_adjacent_location, mining_zone)
--    if not next_block then
--       return nil, nil
--    end

--    -- reserve the block and any supporting blocks before yielding
--    self:_reserve_blocks(reserved_region_for_block, mining_zone)

--    ai:execute('stonehearth:follow_path', {
--       path = path,
--       stop_distance = harvest_range,
--    })

--    return next_block, next_adjacent_location
-- end

return AceDigAdjacent
