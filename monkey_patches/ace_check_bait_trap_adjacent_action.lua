local LootTable = require 'stonehearth.lib.loot_table.loot_table'

--local CheckBaitTrapAdjacent = require 'stonehearth.ai.actions.trapping.check_bait_trap_adjacent_action'
local AceCheckBaitTrapAdjacent = class()

function AceCheckBaitTrapAdjacent:run(ai, entity, args)
   self._entity = entity

   local trap_component = args.trap:add_component('stonehearth:bait_trap')
   local trapping_grounds = trap_component:get_trapping_grounds()

   local trapped_entity = trap_component:get_trapped_entity()
   local trapped_entity_id = nil

   ai:execute('stonehearth:turn_to_face_entity', { entity = args.trap })
   ai:execute('stonehearth:run_effect', { effect = 'fiddle' })

   if trapped_entity and trapped_entity:is_valid() then
      trapped_entity_id = trapped_entity:get_id()
      local job_component = entity:get_component('stonehearth:job')
      local trapper_controller = job_component:get_curr_job_controller()
      if trapper_controller:should_tame(trapped_entity) then
         self:_tame_target(trap_component, trapped_entity)
      else
         self:_gib_target(trapped_entity)

         self:_spawn_loot(trapped_entity, trapping_grounds)

         --If the this entity has the right perk, spawn the loot again!
         local job_component = entity:get_component('stonehearth:job')
         if job_component and job_component:curr_job_has_perk('trapper_efficient_rendering') then
            self:_spawn_loot(trapped_entity, trapping_grounds)
         end

         trapped_entity:set_player_id(entity:get_player_id())  -- Make sure drops are owned by the player.
         radiant.entities.kill_entity(trapped_entity, {source = trapping_grounds})
         trapped_entity = nil
      end
   end

   ai:unprotect_argument(args.trap)
   radiant.entities.kill_entity(args.trap)

   radiant.events.trigger_async(entity, 'stonehearth:clear_trap', {trapped_entity_id = trapped_entity_id})
end

function AceCheckBaitTrapAdjacent:_spawn_loot(target, trapping_grounds)
   local location = radiant.entities.get_world_grid_location(target)
   local json = radiant.entities.get_entity_data(target, 'stonehearth:harvest_beast_loot_table')
   if not json then
      return
   end
   local loot_table = LootTable(json)
   local uris = loot_table:roll_loot()
   radiant.entities.output_items(uris, location, 1, 3, { owner = self._entity }, trapping_grounds, nil, true)
end

return AceCheckBaitTrapAdjacent
