local Entity = _radiant.om.Entity
local BonfiresCheck = class()

local log = radiant.log.create_logger('bonfires_check')

function BonfiresCheck:start(ctx, info)
   local bonfire_entities = { 
      'bonfire_1.entities.bonfire.bonfire', 
      'bonfire_2.entities.bonfire.bonfire', 
      'bonfire_3.entities.bonfire.bonfire' 
   }

   for _, entity in ipairs(bonfire_entities) do
      local bonfire = ctx:get(entity)
      local firepit_component = bonfire:get_component('stonehearth:firepit')
      if not radiant.util.is_a(bonfire, Entity) and bonfire:is_valid() and firepit_component and firepit_component:is_lit() then
         return false
      end
   end
   
   return true
end

return BonfiresCheck
