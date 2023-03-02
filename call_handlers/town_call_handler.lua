local validator = radiant.validator
local TownCallHandler = class()

function TownCallHandler:assign_ownership_proxy(session, response, entity, ownership_type)
   validator.expect_argument_types({'Entity', 'string'}, entity, ownership_type)
   
   local reservation = radiant.entities.create_entity('stonehearth_ace:owner_proxy:bed_owner')
   local owner_proxy = reservation:get_component('stonehearth_ace:owner_proxy')
   owner_proxy:set_type(ownership_type)
   owner_proxy:track_reservation(entity)
end

function TownCallHandler:has_guildmaster_town_bonus(session, response, player_id)
   validator.expect_argument_types({'string'}, player_id)
   local town = stonehearth.town:get_town(player_id)
   local guildmaster = town and town:get_town_bonus('stonehearth:town_bonus:guildmaster')
	response:resolve({ has_guildmaster = guildmaster ~= nil })
end

function TownCallHandler:remove_owner_command(session, response, entity)
   validator.expect_argument_types({'Entity'}, entity)

   local ownable_object_component = entity:get_component('stonehearth:ownable_object')
   if ownable_object_component then
      ownable_object_component:set_owner()
   end
end

function TownCallHandler:craft_and_place_item_type_in_world(session, response, uri, location, rotation, normal)
   validator.expect_argument_types({'string', 'Point3', 'number', 'Point3'}, uri, location, rotation, normal)

   local town = stonehearth.town:get_town(session.player_id)
   if town then
      local placement_info = {
         location = location,
         normal = normal,
         rotation = rotation,
         structure = radiant._root_entity,
         preserve_destination = true,
      }
      town:craft_and_place_item_type(uri, placement_info)

      response:resolve({
         item_uri = uri,
         more_items = true,
      })
   else
      response:reject({error = 'no town for player'})
   end
end

return TownCallHandler
