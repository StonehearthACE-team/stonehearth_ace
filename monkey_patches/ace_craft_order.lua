local CraftOrder = radiant.mods.require('stonehearth.components.workshop.craft_order')
local log = radiant.log.create_logger('craft_order')

local AceCraftOrder = class()

AceCraftOrder._ace_old_on_item_created = CraftOrder.on_item_created
-- In addition to the original on_item_created function (from craft_order.lua),
-- here it's also removing the ingredients tied to the order made from
-- the reserved ingredients.
--
function AceCraftOrder:on_item_created(primary_output)
   local condition = self._sv.condition
   if condition.type == 'make' then
      self._sv.order_list:remove_from_reserved_ingredients(self._recipe.ingredients, self._sv.id, self._sv.player_id)
      -- reduce by the number of requested items by the amount produced (primary product only)
      if condition.requested_amount and primary_output then
         condition.requested_amount = condition.requested_amount - primary_output
      end
   end

   self:_ace_old_on_item_created()
end

function AceCraftOrder:restore()
   if self._sv._auto_crafting then
      self._sv._auto_queued = true
      self._sv._auto_crafting = nil
   end

   local associated_orders = self._sv._associated_orders
   if associated_orders then
      for i = #associated_orders, 1, -1 do
         local order = associated_orders[i]
         if not order.order then
            table.remove(associated_orders, i)
         end
      end
      self._sv.associated_orders = associated_orders
      self._sv._associated_orders = nil
   end
end

-- Paul: a lot of the following overrides and additions are just to support multiple crafters on the same order

AceCraftOrder._ace_old_activate = CraftOrder.activate
function AceCraftOrder:activate()
   self._inventory = stonehearth.inventory:get_inventory(self._sv.player_id)

   self:_ace_old_activate()

   if self._sv.order_progress_by_crafter then
      self._sv._order_progress_by_crafter = self._sv.order_progress_by_crafter
      self._sv.order_progress_by_crafter = nil
   end
   if not self._sv._order_progress_by_crafter then
      self._sv._order_progress_by_crafter = {}
   end

   if not self._sv.curr_crafters then
      self._sv.curr_crafters = {n = 0}
      self._sv.curr_crafter_count = 0

      -- if we're activating from a non-ACE save...
      if self._sv.curr_crafter then
         self:_add_curr_crafter(self._sv.curr_crafter)
         self._sv._order_progress_by_crafter[self._sv.curr_crafter:get_id()] = self._sv.order_progress
      end
   else
      -- make sure it's an array and not a table
      local curr_crafters = {n = 0}
      for id, crafter in pairs(self._sv.curr_crafters) do
         if id ~= 'n' then
            table.insert(curr_crafters, crafter)
         end
      end
      self._sv.curr_crafters = curr_crafters
   end

   for _, crafter in ipairs(self._sv.curr_crafters) do
      local id = crafter:get_id()
      if not self._sv._order_progress_by_crafter[id] then
         self._sv._order_progress_by_crafter[id] = stonehearth.constants.crafting_status.UNSTARTED
      end
   end

   -- track the number of primary products produced by each craft of the recipe
   -- always do this, not just if it was a requested amount
   local num = 0
   local product = self._recipe.produces[1]
   local uri = product and product.item
   if uri then
      for _, prod_item in ipairs(self._recipe.produces) do
         if prod_item.item == uri then
            num = num + 1
         end
      end

      self._num_primary_product_per_craft = math.max(1, num)
   end

   self.__saved_variables:mark_changed()
end

