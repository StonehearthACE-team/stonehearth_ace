local GotoPriorityCareBed = radiant.class()

GotoPriorityCareBed.name = 'go to bed'
GotoPriorityCareBed.does = 'stonehearth_ace:goto_bed'
GotoPriorityCareBed.args = {}
GotoPriorityCareBed.priority = 1.0

local function make_is_available_bed_filter()
   return stonehearth.ai:filter_from_key('stonehearth:rest_from_injuries:rest_in_bed', 'priority_care', function(target)
         local bed_data = radiant.entities.get_entity_data(target, 'stonehearth:bed')
         if bed_data and bed_data.priority_care and not target:add_component('stonehearth:mount'):is_in_use() then
            return true
         end
         return false
      end)
end

local ai = stonehearth.ai
return ai:create_compound_action(GotoPriorityCareBed)
         :execute('stonehearth:goto_entity_type', {
            filter_fn = make_is_available_bed_filter(),
            description = 'rest in priority care bed'
         })
         :set_think_output({destination_entity = ai.PREV.destination_entity})
