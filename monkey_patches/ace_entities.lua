local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3

local constants = require 'stonehearth.constants'
local entity_forms = require 'stonehearth.lib.entity_forms.entity_forms_lib'
local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'
local item_io_lib = require 'stonehearth_ace.lib.item_io.item_io_lib'
local healing_lib = require 'stonehearth_ace.ai.lib.healing_lib'
local WeightedSet = require 'stonehearth.lib.algorithms.weighted_set'
local rng = _radiant.math.get_default_rng()

local log = radiant.log.create_logger('entities')

local ace_entities = {}

-- consume one "stack" of an entity.  if the entity has an item
-- component and the stacks of that item are > 0, it simply decrements
-- the stack count.  otherwise, it conumes the whole item (i.e. we
-- **KILL** it!) <-- only change here is to kill instead of destroy
-- @param - item to consume
-- @param - number of stacks to consume, if nil, default to 1
-- @returns whether or not the item was consumed
function ace_entities.consume_stack(item, num_stacks)
   local stacks_component = item:get_component('stonehearth:stacks')
   local success = false
   local stacks = 0

   if num_stacks == nil then
      num_stacks = 1
   end

   if stacks_component then
      stacks = stacks_component:get_stacks()
      if stacks > 0 then
         stacks = math.max(0, stacks - num_stacks)
         stacks_component:set_stacks(stacks)
         success = true
      end
   end

   if stacks == 0 then
      -- we don't know who's consuming it, but assume it's the same player id as the item itself
      -- (generally this sort of interaction is limited to items the player owns)
      -- this will avoid consideration by the town of queuing up requests to craft this item (e.g., food)
      radiant.entities.kill_entity(item, { source_id = radiant.entities.get_player_id(item) })
   end

   return success
end

function ace_entities.get_effective_health_percentage(entity)
   local effective_max_health_percent = healing_lib.get_effective_max_health_percent(entity)
   if effective_max_health_percent < 1 then
      local expendable_resource_component = entity:get_component('stonehearth:expendable_resources')
      if expendable_resource_component then
         local cur_health = expendable_resource_component:get_value('health')
         local max_health = expendable_resource_component:get_max_value('health')
         return cur_health / (effective_max_health_percent * max_health)
      end
   end

   return radiant.entities.get_health_percentage(entity)
end

-- added an extra parameter to these to include the source of the change
-- so if a kill observer kills them, it can include the killer in the event data
-- Returns true if the health could be modified by the specified amount
function ace_entities.modify_health(entity, health_change, source)
   if health_change > 0 then
      -- We can only modify the health of an entity whose guts are now fully restored.
      assert((radiant.entities.get_resource_percentage(entity, 'guts') or 1) >= 1)
   else
      -- cancel any reduction if the entity is invulnerable
      if radiant.entities.has_property(entity, 'invulnerable') then
         return
      end
   end
   local old_value = radiant.entities.get_health(entity)

   local expendable_resource_component = entity:get_component('stonehearth:expendable_resources')
   if old_value and expendable_resource_component then
      if health_change > 0 then
         -- if trying to increase health, make sure that modification isn't limited by other effects/buffs
         -- we do this check here instead of in modify_resource so we can still force a change there if we want
         local effective_max_health_percent = healing_lib.get_effective_max_health_percent(entity)
         if effective_max_health_percent < 1 then
            local cur_health = expendable_resource_component:get_value('health')
            local max_health = expendable_resource_component:get_max_value('health')
            health_change = math.min(health_change, effective_max_health_percent * max_health - cur_health)

            if health_change <= 0 then
               return false
            end
         end
      elseif health_change < 0 then
         -- if health would drop to 0 and entity is unkillable, make it only drop to 1
         if radiant.entities.has_property(entity, 'unkillable') and old_value + health_change < 1 then
            health_change = 1 - old_value
         end
      end

      local new_value = radiant.entities.modify_resource(entity, 'health', health_change, source)
      return new_value and old_value ~= new_value
   end

   return false
end