AceCraftOrder._ace_old_destroy = CraftOrder.__user_destroy
function AceCraftOrder:destroy()
   for _, crafter in ipairs(self._sv.curr_crafters) do
      local crafter_comp = crafter:is_valid() and crafter:get_component('stonehearth:crafter')
      if crafter_comp then
         crafter_comp:unreserve_fuel()
      end
   end

   -- remove the order from associated orders
   self:remove_associated_order(false)

   -- remove reserved ingredients
   local condition = self:get_condition()
   if condition.type == 'make' and condition.remaining > 0 then
      self._sv.order_list:remove_from_reserved_ingredients(self._recipe.ingredients, self._sv.id, self._sv.player_id, self._sv.condition.remaining)
   end

   self:_ace_old_destroy()
end

function AceCraftOrder:set_recipe(recipe)
   self._sv.recipe = recipe
   self._recipe = recipe
   self:_on_changed()
end

function AceCraftOrder:_add_curr_crafter(crafter)
   local already_crafting = false
   for _, curr_crafter in ipairs(self._sv.curr_crafters) do
      if curr_crafter == crafter then
         already_crafting = true
         break
      end
   end

   if not already_crafting then
      table.insert(self._sv.curr_crafters, crafter)
      self._sv.curr_crafter_count = self._sv.curr_crafter_count + 1
   end
end

function AceCraftOrder:_remove_curr_crafter(crafter)
   for i, curr_crafter in ipairs(self._sv.curr_crafters) do
      if curr_crafter == crafter then
         table.remove(self._sv.curr_crafters, i)
         self._sv.curr_crafter_count = self._sv.curr_crafter_count - 1
         break
      end
   end

   local id = crafter:get_id()
   if self._sv._order_progress_by_crafter[id] then
      self._sv._order_progress_by_crafter[id] = nil
   end
end

function AceCraftOrder:has_current_crafter(crafter)
   for _, curr_crafter in ipairs(self._sv.curr_crafters) do
      if curr_crafter == crafter then
         return true
      end
   end

   return false
end

function AceCraftOrder:reset_progress(crafter)
   local id = crafter:get_id()
   self._sv._order_progress_by_crafter[id] = stonehearth.constants.crafting_status.UNSTARTED
   self:_on_changed()
end

--Progress to the next crafting stage
--We start at unstarted, and then go through collecting, crafting, and distributing
--If we're done distributing, go back to unstarted
function AceCraftOrder:progress_to_next_stage(crafter)
   local id = crafter:get_id()
   -- how does this happen? if the crafter has been removed, don't try to start/progress them
   if self._sv._order_progress_by_crafter[id] then
      self._sv._order_progress_by_crafter[id] = self._sv._order_progress_by_crafter[id] + 1
      if self._sv._order_progress_by_crafter[id] > stonehearth.constants.crafting_status.CLEANUP then
         self._sv._order_progress_by_crafter[id] = stonehearth.constants.crafting_status.UNSTARTED
      end
      -- notify order_list that something has changed, so anyone listening on order_list can have updated information on the order
      self:_on_changed()
   end
end

--Return the progress for the current order
function AceCraftOrder:get_progress(crafter)
   local id = crafter:get_id()
   if not self._sv._order_progress_by_crafter[id] then
      self._sv._order_progress_by_crafter[id] = stonehearth.constants.crafting_status.UNSTARTED
   end
   return self._sv._order_progress_by_crafter[id]
end

function AceCraftOrder:set_crafting_status(crafter, is_crafting)
   if crafter then
      local id = crafter:get_id()
      if is_crafting ~= false then  -- semi-backwards compatibility in case is_crafting is nil
         -- leaving these in here for now for semi-backwards compatibility
         -- self._sv.curr_crafter_id = id
         -- self._sv.curr_crafter = crafter

         self:_add_curr_crafter(crafter)
      else
         self:_remove_curr_crafter(crafter)
         self._sv._order_progress_by_crafter[id] = nil

         -- local new_crafter_id = next(self._sv.curr_crafters)
         -- if new_crafter_id then
         --    self._sv.curr_crafter_id = new_crafter_id
         --    self._sv.curr_crafter = self._sv.curr_crafters[new_crafter_id]
         -- end
      end
   else
      self._sv.curr_crafter_id = nil
      self._sv.curr_crafter = nil

      self._sv.curr_crafters = {n = 0}
      self._sv.curr_crafter_count = 0

      self._sv._order_progress_by_crafter = {}
   end
   local status = #self._sv.curr_crafters > 0
   log:debug('set_crafting_status %s %s => %s: %s', tostring(crafter), tostring(self._sv.is_crafting), status, radiant.util.table_tostring(self._sv.curr_crafters))
   if status ~= self._sv.is_crafting then
      self._sv.is_crafting = status
   end
   self:_on_changed()
