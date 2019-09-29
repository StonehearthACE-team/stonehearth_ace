local entity_forms = require 'stonehearth.lib.entity_forms.entity_forms_lib'
local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'

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
function ace_entities.spawn_items(uris, origin, min_radius, max_radius, options)
   local items = {}

   for uri, detail in pairs(uris) do
      local qualities
      if type(detail) == 'number' then
         qualities = {[1] = detail}
      else
         qualities = detail
      end
      for quality, quantity in pairs(detail) do
         for i = 1, quantity do
            local location = radiant.terrain.find_placement_point(origin, min_radius, max_radius)
            local item = radiant.entities.create_entity(uri, options)
            if quality > 1 then
               item_quality_lib.apply_quality(entity, quality)
            end

            items[item:get_id()] = item
            radiant.terrain.place_entity(item, location)
         end
      end
   end

   return items
end

return ace_entities
