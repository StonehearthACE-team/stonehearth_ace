local Entity = _radiant.om.Entity
local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'
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

function PerformEvolveItemAdjacent:stop(ai, entity, args)
   local evolve = args.item and args.item:is_valid() and args.item:get_component('stonehearth:evolve')
   if evolve then
      evolve:_destroy_effect()
   end
end

function PerformEvolveItemAdjacent:run(ai, entity, args)
   local item = args.item
   local item_id = item:get_id()
   local evolve = item:get_component('stonehearth:evolve')
   local data = radiant.entities.get_entity_data(item, 'stonehearth:evolve_data')

   if evolve then
      radiant.entities.turn_to_face(entity, item)
      ai:unprotect_argument(item)

      local effect = data.evolving_worker_effect
      local times = data.evolving_worker_effect_times
      local duration = data.evolving_effect_duration
      local ingredient = data.evolve_ingredient_uri or data.evolve_ingredient_material
      local ing_item
      
      if ingredient then
         ing_item = radiant.entities.get_carrying(entity)
         ai:execute('stonehearth:drop_carrying_now')
      end

      local evolved_form
      if effect then
         evolve:perform_evolve()
         if duration then
            ai:execute('stonehearth:run_effect_timed', { effect = effect, duration = duration})
         else
            for i = 1, times or 1 do
               ai:execute('stonehearth:run_effect', { effect = effect})
            end
         end
         evolved_form = evolve:evolve()
      else
         evolved_form = evolve:perform_evolve(true)
      end

      if ing_item and ing_item:is_valid() then
         -- apply item quality here if relevant, rather than in the evolve component
         -- because it would be a mess in there passing it around or having to store it
         if data.apply_ingredient_quality and evolved_form then
            item_quality_lib.copy_quality(ing_item, evolved_form)
         end

         ai:unprotect_argument(ing_item)
         radiant.entities.destroy_entity(ing_item)
      end

      if data and data.worker_finished_effect then
         ai:execute('stonehearth:run_effect', { effect = data.worker_finished_effect})
      end
   end
end

return PerformEvolveItemAdjacent
