-- ACE: have to override to give a new rater function

local FillInputBin = radiant.class()

FillInputBin.name = 'fill input bin'
FillInputBin.does = 'stonehearth:fill_input_bin'
FillInputBin.args = {
   storage_filter_key = 'string'  -- the material filter key for the bin, a string of "+" separated material tags
}
FillInputBin.priority = {0, 1}

local function make_input_bin_predicate(player_id, storage_filter_key)
   local get_player_id = radiant.entities.get_player_id
   local exists = radiant.entities.exists
   return stonehearth.ai:filter_from_key('is_input_bin', storage_filter_key .. player_id, function(entity)
         if not exists(entity) then
            return false
         end

         if get_player_id(entity) ~= player_id then
            return false
         end

         local storage = entity:get_component('stonehearth:storage')
         if not storage or storage:is_full() or storage:get_type() ~= 'input_crate' then
            return false
         end

         return storage_filter_key == storage:get_filter_key()
      end)
end

local function rate_input_bin(entity)
   local bounds = stonehearth.constants.inventory.input_bins
   local priority_range = bounds.MAX_PRIORITY - bounds.MIN_PRIORITY
   local storage = entity:get_component('stonehearth:storage')
   
   return math.min(1, 1 - storage:num_items() / storage:get_capacity()) / (priority_range + 1) + storage:get_input_bin_priority()
end


local function make_item_for_bin_predicate(player_id, bin)
   if not radiant.entities.exists(bin) then
      return stonehearth.ai:filter_from_key('item_for_input_bin', 'none', function(item)
         return false
      end)
   end

   local storage = bin:get_component('stonehearth:storage')
   local content_valid_function = storage:get_filter_function()
   local inventory = stonehearth.inventory:get_inventory(player_id)
   local exists = radiant.entities.exists
   local priority = storage:get_input_bin_priority()
   return stonehearth.ai:filter_from_key('item_for_input_bin', player_id .. ';' .. priority .. ';' .. storage:get_filter_key(), function(item)
      if not exists(item) then  -- TODO: Why is this even happening?
         return false
      end

      local source = inventory:container_for(item)
      if source then
         local source_storage = source:get_component('stonehearth:storage')
         if source_storage:get_type() == 'input_crate' and source_storage:get_input_bin_priority() >= priority then
            -- if the filter was changed/removed, we do want to move its items to other input bins
            if source_storage:passes(item) then
               return false
            end
         end
      end

      return content_valid_function(item)
   end)
end

function FillInputBin:start_thinking(ai, entity, args)
   ai:set_think_output({ owner_player_id = radiant.entities.get_work_player_id(entity) })
end

function FillInputBin:compose_utility(entity, self_utility, child_utilities, current_activity)
   return child_utilities:get('stonehearth:find_best_reachable_entity_by_type')
end

local function get_item_location(item, deflt)
   -- return either the location of the item or `deflt`.  sometimes the item in question isn't
   -- in the world (e.g. when the first item we found happened to be in the backpack)
   return radiant.entities.get_world_grid_location(item) or deflt
end

local ai = stonehearth.ai
return ai:create_compound_action(FillInputBin)
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth:work_order:haul:work_player_id_changed',
         })
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.CALL(make_input_bin_predicate, ai.BACK(2).owner_player_id, ai.ARGS.storage_filter_key),
            rating_fn = rate_input_bin,
            description = 'search for an input bin to refill',
         })
         :execute('stonehearth:reserve_storage_space', {
            storage = ai.PREV.item,
         })
         :execute('stonehearth:put_restockable_item_into_backpack', {
            filter_fn = ai.CALL(make_item_for_bin_predicate, ai.BACK(4).owner_player_id, ai.BACK(2).item),
            filter_key = 'unused',
            storage = ai.BACK(2).item,
            restockable_only = false,
            owner_player_id = ai.BACK(4).owner_player_id,
         })
         :execute('stonehearth:get_nearby_items', {
            range = 16,
            location = ai.CALL(get_item_location, ai.PREV.item, ai.CURRENT.location),
            filter_fn = ai.CALL(make_item_for_bin_predicate, ai.BACK(5).owner_player_id, ai.BACK(3).item),
         })
         :execute('stonehearth:fill_backpack_from_items', {
            candidates = ai.PREV.items,
            range = 32,
            storage = ai.BACK(4).item,
            owner_player_id = ai.BACK(6).owner_player_id,
            reserve_space = true,
         })
         :execute('stonehearth:fill_storage_from_backpack', {
            filter_fn = ai.CALL(make_item_for_bin_predicate, ai.BACK(7).owner_player_id, ai.BACK(5).item),
            storage = ai.BACK(5).item,
            owner_player_id = ai.BACK(7).owner_player_id,
         })
