local Entity = _radiant.om.Entity
local validator = radiant.validator

local DebugCallHandler = class()

function DebugCallHandler:instamine_entity_command(session, response, entity)
   validator.expect_argument_types({Entity}, entity)
   
   local mining_zone = entity:get_component('stonehearth:mining_zone')
   if mining_zone then
      stonehearth.mining:insta_mine_zone_command(session, response, mining_zone)
      return
   end

   local building_component = entity:get_component('stonehearth:build2:building')
   if building_component then
      building_component:instamine()
      return
   end
end

return DebugCallHandler
