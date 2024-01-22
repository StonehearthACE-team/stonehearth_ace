local Point3 = _radiant.csg.Point3
local crafting_lib = require 'stonehearth_ace.lib.crafting.crafting_lib'

local AceProduceCraftedItems = radiant.class()

-- Paul: pass the crafter along to the order when getting/setting progress, added fuel consumption
function AceProduceCraftedItems:run(ai, entity, args)
   local outputs = {}
   local order_progress = args.order:get_progress(entity)   -- Paul: changed this line

   if order_progress == stonehearth.constants.crafting_status.CRAFTING then
      -- if fuel was involved, consume it
      local consumer_comp = args.workshop:get_component('stonehearth_ace:consumer')
      if consumer_comp then
         consumer_comp:consume_fuel(entity)
      end

      -- don't fully destroy the ingredients yet, we want to be able to pass them to other scripts
      local ingredients, ingredient_quality = crafting_lib.get_ingredients_and_quality(args.workshop)
      local primary_output, all_outputs = crafting_lib.craft_items(ai, entity, args.workshop, args.order:get_recipe(), ingredients, ingredient_quality)
      crafting_lib.destroy_ingredients(ingredients)
      outputs = all_outputs

      args.workshop:get_component('stonehearth:workshop'):destroy_working_ingredient()

      args.order:on_item_created(primary_output)
      args.order:progress_to_next_stage(entity)  -- Paul: changed this line
   -- if this order is done crafting, but we re-entered this action, we may have gotten interrupted
   -- before the crafter was able to drop off the item, so do now if the crafted item is on the table
   elseif order_progress > stonehearth.constants.crafting_status.CRAFTING then
      local ec = args.workshop:get_component('entity_container')
      if ec and ec:num_children() > 0 then
         for id, item_on_workshop in ec:each_child() do
            outputs[id] = item_on_workshop
         end
      end
   end

   --then, pick up every item that was crafted and put it into the crafter's ingredient pouch
   for id, item in pairs(outputs) do
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
         radiant.log.write('crafter', 5, 'Putting %s with id %s into crafter pack', item, item:get_id())
      end
   end

   local appeal_component = entity:get_component('stonehearth:appeal')
   if appeal_component then
      appeal_component:add_crafting_appeal_thought()
   end
   
   args.workshop:get_component('stonehearth:workshop'):finish_crafting_progress()
end

return AceProduceCraftedItems
