local PastureItemComponent = class()

local log = radiant.log.create_logger('pasture_item')
local RESTOCK_ACTION = 'stonehearth_ace:feed_pasture_trough'

local function make_feed_filter_fn(material, owner)
   return function(item)
         if not radiant.entities.is_material(item, material) then
            -- not the right material?  bail.
            return false
         end
         if owner ~= '' and radiant.entities.get_player_id(item) ~= owner then
            -- not owned by the right person?  also bail!
            return false
         end
         return true
      end
end

function PastureItemComponent:initialize()
   self._sv.trough_feed_uri = nil
   self._sv.num_feed = 0
   self._json = radiant.entities.get_json(self)
   self._type = self._json.type
end

function PastureItemComponent:post_activate()
   -- Register if we are placed in the world
   self._parent_trace = self._entity:get_component('mob'):trace_parent('pasture item added or removed')
      :on_changed(function(parent_entity)
         if parent_entity then
            self:_register_with_town(true)
         else
            self:_register_with_town(false)
         end
      end)
      :push_object_state()
end

function PastureItemComponent:destroy()
   self:_register_with_town(false)
   self:_destroy_traces()
   self:_destroy_restock_tasks()
end

function PastureItemComponent:_destroy_traces()
   if self._parent_trace then
      self._parent_trace:destroy()
      self._parent_trace = nil
   end
end

function PastureItemComponent:_create_restock_tasks()
   self:_destroy_restock_tasks()

   if self._pasture and self:is_trough() then
      if self:is_empty() then
         local feed_material = self._pasture:add_component('stonehearth:shepherd_pasture'):get_animal_feed_material()

         if feed_material then
            local town = stonehearth.town:get_town(self._entity)

            local args = {
               pasture = self._pasture,
               trough = self._entity,
               feed_filter_fn = make_feed_filter_fn(feed_material, self._entity:get_player_id())
            }

            local restock_task = town:create_task_for_group(
               'stonehearth:task_groups:herding',
               RESTOCK_ACTION,
               args)
                  :set_source(self._entity)
                  :start()
            table.insert(self._added_restock_tasks, restock_task)
         end
      else
         -- otherwise, we just refilled it
         radiant.events.trigger_async(self._pasture, 'stonehearth_ace:shepherd_pasture:trough_feed_changed', {trough = self._entity})
      end
   end
   stonehearth.ai:reconsider_entity(self._entity)
end

function PastureItemComponent:_destroy_restock_tasks()
   if self._added_restock_tasks then
      for _, task in ipairs(self._added_restock_tasks) do
         task:destroy()
      end
   end
   self._added_restock_tasks = {}
end

function PastureItemComponent:register_with_town()
   self:_register_with_town(true)
end

function PastureItemComponent:unregister_with_town()
   self:_register_with_town(false)
end

function PastureItemComponent:_register_with_town(register)
   local player_id = radiant.entities.get_player_id(self._entity)
   local town = stonehearth.town:get_town(player_id)
   
   self._pasture = nil

   if town then
      town:unregister_pasture_item(self._entity)
      if register then
         self._pasture = town:register_pasture_item(self._entity, self._type)
      end
      -- unnecessary? may be necessary if pasture-based animal filters are implemented
      -- stonehearth.ai:reconsider_entity(self._entity, '(un)registered with pasture/town')
   end

   self:_create_restock_tasks()
end

function PastureItemComponent:get_pasture()
   return self._pasture
end

function PastureItemComponent:get_type()
   return self._type
end

function PastureItemComponent:is_trough()
   return self._type == 'trough'
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
         self:_create_restock_tasks()
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

   self:_create_restock_tasks()
end

return PastureItemComponent