-- Returns the new value
function ace_entities.modify_resource(entity, resource_name, change, source)
   local expendable_resource_component = entity:get_component('stonehearth:expendable_resources')
   if not expendable_resource_component then
      return false
   end
   return expendable_resource_component:modify_value(resource_name, change, source)
end

ace_entities._ace_old_create_entity = radiant.entities.create_entity
function ace_entities.create_entity(ref, options)
   local entity = ace_entities._ace_old_create_entity(ref, options)
   if entity then
      local create_entity_data = radiant.entities.get_entity_data(entity, 'stonehearth_ace:create_entity')
      local model_variant = options and options.model_variant
      if model_variant then
         entity:add_component('render_info'):set_model_variant(model_variant)
      elseif create_entity_data and create_entity_data.assign_random_model_variant then
         -- if there's a default assigned, try to just find the corresponding model variant from that
         local variant_to_set = radiant.entities.get_model_variant(entity, true)
         if not variant_to_set or variant_to_set == '' or variant_to_set == 'default' then
            local model_variants = radiant.entities.get_component_data(entity, 'model_variants')
            local variants = WeightedSet(rng)
            for id, variant in pairs(model_variants) do
               if id ~= 'default' then
                  variants:add(id, 1)
               end
            end
            variant_to_set = variants:choose_random()
         end
         entity:add_component('render_info'):set_model_variant(variant_to_set or 'default')
      end

      if create_entity_data then
         local vertical_model_offset_range = create_entity_data.vertical_model_offset_range
         if vertical_model_offset_range then
            local min = vertical_model_offset_range.min or 0
            local max = vertical_model_offset_range.max or 0
            local mob = entity:add_component('mob')
            mob:set_model_origin(mob:get_model_origin() + Point3(0, rng:get_real(math.min(min, max), math.max(min, max)), 0))
         end

         local scale_range = create_entity_data.scale_range
         if scale_range then
            local render_info = entity:add_component('render_info')
            local base_scale = render_info:get_scale()
            local min = (scale_range.min or 1) * base_scale
            local max = (scale_range.max or 1) * base_scale
            -- scale can result in performance issues: try to limit the number of different scales and the length of the decimal
            local r = rng:get_int(0, 100) * 0.01
            render_info:set_scale(math.min(min, max) + r * math.abs(min - max))
         end

         local add_loot_command = create_entity_data.add_loot_command
         if add_loot_command then
            if (add_loot_command == 'no_player' and entity:get_player_id() == '') or
                  (add_loot_command == 'any_npc_player' and stonehearth.player:is_npc(entity)) then
               entity:add_component('stonehearth:commands'):add_command('stonehearth:commands:loot_item')
            end
         end
      end
   end

   return entity
end

-- Returns the currently active model variant of the entity
-- if '' or 'default', tries to find a specific model variant with the active model file
function ace_entities.get_model_variant(entity, component_only)
   local render_info = entity and entity:get_component('render_info')
   if render_info then
      local model_variant = render_info:get_model_variant()
      if model_variant == '' or model_variant == 'default' then
         local model_variants = entity:get_component('model_variants')
         if model_variants then
            local models = {}
            local default_models = model_variants:get_variant('default')
            if default_models then
               for model in default_models:each_model() do
                  models[model] = true
               end

               -- now check each other variant to see if the same models are present
               local variant_from_comp, variant_from_json
               for id, variant in model_variants:each_variant() do
                  if id ~= 'default' then
                     if radiant.entities._model_variants_match(variant, models) then
                        variant_from_comp = id
                        break
                     end
                  end
               end

               if not component_only then
                  -- also check the component data in case this entity was created before the separate model variants were added
                  -- (model_variants component doesn't appear to get refreshed on reload, it's loaded separately as part of entity creation)
                  local json = radiant.entities.get_component_data(entity, 'model_variants')
                  if json then
                     for id, variant_data in pairs(json) do
                        if id ~= 'default' then
                           if radiant.entities._model_variants_from_json_match(variant_data, models) then
                              variant_from_json = id
                              break
                           end
                        end
                     end
                  end
               end

               return variant_from_json or variant_from_comp
            end
         end
      end
      return model_variant
   end
