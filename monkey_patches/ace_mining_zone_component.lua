local landmark_lib = require 'stonehearth.lib.landmark.landmark_lib'

local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local log = radiant.log.create_logger('mining')

local AceMiningZoneComponent = class()

function AceMiningZoneComponent:set_region(region)
   region:modify(function(cursor)
         cursor:optimize('new mining zone region')
      end)

   -- if the region object already exists, simply copy the region into it
   if self._sv.region then
      self._sv.region:modify(function(cursor)
            cursor:copy_region(region)
         end)
   else
      self._sv.region = region
   end
   self:_trace_region()
   self:_on_region_changed()
   self.__saved_variables:mark_changed()

   -- have the collision shape use the same region
   self._collision_shape_component:set_region(self._sv.region)

   return self
end

-- point is in world space
-- need to override to handle loot quantity/quality properly when doubling loot from strength town bonus
function AceMiningZoneComponent:mine_point(point)
   local loot = {}

   -- When mining a point, need to inspect the specialized regions to see if the point is a part of them.
   -- Need to pull loot from the specific landmark_blocks table which was specified for this specialized region.
   local region = Region3(Cube3(point))
   local region_intersections = radiant.terrain.find_landmark_intersections(region)
   if #region_intersections > 0 then
      local region_index = region_intersections[1]
      local intersection = radiant.terrain.remove_region_from_landmark(region, region_index)
      loot = landmark_lib.get_loot_from_region(intersection, radiant.terrain._landmarks[region_index][2])
   else
      local block_kind = radiant.terrain.get_block_kind_at(point)
      loot = stonehearth.mining:roll_loot(block_kind)
   end

   -- TODO: detect materials of loot items and only apply town bonuses if they apply
   -- If we have the strength town bonus, there's a chance we spawn more loot.
   local town = stonehearth.town:get_town(self._entity:get_player_id())
   if town then
      local strength_bonus = town:get_town_bonus('stonehearth:town_bonus:strength')
      if strength_bonus and strength_bonus:should_double_roll_mining_loot() then
         for uri, detail in pairs(loot) do
            for quality, quantity in pairs(detail) do
               detail[quality] = (detail[quality] or 0) + quantity
            end
         end
      end
   end

   stonehearth.mining:mine_point(point)

   self:_update_destination()

   if self._destination_component:get_region():get():empty() then
      local location = radiant.entities.get_world_grid_location(self._entity)
      local zone_region = self._sv.region:get()
      local unmined_region = self:_get_working_region(zone_region, location)
      if unmined_region:empty() then
         radiant.entities.destroy_entity(self._entity)
      end
   end

   return loot
end

return AceMiningZoneComponent
