local build_util = require 'stonehearth.lib.build_util'
local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'

local log = radiant.log.create_logger('build_editor')

local AceItemPlacer = class()

--AceItemPlacer._old_go = ItemPlacer.go
function AceItemPlacer:go(session, response, item_to_place, quality, transactional)
   assert(item_to_place)

   self.response = response
   self.transactional = transactional and true or false
   self.specific_item_to_place = nil
   self.item_uri_to_place = nil
   self.quality = nil
   self.forms_to_ignore = {}
   self.placement_structure = nil
   self.placement_structure_normal = nil
   self.location_selector = stonehearth.selection:select_location()
   self.region_shape = nil

   if type(item_to_place) == 'string' then
      -- used for place item type
      self.item_uri_to_place = item_to_place
      self.quality = quality
   else
      -- used for moving a specific item around
      self.specific_item_to_place = item_to_place
      local root_form, iconic_form = entity_forms_lib.get_forms(self.specific_item_to_place)
      self.item_uri_to_place = root_form:get_uri()
      self.forms_to_ignore[root_form:get_id()] = true
      self.forms_to_ignore[iconic_form:get_id()] = true
      if item_to_place == root_form then
         -- use the facing of the existing entity
         local starting_rotation = radiant.math.quantize(radiant.entities.get_facing(root_form), 90)
         self.location_selector:set_rotation(starting_rotation)
      end
   end

   self.ghost_entity = entity_forms_lib.create_ghost_entity(self.item_uri_to_place, quality)
   self.forms_to_ignore[self.ghost_entity:get_id()] = true

   self.placement_test_entity = radiant.entities.create_entity(self.item_uri_to_place)
   assert(self.placement_test_entity, 'could not determine placement test entity')

   self.entity_forms = entity_forms_lib.get_root_entity(self.placement_test_entity)
                                       :get_component('stonehearth:entity_forms')

   -- don't allow rotation if we're placing stuff on the wall
   local rotation_disabled = self.entity_forms:is_placeable_on_wall() and not self.entity_forms:is_placeable_on_ground()
   local cursor_uri = self.ghost_entity and self.ghost_entity:get_uri() or self.placement_test_entity:get_uri()

   local rcs = self.placement_test_entity:get_component('region_collision_shape')
   if rcs then
      self._region_shape_trace = rcs
            :trace_region('item placer placement entity', _radiant.dm.TraceCategories.ASYNC_TRACE)
            :on_changed(function()
                  local region = rcs:get_region()
                  if region then
                     self.region_shape = region:get()
                  end
               end)
            :push_object_state()
   end

   -- ACE (Paul): for advanced placement options, it just makes sense to initialize extra settings *after* all this other stuff is loaded
   -- so we don't have to duplicate uri parsing or something; also allow for that initialization to cancel the selector early
   if not self:_perform_additional_initialization() then
      self:_fail_fn(self.location_selector)
      self:_always_fn()
      return
   end

   self.location_selector
      :use_ghost_entity_cursor(cursor_uri)
      :set_rotation_disabled(rotation_disabled)
      :create_footprint()
      :set_filter_fn(function (result, selector)
            return self:_location_filter(result, selector)
         end)
      :progress(function(selector, location, rotation)
            self:_progress_fn(selector, location, rotation)
         end)
      :done(function(selector, location, rotation)
            self:_done_fn(selector, location, rotation)
         end)
      :fail(function(selector)
            self:_fail_fn(selector)
         end)
      :always(function()
            self:_always_fn()
         end)
      :go()

   stonehearth.selection:register_tool(self, true)

   -- Report that the item_placer is setup, this is for the auto tests.
   radiant.events.trigger_async(radiant, 'radiant:item_placer:go')

   return self
end

function AceItemPlacer:_perform_additional_initialization()
   local advanced_placement = radiant.entities.get_entity_data(self.entity_forms._entity, 'stonehearth_ace:advanced_placement')
   if advanced_placement then
      self._requires_support = advanced_placement.requires_support ~= false
      self._required_components = advanced_placement.required_components or {}
   else
      self._requires_support = true
      self._required_components = {}
   end

   return true
end