end

function ace_entities._model_variants_match(variant, models)
   local variant_models = {}
   for model in variant:each_model() do
      if not models[model] then
         return false
      end
      variant_models[model] = true
   end
   for model, _ in pairs(models) do
      if not variant_models[model] then
         return false
      end
   end

   return true
end

function ace_entities._model_variants_from_json_match(variant, models)
   local variant_models = {}
   for _, model in ipairs(variant.models) do
      if not models[model] then
         return false
      end
      variant_models[model] = true
   end
   for model, _ in pairs(models) do
      if not variant_models[model] then
         return false
      end
   end

   return true
end

-- Use when the entity is being killed in the world
-- Will trigger sync "kill" event so all components can clean up after themselves
-- only changed to include the entity's uri and kill_data in the general event
function ace_entities.kill_entity(entity, kill_data)
   if entity and entity:is_valid() then
      log:debug('killing entity %s', entity)
      radiant.check.is_entity(entity)

      --Trigger an event synchronously, so we don't delete the item till all listeners have done their thing
      radiant.events.trigger(entity, 'stonehearth:kill_event', {
         entity = entity,
         id = entity:get_id(),
         kill_data = kill_data
      })

      radiant.entities._run_kill_effect(entity)

      local sentient = false
      if radiant.entities.is_material(entity, 'human') then
         sentient = true
      else
         local pet_component = entity:get_component('stonehearth:pet')
         if pet_component and pet_component:is_pet() then
            sentient = true
         end
      end

      --Trigger a more general event, for non-affiliated components
      radiant.events.trigger_async(radiant.entities, 'stonehearth:entity_killed', {
         sentient = sentient,
         id = entity:get_id(),
         display_name = radiant.entities.get_display_name(entity),
         custom_name = radiant.entities.get_custom_name(entity),
         custom_data = radiant.entities.get_custom_data(entity),
         player_id = entity:get_player_id(),
         uri = entity:get_uri(),
         kill_data = kill_data
      })

      --For now, just call regular destroy on the entity
      --Review Question: Will it ever be the case that calling destroy is insufficient?
      --for example, if we also need to recursively kill child entities? Are we ever
      --going to apply this to marsupials? If you kill an oiliphant, the dudes on its
      --back aren't immediately killed too, they just fall to the ground, right?
      --"It still only counts as one!" --ChrisGimli
      radiant.entities.destroy_entity(entity)
   end
end

function ace_entities.set_description(entity, description, description_data)
   entity:add_component('stonehearth:unit_info'):set_description(description, description_data)
end

function ace_entities.add_pet(entity, pet, lock_to_owner)
   if entity and entity:is_valid() and pet and pet:is_valid() then
      local pet_component = pet:add_component('stonehearth:pet')
      if not pet_component:is_locked_to_owner() then
         pet_component:convert_to_pet(entity:get_player_id())
         pet_component:set_owner(entity)
         if lock_to_owner then
            pet_component:lock_to_owner()
         end
      end
   end
end

function ace_entities.add_title(entity, title, rank)
   if entity and entity:is_valid() then
      entity:add_component('stonehearth_ace:titles'):add_title(title, rank)
   end
end

function ace_entities.get_current_title(entity)
   if entity and entity:is_valid() then
      local name_component = entity:get_component('stonehearth:unit_info')
      return name_component and name_component:get_current_title()
   end
end

function ace_entities.get_custom_data(entity)
   if entity and entity:is_valid() then
      local name_component = entity:get_component('stonehearth:unit_info')
      return name_component and name_component:get_custom_data()
   end
end

function ace_entities.increment_stat(entity, category, name, value, default)
   -- make sure statistics component is only on the root entity, not iconic
   entity = entity_forms.get_root_entity(entity) or entity
   entity:add_component('stonehearth_ace:statistics'):increment_stat(category, name, value, default)
end

