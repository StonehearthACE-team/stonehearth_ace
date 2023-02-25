local util = require 'stonehearth_ace.lib.util'
local CraftOrderList = radiant.mods.require('stonehearth.components.workshop.craft_order_list')
local AceCraftOrderList = class()
local constants = radiant.mods.require('stonehearth.constants')

local log = radiant.log.create_logger('craft_order_list')

AceCraftOrderList._ace_old_destroy = CraftOrderList.__user_destroy
function AceCraftOrderList:destroy()
   if self._stuck_timer then
      self._stuck_timer:destroy()
      self._stuck_timer = nil
   end

   self:_ace_old_destroy()
end

function AceCraftOrderList:_should_auto_craft_recipe_dependencies(player_id)
   return stonehearth.client_state:get_client_gameplay_setting(player_id, 'stonehearth_ace', 'auto_craft_recipe_dependencies', true)
end

AceCraftOrderList._ace_old_add_order = CraftOrderList.add_order
-- In addition to the original add_order function (from craft_order_list.lua),
-- here it's also checking if the order has enough of the required ingredients and,
-- if it can be crafted, adds those ingredients as orders as well.
--
-- Furthermore, when maintaining orders, it makes sure that there are no more than
-- one instance of each recipe that's maintained.
--
function AceCraftOrderList:add_order(player_id, recipe, condition, building, associated_orders)
   if not self:_should_auto_craft_recipe_dependencies(player_id) then
      return self:insert_order(player_id, recipe, condition, nil, building)
   end

   local is_recursive_call = associated_orders ~= nil

   local inv = stonehearth.inventory:get_inventory(player_id)
   local crafter_info = stonehearth_ace.crafter_info:get_crafter_info(player_id)

   -- Process the recipe's ingredients to see if the crafter has all she needs for it
   for _, ingredient in pairs(recipe.ingredients) do
      local ingredient_id = ingredient.uri or ingredient.material
      
      -- because of the way the UI works with min_stacks, we may need to replace the ingredient count
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
         local in_order_list = {}
         for _, order_list in ipairs(crafter_info:get_order_lists()) do
            local order_list_amount = order_list:_get_ingredient_amount_in_order_list(crafter_info, ingredient)
            for k, v in pairs(order_list_amount) do
               in_order_list[k] = (in_order_list[k] or 0) + v
            end
         end
         missing = math.max(needed - math.max(in_storage + in_order_list.total - crafter_info:get_reserved_ingredients(ingredient_id), 0), 0)

         --log:debug('we need %d, have %d in storage, have %d in order list (%d of which are maintained), and %d reserved so we are missing %d (math is hard, right?)',
         --   needed, in_storage, in_order_list.total, in_order_list.maintain, crafter_info:get_reserved_ingredients(ingredient_id), missing)

         crafter_info:add_to_reserved_ingredients(ingredient_id, math.max(needed - in_order_list.maintain, 0))
      else -- condition.type == 'maintain'
         missing = ingredient.count

         --log:debug('maintaining the recipe requires %d of this ingredient, searching if it can be crafted itself', missing)
      end

      if missing > 0 then

         -- Step 2: Check if the ingredient can be produced through a different recipe:
         --            if it does, proceed to step 3;
         --            if not, continue on to the next ingredient.

         local player_jobs_controller = stonehearth.job:get_jobs_controller(player_id)
         local associated_order = player_jobs_controller:request_craft_product(
               ingredient.uri or ingredient.material, missing, building, false, condition.order_index ~= nil, condition, associated_orders)
         if associated_order and associated_order ~= true then
            -- Add the new order to the appropiate order list
            -- if the associated order had associated orders of its own, that's the table we use
            associated_orders = associated_order:get_associated_orders()
            if not associated_orders then
               associated_orders = {}
               associated_order:set_associated_orders(associated_orders)
               table.insert(associated_orders, {
                  order = associated_order,
                  ingredient_per_craft = missing,
               })
            end
         end
      end
   end

   local old_order_index
   if condition.type == 'maintain' and not condition.order_index then
      -- See if the order_list already contains a maintain order for the recipe:
      --    if it does, remake the order if its amount is lower than `missing`, otherwise ignore it;
      --    if it doesn't, simply add it as usual
      local order = self:_find_craft_order(recipe.recipe_name, 'maintain')
      if order then
         --log:debug('checking if maintain order "%s" is to be replaced', order:get_recipe().recipe_name)
         --log:detail('this is %sa recursive call, the order\'s value is %d and the new one is %d',
         --   is_recursive_call and 'NOT ' or '',
         --   order:get_condition().at_least,
         --   condition.at_least)

         if order:get_condition().at_least < tonumber(condition.at_least) then
            -- The order is to be replaced, so remove the current one so when the new one is added;
            -- there are no duplicates of the same recipe

            --log:debug('replacing the order with %d as its new amount', condition.at_least)

            -- Note: It would be preferable to change the order's `at_least` value directly instead, but
            --       I haven't found a way to accomplish that *and* have the ui update itself instantly

            old_order_index = self:find_index_of(order:get_id())
            self:remove_order(order:get_id())
         else
            log:debug('an order already exists which fulfills the request')
            return true
         end
      end
   end

   local result = self:insert_order(player_id, recipe, condition, old_order_index, building)

   -- if we got to this point, it's because we're auto-crafting dependencies
   result:set_auto_crafting(true)

   if associated_orders then
      for _, associated_order in ipairs(associated_orders) do
         if not associated_order.parent_order then
            associated_order.parent_order = result
         end
      end

      table.insert(associated_orders, {order = result})
      result:set_associated_orders(associated_orders)
   end

   return result
