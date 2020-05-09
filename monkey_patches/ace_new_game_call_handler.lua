local log = radiant.log.create_logger('world_generation')

local AceNewGameCallHandler = class()

-- ACE: add population-based water filter: unless specified, populations shouldn't choose camp locations in water
function AceNewGameCallHandler:choose_camp_location(session, response)
   _radiant.call('stonehearth:get_service', 'population')
      :done(function(r)
         local populations = r.result:get_data().populations
         local pop_faction_data = populations[_radiant.client.get_player_id()]:get_data()

         local filter_fn
         if pop_faction_data.choose_camp_location_filter_script then
            local script = radiant.mods.load_script(pop_faction_data.choose_camp_location_filter_script)
            if script then
               filter_fn = script.filter_fn
            end
         end

         if not filter_fn then
            filter_fn = function (result, selector)
               if not result.entity:get_component('terrain') then
                  return stonehearth.selection.FILTER_IGNORE
               end
   
               local normal = result.normal:to_int()
               local location = result.brick:to_int()
               if normal.y ~= 1 then
                  return stonehearth.selection.FILTER_IGNORE
               end
               if not radiant.terrain.is_standable(location) then
                  return stonehearth.selection.FILTER_IGNORE
               end

               if not pop_faction_data.choose_camp_location_allow_in_water or pop_faction_data.choose_camp_location_require_in_water then
                  local entities = radiant.terrain.get_entities_at_point(location)
                  local found_water = false
                  for _, entity in pairs(entities) do
                     if entity:get_component('stonehearth:water') then
                        found_water = true
                        break
                     end
                  end

                  if pop_faction_data.choose_camp_location_require_in_water then
                     return found_water
                  else
                     return not found_water
                  end
               else
                  return true
               end
            end
         end

         stonehearth.selection:select_location()
            :use_ghost_entity_cursor('stonehearth:camp_standard_ghost')
            :set_filter_fn(filter_fn)
            :done(function(selector, location, rotation)
               local clip_height = self:_get_starting_clip_height(location)
               stonehearth.subterranean_view:set_clip_height(clip_height)

               _radiant.call_obj('stonehearth.game_creation','create_camp_command', location)
                  :done( function(o)
                        response:resolve({result = true, townName = o.random_town_name })
                     end)
                  :fail(function(result)
                        response:reject(result)
                     end)
                  :always(function ()
                        selector:destroy()
                     end)
               end)
            :fail(function(selector)
                  selector:destroy()
                  response:reject('no location')
               end)
            :go()

      end)
end

return AceNewGameCallHandler
