local IngredientList = require 'stonehearth.components.workshop.ingredient_list'
local root_entity = radiant.entities.get_root_entity()
--Given an ingredient, find the ingredient in the world and put it in the crafter's
--special ingredients backpack. Then check the ingredient off the list.

local CollectIngredient = radiant.class()
CollectIngredient.name = 'collect ingredient'
CollectIngredient.status_text_key = 'stonehearth:ai.actions.status_text.collect_ingredient'
CollectIngredient.does = 'stonehearth:collect_ingredient'
CollectIngredient.args = {
   ingredient = 'table',                  -- what to get
   ingredient_list = IngredientList,      -- the tracking list

   rating_fn = {                       -- a function to rate entities on a 0-1 scale to determine the best.
      type = 'function',
      default = stonehearth.ai.NIL,
   },
}
CollectIngredient.priority = 0

function CollectIngredient:start_thinking(ai, entity, args)

   -- Constant state
   self._ai = ai
   self._entity = entity

   -- Notify the crafter component so that it starts a timer that we can use to stop looking after a while
   radiant.events.trigger_async(self._entity, 'stonehearth:entity:started_looking_for_ingredients', {ingredient = args.ingredient})
   if not self._abort_listener then
      self._abort_listener = radiant.events.listen(self._entity, 'stonehearth:entity:abort_looking_for_ingredients', self, self._stop_searching)
   end

   self._ai:set_think_output({})
end

function CollectIngredient:stop_thinking(ai, entity, args)
   self:_clean_up_listener()
end

function CollectIngredient:stop(ai, entity, args)
   self:_clean_up_listener()
   -- Ingredient was either collected or not found. Tell the crafter component to stop the current timer
   radiant.events.trigger_async(self._entity, 'stonehearth:stop_missing_ingredient_timer', {ingredient = args.ingredient})
end

function CollectIngredient:_clean_up_listener()
   if self._abort_listener then
      self._abort_listener:destroy()
      self._abort_listener = nil
   end
end

-- We've been searching for a path to the current ingredient for a while
function CollectIngredient:_stop_searching(ingredient)
   -- We were mounted in a bed or chair, or talking to someone. Don't reset the current order, keep trying.
   -- We can't guard against other hearthling keeping the ingredient on their backpack (for restocking, sleeping, etc)
   -- So we might still abort when we shouldn't
   local parent = radiant.entities.get_parent(self._entity)
   local conv_target = self._entity:get_component('stonehearth:conversation'):get_target()
   if parent == root_entity and conv_target == nil then
      -- Notify the craft items orchestrator to mark the order as stuck, reset it and try with the next one
      radiant.events.trigger_async(self._entity, 'stonehearth:entity:stopped_looking_for_ingredients', {ingredient = ingredient})
      -- Notify crafter component to stop the current timer
      radiant.events.trigger_async(self._entity, 'stonehearth:stop_missing_ingredient_timer', {ingredient = ingredient})
      -- Stop collecting the ingredient
      self._ai:clear_think_output()
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(CollectIngredient)
               :execute('stonehearth:drop_carrying_now')
               :execute('stonehearth:pickup_ingredient', {
                  ingredient = ai.ARGS.ingredient,
                  rating_fn = ai.ARGS.rating_fn
               })
               :execute('stonehearth:call_method', {
                  obj = ai.ENTITY:get_component('stonehearth:crafter'),
                  method = 'add_carrying_to_crafting_items',
                  args = {}
               })
               :execute('stonehearth:call_method', {
                  obj = ai.ARGS.ingredient_list,
                  method = 'check_off_ingredient',
                  args = { ai.ARGS.ingredient }
               })
