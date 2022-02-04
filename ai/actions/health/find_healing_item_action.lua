local Entity = _radiant.om.Entity
local healing_lib = require 'stonehearth_ace.ai.lib.healing_lib'

local FindHealingItem = radiant.class()
FindHealingItem.name = 'find healing item'
FindHealingItem.does = 'stonehearth_ace:find_healing_item'
FindHealingItem.args = {
   target = Entity,     -- the target needing healing
}
FindHealingItem.think_output = {
   item = Entity,       -- the healing item
}
FindHealingItem.priority = 0

function FindHealingItem:start_thinking(ai, entity, args)
   self._ai = ai
   self._entity = entity
   self._target = args.target
   self._ready = false
   self._inventory = stonehearth.inventory:get_inventory(radiant.entities.get_player_id(entity))

   if self._inventory then
      local job = entity:get_component('stonehearth:job')
      self._level = job:get_current_job_level()
      self._conditions = healing_lib.get_conditions_needing_cure(self._target)

      self._tracker = self._inventory:add_item_tracker('stonehearth_ace:healing_item_tracker')
      self:_check_all_tracker_items()
      self._added_listener = radiant.events.listen(self._tracker, 'stonehearth:inventory_tracker:item_added', self, self._on_healing_item_added)
      self._level_changed_listener = radiant.events.listen(self._entity, 'stonehearth:level_up', self, self._on_level_up)
   end
end

function FindHealingItem:_on_level_up()
   self:_check_all_tracker_items()
end

function FindHealingItem:_check_all_tracker_items()
   local guts, health = healing_lib.get_filter_guts_health_missing(self._target)
   self._items = {}
   for id, item in self._tracker:get_tracking_data():each() do
      if item and item:is_valid() then
         self:_check_healing_item(item, guts, health)
      end
   end

   self:_check_ready()
end

function FindHealingItem:_on_healing_item_added(e)
   local id = e.key
   if id then
      local tracking_data = self._tracker:get_tracking_data()
      local item = tracking_data:contains(id) and tracking_data:get(id)
      if item and item:is_valid() then
         self:_check_healing_item(item)
         self:_check_ready()
      end
   end
end

function FindHealingItem:_check_healing_item(item, guts, health)
   if not self._ready then
      if not guts or not health then
         guts, health = healing_lib.get_filter_guts_health_missing(self._target)
      end
      if not healing_lib.filter_healing_item(item, self._conditions, self._level, guts, health) then
         return
      end

      if not stonehearth.ai:can_acquire_ai_lease(item, self._entity) then
         return
      end

      table.insert(self._items, item)
   end
end

function FindHealingItem:_check_ready()
   if not self._ready and #self._items > 0 then
      self._ready = true

      -- pick the best item from the list
      local rater = healing_lib.make_healing_rater(self._entity, self._target)
      local best_item, best_rating
      for _, item in ipairs(self._items) do
         local rating = rater(item)
         if not best_rating or rating > best_rating then
            best_item, best_rating = item, rating
         end
      end

      self._ai:set_think_output({
         item = best_item,
      })
   end
end

function FindHealingItem:stop_thinking(ai, entity)
   self:destroy()
end

function FindHealingItem:destroy()
   if self._added_listener then
      self._added_listener:destroy()
      self._added_listener = nil
   end

   if self._level_changed_listener then
      self._level_changed_listener:destroy()
      self._level_changed_listener = nil
   end
end

return FindHealingItem
