local log = radiant.log.create_logger('swimming')

local SwimmingService = require 'stonehearth.services.server.swimming.swimming_service'
AceSwimmingService = class()

-- override this to only set swimming to false if the entity had a trace
function AceSwimmingService:_destroy_entity_trace(id)
   local trace = self._location_traces[id]
   if trace then
      trace:destroy()
      self._location_traces[id] = nil

      self:_set_swimming(radiant.entities.get_entity(id), false)
   end

   self._cached_mob_shapes[id] = nil
end

function AceSwimmingService:_set_swimming(entity, swimming)
   if not entity or not entity:is_valid() then
      return
   end
   local id = entity:get_id()

   local prev_swimming = self._sv.swimming_state[id]
   if swimming ~= prev_swimming then
      self._sv.swimming_state[id] = swimming

      if swimming then
         if radiant.entities.get_category(entity) == 'aquatic' then
            radiant.entities.remove_buff(entity, 'stonehearth_ace:buffs:not_in_water')
            radiant.entities.add_buff(entity, 'stonehearth_ace:buffs:in_water')
         else
            radiant.entities.add_buff(entity, 'stonehearth:buffs:swimming')            
            
            if radiant.entities.has_buff(entity, 'stonehearth_ace:buffs:weather:chilly') or radiant.entities.has_buff(entity, 'stonehearth_ace:buffs:weather:cold') or radiant.entities.has_buff(entity, 'stonehearth_ace:buffs:weather:freezing')then 
                radiant.entities.add_buff(entity, 'stonehearth_ace:buffs:weather:freezing:water')
            else
                radiant.entities.add_buff(entity, 'stonehearth_ace:buffs:weather:refreshing:water')
            end    
         end            
      elseif radiant.entities.get_category(entity) == 'aquatic' then
         radiant.entities.add_buff(entity, 'stonehearth_ace:buffs:not_in_water')
         radiant.entities.remove_buff(entity, 'stonehearth_ace:buffs:in_water')
      elseif prev_swimming then  -- don't do all this stuff if we were never in the water to begin with
         radiant.entities.remove_buff(entity, 'stonehearth:buffs:swimming')

         radiant.entities.add_buff(entity, 'stonehearth_ace:buffs:weather:soaked', {stacks = 10})
         
         if radiant.entities.has_buff(entity, 'stonehearth_ace:buffs:weather:freezing:water') then
            radiant.entities.remove_buff(entity, 'stonehearth_ace:buffs:weather:freezing:water')
            radiant.entities.add_buff(entity, 'stonehearth_ace:buffs:weather:freezing')
         else
            radiant.entities.remove_buff(entity, 'stonehearth_ace:buffs:weather:refreshing:water')
            radiant.entities.add_buff(entity, 'stonehearth_ace:buffs:weather:refreshed')            
         end     
      end
   end
end

-- if we add more water pathing stuff, enable this
-- check for terrain immediately below the entity as well; if there isn't terrain there and there is water, they should be swimming
-- function AceSwimmingService:_is_swimming(entity, location)
--    if not entity or not entity:is_valid() then
--       return false
--    end

--    if not location then
--       location = radiant.entities.get_world_grid_location(entity)
--    end

--    if not location then
--       return false
--    end

--    local id = entity:get_id()
--    local mob_shape = self._cached_mob_shapes[id]
--    local cube = mob_shape:translated(location):extruded('y', 1, 0)

--    local intersected_entities = radiant.terrain.get_entities_in_cube(cube)
--    local swimming = false
--    local no_terrain_swimming
--    local found_water = false

--    for id, entity in pairs(intersected_entities) do
--       local water_component = entity:get_component('stonehearth:water')
--       if water_component then
--          found_water = true
--          local entity_height = mob_shape.max.y
--          local water_level = water_component:get_water_level()
--          local swim_level = location.y + entity_height * 0.5
--          if water_level > swim_level then
--             swimming = true
--             if no_terrain_swimming == false then
--                break
--             end
--          elseif no_terrain_swimming == nil then
--             no_terrain_swimming = true
--          end
--       end
--       if entity:get_component('terrain') then
--          no_terrain_swimming = false
--          if found_water then
--             break
--          end
--       end
--    end

--    return swimming or no_terrain_swimming
-- end

return AceSwimmingService
