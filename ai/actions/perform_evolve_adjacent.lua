local Entity = _radiant.om.Entity
local PerformEvolveItemAdjacent = radiant.class()

PerformEvolveItemAdjacent.name = 'perform evolve adj'
PerformEvolveItemAdjacent.does = 'stonehearth_ace:perform_evolve_adjacent'
PerformEvolveItemAdjacent.args = {
   item = Entity,      -- the entity to evolve
   owner_player_id = {
      type = 'string',
      default = stonehearth.ai.NIL,
   },
}
PerformEvolveItemAdjacent.priority = 0

function PerformEvolveItemAdjacent:start(ai, entity, args)
   -- TODO: check to make sure we'll be next to the entity
   ai:set_status_text_key('stonehearth_ace:ai.actions.status_text.perform_evolve', { target = args.item })
end

function PerformEvolveItemAdjacent:run(ai, entity, args)
   local item = args.item
   local item_id = item:get_id()
   local evolve = item:get_component('stonehearth:evolve')
   local data = radiant.entities.get_entity_data(item, 'stonehearth:evolve_data')

   if evolve then
      radiant.entities.turn_to_face(entity, item)
      ai:unprotect_argument(item)

      local effect = evolve:perform_evolve()
      if effect then
         repeat
            ai:execute('stonehearth:run_effect', { effect = effect})
         until not item:is_valid()
      end
      if data and data.worker_finished_effect then
         ai:execute('stonehearth:run_effect', { effect = data.worker_finished_effect})
      end
   end
end

return PerformEvolveItemAdjacent
