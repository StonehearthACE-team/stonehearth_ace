local util = require 'stonehearth_ace.lib.util'
local CraftOrderList = radiant.mods.require('stonehearth.components.workshop.craft_order_list')
local AceCraftOrderList = class()
local constants = radiant.mods.require('stonehearth.constants')
local MAX_ORDERS = radiant.util.get_global_config('mods.stonehearth.max_crafter_orders', constants.crafting.DEFAULT_MAX_CRAFT_ORDERS)

local log = radiant.log.create_logger('craft_order_list')

function AceCraftOrderList:create(player_id)
   self._sv._player_id = player_id
   self._sv.secondary_orders = {n=0}
   self._sv.auto_craft_orders = {n=0}
   self._sv.is_secondary_list_paused = false
end

function AceCraftOrderList:restore()
   self:_validate_craft_orders()

   if self._sv.maintain_orders then
      self._sv.secondary_orders = self._sv.maintain_orders
      self._sv.is_secondary_list_paused = self._sv.is_maintain_paused
      self._sv.maintain_orders = nil
      self._sv.is_maintain_paused = nil
   end

   if not self._sv.secondary_orders then
      self._sv.secondary_orders = {n=0}
      -- go through all the orders and move any maintain orders to the secondary_orders list
      for i = #self._sv.orders, 1, -1 do
         local order = self._sv.orders[i]
         if order:get_condition().type == 'maintain' then
            table.insert(self._sv.secondary_orders, order)
            table.remove(self._sv.orders, i)
         end
      end
      self._sv.is_secondary_list_paused = false
   end

   if not self._sv.auto_craft_orders then
      self._sv.auto_craft_orders = {n=0}
      -- go through all the maintain orders and move any auto-craft orders to the auto_craft_orders list
      for i = #self._sv.secondary_orders, 1, -1 do
         local order = self._sv.secondary_orders[i]
         -- can't check ._recipe directly because the order hasn't been activated yet
         if order._sv.recipe.is_auto_craft then
            table.insert(self._sv.auto_craft_orders, order)
            table.remove(self._sv.secondary_orders, i)
         end
      end
   end

   -- make sure we don't have too many orders
   for _, orders in ipairs({self._sv.orders, self._sv.secondary_orders, self._sv.auto_craft_orders}) do
      while #orders > MAX_ORDERS do
         table.remove(orders, #orders)
      end
   end
   self:_on_order_list_changed()
end

AceCraftOrderList._ace_old_destroy = CraftOrderList.__user_destroy
function AceCraftOrderList:destroy()
   if self._stuck_timer then
      self._stuck_timer:destroy()
      self._stuck_timer = nil
   end
   self:_destroy_periodic_stuck_timer()

   self:_ace_old_destroy()
end

function AceCraftOrderList:_destroy_periodic_stuck_timer()
   if self._periodic_stuck_timer then
      self._periodic_stuck_timer:destroy()
      self._periodic_stuck_timer = nil
   end
end

function AceCraftOrderList:_validate_craft_orders()
   -- validate orders list by removing nil indexes
   -- just always remake lists rather than first trying to process through all possible order ids
   local orders = self._sv.orders
   local secondary_orders = self._sv.secondary_orders
   local auto_craft_orders = self._sv.auto_craft_orders
   self._sv.orders = radiant.map_to_array(orders, function(key, value)
      if type(value) == 'table' then
         return nil -- Keep this value
      end
      return false -- Skip this value
   end)
   self._sv.orders.n = 0 -- need to restore this or remoter won't know it's an array

   if secondary_orders then
      self._sv.secondary_orders = radiant.map_to_array(secondary_orders, function(key, value)
         if type(value) == 'table' then
            return nil -- Keep this value
         end
         return false -- Skip this value
      end)
      self._sv.secondary_orders.n = 0 -- need to restore this or remoter won't know it's an array
   end

   self._sv.auto_craft_orders = radiant.map_to_array(auto_craft_orders, function(key, value)
      if type(value) == 'table' then
         return nil -- Keep this value
      end
      return false -- Skip this value
   end)
   self._sv.auto_craft_orders.n = 0 -- need to restore this or remoter won't know it's an array

   -- Populate orders cache
   for _, orders in ipairs({self._sv.orders, self._sv.secondary_orders, self._sv.auto_craft_orders}) do
      if orders then
         for _, order in ipairs(orders) do
            self._orders_cache[order:get_id()] = true
         end
      end
   end
end

-- because of the way the creation of job info controllers and crafter order lists works,
-- we can't actually create the crafter info controller until after it's been fully created
-- (after post_activate) so just do it the first time it's requested instead
function AceCraftOrderList:_get_crafter_info()
   if not self._crafter_info then
      self._crafter_info = stonehearth_ace.crafter_info:get_crafter_info(self._sv._player_id)
   end
   return self._crafter_info
end

function AceCraftOrderList:_should_auto_queue_recipe_dependencies(player_id)
   return stonehearth.client_state:get_client_gameplay_setting(player_id, 'stonehearth_ace', 'auto_craft_recipe_dependencies', true)
end

function AceCraftOrderList:_should_update_maintain_orders(player_id)
   return stonehearth.client_state:get_client_gameplay_setting(player_id, 'stonehearth_ace', 'update_maintain_orders', true)
end

-- returns the number maintained if the recipe is maintained, otherwise nil
function AceCraftOrderList:is_product_maintained(product_uri)
   local order = self:_find_maintained_product_order({uri = product_uri}, true)
   if order then
      return order:get_condition().at_least
   end
end

--Add the order to the order list
function AceCraftOrderList:add_order_command(session, response, recipe, condition)
   if #self:_get_order_list_by_type(condition.type, recipe.is_auto_craft) >= MAX_ORDERS then
      -- do not add orders if we are above the cap
      return false
   end

   self:add_order(session.player_id, recipe, condition)
   return true
end

-- In addition to the original add_order function (from craft_order_list.lua),
-- here it's also checking if the order has enough of the required ingredients and,
-- if it can be crafted, adds those ingredients as orders as well.
--
-- Furthermore, when maintaining orders, it makes sure that there are no more than
-- one instance of each recipe that's maintained.
--
function AceCraftOrderList:add_order(player_id, recipe, condition, building, associated_orders)
   log:debug('add_order(%s, %s, %s, %s, %s)', player_id, recipe, radiant.util.table_tostring(condition), tostring(building), tostring(associated_orders))

   if recipe.is_auto_craft and condition.type ~= 'maintain' then
      -- auto-craft recipes can only be maintain orders
      log:error('auto-craft recipes can only be maintain orders')
      return false
   end

   local is_recursive_call = associated_orders ~= nil

   -- if it's a maintain order, and it's a child order or the player prefers updating maintain orders, try to modify an existing maintain order
   if condition.type == 'maintain' and (is_recursive_call or self:_should_update_maintain_orders(player_id)) then
      -- See if the order_list already contains a maintain order for the recipe:
      --    if it does, remake the order if its amount is lower than `missing`, otherwise ignore it;
      --    if it doesn't, simply add it as usual
      local order = self:_find_craft_order(recipe, 'maintain')
      if order then
         --log:debug('checking if maintain order "%s" is to be replaced', order:get_recipe().recipe_name)
         --log:detail('this is %sa recursive call, the order\'s value is %d and the new one is %d',
         --   is_recursive_call and 'NOT ' or '',
         --   order:get_condition().at_least,
         --   condition.at_least)
         local at_least = tonumber(condition.at_least)
         local order_condition = order:get_condition()
         local order_at_least = order_condition.at_least
         if condition.quick_add then
            at_least = order_at_least + at_least
         end

         if at_least >= order_at_least or (not is_recursive_call and at_least <= order_at_least) then
            -- only allow reducing the quantity if this is a direct add_order call
            -- and not a recursive call to a child order
            if at_least ~= order_at_least and order:change_quantity(at_least) then
               -- if we're specifying an index, move the order there
               if condition.order_index then
                  self:change_order_position(condition.order_index, order:get_id())
               else
                  self:_on_order_list_changed()
                  if order:is_auto_craft_recipe() then
                     self:_on_auto_craft_orders_changed()
                  end
               end
            end
         else
            log:debug('an order already exists which fulfills the request')
         end
         return true
      end
   end

   if not self:_should_auto_queue_recipe_dependencies(player_id) then
      return self:insert_order(player_id, recipe, condition, nil, building)
   end

   associated_orders = associated_orders or {}
   local child_orders = {}

   local inv = stonehearth.inventory:get_inventory(player_id)
   local crafter_info = self:_get_crafter_info()

   -- Process the recipe's ingredients to see if the crafter has all she needs for it
   for _, ingredient in pairs(recipe.ingredients) do
      local ingredient_id = ingredient.uri or ingredient.material

      -- because of the way the UI works with min_stacks, we may need to replace the ingredient count
      log:debug('checking ingredient "%s" with count %s (%s)', ingredient_id, ingredient.count, tostring(ingredient.original_count))
      ingredient.count = ingredient.original_count or ingredient.count

      --log:debug('processing ingredient "%s"', ingredient_id)

      -- Step 1: `make`:
      --         See if there are enough of the asked ingredient in the inventory:
      --            if there is, continue to the next ingredient;
      --            if missing, go to step 2.
      --
      --         `maintain`:
      --         Simply get how much the ingredient asks for and set it as missing,
      --         go to step 2.

      local missing
      if condition.type == 'make' then
         local needed = condition.amount * ingredient.count
         local in_storage = inv:get_amount_in_storage(ingredient.uri, ingredient.material)
         -- Go through and combine the orders in all the order lists
         -- we ignore all maintain orders; only consider make orders for reserved/required ingredients
         local in_order_list = 0
         for _, order_list in ipairs(crafter_info:get_order_lists()) do
            local order_list_amount = order_list:_get_ingredient_amount_in_order_list(ingredient)
            in_order_list = in_order_list + order_list_amount.make
         end
         missing = math.max(needed - math.max(in_storage + in_order_list - crafter_info:get_reserved_ingredients(ingredient_id), 0), 0)

         crafter_info:add_to_reserved_ingredients(ingredient_id, needed)
      else -- condition.type == 'maintain'
         missing = ingredient.count

         if is_recursive_call or self:_should_update_maintain_orders(player_id) then
            -- if it's a maintain order, and it's a child order or the player prefers updating maintain orders,
            -- check if there's an existing maintain order for this product that isn't identical to the recipe,
            -- and if so, update the amount to match what's required for this order
            local order, amount = self:_find_maintained_product_order(ingredient, true, true)
            if order and amount > 0 then
               if amount < missing and order:change_quantity(missing) then
                  order:get_order_list():_on_order_list_changed()
                  if order:is_auto_craft_recipe() then
                     order:get_order_list():_on_auto_craft_orders_changed()
                  end
               end
               missing = 0
            end
         end
         --log:debug('maintaining the recipe requires %d of this ingredient, searching if it can be crafted itself', missing)
      end

      if missing > 0 then

         -- Step 2: Check if the ingredient can be produced through a different recipe:
         --            if it does, proceed to step 3;
         --            if not, continue on to the next ingredient.

         local player_jobs_controller = stonehearth.job:get_jobs_controller(player_id)
         local child_order = player_jobs_controller:request_craft_product(
               ingredient_id, missing, building, false, condition.order_index ~= nil, condition, associated_orders, recipe)
         if child_order and child_order ~= true then
            local associated_order = child_order:set_associated_orders(associated_orders)
            associated_order.ingredient_per_craft = missing
            table.insert(child_orders, associated_order)
         end
      end
   end

   local result = self:insert_order(player_id, recipe, condition, nil, building)

   -- if we got to this point, it's because we're auto-crafting dependencies
   result:set_auto_queued(true)

   if #associated_orders > 0 then
      if #child_orders > 0 then
         for _, associated_order in ipairs(child_orders) do
            log:debug('order %s setting parent order for associated child order %s', result:get_id(), associated_order.order:get_id())
            associated_order.parent_order = result
         end
      end

      result:set_associated_orders(associated_orders)
   end

   return result
end

function AceCraftOrderList:insert_order(player_id, recipe, condition, maintain_order_index, building)
   local order = radiant.create_controller('stonehearth:craft_order', self._sv.next_order_id, recipe, condition, player_id, self)
   if building then
      order:set_building_id(building)
   end

   local order_list = self:_get_order_list_by_type(condition.type, recipe.is_auto_craft)
   table.insert(order_list, condition.order_index or maintain_order_index or #order_list + 1, order)
   self._orders_cache[self._sv.next_order_id] = true
   self._sv.next_order_id = self._sv.next_order_id + 1
   self:_on_order_list_changed()

   if recipe.is_auto_craft then
      self:_on_auto_craft_orders_changed()
   end
   log:debug('inserted order for %d %s', condition.at_least or condition.amount, recipe.recipe_name)

   return order
end

-- this is used by the player_jobs_controller:request_craft_product
function AceCraftOrderList:request_order_of(player_id, recipe_info, produces, amount, building, insert_order, condition, associated_orders)
   log:debug('requesting order of %d %s (%s) with associated orders %s',
         amount, recipe_info.recipe.product_uri, insert_order and 'inserting at top' or 'adding to bottom', tostring(associated_orders))
   -- queue the appropriate number based on how many the recipe produces
   local num = math.ceil(amount / produces)
   if condition then
      condition = radiant.shallow_copy(condition)
   else
      condition = {
         type = 'make',
         order_index = insert_order and 1 or nil,
      }
   end
   if condition.type == 'make' then
      condition.amount = num
      condition.requested_amount = amount
   else -- condition.type == 'maintain'
      condition.at_least = num
   end

   return recipe_info.order_list:add_order(player_id, recipe_info.recipe, condition, building, associated_orders)
end

-- ACE: when changing order, consider clearing stuck order status of affected orders
function AceCraftOrderList:change_order_position_command(session, response, new, id)
   return self:change_order_position(new, id)
end

function AceCraftOrderList:change_order_position(new, id)
   local i, order_list = self:find_index_of(id)
   if i then
      local order = order_list[i]
      table.remove(order_list, i)
      local next_index = #order_list + 1
      if new > next_index then
         -- If new index is more than number of orders put it at the end of the list.
         new = next_index
      end

      if new < 1 then
         new = 1
      end

      -- if moving down and we weren't stuck, unstuck all orders above new index
      -- if moving up above any non-stuck orders and we were stuck, unstuck this
      if new > i and not self._stuck_orders[id] then
         for j = i, new - 1 do
            self._stuck_orders[order_list[j]:get_id()] = nil
         end
      elseif new < i and self._stuck_orders[id] then
         for j = new, i - 1 do
            if not self._stuck_orders[order_list[j]:get_id()] then
               self._stuck_orders[id] = nil
               break
            end
         end
      end

      table.insert(order_list, new, order)
      --TODO: comment out when you've fixed the drag/drop problem
      self:_on_order_list_changed()
      if order:is_auto_craft_recipe() then
         self:_on_auto_craft_orders_changed()
      end

      -- TODO: check if this order *and* any that it moved past are auto-craft orders
      -- if so, trigger the event
      return true
   end
   return false
end

-- ACE: amount is an optional parameter that refers to the amount of primary products, not the quantity of recipes
-- e.g., if a recipe would produce 4 fence posts and you have 2 of the recipe queued, reducing by 1 alone would not change anything
function AceCraftOrderList:remove_order(order_id, amount, remove_associated)
   log:debug('remove_order(%s, %s, %s)', order_id, tostring(amount), tostring(remove_associated))
   local i, order_list = self:find_index_of(order_id)
   if i then
      --log:debug('removing order id %s (index %s)', order_id, i)
      local order = order_list[i]
      if order and (not amount or not order:reduce_quantity(amount)) then
         table.remove(order_list, i)
         self._order_indices_dirty = true
         local order_id = order:get_id()
         local is_auto_craft = order:is_auto_craft_recipe()

         self._orders_cache[order_id] = nil
         self._craftable_orders[order_id] = nil
         if self._stuck_orders[order_id] then
            self._stuck_orders[order_id] = nil
         end

         -- remove the order and its children from associated orders
         order:remove_associated_order(remove_associated ~= false)

         order:destroy()

         if is_auto_craft then
            self:_on_auto_craft_orders_changed()
         end
      else
         self:_on_order_list_changed()
      end

      return true
   end
   return false
end

AceCraftOrderList._ace_old_delete_order_command = CraftOrderList.delete_order_command
-- In addition to the original delete_order_command function (from craft_order_list.lua),
-- here it's also making sure that the ingredients needed for the order are removed
-- from the reserved ingredients table.
--
function AceCraftOrderList:delete_order_command(session, response, order_id, delete_associated_orders)
   local order_index, order_list = self:find_index_of(order_id)
   if order_index then
      local order = order_list[order_index]
      if order then
         if order:get_auto_queued() then
            local condition = order:get_condition()

            local associated_orders = delete_associated_orders and order:get_associated_orders()
            if associated_orders then
               -- also remove any associated orders
               local other_orders = util.filter_list(associated_orders, function(_, associated_order)
                     return associated_order.order ~= order
                  end)
               for _, associated_order in ipairs(other_orders) do
                  --log:debug('order id %s deleting associated order id %s (of %s remaining)', order_id, associated_order.order:get_id(), #other_orders)
                  associated_order.order:get_order_list():delete_order_command(session, response, associated_order.order:get_id())
               end
            end
         end
      end
   end

   --log:debug('order id %s being deleted', order_id)
   return self:_ace_old_delete_order_command(session, response, order_id)
end

-- All within `ingredients` are removed from the reserved ingredients table.
-- `order_id` is the id of the order that we are to remove of.
-- `player_id` says which player id the order belongs to.
-- `multiple` says by how much the ingredients' count will be multiplied by,
-- if it's not specified it will get the value of 1.
--
function AceCraftOrderList:remove_from_reserved_ingredients(ingredients, order_id, player_id, multiple)
   multiple = multiple or 1
   for _, ingredient in pairs(ingredients) do
      local ingredient_id = ingredient.uri or ingredient.material
      self:_get_crafter_info():remove_from_reserved_ingredients(ingredient_id, ingredient.count * multiple)
   end
end

-- Checking `inventory` to see how much of `ingredient` is available.
--
function AceCraftOrderList:_get_ingredient_amount_in_storage(ingredient, inventory)
   local tracking_data = inventory:get_item_tracker('stonehearth:usable_item_tracker')
                                       :get_tracking_data()
   local ingredient_count = 0

   if ingredient.uri then
      local item = ingredient.uri
      local entity_forms = radiant.entities.get_component_data(ingredient.uri, 'stonehearth:entity_forms')
      if entity_forms and entity_forms.iconic_form then
         item = entity_forms.iconic_form
      end

      if tracking_data:contains(item) then
         ingredient_count = tracking_data:get(item).count
      end
   elseif ingredient.material then
      for _, item in tracking_data:each() do
         if radiant.entities.is_material(item.first_item, ingredient.material) then
            ingredient_count = ingredient_count + item.count
         end
      end
   end

   return ingredient_count
end

-- Checks this order list to see how much of `ingredient` it contains.
-- The optional `to_order_id` says that any orders with their id,
-- that are at least as great as that number, will be ignored.
--
function AceCraftOrderList:_get_ingredient_amount_in_order_list(ingredient, to_order_id)
   local ingredient_count = {
      make = 0,
      maintain = 0,
      total = 0,
   }

   local crafter_info = self:_get_crafter_info()
   for _, order_list in ipairs({self._sv.orders, self._sv.secondary_orders}) do
      for i, order in ipairs(order_list) do
         if not to_order_id or order:get_id() < to_order_id then
            local amount = self:_get_order_product_amount(order, ingredient)

            if amount then
               local condition_type = order:get_condition().type
               ingredient_count[condition_type] = ingredient_count[condition_type] + amount
            end
         end
      end
   end

   ingredient_count.total = ingredient_count.make + ingredient_count.maintain
   return ingredient_count
end

-- product is formatted as an ingredient, like {uri = uri, material = material}
function AceCraftOrderList:_get_order_product_amount(order, product)
   local recipe = self:_get_crafter_info():get_formatted_recipe(order:get_recipe())

   if recipe then
      local condition = order:get_condition()

      local material_produces = product.material and self:_recipe_produces_materials(recipe, product.material)
      local uri_produces = product.uri and recipe.products[product.uri]
      local num_produces = material_produces or uri_produces

      if num_produces and num_produces > 0 then
         if condition.type == 'make' then
            return condition.remaining * num_produces
         else
            return math.max(num_produces, condition.at_least)
         end
      end
   end

   return 0
end

function AceCraftOrderList:_recipe_produces_materials(recipe, material)
   return util.sum_where_all_keys_present(recipe.product_materials, recipe.products, material)
end

-- Gets the craft order which matches `recipe_name`, if an `order_type`
-- is defined, then it will also check for a match against it.
-- Returns nil if no match was found.
--
function AceCraftOrderList:_find_craft_order(recipe, order_type)
   --log:debug('finding a recipe for "%s"', recipe_name)
   --log:debug('There are %d orders', radiant.size(self._sv.orders) - 1)

   local order_list = self:_get_order_list_by_type(order_type, recipe.is_auto_craft)
   for i, order in ipairs(order_list) do
      local order_recipe_name = order:get_recipe().recipe_name
      --log:debug('evaluating order with recipe "%s"', order_recipe_name)
      if order_recipe_name == recipe.recipe_name then
         return order
      end
   end

   return nil
end

-- Gets the craft order with a product that matches `product`, if an `order_type`
-- is defined, then it will also check for a match against it.
-- product is formatted as an ingredient, like {uri = uri, material = material}
-- Returns nil if no match was found.
--
function AceCraftOrderList:_find_maintained_product_order(product, check_auto, find_biggest)
   local list = self:_get_order_list_by_type('maintain')
   local order_lists = {list}
   if check_auto then
      table.insert(order_lists, self:_get_order_list_by_type('maintain', true))
   end
   local biggest_order, biggest_amount
   for _, order_list in ipairs(order_lists) do
      for i, order in ipairs(order_list) do
         if find_biggest then
            local amount = self:_get_order_product_amount(order, product)
            if not biggest_order or amount > biggest_amount then
               biggest_order = order
               biggest_amount = amount
            end
         elseif (product.uri and order:produces(product.uri)) or
               (product.material and
                  self:_recipe_produces_materials(self:_get_crafter_info():get_formatted_recipe(order:get_recipe()), product.material)) then
            return order
         end
      end
   end

   return biggest_order, biggest_amount
end

function AceCraftOrderList:register_stuck_order(order_id)
   self._stuck_orders[order_id] = true

   self:_ensure_periodic_stuck_timer()
end

function AceCraftOrderList:_ensure_periodic_stuck_timer()
   if not self._periodic_stuck_timer then
      self._periodic_stuck_timer = stonehearth.calendar:set_timer("periodically reconsider stuck orders", constants.crafting.PERIODIC_RECONSIDER_ORDERS_COOLDOWN,
         function()
            self._periodic_stuck_timer = nil
            self:_create_stuck_timer()
         end)
   end
end

function AceCraftOrderList:is_secondary_list_paused()
   return self._sv.is_secondary_list_paused
end

function AceCraftOrderList:toggle_secondary_list_pause()
   self._sv.is_secondary_list_paused = not self._sv.is_secondary_list_paused
   self:_on_order_list_changed()
   self:_on_auto_craft_orders_changed()
   self.__saved_variables:mark_changed()
end

-- overrides this base function in order to support multiple crafters on the same order
-- the craft items orchestrator that calls this is only used by actual hearthling crafters, not auto-crafters
function AceCraftOrderList:get_next_order(crafter)
   --log:debug('craft_order_list: There are %s orders', #self._sv.orders)
   local count = 0
   --log:debug('trying to feed order to %s', crafter)
   if not self:is_paused() then
      local order, num = self:_get_next_order(crafter, self._sv.orders)
      if order then
         return order
      else
         count = count + num
      end
   end
   if not self:is_secondary_list_paused() then
      local order, num = self:_get_next_order(crafter, self._sv.secondary_orders)
      if order then
         return order
      else
         count = count + num
      end
   end

   if count > 0 then
      self:_create_stuck_timer()
   end
end

function AceCraftOrderList:_get_next_order(crafter, order_list)
   local count = 0
   for i, order in ipairs(order_list) do
      count = count + 1
      --log:debug('craft_order_list: evaluating order with recipe %s', order:get_recipe().recipe_name)
      local order_id = order:get_id()
      local craftable = self._craftable_orders[order_id]
      if craftable ~= false then
         if (order:has_current_crafter(crafter) or order:conditions_fulfilled()) and
               order:should_execute_order(crafter) then
            --log:debug('given order %d back to crafter %s', i, crafter)

            if craftable == nil then
               craftable = order:has_ingredients()
               self._craftable_orders[order_id] = craftable
            end
            if craftable and not self._stuck_orders[order_id] then
               return order
            else
               local crafter_comp = crafter:get_component('stonehearth:crafter')
               if crafter_comp then
                  crafter_comp:unreserve_fuel()
               end
            end
         end
      end
      -- This is a hot path. Commenting out the debug logs for now. -yshan
      --log:debug('craft_order_list: We are not going to continue this order of recipe %s', order:get_recipe().recipe_name)
      --log:debug('craft_order_list: Current crafter should be %s and crafter id is %s', order:get_current_crafter_id(), crafter:get_id())
      --log:debug('craft_order_list: Crafting status is %s', order:get_crafting_status())
   end
   return nil, count
end

-- UPDATE: for now, instead of trying to get the next available order, the auto_craft component pulls them all
-- and evaluates against its enabled recipes to find the best one to start
function AceCraftOrderList:get_next_auto_craft_order(auto_crafter)
   -- look through the maintain order list (auto craft orders can only be maintain orders)
   -- check each auto-craft recipe order to see if the auto-crafter can craft it
   -- the auto-crafter needs to have that recipe enabled and have the required ingredients
   for i, order in ipairs(self._sv.auto_craft_orders) do
      --log:debug('craft_order_list: evaluating order with recipe %s', order:get_recipe().recipe_name)
      local order_id = order:get_id()
      if (order:has_current_crafter(auto_crafter) or order:conditions_fulfilled()) and
            order:has_ingredients(auto_crafter) then
         return order
      end
   end
end

-- ACE: auto-crafters need to know what all orders are queued up
-- so they can request ingredients for those that match up with what they have enabled
function AceCraftOrderList:get_all_auto_craft_orders()
   return self._sv.auto_craft_orders
end

function AceCraftOrderList:_create_stuck_timer()
   self:_destroy_periodic_stuck_timer()

   -- Note: don't clear the stuck_orders table in _on_inventory_changed, since the inventory changes when the crafter drops the leftovers
   -- so the same order would be picked again and again
   if self:has_stuck_orders() then
      -- Only refresh the list if there are still orders in it, and some/all of them were tagged as stuck
      self._stuck_orders = {}
      -- Now set a timer to make the crafter reconsider the orders. It has to be done after a while because of a race
      -- We now wait for the thread to be suspended, so that this event will make it resume safely
      -- Otherwise there can be problems with multiple crafters or depending on whether the last order was stuck or not
      if not self._stuck_timer then
         self._stuck_timer = stonehearth.calendar:set_timer("reconsider stuck orders", constants.crafting.RECONSIDER_ORDERS_COOLDOWN,
                           function()
                              self._stuck_timer = nil
                              radiant.events.trigger(self, 'stonehearth:order_list_changed')
                           end)
      end
   end
end

function AceCraftOrderList:reconsider_category(category)
   for _, order in ipairs(self._sv.orders) do
      local order_category = order:get_recipe().category
      if order_category == category then
         self._stuck_orders[order:get_id()] = nil
      end
   end

   self:_on_inventory_changed()
end

function AceCraftOrderList:remove_craft_orders_for_building(bid)
   local to_remove = {}
   for i, order in ipairs(self._sv.orders) do
      if order:get_building_id() == bid then
         table.insert(to_remove, order:get_id())
      end
   end
   for _, order_id in ipairs(to_remove) do
      self:remove_order(order_id)
   end
end

-- UNUSED FUNCTIONS
function AceCraftOrderList:_matching_tags(tags1, tags2)
   if type(tags1) == 'string' then
      tags1 = radiant.util.split_string(tags1, ' ')
   end
   if type(tags2) == 'string' then
      tags2 = radiant.util.split_string(tags2, ' ')
   end

   -- this isn't necessarily super efficient, but these are tiny arrays; better to do this than generate a map
   for _, tag in ipairs(tags1) do
      local found = false
      for _, tag2 in ipairs(tags2) do
         if tag == tag2 then
            found = true
            break
         end
      end
      if not found then
         return false
      end
   end

   return true
end

-- Checks to see if `tags_string1` is a sub-set of `tags_string2`.
-- Returns true if it is, else false.
--
function AceCraftOrderList:_matching_tags__strings(tags_string1, tags_string2)
   -- Hack!
   -- Add a space at the end to make the frontier pattern search succeed at all times
   tags_string2 = tags_string2 .. ' '
   -- gmatch will return either 1 tag or the empty string
   -- make sure we skip over the empty strings!
   for tag in tags_string1:gmatch("([^ ]*)") do
      -- use frontier pattern to find the tag,
      -- whilst making sure that it's a word-border search
      if tag ~= '' and not tags_string2:find("%f[%a%d_]".. tag .."%f[ ]") then
         return false
      end
   end
   return true
end

function AceCraftOrderList:_get_order_list_by_type(order_type, is_auto_craft)
   if is_auto_craft then
      return self._sv.auto_craft_orders
   elseif order_type == 'maintain' then
      return self._sv.secondary_orders
   else
      return self._sv.orders
   end
end

--[[
   Find a craft_order by its ID.
   order_id: the unique ID that represents this order
   returns:  the craft_order associated with the ID or nil if the order
             cannot be found,
             and the order_list it was found in (self._sv.orders or self._sv.secondary_orders)
]]
function AceCraftOrderList:find_index_of(order_id)
   if rawget(self, '_order_indices_dirty') then
      local order_indices = {}
      for i, order in ipairs(self._sv.orders) do
         rawset(order_indices, order:get_id(), {i, self._sv.orders})
      end
      for i, order in ipairs(self._sv.secondary_orders) do
         rawset(order_indices, order:get_id(), {i, self._sv.secondary_orders})
      end
      for i, order in ipairs(self._sv.auto_craft_orders) do
         rawset(order_indices, order:get_id(), {i, self._sv.auto_craft_orders})
      end
      self._order_indices_dirty = false
      self._order_indices = order_indices
   end

   -- If it can't find the order, the user probably deleted the order out of the queue
   local result = rawget(rawget(self, '_order_indices'), order_id)
   if result then
      return unpack(result)
   end
end

function AceCraftOrderList:_on_auto_craft_orders_changed()
   radiant.events.trigger(self, 'stonehearth_ace:craft_order_list:auto_craft_orders_changed')
end

return AceCraftOrderList
