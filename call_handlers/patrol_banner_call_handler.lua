local validator = radiant.validator

local PATROL_BANNER = 'stonehearth_ace:patrol_banner'
local PATROL_BANNER_ENTITY = 'stonehearth_ace:gizmos:patrol_banner'

local PatrolBannerCallHandler = class()

function PatrolBannerCallHandler:get_patrol_banners_command(session, response)
   local banners = stonehearth.town_patrol:get_patrol_banners(session.player_id)
   response:resolve({patrol_banners = banners})
end

function PatrolBannerCallHandler:remove_patrol_banners_by_party_command(session, response, party_id)
   validator.expect_argument_types({'string'}, party_id)

   local banners = stonehearth.town_patrol:get_patrol_banners(session.player_id)
   local party_banners = banners:get_banners_by_party(party_id)
   for _, banner in pairs(party_banners) do
      radiant.entities.destroy_entity(banner:get_object())
   end

   response:resolve({})
end

function PatrolBannerCallHandler:update_ordered_patrol_banners_command(session, response, party_id)
   validator.expect_argument_types({validator.optional('string')}, party_id)

   self:update_ordered_patrol_banners(session.player_id, party_id)
   response:resolve({})
end

function PatrolBannerCallHandler:update_ordered_patrol_banners(player_id, party_id)
   local banners = stonehearth.town_patrol:get_patrol_banners(player_id)
   banners:update_ordered_party_banners(party_id)
end

--[[
   this is used to swap the order of two banners: the one passed in and the "next" one;
   if the party has fewer than three banners, no order swapping will be performed because it doesn't make sense
]]
function PatrolBannerCallHandler:swap_patrol_banners_order_command(session, response, banner)
   validator.expect_argument_types({'Entity'}, banner)

   local pb_comp = banner:get_component(PATROL_BANNER)
   if not pb_comp then
      response:reject('not a valid patrol banner')
      return
   end

   local next_banner = pb_comp:get_next_banner()
   if not next_banner then
      response:reject('has no next banner')
      return
   end
   local next_comp = next_banner:get_component(PATROL_BANNER)

   local prev_banner = pb_comp:get_prev_banner()
   if not prev_banner or prev_banner == next_banner then
      response:reject('has no previous banner, or only 2 banners exist')
      return
   end
   local prev_comp = prev_banner:get_component(PATROL_BANNER)

   local next_banner_2 = next_comp:get_next_banner()
   if not next_banner_2 then
      response:reject('has no next-next banner')
      return
   end
   local next_comp_2 = next_banner_2:get_component(PATROL_BANNER)

   prev_comp:set_next_banner(next_banner)
   pb_comp:set_prev_banner(next_banner)
   pb_comp:set_next_banner(next_banner_2)
   next_comp:set_prev_banner(prev_banner)
   next_comp:set_next_banner(banner)
   next_comp_2:set_prev_banner(banner)

   self:update_ordered_patrol_banners(session.player_id, pb_comp:get_party())

   response:resolve({})
end

function PatrolBannerCallHandler:move_patrol_banner_command(session, response, banner)
   validator.expect_argument_types({'Entity'}, banner)

   local pb_comp = banner:get_component(PATROL_BANNER)
   if not pb_comp then
      response:reject('not a valid patrol banner')
   end

   _radiant.call('stonehearth:teleport_entity', banner)
      :done(function(result)
         _radiant.call('stonehearth_ace:update_ordered_patrol_banners_command')
         :done(function(r)
            response:resolve(result)
         end)
      end)
      :fail(function(reason)
         response:reject(reason)
      end)
end

--[[
   first do an item placement location selection
   if successful, create a new banner at the specified spot and assign its party
   finally, set next banners accordingly
]]
function PatrolBannerCallHandler:add_patrol_banner_command(session, response, party_id, prev_banner, next_banner)
   validator.expect_argument_types({'string', validator.optional('Entity'), validator.optional('Entity')}, party_id, prev_banner, next_banner)

   _radiant.call('stonehearth_ace:create_patrol_banner', party_id)
   :done(function(result)
      local new_banner = result.new_banner

      stonehearth.selection:deactivate_all_tools()
      stonehearth.selection:select_location()
         :set_cursor_entity(new_banner)
         :done(function(selector, location, rotation)
            _radiant.call('stonehearth_ace:place_patrol_banner', new_banner, location, prev_banner, next_banner)
               :done(function()
                  response:resolve({new_banner = new_banner})
               end)
               :fail(function()
                  _radiant.call('stonehearth_ace:destroy_patrol_banner', new_banner)
                  response:reject('failed to place')
               end)
            end)
         :fail(function(selector)
            _radiant.call('stonehearth_ace:destroy_patrol_banner', new_banner)   
            selector:destroy()
            response:reject('no location')
         end)
      :always(function()
         end)
      :go()
   end)
end

function PatrolBannerCallHandler:create_patrol_banner(session, response, party_id)
   validator.expect_argument_types({'string'}, party_id)
   
   local new_banner = radiant.entities.create_entity(PATROL_BANNER_ENTITY, { owner = session.player_id })
   new_banner:add_component(PATROL_BANNER):set_party(party_id)
   
   response:resolve({new_banner = new_banner})
end

function PatrolBannerCallHandler:place_patrol_banner(session, response, banner, location, prev_banner, next_banner)
   validator.expect_argument_types({'Entity', 'Point3', validator.optional('Entity'), validator.optional('Entity')},
         banner, location, prev_banner, next_banner)
   
   location = radiant.util.to_point3(location)
   radiant.terrain.place_entity(banner, location)

   local pb_comp = banner:get_component(PATROL_BANNER)
   local prev_pb_comp = prev_banner and prev_banner:get_component(PATROL_BANNER)
   local next_pb_comp = next_banner and next_banner:get_component(PATROL_BANNER)
   
   -- this should handle adding a single initial banner, adding a second when there's only one (specified as either previous or next), or adding between two specified
   if not prev_pb_comp then
      if next_pb_comp then
         prev_banner = next_pb_comp:get_prev_banner()
      end
      if prev_banner then
         prev_pb_comp = prev_banner:get_component(PATROL_BANNER)
      else
         prev_banner = next_banner
         prev_pb_comp = next_pb_comp
      end
   elseif not next_pb_comp then
      next_banner = prev_pb_comp:get_next_banner()
      if next_banner then
         next_pb_comp = next_banner:get_component(PATROL_BANNER)
      else
         next_banner = prev_banner
         next_pb_comp = prev_pb_comp
      end
   end

   if prev_pb_comp then
      prev_pb_comp:set_next_banner(banner)
   end
   if next_pb_comp then
      next_pb_comp:set_prev_banner(banner)
   end

   pb_comp:set_next_banner(next_banner)
   pb_comp:set_prev_banner(prev_banner)
   
   response:resolve({})
end

function PatrolBannerCallHandler:destroy_patrol_banner(session, response, banner)
   validator.expect_argument_types({'Entity'}, banner)
   
   radiant.entities.destroy_entity(banner)
   
   return true
end

function PatrolBannerCallHandler:remove_patrol_banner_command(session, response, banner_to_remove)
   validator.expect_argument_types({'Entity'}, banner_to_remove)

   local pb_comp = banner_to_remove:get_component(PATROL_BANNER)
   if not pb_comp then
      response:reject('not a patrol banner')
      return
   end

   radiant.entities.destroy_entity(banner_to_remove)

   response:resolve({})
end

return PatrolBannerCallHandler