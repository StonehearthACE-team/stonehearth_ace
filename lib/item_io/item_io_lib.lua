local log = radiant.log.create_logger('item_io_lib')

local item_io_lib = {}

function item_io_lib._rank_inputs(inputs)
   local ranked_inputs = {}
   for _, input in pairs(inputs or {}) do
      local input_comp = input:is_valid() and input:get_component('stonehearth_ace:input')
      if input_comp then
         table.insert(ranked_inputs, input_comp)
      end
   end

   -- sort the inputs by priority
   if #ranked_inputs > 0 then
      table.sort(ranked_inputs, function(a, b)
         return a:get_priority() > b:get_priority()
      end)
   end

   return ranked_inputs
end

function item_io_lib.try_output(items, inputs, options)
   local spills = {}
   local successes = {}
   local fails = {}
   options = options or {}
   local location = options.location
   local add_spilled_to_inventory = options.add_spilled_to_inventory

   local ranked_inputs = item_io_lib._rank_inputs(inputs)
   item_io_lib._output_to_inputs(items, ranked_inputs, successes, fails)
   
   local prev_outputs = {}
   local output = options.output
   while output do
      -- don't need to (continue) process(ing) through outputs if there are no (more) fails
      if not next(fails) then
         break
      end
      if prev_outputs[output] then
         break
      end
      local output_comp = output:get_component('stonehearth_ace:output')
      if not output_comp then
         break
      end

      prev_outputs[output] = true

      ranked_inputs = item_io_lib._rank_inputs(output_comp:get_inputs())
      if #ranked_inputs > 0 then
         items = fails
         fails = {}
         item_io_lib._output_to_inputs(items, ranked_inputs, successes, fails, location, options.force_add, options.require_matching_filter_override)
      end
      
      output = output_comp:get_parent_output()
   end

   if options.spill_fail_items then
      local origin = options.spill_origin
      local min_radius = options.spill_min_radius
      local max_radius = options.spill_max_radius

      for id, item in pairs(fails) do
         local location = radiant.terrain.find_placement_point(origin, min_radius, max_radius, nil, nil, options.require_reachable)
         radiant.terrain.place_entity(item, location)
         spills[id] = item
         fails[id] = nil
         
         -- in case something else "catches" these items and does something with them,
         -- check that they're actually in the world
         if add_spilled_to_inventory then
            local inventory = stonehearth.inventory:get_inventory(item)
            if inventory then
               inventory:add_item_if_not_full(item)
            end
         end
      end
   elseif options.delete_fail_items ~= false then  -- do this unless otherwise specified so we don't have entities in the void
      for id, item in pairs(fails) do
         radiant.entities.destroy_entity(item)
         fails[id] = nil
      end
   end

   return {
      spilled = spills,
      succeeded = successes,
      failed = fails
   }
end

function item_io_lib._output_to_inputs(items, inputs, successes, fails, location, force_add, require_matching_filter_override)
   for id, item in pairs(items) do
      -- check to make sure the item actually *should* be addable to a storage: it's an item or has an iconic version
      local catalog_data = stonehearth.catalog:get_catalog_data(item:get_uri())
      if catalog_data and (catalog_data.is_item or catalog_data.iconic_uri) then
         for _, input in ipairs(inputs) do
            log:debug('trying to output %s to %s (%s, %s)', item, input, tostring(force_add), tostring(require_matching_filter_override))
            if input:try_input(item, location, force_add, require_matching_filter_override) then
               successes[id] = item
               break
            end
         end
      end

      if not successes[id] then
         fails[id] = item
      end
   end
end

-- determines if items simply *can* be output to their respective destinations
-- ignores spill settings, because if spill is allowed then of course the items can be output
-- if reservations obtained for all items, returns function to perform the output
-- otherwise, destroys any successful reservations and returns false
function item_io_lib.can_output(items, inputs, options)
   local successes = {}
   local fails = {}
   options = options or {}
   local location = options.location

   local ranked_inputs = item_io_lib._rank_inputs(inputs)
   item_io_lib._can_output_to_inputs(items, ranked_inputs, successes, fails, location, options.require_matching_filter_override)
   
   local prev_outputs = {}
   local output = options.output
   while output do
      -- don't need to (continue) process(ing) through outputs if there are no (more) fails
      if not next(fails) then
         break
      end
      if prev_outputs[output] then
         break
      end
      local output_comp = output:get_component('stonehearth_ace:output')
      if not output_comp then
         break
      end

      prev_outputs[output] = true

      ranked_inputs = item_io_lib._rank_inputs(output_comp:get_inputs())
      if #ranked_inputs > 0 then
         items = fails
         fails = {}
         item_io_lib._can_output_to_inputs(items, ranked_inputs, successes, fails, location, options.require_matching_filter_override)
      end
      
      output = output_comp:get_parent_output()
   end

   if next(fails) then
      -- release all reserved spaces
      for id, reservation in pairs(successes) do
         reservation.destroy()
      end
      return false
   end

   return function()
      --log:debug('trying to output %s', radiant.util.table_tostring(items))
      for id, success in pairs(successes) do
         success.output()
      end
   end
end

function item_io_lib._can_output_to_inputs(items, inputs, successes, fails, location, require_matching_filter_override)
   for id, item in pairs(items) do
      -- check to make sure the item actually *should* be addable to a storage: it's an item or has an iconic version
      local catalog_data = stonehearth.catalog:get_catalog_data(item:get_uri())
      if catalog_data and (catalog_data.is_item or catalog_data.iconic_uri) then
         for _, input in ipairs(inputs) do
            local result = input:can_input(item, location)
            if result then
               successes[id] = {
                  destroy = result.destroy,
                  output = function()
                     --log:debug('trying to push %s into %s', item, input._entity)
                     -- first destroy the space reservation
                     result.destroy()
                     -- then force input the item
                     input:try_input(item, location, true, require_matching_filter_override)
                  end
               }
               break
            end
         end
      end

      if not successes[id] then
         fails[id] = item
      end
   end
end

return item_io_lib
