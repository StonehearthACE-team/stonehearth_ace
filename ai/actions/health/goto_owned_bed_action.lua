local GotoOwnedBed = radiant.class()

GotoOwnedBed.name = 'go to bed'
GotoOwnedBed.does = 'stonehearth_ace:goto_bed'
GotoOwnedBed.args = {}
GotoOwnedBed.priority = 0.75

function GotoOwnedBed:start_thinking(ai, entity, args)
   local entity_id = entity:get_id()

   local filter_fn = stonehearth.ai:filter_from_key('stonehearth:rest_from_injuries:rest_in_bed', 'owned', function(target)
      local bed_data = radiant.entities.get_entity_data(target, 'stonehearth:bed')
      if bed_data and not bed_data.priority_care and not target:add_component('stonehearth:mount'):is_in_use() then
         local ownable_component = target:get_component('stonehearth:ownable_object')
         local owner = ownable_component and ownable_component:get_owner()
         if owner and owner:get_id() == entity_id then
            return true
         end
      end
      return false
   end)

   ai:set_think_output({
      filter_fn = filter_fn
   })
end

local ai = stonehearth.ai
return ai:create_compound_action(GotoOwnedBed)
         :execute('stonehearth:goto_entity_type', {
            filter_fn = ai.PREV.filter_fn,
            description = 'rest in own bed'
         })
         :set_think_output({destination_entity = ai.PREV.destination_entity})
