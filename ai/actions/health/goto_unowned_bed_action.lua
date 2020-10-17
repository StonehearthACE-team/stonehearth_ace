local GotoUnownedBed = radiant.class()

GotoUnownedBed.name = 'go to bed'
GotoUnownedBed.does = 'stonehearth_ace:goto_bed'
GotoUnownedBed.args = {}
GotoUnownedBed.priority = 0.5

local function make_is_available_bed_filter()
   return stonehearth.ai:filter_from_key('stonehearth:rest_from_injuries:rest_in_bed', 'none', function(target)
         local bed_data = radiant.entities.get_entity_data(target, 'stonehearth:bed')
         if bed_data and not bed_data.priority_care and not target:add_component('stonehearth:mount'):is_in_use() then
            local ownable_component = target:get_component('stonehearth:ownable_object')
            local owner = ownable_component and ownable_component:get_owner()
            if not owner or not owner:is_valid() then
               return true
            end
         end
         return false
      end)
end

local ai = stonehearth.ai
return ai:create_compound_action(GotoUnownedBed)
         :execute('stonehearth:goto_entity_type', {
            filter_fn = make_is_available_bed_filter(),
            description = 'rest in unowned bed'
         })
         :set_think_output({destination_entity = ai.PREV.destination_entity})