end

function AceCraftOrderList:insert_order(player_id, recipe, condition, maintain_order_index, building)
   self:_ace_old_add_order(player_id, recipe, condition)
   log:debug('inserted order for %d %s', condition.at_least or condition.amount, recipe.recipe_name)

   local order = self._sv.orders[#self._sv.orders]
   if building then
      order:set_building_id(building)
   end

	local old_order_index = condition.order_index or maintain_order_index
	if old_order_index and old_order_index < #self._sv.orders then
		-- Change the order of the recipe to what its predecessor had

		-- Note: We could call the function `change_order_position` for this one,
		--       but it uses an order's id to find its index in the table. And since
		--       we know that the newly created order is in the last index; it seems
		--       like a waste of resources to just do that sort of operation. So
		--       we just copy that function's body here with that change in mind.

		table.remove(self._sv.orders, #self._sv.orders)
		table.insert(self._sv.orders, old_order_index, order)

		self:_on_order_list_changed()
   end
   
   return order
end

-- this is used by the player_jobs_controller:request_craft_product
function AceCraftOrderList:request_order_of(player_id, recipe_info, produces, amount, building, insert_order, condition, associated_orders)
   log:debug('requesting order of %d %s (%s)', amount, recipe_info.recipe.product_uri, insert_order and 'inserting at top' or 'adding to bottom')
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
AceCraftOrderList._ace_old_delete_order_command = CraftOrderList.delete_order_command
function AceCraftOrderList:change_order_position_command(session, response, new, id)
   local i = self:find_index_of(id)
   if i then
      local order = self._sv.orders[i]
      table.remove(self._sv.orders, i)
      local next_index = #self._sv.orders + 1
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
            self._stuck_orders[self._sv.orders[j]:get_id()] = nil
         end
      elseif new < i and self._stuck_orders[id] then
         for j = new, i - 1 do
            if not self._stuck_orders[self._sv.orders[j]:get_id()] then
               self._stuck_orders[id] = nil
               break
            end
         end
      end

      table.insert(self._sv.orders, new, order)
      --TODO: comment out when you've fixed the drag/drop problem
      self:_on_order_list_changed()
      return true
   end
   return false
end

-- ACE: amount is an optional parameter that refers to the amount of primary products, not the quantity of recipes
-- e.g., if a recipe would produce 4 fence posts and you have 2 of the recipe queued, reducing by 1 alone would not change anything
function AceCraftOrderList:remove_order(order_id, amount, remove_associated)
   log:debug('remove_order(%s, %s)', order_id, tostring(amount))
   local i = self:find_index_of(order_id)
   if i then
      local order = self._sv.orders[i]
      if order and (not amount or not order:reduce_quantity(amount)) then
         table.remove(self._sv.orders, i)
         local order_id = order:get_id()

         self._orders_cache[order_id] = nil
         self._craftable_orders[order_id] = nil
         if self._stuck_orders[order_id] then
            self._stuck_orders[order_id] = nil
         end

         -- remove the order and its children from associated orders
         order:remove_associated_order(remove_associated ~= false)

         order:destroy()
      end
      
      self:_on_order_list_changed()
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
   local order_index = self:find_index_of(order_id)
   if order_index then
      local order = self._sv.orders[order_index]
      if order then
         if order:get_auto_crafting() then
            local condition = order:get_condition()

            local associated_orders = delete_associated_orders and order:get_associated_orders()
            if associated_orders then
               -- also remove any associated orders
               for _, associated_order in ipairs(associated_orders) do
                  if order_id ~= associated_order.order:get_id() then
                     associated_order.order:get_order_list():delete_order_command(session, response, associated_order.order:get_id())
                  end
               end
            end
         end
      end
   end

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
   local crafter_info = stonehearth_ace.crafter_info:get_crafter_info(player_id)
   for _, ingredient in pairs(ingredients) do
      local in_order_list = self:_get_ingredient_amount_in_order_list(crafter_info, ingredient, order_id)
      local ingredient_id = ingredient.uri or ingredient.material
      local amount = math.max(ingredient.count * multiple - in_order_list.maintain, 0)

      crafter_info:remove_from_reserved_ingredients(ingredient_id, amount)
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
function AceCraftOrderList:_get_ingredient_amount_in_order_list(crafter_info, ingredient, to_order_id)
   local ingredient_count = {
      make = 0,
      maintain = 0,
      total = 0,
   }

   for i, order in ipairs(self._sv.orders) do
      if not to_order_id or order:get_id() < to_order_id then
         local recipe = crafter_info:get_formatted_recipe(order:get_recipe())

         if recipe then
            local condition = order:get_condition()

            local material_produces = ingredient.material and self:_recipe_produces_materials(recipe, ingredient.material)
            local uri_produces = ingredient.uri and recipe.products[ingredient.uri]
            local num_produces = material_produces or uri_produces

            if num_produces then
               local amount
               if condition.type == 'make' then
                  amount = condition.remaining * num_produces
               else
                  amount = math.max(num_produces, condition.at_least)
               end
               ingredient_count[condition.type] = ingredient_count[condition.type] + amount
            end
         end
      end
   end

   ingredient_count.total = ingredient_count.make + ingredient_count.maintain
   return ingredient_count
end


function AceCraftOrderList:_recipe_produces_materials(recipe, material)
   return util.sum_where_all_keys_present(recipe.product_materials, recipe.products, material)
end

-- Gets the craft order which matches `recipe_name`, if an `order_type`
-- is defined, then it will also check for a match against it.
-- Returns nil if no match was found.
--
function AceCraftOrderList:_find_craft_order(recipe_name, order_type)
   --log:debug('finding a recipe for "%s"', recipe_name)
   --log:debug('There are %d orders', radiant.size(self._sv.orders) - 1)

   for i, order in ipairs(self._sv.orders) do
      local order_recipe_name = order:get_recipe().recipe_name
      --log:debug('evaluating order with recipe "%s"', order_recipe_name)

      if order_recipe_name == recipe_name and (not order_type or order:get_condition().type == order_type) then
         return order
      end
   end

   return nil
end

-- overrides this base function in order to support multiple crafters on the same order
function AceCraftOrderList:get_next_order(crafter)
   --log:debug('craft_order_list: There are %s orders', #self._sv.orders)
   local count = 0
   --log:debug('trying to feed order to %s', crafter)
   for i, order in ipairs(self._sv.orders) do
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

   -- Note: don't clear the stuck_orders table in _on_inventory_changed, since the inventory changes when the crafter drops the leftovers
   -- so the same order would be picked again and again
   if count > 0 and self:has_stuck_orders() then
      -- Only refresh the list if there are still orders in it, and some/all of them were tagged as stuck
      self._stuck_orders = {}
      -- Now set a timer to make the crafter reconsider the orders. It has to be done after a while because of a race
      -- We now wait for the thread to be suspended, so that this event will make it resume safely
      -- Otherwise there can be problems with multiple crafters or depending on whether the last order was stuck or not
      if not self._stuck_timer then
         self._stuck_timer = stonehearth.calendar:set_timer("reconsider stuck orders", constants.crafting.RECONSIDER_ORDERS_COOLDOWN,
                             function() radiant.events.trigger(self, 'stonehearth:order_list_changed') end)
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

return AceCraftOrderList