end

function AceCraftOrder:is_missing_ingredient(ingredients)
   -- these ingredients still maintain the old counts but are separated out
   -- need to count them up
   -- TODO: integrate this into the ingredient_list controller
   local combined_ingredients = {}
   for _, ingredient in ipairs(ingredients) do
      local combined = combined_ingredients[ingredient.uri or ingredient.material]
      if not combined then
         combined = radiant.shallow_copy(ingredient)
         combined.count = 0
         combined_ingredients[ingredient.uri or ingredient.material] = combined
      end
      combined.count = combined.count + 1
   end

   local tracking_data = self._usable_item_tracking_data
   -- Process all uri ingredients first since it is less expensive to early exit here
   for _, ingredient in pairs(combined_ingredients) do
      if ingredient.uri then
         if not self:_has_uri_ingredients_for_item(ingredient, tracking_data) then
            return ingredient
         end
      elseif ingredient.material then
         if not self:_has_material_ingredients_for_item(ingredient, tracking_data) then
            return ingredient
         end
      end
   end
   return false
end

function AceCraftOrder:has_output_storage_capacity(auto_crafter)
   -- check to make sure an auto-crafter has enough output storage space for the products of this recipe
   local auto_craft_comp = auto_crafter:get_component('stonehearth_ace:auto_craft')
   if auto_craft_comp then
      local crafter_info = self._sv.order_list:get_crafter_info()
      local recipe = crafter_info and crafter_info:get_formatted_recipe(self._recipe)
      return recipe and auto_craft_comp:get_output_capacity() >= recipe.total_products
   end

   return false
end

function AceCraftOrder:has_ingredients(auto_crafter)
   if auto_crafter and auto_crafter:get_component('stonehearth_ace:auto_craft') then
      -- if an auto-crafter is specified, check its ingredient storage instead of the usable item tracker
      local auto_craft_comp = auto_crafter:get_component('stonehearth_ace:auto_craft')
      local ingredient_storage = auto_craft_comp:get_ingredient_storage()
      local quest_storage = ingredient_storage and ingredient_storage:get_component('stonehearth_ace:quest_storage')
      if quest_storage then
         for _, ingredient in ipairs(self._recipe.ingredients) do
            local storage = quest_storage:get_storage_by_requirement(ingredient.uri or ingredient.material)
            if not storage then
               return false
            end

            if ingredient.min_stacks then
               return false

               -- TODO: allow for min_stacks type ingredients
               -- local count = 0
               -- for _, item in pairs(storage:get_items()) do
               --    local stacks_comp = item:get_component('stonehearth:stacks')
               --    if stacks_comp then
               --       count = count + stacks_comp:get_stacks()
               --    end
               -- end
               -- if count < ingredient.min_stacks then
               --    return false
               -- end
            else
               if storage:get_num_items() < ingredient.count then
                  return false
               end
            end
         end

         return true
      end
      return false
   end

   local tracking_data = self._usable_item_tracking_data
   -- Process all uri ingredients first since it is less expensive to early exit here
   for _, ingredient in ipairs(self._recipe.ingredients) do
      if ingredient.uri then
         if not self:_has_uri_ingredients_for_item(ingredient, tracking_data) then
            return false
         end
      elseif ingredient.material then
         if not self:_has_material_ingredients_for_item(ingredient, tracking_data) then
            return false
         end
      end
   end
   return true