function ace_entities.add_to_stat_list(entity, category, name, value, default)
   -- make sure statistics component is only on the root entity, not iconic
   entity = entity_forms.get_root_entity(entity) or entity
   entity:add_component('stonehearth_ace:statistics'):add_to_stat_list(category, name, value, default)
end

function ace_entities.get_property_value(entity, property)
   local pv_comp = entity:get_component('stonehearth_ace:property_values')
   return pv_comp and pv_comp:get_property(property)
end

-- replace defaults to true, specify as false if you want to avoid replacing existing values
-- returns true if successful
function ace_entities.set_property_value(entity, property, value, replace)
   local pv_comp = entity:add_component('stonehearth_ace:property_values')
   return pv_comp:set_property(property, value, replace)
end

function ace_entities.get_renown(entity) --, include_equipment)
   if not entity or not entity:is_valid() then
      return
   end

   local renown = 0
   local titles_comp = entity:get_component('stonehearth_ace:titles')
   if titles_comp then
      renown = titles_comp:get_renown()
   end

   -- if include_equipment ~= false then
   --    local equipment_component = entity:get_component('stonehearth:equipment')
   --    for key, item in pairs(equipment_component:get_all_items()) do
   --       titles_comp = item:get_component('stonehearth_ace:titles')
   --       if titles_comp then
   --          renown = renown + titles_comp:get_renown()
   --       end
   --    end
   -- end

   return renown
end

-- uris are key, value pairs of uri, quantity
-- quantity can also be a table of quality/quantity pairs
function ace_entities.spawn_items(uris, origin, min_radius, max_radius, options, place_items)
   local items = {}
   options = options or {}
   local owner_id = options.owner
   owner_id = owner_id and type(owner_id) ~= 'string' and owner_id:get_player_id() or owner_id
   local quality = options.quality
   local quality_options = quality and {max_quality = owner_id and item_quality_lib.get_max_random_quality(owner_id) or nil}
   local inventory
   if owner_id and options.add_spilled_to_inventory then
      inventory = stonehearth.inventory:get_inventory(owner_id)
   end

   for uri, detail in pairs(uris) do
      local qualities
      if type(detail) == 'number' then
         qualities = {[1] = detail}
      else
         qualities = detail
      end
      for item_quality, quantity in pairs(qualities) do
         if quality_options and item_quality > 1 then
            quality_options.min_quality = item_quality
         end
         local this_quality = quality or item_quality

         for i = 1, quantity do
            -- log:debug('trying to create %s with options: %s', uri, radiant.util.table_tostring(options))
            local item = radiant.entities.create_entity(uri, options)
            item_quality_lib.apply_quality(item, this_quality, quality_options)

            items[item:get_id()] = item

            if place_items ~= false then
               local location = radiant.terrain.find_placement_point(origin, min_radius, max_radius)
               radiant.terrain.place_entity(item, location)

               if inventory then
                  inventory:add_item_if_not_full(item)
               end
            end
         end
      end
   end

   return items
end

-- if no valid output is specified
function ace_entities.output_items(uris, origin, min_radius, max_radius, options) --, output, inputs, spill_fail_items, quality)
   options = options or {}
   local inputs = options.inputs
   local output = options.output

   local output_comp = output and output:is_valid() and output:get_component('stonehearth_ace:output')
   if inputs and type(inputs) ~= 'table' then
      -- if it's not a single entity, it's wrong and should post an error message
      if radiant.entities.is_entity(inputs) and inputs:is_valid() then
         inputs = {[inputs:get_id()] = inputs}
      else
         log:error('trying to output items with invalid input/source: %s', tostring(inputs))
         inputs = nil
      end
      options.inputs = inputs
   end
   if not output_comp and (not inputs or not next(inputs)) then
      if options.spill_fail_items then
         local result = radiant.entities.get_empty_output_table()
         result.spilled = radiant.entities.spawn_items(uris, origin, min_radius, max_radius, options, true)
         return result
      else
         return radiant.entities.get_empty_output_table()
      end
   end

   local items = radiant.entities.spawn_items(uris, origin, min_radius, max_radius, options, false)
   return ace_entities.output_spawned_items(items, origin, min_radius, max_radius, options)
