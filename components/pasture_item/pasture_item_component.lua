local PastureItemComponent = class()

function PastureItemComponent:initialize()
   self._sv.trough_feed_uri = nil
   self._sv.num_feed = 0
   self._json = radiant.entities.get_json(self)
   self._type = self._json.type
end

function PastureItemComponent:restore()
   -- Register if we are placed in the world in our root form
   local entity_forms_component = self._entity:get_component('stonehearth:entity_forms')
   self._is_placed = not entity_forms_component or entity_forms_component:is_root_form_in_world()
end

function PastureItemComponent:post_activate()
   self._parent_trace = self._entity:get_component('mob'):trace_parent('pasture item added or removed')
      :on_changed(function(parent_entity)
         if parent_entity then
            self:_register_with_town(true)
         else
            self:_register_with_town(false)
         end
      end)
   if self._is_placed then
      self:_register_with_town(true)
   end
end

function PastureItemComponent:destroy()
   self:_register_with_town(false)
   self:_destroy_traces()
end

function PastureItemComponent:_destroy_traces()
   if self._parent_trace then
      self._parent_trace:destroy()
      self._parent_trace = nil
   end
end

function PastureItemComponent:_register_with_town(register)
   local player_id = radiant.entities.get_player_id(self._entity)
   local town = stonehearth.town:get_town(player_id)
   if town then
      self._is_placed = register
      if register then
         town:register_pasture_item(self._entity, self._type)
      else
         town:unregister_pasture_item(self._entity)
      end
   end
end

function PastureItemComponent:is_empty()
   return self._sv.num_feed < 1
end

function PastureItemComponent:eat_from_trough(animal)
   local num_feed = self._sv.num_feed
   if num_feed > 0 then
      local feed_uri = self._sv.trough_feed_uri
      local quality = self._sv._feed_quality

      num_feed = num_feed - 1
      self._sv.num_feed = num_feed
      if num_feed < 1 then
         self._sv.trough_feed_uri = nil
         self._sv._feed_quality = nil
         self:_signal_empty_status_changed(true)
      end
      self.__saved_variables:mark_changed()

      return feed_uri, quality
   else
      return false
   end
end

function PastureItemComponent:set_trough_feed(feed)
   local feed_uri = feed:get_uri()
   self._sv.trough_feed_uri = feed_uri
   self._sv._feed_quality = radiant.entities.get_item_quality(feed)

   local stacks = radiant.entities.get_component_data(feed_uri .. ':ground', 'stonehearth:stacks')
   self._sv.num_feed = stacks and stacks.max_stacks or 1
   
   self.__saved_variables:mark_changed()

   self:_signal_empty_status_changed(false)
end

function PastureItemComponent:_signal_empty_status_changed(empty_status)
   radiant.events.trigger(self._entity, 'stonehearth_ace:trough:empty_status_changed', empty_status)
end

return PastureItemComponent