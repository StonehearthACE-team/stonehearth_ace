--[[
   based on stonehearth.components.terrain_patch_component, but instantly places all the terrain in a region
   minus any intersection with existing terrain

   TODO: allow for specifying a terrain_type instead of specific terrain_tag
      and have it determine the proper tags based on elevation in this biome
]]

local connection_utils = require 'stonehearth_ace.lib.connection.connection_utils'
local terrain_blocks = radiant.resources.load_json('stonehearth:terrain_blocks')
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3

local PlaceTerrainComponent = class()

local DEFAULT_REGION = Region3(Cube3(Point3.zero))
local DEFAULT_TERRAIN_TAG = terrain_blocks.block_types.dirt.tag

local log = radiant.log.create_logger('place_terrain_component')

function PlaceTerrainComponent:activate()
   assert(not self._entity:get('stonehearth:iconic_form'), 'place terrain components are not allowed on iconic forms.')
   
   local json = radiant.entities.get_json(self) or {}
   local terrain_tag = json.terrain_tag and terrain_blocks.block_types[json.terrain_tag].tag or DEFAULT_TERRAIN_TAG
   local region = json.region and connection_utils.import_region(json.region) or DEFAULT_REGION

   self._sv.spec = {
      terrain_tag = terrain_tag,
      region = region
   }
   self.__saved_variables:mark_changed()

   -- Wait until we are actually in the world before starting the replacement.
   self._added_to_world_trace = radiant.events.listen_once(self._entity, 'stonehearth:on_added_to_world', function()
         self:_place_terrain()
         self._added_to_world_trace = nil
      end)
end

function PlaceTerrainComponent:destroy()
   if self._added_to_world_trace then
      self._added_to_world_trace:destroy()
      self._added_to_world_trace = nil
   end
end

function PlaceTerrainComponent:_place_terrain()
   if self._entity:get('stonehearth:ghost_form') then
      return
   end

   local location = radiant.entities.get_world_grid_location(self._entity)
   -- clip region with existing terrain and just get the new stuff
   local region = radiant.terrain.clip_region(radiant.entities.local_to_world(self._sv.spec.region, self._entity))

   local commands_component = self._entity:get('stonehearth:commands')
   commands_component:remove_command('stonehearth:commands:move_item')
   commands_component:remove_command('stonehearth:commands:undeploy_item')

   for cube in region:each_cube() do
      radiant.terrain.add_cube(Cube3(cube.min, cube.max, self._sv.spec.terrain_tag))
   end

   local proxy = radiant.entities.create_entity('stonehearth:object:transient', { debug_text = 'terrain patch effect anchor' })
   radiant.terrain.place_entity_at_exact_location(proxy, location + Point3(0.5, 0.5, 0.5))
   local effect = radiant.effects.run_effect(proxy, 'stonehearth:effects:terrain_patch_spawn')
   effect:set_finished_cb(function()
      radiant.entities.destroy_entity(proxy)
   end)
   
   radiant.entities.destroy_entity(self._entity)
end

return PlaceTerrainComponent