function AceItemPlacer:_location_filter(result, selector)
   local entity = result.entity

   if not entity then
      return false
   end

   -- if the entity is any of the forms of the thing we want to place, ignore it
   if self.forms_to_ignore[entity:get_id()] then
      return stonehearth.selection.FILTER_IGNORE
   end

   local normal = result.normal:to_int()
   local location = result.brick:to_int()

   if not self:_is_placeable_orientation(self.entity_forms, normal) then
      return false
   end

   local hanging = normal.y == 0
   if hanging then
      -- when hanging, the surface normal determines orientation
      selector:set_rotation(build_util.normal_to_rotation(normal))
   end

   self.placement_structure = nil
   self.placement_structure_normal = nil

   local entities = radiant.terrain.get_entities_at_point(location - normal)

   -- look for blueprints that could support the structure
   for _, e in pairs(entities) do
      local structure = e:get_component('stonehearth:construction_progress')
      if structure and not structure:get_finished() then
         if self.specific_item_to_place and not self.specific_item_to_place:get_component('stonehearth:iconic_form') then
            -- Right now, lets say that you cannot move a _specific_ (placed) item onto a
            -- in-design structure.
            return false
         end

         local building = build_util.get_building_for(e)
         if building:get_component('stonehearth:building'):is_started() and not building:get_component('stonehearth:construction_progress'):get_finished() then
            -- Cannot (yet) place on buildings that are in the middle of building.
            return false
         end

         self.placement_structure = build_util.get_blueprint_for(e)
         self.placement_structure_normal = normal
         break
      end
   end

   -- If not placed on building, then see if placed on an object that is solid
   if not self.placement_structure then
      for _, e in pairs(entities) do
         if radiant.entities.is_solid_entity(e) and e ~= self.specific_item_to_place then
            local bp = build_util.get_blueprint_for(e)
            if bp then
               entity = bp
            end

            self.placement_structure = e
            self.placement_structure_normal = normal
            break
         end
      end
   end

   if not self.placement_structure then
      local rcs = entity:get_component('region_collision_shape')
      if rcs and rcs:get_region_collision_type() == _radiant.om.RegionCollisionShape.NONE then
         return stonehearth.selection.FILTER_IGNORE
      end
   end

   local rotation = selector:get_rotation()
   radiant.entities.turn_to(self.placement_test_entity, rotation)

   -- if the space occupied by the cursor is blocked, we can't place the item there
   -- TODO: prohibit placement when placing over other ghost entities'f
   -- root form's solid collision region
   local blocking_entities = radiant.terrain.get_blocking_entities(self.placement_test_entity, location)
   for _, blocking_entity in pairs(blocking_entities) do
      local ignore = self.forms_to_ignore[blocking_entity:get_id()]
      ignore = ignore or blocking_entity:get('stonehearth:build2:fixture_widget')
      if not ignore then
         return false
      end
   end
   
   if self.region_shape then
      local region_w = radiant.entities.local_to_world(self.region_shape, self.placement_test_entity):translated(location)
      local designations = radiant.terrain.get_entities_in_region(region_w, function(e)
            local designation = radiant.entities.get_entity_data(e, 'stonehearth:designation')
            return designation and not designation.allow_placed_items
         end)
      if not radiant.empty(designations) then
         return false
      end
   else
      local designation = radiant.entities.get_entity_data(entity, 'stonehearth:designation')
      if designation and not designation.allow_placed_items then
         return false
      end
   end

   if self.region_shape then
      local region_w = radiant.entities.local_to_world(self.region_shape, selector:get_cursor_entity())
      local envelopes = radiant.terrain.get_entities_in_region(region_w, function(e)
            return e:get_uri() == 'stonehearth:build2:entities:envelope'
         end)
      if not radiant.empty(envelopes) then
         return false
      end
   end

   -- ACE other conditions
   local return_val = self:_compute_additional_required_placement_conditions(result, selector)
   if return_val ~= true then
      return return_val
   end

   if self.placement_structure then
      -- we're unblocked and found a structure to attach to
      return true
   end

   -- ACE change to conditional
   if not self._requires_support or radiant.terrain.is_supported(self.placement_test_entity, location) then
      -- we're unblocked and supported so we're good!
      return true
   end

   -- ACE optional conditions
   local return_val = self:_compute_additional_optional_placement_conditions(result, selector)

   return return_val or stonehearth.selection.FILTER_IGNORE
end

function AceItemPlacer:_compute_additional_required_placement_conditions(result, selector)
   if next(self._required_components) then
      for component_name, check_script in pairs(self._required_components) do
         local component = result.entity:get_component(component_name)
         if component then
            if check_script and check_script ~= '' then
               local script = radiant.mods.require(check_script)
               if script and script._item_placer_can_place then
                  if script._item_placer_can_place(self.item_uri_to_place, self:_get_entity_table(selector:get_cursor_entity()), self:_get_entity_table(result.entity)) then
                     return true
                  end
               end
            else
               return true
            end
         end
      end

      return false
   end

   return true
end

function AceItemPlacer:_get_entity_table(entity)
   return {
      entity = entity,
      location = radiant.entities.get_world_grid_location(entity),
      facing = radiant.entities.get_facing(entity)
   }
end

function AceItemPlacer:_compute_additional_optional_placement_conditions(result, selector)

end

return AceItemPlacer
