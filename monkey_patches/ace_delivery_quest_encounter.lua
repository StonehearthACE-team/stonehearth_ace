local DeliveryQuest = require 'stonehearth.services.server.game_master.controllers.encounters.delivery_quest_encounter'
local AceDeliveryQuest = class()

AceDeliveryQuest._ace_old_destroy = DeliveryQuest.__user_destroy
function AceDeliveryQuest:destroy()
   self:_ace_old_destroy()
   self:_destroy_quest_storage()
end

function AceDeliveryQuest:_destroy_quest_storage()
   if self._sv._quest_storage then
      self._sv._quest_storage:add_component('stonehearth_ace:quest_storage'):destroy_storage(false)
      self._sv._quest_storage = nil
   end
end

AceDeliveryQuest._ace_old_start = DeliveryQuest.start
function AceDeliveryQuest:start(ctx, info)
   self:_ace_old_start(ctx, info)

   local item_requirements = self:_get_item_requirements()
   if #item_requirements < 1 then
      -- no item requirements? no need for quest storage
      return
   end

   local town = stonehearth.town:get_town(ctx.player_id)
   local drop_origin = town:get_landing_location()
   if not drop_origin then
      return
   end

   local quest_storage = radiant.entities.create_entity('stonehearth_ace:containers:quest', {owner = ctx.player_id})
   local location, valid = radiant.terrain.find_placement_point(drop_origin, 4, 7, quest_storage)
   if not valid then
      radiant.entities.destroy_entity(quest_storage)
      return
   end

   -- create a quest storage near the town banner for these items
   local qs_comp = quest_storage:add_component('stonehearth_ace:quest_storage')
   qs_comp:set_requirements(item_requirements)
   qs_comp:set_bulletin(self._sv.bulletin)
   radiant.terrain.place_entity_at_exact_location(quest_storage, location, {force_iconic = false})
   radiant.effects.run_effect(quest_storage, 'stonehearth:effects:gib_effect')

   self._sv._quest_storage = quest_storage
end

function AceDeliveryQuest:_get_item_requirements()
   local requirements = {}
   for _, requirement in ipairs(self._sv._info.requirements) do
      if requirement.type == 'give_item' and not requirement.keep_items then
         table.insert(requirements, {
            uri = requirement.uri,
            quantity = requirement.count,
         })
      elseif requirement.type == 'give_material' and not requirement.keep_items then
         table.insert(requirements, {
            material = requirement.material,
            quantity = requirement.count,
         })
      end
   end
   return requirements
end

function AceDeliveryQuest:_execute_requirements()
   local removed = {}
   if self._sv._quest_storage then
      local consumed = self._sv._quest_storage:add_component('stonehearth_ace:quest_storage'):destroy_storage(true)
      -- destroying actually destroys the entity, so clear our reference to it
      self._sv._quest_storage = nil

      for _, consumed_data in ipairs(consumed) do
         local id = consumed_data.requirement.uri or consumed_data.requirement.material
         if id then
            removed[id] = (removed[id] or 0) + consumed_data.num_consumed
         end
      end
   end

   for _, requirement in ipairs(self._sv._info.requirements) do
      if requirement.type == 'give_item' then
         if not requirement.keep_items then
            local count = requirement.count - (removed[requirement.uri] or 0)
            if count > 0 then
               local inventory = stonehearth.inventory:get_inventory(self._sv.ctx.player_id)
               local removed_successfully = inventory:try_remove_items(requirement.uri, count)
               assert(removed_successfully)
            end
         end
      elseif requirement.type == 'give_material' then
         if not requirement.keep_items then
            local count = requirement.count - (removed[requirement.material] or 0)
            if count > 0 then
               local inventory = stonehearth.inventory:get_inventory(self._sv.ctx.player_id)
               local removed_successfully = inventory:try_remove_items(requirement.material, count, 'stonehearth:resource_material_tracker')
               assert(removed_successfully)
            end
         end
      elseif requirement.type == 'job_level' then
         -- Nothing to execute.
      elseif requirement.type == 'happiness' then
         -- Nothing to execute.
      elseif requirement.type == 'gold' then
         if requirement.subtype == 'give' then
            local inventory = stonehearth.inventory:get_inventory(self._sv.ctx.player_id)
            inventory:subtract_gold(requirement.count)
         end
      elseif requirement.type == 'have_item_quality' then
         -- Nothing to execute.
      else
         self._log:error('Invalid delivery quest requirement type: %s', requirement.type)
      end
   end
end

AceDeliveryQuest._ace_old__on_abandon = DeliveryQuest._on_abandon
function AceDeliveryQuest:_on_abandon(session, request)
   self:_destroy_quest_storage()
   self:_ace_old__on_abandon(session, request)
end

AceDeliveryQuest._ace_old__complete = DeliveryQuest._complete
function AceDeliveryQuest:_complete()
   self:_destroy_quest_storage()
   self:_ace_old__complete()
end

return AceDeliveryQuest