end

function AceCraftOrder:ingredient_has_multiple_qualities(ingredient)
   local tracking_data = self._usable_item_tracking_data
   if ingredient.uri then
      return self:_has_multiple_qualities_uri_ingredient(ingredient, tracking_data)
   elseif ingredient.material then
      return self:_has_multiple_qualities_material_ingredient(ingredient, tracking_data)
   end
end

function AceCraftOrder:_has_multiple_qualities_uri_ingredient(ingredient, tracking_data)
   local data = radiant.entities.get_component_data(ingredient.uri , 'stonehearth:entity_forms')
   local lookup_key
   if data and data.iconic_form then
      lookup_key = data.iconic_form
   else
      lookup_key = ingredient.uri
   end

   if not tracking_data:contains(lookup_key) then
      return false
   end

   local tracking_data_for_key = tracking_data:get(lookup_key)
   if tracking_data_for_key then
      local count = 0
      for item_quality_key, entry in pairs(tracking_data_for_key.item_qualities) do
         count = count + 1
      end
      return count > 1
   end

   return false
end

function AceCraftOrder:_has_multiple_qualities_material_ingredient(ingredient, tracking_data)
   local material_id = stonehearth.catalog:get_material_object(ingredient.material):get_id()
   -- Get cached uris that match the material. Speeds up material checking tremendously.
   local uris_matching_material = stonehearth.catalog:get_materials_to_matching_uris()[material_id]

   local ingredient_count = 0
   if uris_matching_material then
      local qualities = {}
      for uri, _ in pairs(uris_matching_material) do
         if tracking_data:contains(uri) then
            local tracking_data_for_key = tracking_data:get(uri)
            for item_quality_key, entry in pairs(tracking_data_for_key.item_qualities) do
               qualities[item_quality_key] = true
            end
            if radiant.size(qualities) > 1 then
               return true
            end
         end
      end
   end

   return false
end

-- override this to consider stacks for items and also make sure items aren't inside of consumers (because that's fuel/reserved)
function AceCraftOrder:_has_uri_ingredients_for_item(ingredient, tracking_data)
   local data = radiant.entities.get_component_data(ingredient.uri , 'stonehearth:entity_forms')
   local lookup_key
   if data and data.iconic_form then
      lookup_key = data.iconic_form
   else
      lookup_key = ingredient.uri
   end
   if not tracking_data:contains(lookup_key) then
      return false
   end
   local tracking_data_for_key = tracking_data:get(lookup_key)
   if not tracking_data_for_key then
      return false
   end

   local count = 0
   for id, item in pairs(tracking_data_for_key.items) do
      -- local container = self._inventory and self._inventory:container_for(item)
      -- if not container or not container:get_component('stonehearth_ace:consumer') then
         if ingredient.min_stacks then
            local stacks_comp = item:get_component('stonehearth:stacks')
            if stacks_comp then
               count = count + stacks_comp:get_stacks()
            end
         else
            count = count + 1
         end

         if count >= (ingredient.min_stacks or ingredient.count) then
            return true
         end
      -- end
   end

   return false
end

function AceCraftOrder:_has_material_ingredients_for_item(ingredient, tracking_data)
   local material_id = stonehearth.catalog:get_material_object(ingredient.material):get_id()
   -- Get cached uris that match the material. Speeds up material checking tremendously.
   local uris_matching_material = stonehearth.catalog:get_materials_to_matching_uris()[material_id]

   local ingredient_count = 0
   if uris_matching_material then
      -- Iterate through every uri that provides this ingredient's material
      -- and check whether we have that item in our usable items tracker
      for uri, _ in pairs(uris_matching_material) do
         if tracking_data:contains(uri) then
            local data = tracking_data:get(uri)
            for id, item in pairs(data.items) do
               -- local container = self._inventory and self._inventory:container_for(item)
               -- if not container or not container:get_component('stonehearth_ace:consumer') then
                  if ingredient.min_stacks then
                     local stacks_comp = item:get_component('stonehearth:stacks')
                     if stacks_comp then
                        ingredient_count = ingredient_count + stacks_comp:get_stacks()
                     end
                  else
                     ingredient_count = ingredient_count + 1
                  end

                  if ingredient_count >= (ingredient.min_stacks or ingredient.count) then
                     return true
                  end
               -- end
            end
         end
      end
   end

   return false
