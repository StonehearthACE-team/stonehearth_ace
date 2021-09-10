local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'

local StorageComponent = require 'stonehearth.components.storage.storage_component'
AceStorageComponent = class()

local GOLD_URI = 'stonehearth:loot:gold'

AceStorageComponent._ace_old_create = StorageComponent.create
function AceStorageComponent:create()
   self._is_create = true
   self:_ace_old_create()

   if self._type == 'input_crate' then
      self:_set_filter_to_none()
   elseif self._type == 'output_crate' and self._sv.filter_list == 'stonehearth:ui:stockpile:filters' then
      self._sv.filter_list = 'stonehearth_ace:ui:output_box:filters'
   end
end

AceStorageComponent._ace_old_restore = StorageComponent.restore
function AceStorageComponent:restore()
   if self._entity:get_component('stonehearth_ace:universal_storage') and radiant.entities.get_world_grid_location(self._entity) then
      -- move all entities out of this storage and queue them up to be transferred in the proper universal_storage entity
      stonehearth_ace.universal_storage:queue_items_for_transfer_on_registration(self._entity, self._sv.items)
      self._sv.items = {}
      self._sv.num_items = 0
      self._entity:remove_component('stonehearth:storage')
      return
   end

   self:_ace_old_restore()
end

AceStorageComponent._ace_old_activate = StorageComponent.activate
function AceStorageComponent:activate()
   -- if it's already been destroyed, don't activate it
   if self.__destroying then
      return
   end

   self:_ace_old_activate()
   
   local json = radiant.entities.get_json(self) or {}
   if self._is_create then
      if json.default_filter then
         self:set_filter(json.default_filter)
      end
      -- also set the filter to none if it's hidden storage
      -- if self._sv.is_hidden then
      --    self:_set_filter_to_none()
      -- end
   end

   self._sv.is_hidden = json.is_hidden or false -- public inventory that's accessible, but hidden from UI
   self._sv.allow_default = json.allow_default ~= false  -- can be set to town default storage
   if self._type == 'output_crate' then
      self._sv.allow_default = false
   end
   -- starting default can override allow_default (that way you can create default storage that can't be toggled by the user)
   if self._is_create and json.start_default then
      local town = stonehearth.town:get_town(self._entity)
      if town then
         town:add_default_storage(self._entity)
      end
   end

   if json.limit_all_filter ~= false then
      local filter = {}
      local data = radiant.resources.load_json(self._sv.filter_list, true, false)
      
      if data and data.stockpile then
         for _, group in pairs(data.stockpile) do
            if group.categories then
               for _, entry in pairs(group.categories) do
                  if entry.filter then
                     table.insert(filter, entry.filter)
                  end
               end
            end
         end
      end

      self._limited_all_filter = filter
   end

   self._ignore_restock = json.ignore_restock

   local bounds = stonehearth.constants.inventory.input_bins
   if self._type == 'input_crate' then
      local priority_range = bounds.MAX_PRIORITY - bounds.MIN_PRIORITY
      local priority = math.min(math.max(json.priority or 1, bounds.MIN_PRIORITY), bounds.MAX_PRIORITY)
      self._is_input_bin_highest_priority = (priority == bounds.MAX_PRIORITY)
      self._input_bin_priority = (priority - bounds.MIN_PRIORITY) / (priority_range + 1)
   else
      self._input_bin_priority = bounds.MIN_PRIORITY
   end

   -- communicate this setting to the renderer
   self._sv.render_root_items = json.render_root_items
	self._sv.render_filter_model = json.render_filter_model
	self._sv.render_filter_model_threshold = json.render_filter_model_threshold or 0.5
   self._sv.reposition_items = json.reposition_items
   self.__saved_variables:mark_changed()
end

AceStorageComponent._ace_old_post_activate = StorageComponent.post_activate
function AceStorageComponent:post_activate()
   -- if it's already been destroyed, don't activate it
   if self.__destroying then
      return
   end

   self:_ace_old_post_activate()
end

AceStorageComponent._ace_old_destroy = StorageComponent.__user_destroy
function AceStorageComponent:destroy()
   self.__destroying = true
   self:_ace_old_destroy()
end

AceStorageComponent._ace_old__on_contents_changed = StorageComponent._on_contents_changed
function AceStorageComponent:_on_contents_changed()

	self:_ace_old__on_contents_changed()

	if not self:is_empty() and self._sv.filter and self._sv.render_filter_model then
		if (self._sv.num_items / self._sv.capacity) >= self._sv.render_filter_model_threshold then
			self._entity:get_component('render_info'):set_model_variant(tostring(self._cached_filter_key))
		else
			self._entity:get_component('render_info'):set_model_variant('')
		end
	end

   stonehearth_ace.universal_storage:storage_contents_changed(self._entity, self:is_empty())
end

function AceStorageComponent:get_limited_all_filter()
   return self._limited_all_filter
end

function AceStorageComponent:get_filter()
   return self._sv.filter or self._limited_all_filter
end

function AceStorageComponent:get_filter_key()
   if not self._cached_filter_key then
      self._cached_filter_key = stonehearth.inventory:get_inventory(radiant.entities.get_player_id(self._entity)):filter_to_key(self._sv.filter)
   end

   return self._cached_filter_key
end

function AceStorageComponent:is_input_bin_highest_priority()
   return self._is_input_bin_highest_priority
end

function AceStorageComponent:get_input_bin_priority()
   return self._input_bin_priority
end

function AceStorageComponent:get_ignore_restock()
   return self._ignore_restock
end

function AceStorageComponent:is_hidden()
   return self._sv.is_hidden
end

function AceStorageComponent:allow_default()
   return self._sv.allow_default
end

function AceStorageComponent:is_output_bin_for_crafter(job_id)
   if job_id and self._type == 'output_crate' then
      if not self._sv.filter then
         return true
      end
      if not self._sv.filter.is_exact_filter then
         for _, mat in ipairs(self._sv.filter) do
            if mat == job_id then
               return true
            end
         end
      end
   end
end

-- allow for specifying a priority_location for universal_storage, and try to send to default storage instead of landing location
-- if priority_location is false (not nil), *this* entity's location will be ignored
function AceStorageComponent:drop_all(fallback_location, priority_location)
   if self:is_empty() then
      return {} -- Nothing to drop
   end

   local items = {}
   for id, item in pairs(self._sv.items) do
      if item and item:is_valid() then
         table.insert(items, item)
      end
   end

   local get_player_id = radiant.entities.get_player_id
   for _, item in ipairs(items) do
      self:remove_item(item:get_id(), nil, get_player_id(item))
   end

   local player_id = get_player_id(self._entity)
   local default_storage
   local town = stonehearth.town:get_town(player_id)
   if town then
      -- unregister this storage from default; if we're dropping all the items, even if it's not getting destroyed, we probably don't want more stuff in here
      -- especially the items we're trying to drop!
      town:remove_default_storage(self._entity:get_id())
      default_storage = town:get_default_storage()
   end
   local entity = entity_forms_lib.get_in_world_form(self._entity)
   local location = priority_location or
         (priority_location == nil and (radiant.entities.get_world_grid_location(entity or self._entity) or fallback_location)) or
         (town and town:get_landing_location())

   local options = {
      owner = player_id,
      inputs = default_storage,
      spill_fail_items = true,
      require_matching_filter_override = true,
   }
   radiant.entities.output_spawned_items(items, location, 1, 4, options)

   stonehearth.ai:reconsider_entity(self._entity, 'removed all items from storage')

   return items
end

function AceStorageComponent:add_gold_item(item, combine_only)
   if item:get_uri() == GOLD_URI then
      local stacks_comp = item:add_component('stonehearth:stacks')
      local stacks = stacks_comp:get_stacks()
      local result = self:add_gold(stacks, combine_only)
      if radiant.util.is_number(result) then
         stacks_comp:set_stacks(result)
      else
         radiant.entities.destroy_entity(item)
         return result
      end
   end

   return false
end

function AceStorageComponent:add_gold(amount, combine_only)
   return self._inventory:add_gold(amount, self._entity, combine_only)
end

function AceStorageComponent:get_items_of_type(uri)
   local tracking_data = self._sv.item_tracker:get_tracking_data()
   if tracking_data:contains(uri) then
      return tracking_data:get(uri)
   end
   return nil
end

return AceStorageComponent