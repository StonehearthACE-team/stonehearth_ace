local EntityFormsLib = require 'stonehearth.lib.entity_forms.entity_forms_lib'
local AceEntityFormsLib = class()

local Entity = _radiant.om.Entity

function AceEntityFormsLib.initialize_ghost_form_components(ghost, root_uri, quality, json, placement_info)
   local ghost_form = ghost:add_component('stonehearth:ghost_form')
   if placement_info then
      ghost_form:set_placement_info(placement_info)
   end
   if quality then
      ghost_form:set_requested_quality(quality)
   end

   local loaded_json = json or radiant.resources.load_json(root_uri)

   local components_json = loaded_json and loaded_json.components
   if not components_json then
      return
   end

   -- if the ghost form explicitly specifies any shapes, don't override them
   if ghost:get_component('destination') or ghost:get_component('region_collision_shape') then
      return
   end

   -- We DO NOT want to copy the region_origin, align_to_grid and allow_vertical_adjacent flags from the root form.
   local mob_json = components_json.mob
   if mob_json then
      local mob = ghost:add_component('mob')
      --mob:load_from_json(mob_json)

      -- make the ghost discoverable by the navgrid/BFS when there is no destination
      -- or region_collision_shape
      mob:set_mob_collision_type(_radiant.om.Mob.TINY)

      if placement_info then
         mob:set_ignore_gravity(placement_info.ignore_gravity == true)
      end
   end

   -- Copy the root form's destination region which includes the adjacent region or
   -- a flag to auto_update the adjacent.
   local destination_json = components_json.destination
   if destination_json then
      ghost:add_component('destination')
               :load_from_json(destination_json)
   end

   -- Make the ghost shape the same as the root form's shape, except being non-solid.
   -- When we query the world for entities, the ghost shape should register with the
   -- same boundaries as the root form by default.
   local region_collision_shape_json = components_json.region_collision_shape
   if region_collision_shape_json then
      ghost:add_component('region_collision_shape')
               :load_from_json(region_collision_shape_json)
               :set_region_collision_type(_radiant.om.RegionCollisionShape.NONE)
   end
end

return AceEntityFormsLib
