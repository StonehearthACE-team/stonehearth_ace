--[[
   use connections to automatically register as an input/output for connected entities
]]

local AutoIOComponent = class()

local log = radiant.log.create_logger('auto_io_component')

function AutoIOComponent:activate()
   self._json = radiant.entities.get_json(self) or {}
   self._input = self._json.input
   self._output = self._json.output
   self._connection_types = self._json.connection_types or {'i_o'}
   self._connection_changed_listeners = {}
end

function AutoIOComponent:post_activate()
   -- check to make sure it has the connection component; otherwise it can't do anything
   self._connection = self._entity:get_component('stonehearth_ace:connection')

   if not self._connection then
      log:debug('cannot set up auto-io component for %s, missing stonehearth_ace:connection component', self._entity)
      return
   end

   self:_setup()
end

function AutoIOComponent:destroy()
   self:_destroy_listeners()
end

function AutoIOComponent:_destroy_listeners()
   for _, listener in pairs(self._connection_changed_listeners) do
      listener:destroy()
   end
   self._connection_changed_listeners = {}
end

function AutoIOComponent:_setup()
   self:_destroy_listeners()

   for _, connection_type in ipairs(self._connection_types) do
      self._connection_changed_listeners[connection_type] = 
         radiant.events.listen(self._entity, 'stonehearth_ace:connection:' .. connection_type .. ':connection_changed', self, self._on_connection_changed)

      -- go through all existing connections and create listeners
      local connections = self._connection:get_connected_stats(connection_type)
      if connections and connections[connection_type] and connections[connection_type].num_connections > 0 then
         for _, conn_data in pairs(connections[connection_type].connectors) do
            if conn_data.num_connections > 0 then
               for connected_to_id, threshold in pairs(conn_data.connected_to) do
                  local target = stonehearth_ace.connection:get_entity_from_connector(connected_to_id)
                  if target and target:is_valid() then
                     self:_try_connecting(target, threshold.threshold)
                  end
               end
            end
         end
      end
   end
end

function AutoIOComponent:_on_connection_changed(args)
   log:debug('%s connection changed: %s', self._entity, radiant.util.table_tostring(args))
   if args.connected_to_entity then
      if args.threshold then
         self:_try_connecting(args.connected_to_entity, args.threshold)
      else
         self:_try_disconnecting(args.connected_to_entity)
      end
   end
end

function AutoIOComponent:_try_connecting(target, threshold)
   local target_output = self._input and target:get_component('stonehearth_ace:output')
   if target_output then
      self._entity:add_component('stonehearth_ace:input')
      target_output:add_input(self._entity)
   end

   local output = self._output and self._entity:add_component('stonehearth_ace:output')
   if output and target:get_component('stonehearth_ace:input') then
      output:add_input(target)
   end
end

function AutoIOComponent:_try_disconnecting(target)
   if target and target:is_valid() then
      local target_output = self._input and target:get_component('stonehearth_ace:output')
      if target_output then
         target_output:remove_input(self._entity)
      end

      local output = self._output and self._entity:add_component('stonehearth_ace:output')
      if output then
         output:remove_input(target)
      end
   end
end

return AutoIOComponent
