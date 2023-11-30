local Entity = _radiant.om.Entity
local validator = radiant.validator

local DebugCallHandler = class()

local log = radiant.log.create_logger('debug_call_handler')

function DebugCallHandler:instamine_current_building_command(session, response)
   local current_building = stonehearth.building:get_current_building()
   if current_building then
      log:debug('instamine_current_building_command: %s', current_building)
      _radiant.call('stonehearth_ace:instamine_entity_command', current_building)
         :done(function(r)
            response:resolve(r)
         end)
         :fail(function(e)
            response:reject(e)
         end)
   else
      response:reject('no current building')
   end
end

function DebugCallHandler:instamine_entity_command(session, response, entity)
   log:debug('instamine_entity_command: %s', tostring(entity))
   -- why does this throw an error? it *is* an entity
   --validator.expect_argument_types({'Entity'}, entity)

   local mining_zone = entity:get_component('stonehearth:mining_zone')
   if mining_zone then
      stonehearth.mining:insta_mine_zone_command(session, response, mining_zone)
      response:resolve({})
      return
   end

   local building_component = entity:get_component('stonehearth:build2:building')
   if building_component then
      building_component:instamine()
      response:resolve({})
      return
   end

   response:reject('not a mining zone or building')
end

return DebugCallHandler