end

function ace_entities.output_spawned_items(items, origin, min_radius, max_radius, options) --, output, inputs, spill_fail_items, delete_fail_items)
   --local output_comp = output and output:is_valid() and output:get_component('stonehearth_ace:output')
   options = options or {}
   local inputs = options.inputs
   
   if inputs and type(inputs) ~= 'table' then
      inputs = {[inputs:get_id()] = inputs}
      options.inputs = inputs
   end

   options.spill_origin = origin
   options.spill_min_radius = min_radius
   options.spill_max_radius = max_radius

   return item_io_lib.try_output(items, inputs, options)
end

function ace_entities.can_output_spawned_items(items, output, inputs, require_matching_filter_override)
   if inputs and type(inputs) ~= 'table' then
      inputs = {[inputs:get_id()] = inputs}
   end

   local options = {
      output = output,
      require_matching_filter_override = require_matching_filter_override,
   }

   return item_io_lib.can_output(items, inputs, options)
end

function ace_entities.get_successfully_output_items(output_table)
   -- combine the spilled and succeeded tables into an array
   local combined = {}
   for _, category in ipairs({'succeeded', 'spilled'}) do
      for _, item in pairs(output_table[category]) do
         table.insert(combined, item)
      end
   end

   return combined
end

function ace_entities.get_empty_output_table()
   return {spilled = {}, succeeded = {}, failed = {}}
end

function ace_entities.combine_output_tables(t1, t2)
   local result = radiant.entities.get_empty_output_table()

   for category, items in pairs(result) do
      if t1 and t1[category] then
         radiant.util.merge_into_table(items, t1[category])
      end
      if t2 and t2[category] then
         radiant.util.merge_into_table(items, t2[category])
      end
   end

   return result
end

-- copied from choose_unreserved_point_in_destination_action
function ace_entities.get_destination_location(target, source)
   local dst = target:get_component('destination')
   if not dst then
      return
   end

   local origin = radiant.entities.get_world_grid_location(target)

   -- calculate the region minus the actual reserved region.
   local rgn = Region3()
   rgn:copy_region(dst:get_region():get())

   local reserved = dst:get_reserved()
   if reserved then
      rgn:subtract_region(reserved:get())
   end

   if rgn:empty() then
      return
   end
   local offset = rgn:get_closest_point(source and (radiant.entities.get_world_grid_location(source) - origin) or Point3.zero)
   
   return offset + origin
end

function ace_entities.get_facing(entity)
   if not entity or not entity:is_valid() then
      return nil
   end

   local mob = entity:get_component('mob')
   if not mob then
      return nil
   end

   local rotation = mob:get_rotation()
   if rotation.x ~= 0 or rotation.z ~= 0 then
      -- if it's rotated on x or z, mob:get_facing() will cause a c++ assert fail!
      -- so get the flat y rotation instead
      rotation.x = 0
      rotation.z = 0
      rotation:normalize()
      -- angle in radians = 2 * acos(q.w); multiply by 180 / pi to convert to degrees
      return 360 * math.acos(rotation.w) / math.pi
   else
      return mob:get_facing()
   end
end

-- Returns the (voxel, integer) grid location in front of the specified entity.
function ace_entities.get_grid_in_front(entity)
   local mob = entity:get_component('mob')
   local facing = radiant.math.round(radiant.entities.get_facing(entity) / 90) * 90
   local location = mob:get_world_grid_location()
   local offset = radiant.math.rotate_about_y_axis(-Point3.unit_z, facing):to_closest_int()
   return location + offset
end

function ace_entities.get_region_world_to_local(region, entity)
   local mob = entity:add_component('mob')
   local location = mob:get_world_grid_location()
   if location then
      local region_origin = mob:get_region_origin()
      return region:translated(-location - region_origin):rotated(-mob:get_facing()):translated(region_origin)
   end
end

function ace_entities.is_entity_town_suspended(entity)
   local town = stonehearth.town:get_town(entity)
   if town then
      return town:is_town_suspended()
   end
end

