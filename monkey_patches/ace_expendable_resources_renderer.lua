-- ACE: modified to only update if self._y_offset is set (i.e., if presence_client has properly initialized)
-- this fixes the issue of reloading not displaying expendable resource toasts (they were being created with a nil offset)

local ExpendableResourcesRenderer = require 'stonehearth.renderers.expendable_resources.expendable_resources_renderer'
local AceExpendableResourcesRenderer = class()

local log = radiant.log.create_logger('ExpendableResourcesRenderer')

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
      :push_object_state()

   self._is_npc_listener = radiant.events.listen(stonehearth.presence_client, 'stonehearth:presence_datastore_changed:is_non_npc', function(e)
         local is_non_npc = e.new_value
         self._y_offset = is_non_npc and Y_OFFSETS.NON_NPC or Y_OFFSETS.NPC
         self:_update()
      end)
end

AceExpendableResourcesRenderer._ace_old__update = ExpendableResourcesRenderer._update
function AceExpendableResourcesRenderer:_update()
   --log:debug('%s _update (%s, %s)', self._entity, self._started, tostring(self._y_offset))
   if not self._y_offset then
      return
   end

   --log:debug('%s datastore: %s', self._entity, radiant.util.table_tostring(self._datastore:get_data()))
   -- log:debug('%s PRE-UPDATE _current_uris: %s', self._entity, radiant.util.table_tostring(self._current_uris))
   -- log:debug('%s PRE-UPDATE _last_percentages: %s', self._entity, radiant.util.table_tostring(self._last_percentages))
   -- log:debug('%s PRE-UPDATE _started_effects: %s', self._entity, radiant.util.table_tostring(self._started_effects))
   
   self:_ace_old__update()

   -- log:debug('%s POST-UPDATE _current_uris: %s', self._entity, radiant.util.table_tostring(self._current_uris))
   -- log:debug('%s POST-UPDATE _last_percentages: %s', self._entity, radiant.util.table_tostring(self._last_percentages))
   -- log:debug('%s POST-UPDATE _started_effects: %s\n', self._entity, radiant.util.table_tostring(self._started_effects))
end

-- AceExpendableResourcesRenderer._ace_old__change_toast = ExpendableResourcesRenderer._change_toast
-- function AceExpendableResourcesRenderer:_change_toast(resource_name, toast_uri)
--    log:debug('%s _change_toast (%s, %s)', self._entity, tostring(resource_name), tostring(toast_uri))
--    self:_ace_old__change_toast(resource_name, toast_uri)
-- end

return AceExpendableResourcesRenderer
