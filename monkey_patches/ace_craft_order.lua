local CraftOrder = radiant.mods.require('stonehearth.components.workshop.craft_order')
local log = radiant.log.create_logger('craft_order')

local AceCraftOrder = class()

AceCraftOrder._ace_ace_old_on_item_created = CraftOrder.on_item_created
-- In addition to the original on_item_created function (from craft_order.lua),
-- here it's also removing the ingredients tied to the order made from
-- the reserved ingredients.
--
function AceCraftOrder:on_item_created()
   if self._sv.condition.type == 'make' then
      self._sv.order_list:remove_from_reserved_ingredients(self._recipe.ingredients, self._sv.id, self._sv.player_id)
   end
   
   self:_ace_ace_old_on_item_created()
end

-- Paul: the following overrides and additions are all in order to support multiple crafters on the same order

AceCraftOrder._ace_old_activate = CraftOrder.activate
function AceCraftOrder:activate()
   self:_ace_old_activate()

   if not self._sv.order_progress_by_crafter then
      self._sv.order_progress_by_crafter = {}
   end

   if not self._sv.curr_crafters then
      self._sv.curr_crafters = {}
      self._sv.curr_crafter_count = 0
      
      -- if we're activating from a non-ACE save...
      if self._sv.curr_crafter then
         self:_add_curr_crafter(self._sv.curr_crafter)
         self._sv.order_progress_by_crafter[self._sv.curr_crafter:get_id()] = self._sv.order_progress
      end
   end

   for id, crafter in pairs(self._sv.curr_crafters) do
      if not self._sv.order_progress_by_crafter[id] then
         self._sv.order_progress_by_crafter[id] = stonehearth.constants.crafting_status.UNSTARTED
      end
   end

   self.__saved_variables:mark_changed()
end

-- false for lower quality, true for higher quality
function AceCraftOrder:get_high_quality_preference()
   return self._sv.condition.prefer_high_quality
end

function AceCraftOrder:_add_curr_crafter(crafter)
   local id = crafter:get_id()
   if not self._sv.curr_crafters[id] then
      self._sv.curr_crafters[id] = crafter
      self._sv.curr_crafter_count = self._sv.curr_crafter_count + 1
   end
end

function AceCraftOrder:_remove_curr_crafter(crafter)
   local id = crafter:get_id()
   if self._sv.curr_crafters[id] then
      self._sv.curr_crafters[id] = nil
      self._sv.curr_crafter_count = self._sv.curr_crafter_count - 1
   end
   if self._sv.order_progress_by_crafter[id] then
      self._sv.order_progress_by_crafter[id] = nil
   end
end

function AceCraftOrder:has_current_crafter(crafter)
   local id = crafter:get_id()
   return self._sv.curr_crafters[id] ~= nil
end

function AceCraftOrder:reset_progress(crafter)
   local id = crafter:get_id()
   self._sv.order_progress_by_crafter[id] = stonehearth.constants.crafting_status.UNSTARTED
   self:_on_changed()
end

--Progress to the next crafting stage
--We start at unstarted, and then go through collecting, crafting, and distributing
--If we're done distributing, go back to unstarted
function AceCraftOrder:progress_to_next_stage(crafter)
   local id = crafter:get_id()
   self._sv.order_progress_by_crafter[id] = self._sv.order_progress_by_crafter[id] + 1
   if self._sv.order_progress_by_crafter[id] > stonehearth.constants.crafting_status.CLEANUP then
      self._sv.order_progress_by_crafter[id] = stonehearth.constants.crafting_status.UNSTARTED
   end
   -- notify order_list that something has changed, so anyone listening on order_list can have updated information on the order
   self:_on_changed()
end

--Return the progress for the current order
function AceCraftOrder:get_progress(crafter)
   local id = crafter:get_id()
   if not self._sv.order_progress_by_crafter[id] then
      self._sv.order_progress_by_crafter[id] = stonehearth.constants.crafting_status.UNSTARTED
   end
   return self._sv.order_progress_by_crafter[id]
end

function AceCraftOrder:set_crafting_status(crafter, is_crafting)
   if crafter then
      local id = crafter:get_id()
      if is_crafting ~= false then  -- semi-backwards compatibility in case is_crafting is nil
         -- leaving these in here for now for semi-backwards compatibility
         self._sv.curr_crafter_id = id
         self._sv.curr_crafter = crafter
         
         self:_add_curr_crafter(crafter)
      else
         self:_remove_curr_crafter(crafter)
         self._sv.order_progress_by_crafter[id] = nil

         local new_crafter_id = next(self._sv.curr_crafters)
         if new_crafter_id then
            self._sv.curr_crafter_id = new_crafter_id
            self._sv.curr_crafter = self._sv.curr_crafters[new_crafter_id]
         end
      end
   else
      self._sv.curr_crafter_id = nil
      self._sv.curr_crafter = nil

      self._sv.curr_crafters = {}
      self._sv.curr_crafter_count = 0

      self._sv.order_progress_by_crafter = {}
   end
   local status = next(self._sv.curr_crafters) ~= nil
   if status ~= self._sv.is_crafting then
      self._sv.is_crafting = status
   end
   self:_on_changed()
end

function CraftOrder:conditions_fulfilled(crafter)
   -- if we don't satisfy the order conditions, return false
   -- we're doing this BEFORE the has_ingredients because it is cheaper to early out
   
   -- we pass in the crafter so we can check if that crafter is already crafting this order
   -- if they are, we can reduce the remaining/at_least check by 1
   local num_being_made = self._sv.curr_crafter_count
   if crafter and self:has_current_crafter(crafter) then
      num_being_made = num_being_made - 1
   end

   local condition = self._sv.condition
   if condition.type == "make" then
      if condition.remaining <= num_being_made then
         return false
      end
   elseif condition.type == "maintain" then
      if condition.at_least <= num_being_made then
         return false
      end

      local we_have = num_being_made
      local uri = self._recipe.produces[1].item
      local data = radiant.entities.get_component_data(uri, 'stonehearth:entity_forms')
      if data and data.iconic_form then
         uri = data.iconic_form
      end

      local data = self._inventory:get_items_of_type(uri)
      if data and data.items then
         for _, item in pairs(data.items) do
            we_have = we_have + 1
            if we_have >= condition.at_least then
               --log:detail('craft_order: We are maintaining recipe %s and now have enough of it. Stopping.', self._recipe.recipe_name)
               return false
            end
         end
      end
   end

   return true
end

function AceCraftOrder:get_auto_crafting()
   return self._sv._auto_crafting
end

function AceCraftOrder:set_auto_crafting(value)
   self._sv._auto_crafting = value
   self.__saved_variables:mark_changed()
end

function AceCraftOrder:get_associated_orders()
   return self._sv._associated_orders
end

function AceCraftOrder:set_associated_orders(associated_orders)
   self._sv._associated_orders = associated_orders
   self.__saved_variables:mark_changed()
end

return AceCraftOrder
