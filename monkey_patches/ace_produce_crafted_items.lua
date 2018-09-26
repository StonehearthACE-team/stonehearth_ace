local AceProduceCraftedItems = radiant.class()

-- Paul: only changed two lines to pass the crafter along to the order when getting/setting progress
function AceProduceCraftedItems:run(ai, entity, args)
   self._outputs = {}
   local order_progress = args.order:get_progress(entity)   -- Paul: changed this line

   if order_progress == stonehearth.constants.crafting_status.CRAFTING then
      self:_destroy_ingredients(args)
      self:_add_outputs_to_bench(entity, args.workshop, args.order:get_recipe())

      args.order:on_item_created()
      args.order:progress_to_next_stage(entity)  -- Paul: changed this line
   -- if this order is done crafting, but we re-entered this action, we may have gotten interrupted
   -- before the crafter was able to drop off the item, so do now if the crafted item is on the table
   elseif order_progress > stonehearth.constants.crafting_status.CRAFTING then
      local ec = args.workshop:get_component('entity_container')
      if ec and ec:num_children() > 0 then
         for _, item_on_workshop in ec:each_child() do
            table.insert(self._outputs, item_on_workshop)
         end
      end
   end

   --then, pick up every item that was crafted and put it into the crafter's ingredient pouch
   for i, item in ipairs(self._outputs) do
      assert(not radiant.entities.is_carrying(entity))
      if args.workshop:get_uri() == 'stonehearth:crafter:temporary_workbench' then
         ai:execute('stonehearth:pickup_item_adjacent', { item = item })
      else
         ai:execute('stonehearth:pickup_item_on_table_adjacent', { item = item })
      end
      local crafter_component = entity:get_component('stonehearth:crafter')
      if crafter_component then
         -- If Crafter stopped being a crafter while picking up produced products.
         -- Too bad. All the stuff will be stuck on the bench. -yshan

         crafter_component:add_carrying_to_crafting_items()
         radiant.log.write('crafter', 5, 'Putting %s with id %s ubti crafter pack', item, item:get_id())
      end
   end

   local appeal_component = entity:get_component('stonehearth:appeal')
   if appeal_component then
      appeal_component:add_crafting_appeal_thought()
   end
   
   args.workshop:get_component('stonehearth:workshop'):finish_crafting_progress()
end

return AceProduceCraftedItems
