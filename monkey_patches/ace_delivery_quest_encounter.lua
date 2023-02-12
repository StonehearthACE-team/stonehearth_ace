local game_master_lib = require 'stonehearth.lib.game_master.game_master_lib'

local DeliveryQuest = require 'stonehearth.services.server.game_master.controllers.encounters.delivery_quest_encounter'
local AceDeliveryQuest = class()

AceDeliveryQuest._ace_old_restore = DeliveryQuest.restore
function AceDeliveryQuest:restore()
   self:_ace_old_restore()
   self:_create_quest_storage_listener()
end

AceDeliveryQuest._ace_old_destroy = DeliveryQuest.__user_destroy
function AceDeliveryQuest:destroy()
   self:_ace_old_destroy()
   self:_destroy_quest_storage()
end

function AceDeliveryQuest:_destroy_quest_storage()
   if self._quest_storage_listener then
      self._quest_storage_listener:destroy()
      self._quest_storage_listener = nil
   end
   if self._sv._quest_storage then
      self._sv._quest_storage:add_component('stonehearth_ace:quest_storage'):destroy_storage(false)
      self._sv._quest_storage = nil
   end
end

function AceDeliveryQuest:_create_quest_storage_listener()
   if self._sv._quest_storage then
      self._quest_storage_listener = radiant.events.listen(self._sv._quest_storage, 'stonehearth_ace:quest_storage:all_requirements_satisfied', self, self._on_recalculate_requirements)
   end
end

AceDeliveryQuest._ace_old_start = DeliveryQuest.start
function AceDeliveryQuest:start(ctx, info)
   self:_ace_old_start(ctx, info)

   if stonehearth.client_state:get_client_gameplay_setting(ctx.player_id, 'stonehearth_ace', 'use_quest_storage', true) then
      local item_requirements = self:_get_item_requirements()
      if #item_requirements < 1 then
         -- no item requirements? no need for quest storage
         return
      end

      self._sv._quest_storage = game_master_lib.create_quest_storage(ctx.player_id, info.quest_storage_uri, item_requirements, self._sv.bulletin)
      self:_create_quest_storage_listener()
   end
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

function AceDeliveryQuest:_get_stored_item_quantity(quest_storage_status, requirement)
   if quest_storage_status then
      for _, storage in ipairs(quest_storage_status) do
         if requirement.uri == storage.requirement.uri and requirement.material == storage.requirement.material then
            return storage.quantity
         end
      end
   end

   return 0
end

-- ACE: need to override to account for items added directly to quest storage
function AceDeliveryQuest:_check_requirements()
   local quest_storage = self._sv._quest_storage
   local item_requirements_status = quest_storage and quest_storage:add_component('stonehearth_ace:quest_storage'):get_requirements_status()
   local all_satisfied = true
   for _, requirement in ipairs(self._sv._info.requirements) do
      if requirement.type == 'give_item' then
         local inventory = stonehearth.inventory:get_inventory(self._sv.ctx.player_id)
         local sellable_item_tracker = inventory:get_item_tracker('stonehearth:sellable_item_tracker')
         local tracking_data = sellable_item_tracker:get_tracking_data()
         local tracking_quantity = tracking_data:contains(requirement.uri) and tracking_data:get(requirement.uri).count or 0
         local stored_quantity = self:_get_stored_item_quantity(item_requirements_status, requirement)
         
         if tracking_quantity + stored_quantity < requirement.count then
            all_satisfied = false
         end
      elseif requirement.type == 'give_material' then
         local inventory = stonehearth.inventory:get_inventory(self._sv.ctx.player_id)
         local sellable_item_tracker = inventory:get_item_tracker('stonehearth:resource_material_tracker')
         local tracking_data = sellable_item_tracker:get_tracking_data()
         local tracking_quantity = tracking_data:contains(requirement.material) and tracking_data:get(requirement.material).count or 0
         local stored_quantity = self:_get_stored_item_quantity(item_requirements_status, requirement)
         
         if tracking_quantity + stored_quantity < requirement.count then
            all_satisfied = false
         end
      elseif requirement.type == 'job_level' then
         local highest_level = stonehearth.job:get_job_info(self._sv.ctx.player_id, requirement.uri):get_highest_level()
         if highest_level < requirement.level then
            all_satisfied = false
         end
      elseif requirement.type == 'happiness' then
         local population = stonehearth.population:get_population(self._sv.ctx.player_id)

         local num_happy_enough = 0
         for _, citizen in population:get_citizens():each() do
            local happiness = citizen:get_component('stonehearth:happiness'):get_current_happiness()
            if happiness >= requirement.min_value then
               num_happy_enough = num_happy_enough + 1
            end
         end

         local num_required = requirement.min_citizens == 'all' and population:get_citizen_count() or requirement.min_citizens
         if num_happy_enough < num_required then
            all_satisfied = false
         end
      elseif requirement.type == 'gold' then
         local inventory = stonehearth.inventory:get_inventory(self._sv.ctx.player_id)
         local amount = 0
         if requirement.subtype == 'give' or requirement.subtype == 'have' then
            amount = inventory:get_gold_count()
         elseif requirement.subtype == 'spent' then
            amount = inventory:get_trade_gold_spent()
         elseif requirement.subtype == 'earned' then
            amount = inventory:get_trade_gold_earned()
         else
            self._log:error('Invalid delivery quest gold requirement dubtype: %s', requirement.subtype)
         end
         if amount < requirement.count then
            all_satisfied = false
         end
      elseif requirement.type == 'have_item_quality' then
         local inventory = stonehearth.inventory:get_inventory(self._sv.ctx.player_id)
         local item_tracker = inventory:get_item_tracker('stonehearth:basic_inventory_tracker')
         local tracking_data = item_tracker:get_tracking_data()
         local num_available = 0

         for _, entry in tracking_data:each() do
            for _, item_quality_entry in pairs(entry.item_qualities) do
               if item_quality_entry.item_quality >= requirement.quality then
                  num_available = num_available + item_quality_entry.count
               end
            end
         end
         
         if num_available < requirement.count then
            all_satisfied = false
         end
      elseif requirement.type == 'net_worth' then
         local net_worth = stonehearth.player:get_net_worth(self._sv.ctx.player_id) or 0
         if net_worth < requirement.value then
            all_satisfied = false
         end
      elseif requirement.type == 'placed_item' then
         local found = false
         local inventory = stonehearth.inventory:get_inventory(self._sv.ctx.player_id)
         local matching = inventory and inventory:get_items_of_type(requirement.uri)
         for _, entity in pairs(matching and matching.items or {}) do
            if radiant.entities.exists_in_world(entity) then
               found = true
               break
            end
         end

         if not found then
            all_satisfied = false
         end
      else
         self._log:error('Invalid delivery quest requirement type: %s', requirement.type)
      end
   end
   return all_satisfied
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
