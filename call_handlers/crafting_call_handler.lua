local validator = radiant.validator
local CraftingCallHandler = class()

function CraftingCallHandler:modify_order_amount(session, response, job_alias, order_id, amount)
   validator.expect_argument_types({'string', 'number', 'number'}, job_alias, order_id, amount)

   local job_info = stonehearth.job:get_job_info(session.player_id, job_alias)
   local order_list = job_info and job_info:get_order_list()

   if order_list then
      local order = order_list:get_order(order_id)
      if order and order:change_quantity(amount) then
         order_list:_on_order_list_changed()
         if order:is_auto_craft_recipe() then
            order_list:_on_auto_craft_orders_changed()
         end
         return true
      end
   end
end

function CraftingCallHandler:toggle_order_list_priority(session, response, job_alias, order_id)
   validator.expect_argument_types({'string', 'number'}, job_alias, order_id)

   local job_info = stonehearth.job:get_job_info(session.player_id, job_alias)
   local order_list = job_info and job_info:get_order_list()

   if order_list then
      order_list:toggle_order_priority(order_id)
      return true
   end
end

function CraftingCallHandler:toggle_secondary_order_list_pause(session, response, job_alias)
   validator.expect_argument_types({'string'}, job_alias)

   local job_info = stonehearth.job:get_job_info(session.player_id, job_alias)
   local order_list = job_info and job_info:get_order_list()

   if order_list and order_list.toggle_secondary_list_pause then
      order_list:toggle_secondary_list_pause()
      return true
   end
end

return CraftingCallHandler