end

--[[
   Used to determine if we should proceed with executing the order.
   If this order has a condition which are unsatisfied, (ie, less than x amount
   was built, or less than x inventory exists in the world) return true.
   If this order's conditions are met, and we don't need to execute this
   order, return false.
   returns: true if conditions are not yet met, false if conditions are met
]]
function AceCraftOrder:should_execute_order(crafter)
   --If the crafter is not appropriately leveled, return false
   local job_component = crafter:get_component('stonehearth:job')
   local job_level = job_component:get_current_job_level()
   if job_level and self._recipe.level_requirement and job_level < self._recipe.level_requirement then
      log:detail('craft_order: cannot execute order with recipe %s, crafter %s does not meet requriements', self._recipe.recipe_name, crafter)
      return false
   end

   -- also make sure this category of crafting isn't disabled for this crafter
   if self._recipe.category and job_component:get_crafting_category_disabled(self._recipe.category) then
      log:detail('craft_order: cannot execute order with recipe %s, crafter %s has crafting for category %s disabled',
            self._recipe.recipe_name, crafter, self._recipe.category)
      return false
   end

   -- If crafter is incapacitated, return false
   local incapacitation = crafter:get_component('stonehearth:incapacitation')
   if incapacitation and incapacitation:is_incapacitated() then
      log:detail('craft order: cannot execute order with recipe %s, crafter %s is incapacitated', self._recipe.recipe_name, crafter)
      return false
   end

   --If a workshop is required and there is no placed workshop, return false
   if self._recipe.workshop then
      local workshop_uri = self._recipe.workshop.uri
      local found_valid_workshop = false

      if self:_has_valid_workshop(crafter, workshop_uri) then
         found_valid_workshop = true
      else
         -- Not an exact match. Maybe a valid equivalent?
         local workshop_catalog_data = stonehearth.catalog:get_catalog_data(workshop_uri)
         if workshop_catalog_data then
            local equivalents = workshop_catalog_data.workshop_equivalents
            if equivalents then
               for _, equivalent in ipairs(equivalents) do
                  if self:_has_valid_workshop(crafter, equivalent) then
                     found_valid_workshop = true
                     break
                  end
               end
            end
         end
      end

      if not found_valid_workshop then
         log:detail('craft_order: cannot execute order with recipe %s, no workshops of appropriate type: %s',
                    tostring(self._recipe.recipe_name), tostring(self._recipe.workshop.uri))
         return false
      end
   end

   log:detail('returning true from should_execute_order')
   return true
end

function AceCraftOrder:_has_valid_workshop(crafter, workshop_uri)
   local workshop_data = self._inventory:get_items_of_type(workshop_uri)

   if workshop_data and workshop_data.count > 0 then
      local consumer_data = radiant.entities.get_component_data(workshop_uri, 'stonehearth_ace:consumer')
      if consumer_data then
         for _, workshop in pairs(workshop_data.items) do
            local consumer_comp = workshop:get_component('stonehearth_ace:consumer')
            if consumer_comp and consumer_comp:reserve_fuel(crafter) then
               return true
            end
         end
      else
         return true
      end
   end

   return false
end

