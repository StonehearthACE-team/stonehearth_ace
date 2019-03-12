local MemorializeDeathAction = require 'stonehearth.ai.actions.memorialize_death_action'
local AceMemorializeDeathAction = radiant.class()

-- consider separating all these 'effects' into a compound action
AceMemorializeDeathAction._ace_old_run = MemorializeDeathAction.run
function AceMemorializeDeathAction:run(ai, entity, args)
   self:_ace_old_run(ai, entity, args)
   
   local custom_data = radiant.entities.get_custom_data(entity)

   local tombstone = self.notification_bulletin:get_data().zoom_to_entity
   local name_component = tombstone:add_component('stonehearth:unit_info')
   local custom_name = name_component:get_custom_name()
   if custom_name then
      name_component:set_custom_name(name_component:get_custom_name(), custom_data)
   end

   self.notification_bulletin:add_i18n_data('entity_custom_data', custom_data)
end

return AceMemorializeDeathAction
