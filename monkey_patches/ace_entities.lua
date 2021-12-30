local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3

local entity_forms = require 'stonehearth.lib.entity_forms.entity_forms_lib'
local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'
local item_io_lib = require 'stonehearth_ace.lib.item_io.item_io_lib'
local healing_lib = require 'stonehearth_ace.ai.lib.healing_lib'

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
         -- if decreasing health, apply a "wounded" debuff stack if they drop below a threshold
         -- nope! don't automatically apply wounds, let those get specifically applied by monsters/events
         -- "WOUNDED_BUFF": "stonehearth_ace:buffs:wounded"
         -- "WOUNDED_PERCENT_THRESHOLD": 0.15
         -- local threshold = stonehearth.constants.healing.WOUNDED_PERCENT_THRESHOLD
         -- local max_health = expendable_resource_component:get_max_value('health')
         -- if math.floor((1 - old_value / max_health) / threshold) < math.floor((1 - (old_value + health_change) / max_health) / threshold) then
         --    radiant.entities.add_buff(entity, stonehearth.constants.healing.WOUNDED_BUFF)
         -- end
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

function ace_entities.get_current_title(entity)
   local current_title
   local name_component = entity:get_component('stonehearth:unit_info')

   if name_component then
      current_title = name_component:get_current_title()
   end

   return current_title or {display_name = '', description = ''}
end

function ace_entities.get_custom_data(entity)
   local custom_data
   local name_component = entity:get_component('stonehearth:unit_info')

   if name_component then
      custom_data = name_component:get_custom_data()
   end

   return custom_data or {}
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

-- uris are key, value pairs of uri, quantity
-- quantity can also be a table of quality/quantity pairs
function ace_entities.spawn_items(uris, origin, min_radius, max_radius, options, place_items)
   local items = {}
   options = options or {}
   local owner_id = options.owner
   owner_id = owner_id and type(owner_id) ~= 'string' and owner_id:get_player_id() or owner_id
   local quality = options.quality
   local quality_options = quality and owner_id and {max_quality = item_quality_lib.get_max_random_quality(owner_id)}
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
         for i = 1, quantity do
            -- log:debug('trying to create %s with options: %s', uri, radiant.util.table_tostring(options))
            local item = radiant.entities.create_entity(uri, options)
            -- manually passed quality will override any quality from the table (e.g., from a LootTable), even if it's lower
            item_quality_lib.apply_quality(item, quality or item_quality, quality_options)

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
      inputs = {[inputs:get_id()] = inputs}
      options.inputs = inputs
   end
   if not output_comp and (not inputs or not next(inputs)) then
      if options.spill_fail_items then
         local result = ace_entities.get_empty_output_table()
         result.spilled = ace_entities.spawn_items(uris, origin, min_radius, max_radius, options, true)
         return result
      else
         return ace_entities.get_empty_output_table()
      end
   end

   local items = ace_entities.spawn_items(uris, origin, min_radius, max_radius, options, false)
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
   local result = ace_entities.get_empty_output_table()

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
         if catalog_data and (catalog_data.category == 'plants' or catalog_data.category == 'herbalist_planter') then
            appeal = floor(appeal * VITALITY_PLANT_APPEAL_MULTIPLIER + 0.5)
         end
      end

      return appeal
   end
end)()

return ace_entities