function AceCraftOrder:conditions_fulfilled(crafter)
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
      num_being_made = num_being_made * self._num_primary_product_per_craft
      if condition.at_least <= num_being_made then
         return false
      end

      local we_have = num_being_made
      local uris = { self:_get_primary_product_uri(self._recipe.produces) }
      if self._recipe.ace_smart_crafter_consider_as and #self._recipe.ace_smart_crafter_consider_as > 0 then
         table.insert(uris, self:_get_primary_product_uri(self._recipe.ace_smart_crafter_consider_as))
      end

      for _, uri in ipairs(uris) do
         local data = self._inventory:get_items_of_type(uri)
         if data and data.items then
            for _, item in pairs(data.items) do
               -- check if the item is contained in a consumer that wants it; if so, disregard
               local container = self._inventory:public_container_for(item)
               local consumer = container and container:get_component('stonehearth_ace:consumer')
               local consumer_storage = consumer and container:get_component('stonehearth:storage')
               if not consumer_storage or not consumer_storage:passes(item) then -- is this faster than checking for a lease? should consumer have a check?
                  we_have = we_have + 1
                  if we_have >= condition.at_least then
                     --log:detail('craft_order: We are maintaining recipe %s and now have enough of it. Stopping.', self._recipe.recipe_name)
                     return false
                  end
               end
            end
         end
      end
   end

   return true
end

function AceCraftOrder:_get_primary_product_uri(products)
   local uri = products[1].item
   local data = radiant.entities.get_component_data(uri, 'stonehearth:entity_forms')
   if data and data.iconic_form then
      uri = data.iconic_form
   end

   return uri
end

function AceCraftOrder:get_max_ingredients_to_animate_dropping()
   return self._recipe.max_ingredients_to_animate_dropping or stonehearth.constants.crafting.MAX_INGREDIENTS_TO_ANIMATE_DROPPING
end

function AceCraftOrder:produces(product_uri)
   if self._recipe.produces[1].item == product_uri then
      return true
   end
   if self._recipe.ace_smart_crafter_consider_as and #self._recipe.ace_smart_crafter_consider_as > 0 and
         self._recipe.ace_smart_crafter_consider_as[1].item == product_uri then
      return true
   end
   return false
end

function AceCraftOrder:is_auto_craft_recipe()
   -- reference the saved variables recipe because this might be pre-activate
   return self._sv.recipe.is_auto_craft
end

function AceCraftOrder:is_auto_queued()
   return self._sv.condition.auto_queued
end

function AceCraftOrder:get_num_primary_product_per_craft()
   return self._num_primary_product_per_craft
end

-- this auto queuing field is for regular automatic *requests* for crafting
-- not for crafting done by auto-crafters
function AceCraftOrder:get_auto_queued()
   return self._sv._auto_queued
end

function AceCraftOrder:set_auto_queued(value)
   self._sv._auto_queued = value
end

function AceCraftOrder:get_associated_orders()
   return self._sv.associated_orders
end

