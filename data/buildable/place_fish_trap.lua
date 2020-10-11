local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3

local water_lib = require 'stonehearth_ace.lib.water.water_lib'
local log = radiant.log.create_logger('place_fish_trap')

local place_fish_trap = {}

function place_fish_trap.placement_filter_fn(selector, fish_trap, terrain_entity, location, normal, terrain_kind)
   -- don't allow placing in water
   local entities = radiant.terrain.get_entities_at_point(location)
   for _, entity in pairs(entities) do
      if entity:get_component('stonehearth:water') then
         return false
      end
   end

   local water, origin, rotation = water_lib.get_water_below_cliff(location, selector:get_rotation(), true)
   fish_trap:add_component('stonehearth_ace:fish_trap'):set_water_entity(water, origin)
   if rotation then
      selector:set_rotation(rotation)
   end
   return water ~= nil
end

function place_fish_trap.designation_filter_fn(selector, fish_trap, terrain_entity, location, normal, designation_data)
   -- don't allow placement on designation zones
   if designation_data then
      return false
   end

   return true
end

return place_fish_trap