function ace_entities.is_solid_location(location)
   local entities = radiant.terrain.get_entities_at_point(location)

   for _, entity in pairs(entities) do
      if radiant.entities.is_solid_entity(entity) then
         return true
      end
   end

   return false
end

function ace_entities.is_entity_protected_from_targeting(entity)
   -- perhaps add a property that can be set dynamically? for now just use a material
   return radiant.entities.is_material(entity, 'protected_from_targeting')
end

function ace_entities.set_entity_movement_modifier(entity, region, mm_data)
   local base_mm_data = mm_data or radiant.entities.get_entity_data(entity, 'movement_modifier_shape')
   
   if not base_mm_data then
      return
   end

   local movement_modifier = base_mm_data.modifier
   local nav_preference_modifier = base_mm_data.nav_preference_modifier

   local mms = entity:add_component('movement_modifier_shape')
   if not mms:get_region() then
      mms:set_region(_radiant.sim.alloc_region3())
   end
   mms:get_region():modify(function(cursor)
         cursor:copy_region(region)
         cursor:optimize_by_defragmentation('entity movement modifier shape')
      end)
   
   if movement_modifier then
      mms:set_modifier(movement_modifier)
   end
   if nav_preference_modifier then
      mms:set_nav_preference_modifier(nav_preference_modifier)
   end
end

function ace_entities.get_alternate_uris(uri)
   local catalog_data = stonehearth.catalog:get_catalog_data(uri)
   return catalog_data and catalog_data.alternate_uris
end

function ace_entities.get_alternate_iconic_uris(uri)
   local catalog_data = stonehearth.catalog:get_catalog_data(uri)
   return catalog_data and (catalog_data.iconic_uri and catalog_data.alternate_uris or catalog_data.alternate_iconic_uris)
end

ace_entities.get_appeal_optimized = (function()
   local get_entity_data = radiant.entities.get_entity_data
   local apply_item_quality_bonus = radiant.entities.apply_item_quality_bonus
   local item_quality_bonuses = stonehearth.constants.item_quality.bonuses.appeal
   local floor = math.floor
   local min = math.min
   local abs = math.abs
   local VITALITY_PLANT_APPEAL_MULTIPLIER = stonehearth.constants.town_progression.bonuses.VITALITY_PLANT_APPEAL_MULTIPLIER
   local VITALITY_PLANTER_APPEAL_ADDITION = stonehearth.constants.town_progression.bonuses.VITALITY_PLANTER_APPEAL_ADDITION
   local catalog, get_catalog_data

   return function(entity, uri, player_id, has_town_vitality_bonus)
      if not catalog then
         catalog = stonehearth.catalog
         get_catalog_data = catalog.get_catalog_data
      end

      local catalog_data = get_catalog_data(catalog, uri)
      local appeal = catalog_data and catalog_data.appeal

      if appeal == nil then
         return nil
      end

      if entity then
         local item_quality = entity:get_component('stonehearth:item_quality')
         if item_quality then
            local quality = item_quality:get_quality()
            local bonus = item_quality_bonuses[quality]
            if bonus ~= nil then
               if appeal < 0 then
                  -- If value is negative, tend the value towards 0 instead of applying the multiplier on top
                  appeal = min(appeal + (abs(appeal) * bonus), 0)
               else
                  appeal = appeal + (appeal * bonus)
               end
               appeal = floor(appeal + 0.5)
            end
         end
      end

      -- Apply the "vitality" town bonus if it's applicable. If we ever have more of these,
      -- we'll need a generic hook, but for now, let's keep it light.
      if has_town_vitality_bonus then
         local catalog_data = get_catalog_data(catalog, uri)
         if catalog_data then
            if catalog_data.category == 'plants' then
               appeal = floor(appeal * VITALITY_PLANT_APPEAL_MULTIPLIER + 0.5)
            elseif catalog_data.category == 'herbalist_planter' then
               appeal = appeal + VITALITY_PLANTER_APPEAL_ADDITION
            end
         end
      end

      return appeal
   end
end)()

return ace_entities