-- returns the entry for this order
function AceCraftOrder:set_associated_orders(associated_orders)
   self._sv.associated_orders = associated_orders
   if not associated_orders then
      self.__saved_variables:mark_changed()
      return
   end

   -- if this order is already in the associated orders, return its entry
   for _, associated_order in ipairs(associated_orders) do
      if associated_order.order == self then
         return associated_order
      end
   end

   -- otherwise we need to add it
   table.insert(associated_orders, {
      order = self,
   })
   self.__saved_variables:mark_changed()
   return associated_orders[#associated_orders]
end

function AceCraftOrder:remove_associated_order(remove_children)
   local associated_orders = self:get_associated_orders()
   if associated_orders and #associated_orders > 0 then
      log:debug('order %s removing from %s associated orders', self:get_id(), #associated_orders)
      -- first remove any child orders; this will recursively remove any orders necessary
      if remove_children then
         local child_orders = {}
         for _, child_order in ipairs(associated_orders) do
            if child_order.parent_order == self then
               table.insert(child_orders, child_order)
            end
         end
         for _, child_order in ipairs(child_orders) do
            --log:debug('order %s removing child order %s', self:get_id(), child_order.order:get_id())
            child_order.order:get_order_list():remove_order(child_order.order:get_id())
         end
      end

      -- finally search associated orders for this order and remove it
      for i, order in ipairs(associated_orders) do
         if order.order ~= self then
            order.order:remove_associated_order_reference(self)
         end
      end

      self._sv.associated_orders = nil
      self.__saved_variables:mark_changed()
   end
end

function AceCraftOrder:remove_associated_order_reference(order)
   log:debug('order %s (%s) removing associated order reference %s (%s)',
         self:get_id(), self._sv.recipe.recipe_name, order:get_id(), order:get_recipe().recipe_name)
   local associated_orders = self:get_associated_orders()
   if associated_orders then
      for i, associated_order in ipairs(associated_orders) do
         if associated_order.order == order then
            log:debug('found order %s in associated orders, removing', order:get_id())
            table.remove(associated_orders, i)
            break
         end
      end
      -- if it's down to only this order or no orders, remove the associated_orders table
      log:debug('associated_orders now has %s orders', #associated_orders)
      if #associated_orders < 2 then
         self._sv.associated_orders = nil
      end
      self.__saved_variables:mark_changed()
   end
end

function AceCraftOrder:get_building_id()
   return self._sv.building_id
end

function AceCraftOrder:set_building_id(building_id)
   self._sv.building_id = building_id
   self.__saved_variables:mark_changed()
end

function AceCraftOrder:get_order_list()
   return self._sv.order_list
end

-- reduce the quantity of the primary product to craft with this order, as necessary
-- only affects make orders
-- returns true if the order changed and the order list should be updated
-- returns false if the number remaining to make was less than or equal to the amount to reduce
-- returns nil otherwise
function AceCraftOrder:reduce_product_quantity(reduction)
   log:debug('[%s] reduce_product_quantity(%s)', self:get_id(), reduction)
   local condition = self._sv.condition
   if condition.type == 'make' and condition.requested_amount and self._num_primary_product_per_craft then
      log:debug('reducing quantity requested by [%s] from %s to %s', self:get_id(), condition.requested_amount, condition.requested_amount - reduction)
      condition.requested_amount = condition.requested_amount - reduction
      local new_remaining = math.ceil(condition.requested_amount / self._num_primary_product_per_craft)

      if new_remaining < condition.remaining then
         return self:reduce_quantity(condition.remaining - new_remaining)
      else
         self.__saved_variables:mark_changed()
         return false
      end
   end
end

-- reduce_quantity and increase_quantity accept a delta amount, not a new total amount
-- returns true if it successfully reduced the quantity to craft from an order
-- returns false if the number remaining to make was less than or equal to the amount to reduce
-- returns nil otherwise
function AceCraftOrder:reduce_quantity(reduction)
   log:debug('[%s] reduce_quantity(%s)', self:get_id(), reduction)
   local condition = self._sv.condition
   if condition.type == 'make' then
      local reduced = condition.remaining - reduction
      log:debug('reducing recipe quantity by [%s] from %s to %s', self:get_id(), condition.remaining, reduced)

      if reduced == 0 then
         self._sv.order_list:remove_order(self:get_id())
         return false
      end

      self._sv.order_list:remove_from_reserved_ingredients(self._recipe.ingredients, self._sv.id, self._sv.player_id, reduction)
      condition.remaining = reduced
      self:_remove_desires(reduction)
      self.__saved_variables:mark_changed()

      self:_update_associated_orders_quantity()
      return true
   elseif condition.at_least then
      -- maintain orders can be reduced, they just won't change any associated orders
      condition.at_least = condition.at_least - reduction
      self:_remove_desires(reduction)
      self.__saved_variables:mark_changed()
      return true
   end
end

function AceCraftOrder:increase_quantity(increase)
   log:debug('[%s] increase_quantity(%s)', self:get_id(), increase)
   local condition = self._sv.condition
   if condition.type == 'make' then
      local increased = condition.remaining + increase
      log:debug('increasing recipe quantity by [%s] from %s to %s', self:get_id(), condition.remaining, increased)
      self._sv.order_list:add_to_reserved_ingredients(self._recipe.ingredients, self._sv.id, self._sv.player_id, increase)
      condition.remaining = increased
      self:_add_desires(increase)
      self.__saved_variables:mark_changed()

      self:_update_associated_orders_quantity()
      return true
   elseif condition.at_least then
      -- maintain orders can be increased, they just won't change any associated orders
      condition.at_least = condition.at_least + increase
      self:_add_desires(increase)
      self.__saved_variables:mark_changed()
      return true
   end
end

-- change_quantity functions accept a new total amount, not a delta amount
function AceCraftOrder:change_product_quantity(amount)
   log:debug('[%s] change_product_quantity(%s)', self:get_id(), amount)
   local condition = self._sv.condition
   if self._num_primary_product_per_craft then
      if condition.type == 'make' then
         condition.requested_amount = amount
      end
      local new_remaining = math.ceil(amount / self._num_primary_product_per_craft)
      local prev_remaining = condition.remaining or condition.at_least
      if new_remaining < prev_remaining then
         return self:reduce_quantity(prev_remaining - new_remaining)
      elseif new_remaining > prev_remaining then
         return self:increase_quantity(new_remaining - prev_remaining)
      else
         self.__saved_variables:mark_changed()
         return false
      end
   end
end

-- returns true if the order changed and the order list should be updated
function AceCraftOrder:change_quantity(quantity)
   log:debug('[%s] change_quantity(%s)', self:get_id(), quantity)
   -- if trying to change quantity to less than 1, simply remove the order
   if quantity < 1 then
      self._sv.order_list:remove_order(self:get_id())
      return false   -- order list will already be updated by removing the order
   end

   if self._num_primary_product_per_craft then
      return self:change_product_quantity(quantity * self._num_primary_product_per_craft)
   end
end

-- only called internally for make orders
function AceCraftOrder:_update_associated_orders_quantity()
   log:debug('[%s] _update_associated_orders_quantity()', self:get_id())
   local associated_orders = self:get_associated_orders()
   if associated_orders and #associated_orders > 1 then
      local condition = self._sv.condition
      for _, associated_order in ipairs(associated_orders) do
         -- if the associated order is an ingredient for this recipe, reduce it by the amount that this recipe requires
         if associated_order.parent_order == self then
            local ing_amount = condition.remaining * associated_order.ingredient_per_craft
            local order_list = associated_order.order:get_order_list()
            if associated_order.order:change_product_quantity(ing_amount) then
               order_list:_on_order_list_changed()
               if associated_order.order:is_auto_craft_recipe() then
                  order_list:_on_auto_craft_orders_changed()
               end
            end
         end
      end
   end
end

function AceCraftOrder:_add_desires(num)
   assert(num or not next(self._desires))
   -- TODO: For maintain orders, we could batch all the counts together.
   local count = num or self._sv.condition.amount or self._sv.condition.at_least

   local desires_tracker = stonehearth.inventory:get_inventory(self._sv.player_id):get_desires()
   for _ = 1, count do
      local desire = {}
      for _, ingredient in ipairs(self._recipe.ingredients) do
         if ingredient.uri then
            table.insert(desire, desires_tracker:request_item(ingredient.uri, ingredient.count))
         elseif ingredient.material then
            table.insert(desire, desires_tracker:request_material(ingredient.material, ingredient.count))
         end
      end
      table.insert(self._desires, desire)
   end
end

AceCraftOrder._ace_old__remove_desires = CraftOrder._remove_desires
function AceCraftOrder:_remove_desires(num)
   if not self._desires then
      return
   end

   self:_ace_old__remove_desires(num)
end

return AceCraftOrder
