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
      radiant.entities.kill_entity(item)
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

return ace_entities
