local SwimmingService = require 'stonehearth.services.server.swimming.swimming_service'
AceSwimmingService = class()

function AceSwimmingService:_set_swimming(entity, swimming)
   if not entity or not entity:is_valid() then
      return
   end
   local id = entity:get_id()

   if swimming ~= self._sv.swimming_state[id] then
      self._sv.swimming_state[id] = swimming

      if swimming then
		 if radiant.entities.get_category(entity) == 'aquatic' then
		 radiant.entities.remove_buff(entity, 'stonehearth_ace:buffs:not_in_water')
		 else
         radiant.entities.add_buff(entity, 'stonehearth:buffs:swimming')
		 end
      elseif radiant.entities.get_category(entity) == 'aquatic' then
		 radiant.entities.add_buff(entity, 'stonehearth_ace:buffs:not_in_water')
	  else
         radiant.entities.remove_buff(entity, 'stonehearth:buffs:swimming')
      end
   end
end

return AceSwimmingService
