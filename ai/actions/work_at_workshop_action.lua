-- ACE overrides in order to do an available_for_work check on the workshop for fuel reservation

local CraftOrder = require 'stonehearth.components.workshop.craft_order'
local Entity = _radiant.om.Entity

local WorkAtWorkshop = radiant.class()

--This action runs if we have a specific workshop in mind (due to save/load or proxy workshop)
--The action assumes all recipe ingredients are already in the crafter's backpack
--or actively on the workshop. This action has us go to the workshop,
--produce the recipe outputs, and puts them in the backpack.

WorkAtWorkshop.name = 'work at current workshop'
WorkAtWorkshop.does = 'stonehearth:craft_item'
WorkAtWorkshop.args = {
   workshop_type = {
      type = 'string',
      default = stonehearth.ai.NIL
   },
   proxy_workshop = {
      type = Entity,
      default = stonehearth.ai.NIL
   },
   craft_order = CraftOrder,
   ingredients = 'table',
   item_name = 'string'
}
WorkAtWorkshop.priority = 0

function WorkAtWorkshop:start_thinking(ai, entity, args)
   local workshop
   
   if args.proxy_workshop then
      workshop = args.proxy_workshop
   else
      -- Use workshop currently assigned to crafter if no proxy workshop
      local crafter_component = entity:get_component('stonehearth:crafter')
      if crafter_component then
         local curr_workshop = crafter_component:get_current_workshop()
         if radiant.entities.exists(curr_workshop) then
            workshop = curr_workshop
         end
      end
   end

   if workshop then
      local workshop_comp = workshop:get_component('stonehearth:workshop')
      if workshop_comp and workshop_comp:available_for_work(entity) then
         ai:set_think_output({
            workshop = workshop
         })
         return
      end
   end

   -- TODO: Wait for a workshop?
   ai:set_debug_progress('dead: got no workshop')
end

function WorkAtWorkshop:start(ai, entity, args)
   ai:set_status_text_key('stonehearth:ai.actions.status_text.work_at_workshop', { craftable_name = args.item_name })
end

local ai = stonehearth.ai
return ai:create_compound_action(WorkAtWorkshop)
            :execute('stonehearth:drop_backpack_contents_on_ground')
            :execute('stonehearth:goto_entity', {
               entity = ai.BACK(2).workshop
            })
            :execute('stonehearth:drop_crafting_ingredients', {
               target = ai.BACK(3).workshop,
            })
            :execute('stonehearth:run_crafting_effect', {
               order = ai.ARGS.craft_order,
               workshop = ai.BACK(4).workshop,
            })
            :execute('stonehearth:produce_crafted_items', {
               order = ai.ARGS.craft_order,
               workshop = ai.BACK(5).workshop,
            })
