local Cube3 = _radiant.csg.Cube3
local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Color4 = _radiant.csg.Color4
local validator = radiant.validator
local constants = require 'stonehearth.constants'
local DEFAULT_QUEST_STORAGE_URI = constants.game_master.quests.DEFAULT_QUEST_STORAGE_CONTAINER_URI
local QUEST_STORAGE_ZONE_URI = constants.game_master.quests.QUEST_STORAGE_ZONE_URI

local QuestCallHandler = class()

-- store this outside the choose_quest_storage_zone_location function so it doesn't reset after each zone placement
--local rotation = 0

function QuestCallHandler:get_default_quest_storage_uri(session, response)
   local town = stonehearth.town:get_town(session.player_id)
   assert(town, 'missing town for player ' .. session.player_id .. '!')
   response:resolve({uri = town:get_default_quest_storage_uri()})
end

function QuestCallHandler:choose_quest_storage_zone_location(session, response)
   _radiant.call('stonehearth_ace:get_default_quest_storage_uri')
   :done(function(result)
         self:_choose_quest_storage_zone_location(session, response, result.uri or DEFAULT_QUEST_STORAGE_URI)
      end)
   :fail(function()
         self:_choose_quest_storage_zone_location(session, response, DEFAULT_QUEST_STORAGE_URI)
      end)
end

function QuestCallHandler:_choose_quest_storage_zone_location(session, response, uri)
   --local orig_rotation = rotation
   local data = radiant.entities.get_component_data(QUEST_STORAGE_ZONE_URI, 'stonehearth_ace:quest_storage_zone') or {}
   local size = data.size or {min = 2, max = 20}
   local pattern = data.pattern or {{0, 0, 1}, {0, 0, 0}}
   local border = data.border or 1
   local color = Color4(unpack(data.zone_color or {153, 51, 255, 76}))
   local sample_container = uri

   stonehearth.selection:select_pattern_designation_region(stonehearth.constants.xz_region_reasons.QUEST_STORAGE)
      :set_min_size(size.min or 2)
      :set_max_size(size.max or 20)
      :set_valid_dims(size.valid_x, size.valid_y)
      :set_border(border)
      :set_color(color)
      --:set_rotation(rotation)
      :set_auto_rotate(true)
      :set_rotate_entities(true)
      :set_pattern(pattern, {
         [1] = {
            uri = sample_container,
         }
      })
      :set_cursor('stonehearth_ace:cursors:zone_quest_storage')
      :set_find_support_filter(function(result)
         local entity = result.entity
         local brick = result.brick

         local rcs = entity:get_component('region_collision_shape')
         local region_collision_type = rcs and rcs:get_region_collision_type()
         if region_collision_type == _radiant.om.RegionCollisionShape.NONE then
            return stonehearth.selection.FILTER_IGNORE
         end
   
         if entity:get_id() ~= radiant._root_entity_id then
            return false
         end
   
         return true
      end)
      :done(function(selector, box)
            local size = {
               x = box.max.x - box.min.x,
               y = box.max.z - box.min.z,
            }
            local points = selector:get_grid_entity_locations()
            _radiant.call('stonehearth_ace:create_quest_storage_zone', box.min, size, selector:get_rotation(), points[1])
                     :done(function(r)
                           response:resolve({ quest_storage = r.quest_storage })
                        end)
                     :always(function()
                           selector:destroy()
                        end)
         end)
      :fail(function(selector)
            selector:destroy()
            response:reject('no region')
            --rotation = orig_rotation
         end)
      :go()
end

function QuestCallHandler:create_quest_storage_zone(session, response, location, size, rotation, points)
   validator.expect_argument_types({'Point3', 'table', 'number', 'table'}, location, size, rotation, points)
   location = radiant.util.to_point3(location)
   local entity = radiant.entities.create_entity(QUEST_STORAGE_ZONE_URI, { owner = session.player_id })
   radiant.terrain.place_entity(entity, location)

   self:_add_region_components(entity, size)

   local zone_component = entity:add_component('stonehearth_ace:quest_storage_zone')
   zone_component:apply_settings(Point2(size.x, size.y), rotation, points)

   response:resolve({ quest_storage = entity })
end

function QuestCallHandler:dump_quest_storage_command(session, response, entity)
   validator.expect_argument_types({'Entity'}, entity)
   validator.expect.matching_player_id(session.player_id, entity)

   local quest_storage = entity:get_component('stonehearth_ace:quest_storage')
   if quest_storage then
      quest_storage:set_enabled(false)
      quest_storage:dump_items()
   end
end

function QuestCallHandler:_add_region_components(entity, size)
   local shape = Cube3(Point3.zero, Point3(size.x, 1, size.y))

   entity:add_component('region_collision_shape')
            :set_region_collision_type(_radiant.om.RegionCollisionShape.NONE)
            :set_region(_radiant.sim.alloc_region3())
            :get_region():modify(function(cursor)
                  cursor:add_unique_cube(shape)
               end)

end

return QuestCallHandler
