local CraftOrder = radiant.mods.require('stonehearth.components.workshop.craft_order')
local log = radiant.log.create_logger('craft_order')

local AceCraftOrder = class()

AceCraftOrder._ace_old_on_item_created = CraftOrder.on_item_created
-- In addition to the original on_item_created function (from craft_order.lua),
-- here it's also removing the ingredients tied to the order made from
-- the reserved ingredients.
--
function AceCraftOrder:on_item_created()
   if self._sv.condition.type == 'make' then
      self._sv.order_list:remove_from_reserved_ingredients(self._recipe.ingredients, self._sv.id, self._sv.player_id)
   end
   
   self:_ace_old_on_item_created()
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

-- AceCraftOrder._ace_old_has_ingredients = CraftOrder.has_ingredients
-- function AceCraftOrder:has_ingredients()
--    local result = self:_ace_old_has_ingredients()
   
--    -- only bother checking fuel requirements if we have all the other ingredients
--    if result then
--       local fuel_required = self._sv.condition.fuel_requirement
--       if fuel_required then

--          local tracking_data = self._inventory:get_item_tracker('stonehearth_ace:fuel_tracker'):get_tracking_data()
         
         
--       end
--    end

--    return result
-- end

function CraftOrder:is_missing_ingredient(ingredients)
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

-- override this to consider stacks for items
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

   if ingredient.min_stacks then
      local count = 0
      for id, item in pairs(tracking_data_for_key.items) do
         local stacks_comp = item:get_component('stonehearth:stacks')
         if stacks_comp then
            count = count + stacks_comp:get_stacks()
         end
      end
      return count >= ingredient.min_stacks
   end
   
   return tracking_data_for_key.count >= ingredient.count
end

--[[
   Used to determine if we should proceed with executing the order.
   If this order has a condition which are unsatisfied, (ie, less than x amount
   was built, or less than x inventory exists in the world) return true.
   If this order's conditions are met, and we don't need to execute this
   order, return false.
   returns: true if conditions are not yet met, false if conditions are met
]]
function CraftOrder:should_execute_order(crafter)
   --If the crafter is not appropriately leveled, return false
   local job_level = crafter:get_component('stonehearth:job'):get_current_job_level()
   if job_level and self._recipe.level_requirement and
      job_level < self._recipe.level_requirement then
      log:detail('craft_order: cannot execute order with recipe %s, crafter %s does not meet requriements', self._recipe.recipe_name, crafter)
      return false
   end

   --If a workshop is required and there is no placed workshop, return false
   if self._recipe.workshop then
      local workshop_data = self._inventory:get_items_of_type(self._recipe.workshop.uri)
      local workshop_entity_data
      
      if not workshop_data or workshop_data.count < 1 then
         -- Not an exact match. Maybe a valid equivalent?
         workshop_entity_data = radiant.entities.get_entity_data(self._recipe.workshop.uri, 'stonehearth:workshop')
         if workshop_entity_data then
            local equivalents = workshop_entity_data.equivalents
            if equivalents then
               for _, equivalent in ipairs(equivalents) do
                  workshop_data = self._inventory:get_items_of_type(equivalent)
                  if workshop_data and workshop_data.count > 0 then
                     break
                  end
               end
            end
         end
      end

      if not workshop_data or workshop_data.count < 1 then
         log:detail('craft_order: cannot execute order with recipe %s, no workshops of appropriate type: %s',
                    tostring(self._recipe.recipe_name), tostring(self._recipe.workshop.uri))
         return false
      end

      -- if this workshop uses fuel, we need to check if any of these workshops actually have fuel available
      if workshop_entity_data and workshop_entity_data.fuel_settings and workshop_entity_data.fuel_settings.uses_fuel then
         local found_workshop = false
         for _, workshop in pairs(workshop_data.items) do
            local workshop_comp = workshop:get_component('stonehearth:workshop')
            if workshop_comp then
               if workshop_comp:reserve_fuel(crafter) then
                  found_workshop = true
                  break
               end
            end
         end

         if not found_workshop then
            log:detail('craft_order: cannot execute order with recipe %s, no workshops with available fuel for crafter %s',
                       self._recipe.recipe_name, crafter)
            return false
         end
      end
   end

   -- If crafter is incapacitated, return false
   local incapacitation = crafter:get_component('stonehearth:incapacitation')
   if incapacitation and incapacitation:is_incapacitated() then
      log:detail('craft order: cannot execute order with recipe %s, crafter %s is incapacitated', self._recipe.recipe_name, crafter)
      return false
   end

   log:detail('returning true from should_execute_order')
   return true
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
   --self.__saved_variables:mark_changed()
end

function AceCraftOrder:get_associated_orders()
   return self._sv._associated_orders
end

function AceCraftOrder:set_associated_orders(associated_orders)
   self._sv._associated_orders = associated_orders
   --self.__saved_variables:mark_changed()
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

-- returns true if it successfully reduced the quantity to craft from a 'make' order
-- returns false if the number remaining to make was less than or equal to the amount to reduce
-- returns nil otherwise, e.g., if it's a 'maintain' order
function AceCraftOrder:reduce_quantity(amount)
   local condition = self._sv.condition
   if condition.type == 'make' then
      if condition.remaining > amount then
         condition.remaining = condition.remaining - amount
         self.__saved_variables:mark_changed()
         return true
      else
         return false
      end
   end
end

return AceCraftOrder
