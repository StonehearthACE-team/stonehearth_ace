-- ACE: modified to only update if self._y_offset is set (i.e., if presence_client has properly initialized)
-- this fixes the issue of reloading not displaying expendable resource toasts (they were being created with a nil offset)

local ExpendableResourcesRenderer = require 'stonehearth.renderers.expendable_resources.expendable_resources_renderer'
local AceExpendableResourcesRenderer = class()

local log = radiant.log.create_logger('ExpendableResourcesRenderer')

local DEFAULT_EFFECT_DEFINITIONS_JSON = radiant.resources.load_json('stonehearth:expendable_resources:effects:default')
local Y_OFFSETS = {
   NPC = 0,
   NON_NPC = -0.9,
}

function AceExpendableResourcesRenderer:initialize(render_entity, datastore)
   self._datastore = datastore
   self._render_entity = render_entity
   self._entity = render_entity:get_entity()
   self._started = false
   self._y_offset = nil
   self._y_offset_changed = nil

   self._current_uris = {}
   self._last_percentages = {}
   self._started_effects = {}

   self._component_trace = self._entity:trace_components('effect_list')
                           :on_added(function(key, value)
                              if key == 'effect_list' and not self._started then
                                 self._started = true
                                 self:_update()
                              end
                           end)
                           :push_object_state()

   self._datastore_trace = self._datastore:trace_data('rendering expendable resources')
      :on_changed(
         function()
            self:_update()
         end
      )

   local update_is_non_npc = function(is_non_npc)
      local prev_y_offset = self._y_offset
      self._y_offset = is_non_npc and Y_OFFSETS.NON_NPC or Y_OFFSETS.NPC
      self._y_offset_changed = self._y_offset ~= prev_y_offset
      self:_update()
      self._y_offset_changed = nil
   end

   self._is_npc_listener = radiant.events.listen(stonehearth.presence_client, 'stonehearth:presence_datastore_changed:is_non_npc', function(e)
         update_is_non_npc(e.new_value)
      end)

   local player_id = self._entity:get_player_id()
   if stonehearth.presence_client:has_player(player_id) then
      update_is_non_npc(stonehearth.presence_client:is_non_npc(player_id))
   end
end

--AceExpendableResourcesRenderer._ace_old__update = ExpendableResourcesRenderer._update
function AceExpendableResourcesRenderer:_update()
   --log:debug('%s _update (%s, %s)', self._entity, self._started, tostring(self._y_offset))
   if not self._y_offset or not self._started then
      return
   end

   local data = self._datastore:get_data()
   local resource_percentages = data.resource_percentages
   if resource_percentages then
      for resource_name, resource_percentage in pairs(resource_percentages) do
         assert(DEFAULT_EFFECT_DEFINITIONS_JSON, 'default effect definitions is missing or failed to load')
         local effect_definitions = DEFAULT_EFFECT_DEFINITIONS_JSON.resources[resource_name]
         if effect_definitions then
            if resource_percentage > 0 and resource_percentage < 1 then
               local last_percentage = self._last_percentages[resource_name] or 1

               local current_quartile = self:_get_quartile(resource_percentage, effect_definitions)

               local is_current_player = (radiant.entities.get_player_id(self._entity) == _radiant.client.get_player_id())
               local effect_definitions_to_use = effect_definitions.default
               if is_current_player and effect_definitions.current_player then
                  effect_definitions_to_use = effect_definitions.current_player
               end

               local uri_table = nil
               if self._y_offset_changed or resource_percentage > last_percentage then
                  uri_table = effect_definitions_to_use.gaining_resource
               elseif resource_percentage < last_percentage then
                  uri_table = effect_definitions_to_use.losing_resource
               end
               if uri_table then
                  self:_change_toast(resource_name, uri_table[current_quartile])
               end
            else
               if self._started_effects[resource_name] then
                  self._render_entity:stop_client_only_effect(self._started_effects[resource_name])
                  self._started_effects[resource_name] = nil
               end
            end
            self._last_percentages[resource_name] = resource_percentage
         end
      end
   end
end

function ExpendableResourcesRenderer:_change_toast(resource_name, toast_uri)
   -- we do still want to replace the effects if the y offset has changed
   if not self._y_offset_changed and toast_uri == self._current_uris[resource_name] then
      return
   end

   self._current_uris[resource_name] = toast_uri

   if self._started_effects[resource_name] then
      self._render_entity:stop_client_only_effect(self._started_effects[resource_name])
      self._started_effects[resource_name] = nil
   end

   if not toast_uri then
      return
   end

   self._started_effects[resource_name] = self._render_entity:start_client_only_effect(toast_uri, { yOffset = self._y_offset })
end

return AceExpendableResourcesRenderer
