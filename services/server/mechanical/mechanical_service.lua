local log = radiant.log.create_logger('mechanical_service')

local MechanicalService = class()

function MechanicalService:initialize()
   self._networks = {}
   self._entity_listeners = {}
   self._networks_by_entity = {}

   -- query connection service for connection info and listen for changes
   self:_update_graphs()
   self._connections_changed_listener = radiant.events.listen(stonehearth_ace.connection, 'stonehearth_ace:connections:mechanical:changed', self, self._on_connections_changed)
   for id, _ in pairs(self._graphs) do
      self:_update_network(id)
   end
end

function MechanicalService:destroy()
	self:_destroy_listeners()
end

function MechanicalService:_destroy_listeners()
   if self._connections_changed_listener then
      self._connections_changed_listener:destroy()
      self._connections_changed_listener = nil
   end
   for id, _ in pairs(self._entity_listeners) do
      self:_destroy_entity_listener(id)
   end
end

function MechanicalService:_update_graphs()
   self._graphs = stonehearth_ace.connection:get_graphs_by_type('mechanical')
end

function MechanicalService:_on_connections_changed(type, graphs_changed)
   self:_update_graphs()
   for id, _ in pairs(graphs_changed) do
      self:_update_network(id)
   end
end

function MechanicalService:_get_networks_by_entity(id)
   local networks = self._networks_by_entity[id]
   if not networks then
      networks = {}
      self._networks_by_entity[id] = networks
   end
   return networks
end

function MechanicalService:_remove_entity_from_n_by_e_network(entity_id, network_id)
   local n_by_entities_n = self._networks_by_entity[entity_id]
   if n_by_entities_n then
      n_by_entities_n[network_id] = nil
      if not next(n_by_entities_n) then
         self._networks_by_entity[entity_id] = nil
      end
   end
end

function MechanicalService:_update_network(id)
   -- if this graph id exists in our networks but not in connections, we need to disable that network
   -- if this graph id exists in connections, we need to make sure it exists in our network and enable it
   local network = self._networks[id]

   local graph = self._graphs[id]
   if graph then
      network = self:_add_network(id)
      self:_enable_network(network, graph)
   else
      self:_disable_network(network)
   end
end

function MechanicalService:_add_network(id)
   local network = self._networks[id]
   if not network then
      network = {id = id, entities = {}, produced = 0, consumed = 0, resistance = 0, power_percentage = 0}
      
      self._networks[id] = network
   end
   return network
end

function MechanicalService:_enable_network(network, graph)
   -- if the network already existed, determine if there are any entities that are no longer in the network
   for id, entity in pairs(network.entities) do
      if not graph.nodes[id] then
         -- tell this entity it is no longer welcome here
         self:_disable_entity_in_network(entity, network)
         self:_remove_entity_from_n_by_e_network(id, network.id)
      end
   end

   -- make sure all our new entities exist
   for id, node in pairs(graph.nodes) do
      if not network.entities[id] then
         local entity = radiant.entities.get_entity(node.entity_id)
         network.entities[id] = entity
         self:_create_entity_listener(entity)
      end
      local n_by_entities_n = self:_get_networks_by_entity(id)
      n_by_entities_n[network.id] = true
   end

   -- then go through all the entities in this network and calculate the power levels, etc.
   local produced = 0
   local consumed = 0
   local resistance = 0
   for id, entity in pairs(network.entities) do
      local mech_comp = entity:add_component('stonehearth_ace:mechanical')
      produced = produced + mech_comp:get_power_produced()
      consumed = consumed + mech_comp:get_power_consumed()
      resistance = resistance + mech_comp:get_resistance()
   end

   local percentage = math.min(1, (produced - resistance) / math.max(1, consumed))
   if percentage < 0.01 then
      percentage = 0
   end
   network.produced = produced
   network.consumed = consumed
   network.resistance = resistance
   network.power_percentage = percentage

   -- finally, go through all the entities and set their power percentage
   for id, entity in pairs(network.entities) do
      local mech_comp = entity:get_component('stonehearth_ace:mechanical')
      mech_comp:set_power_percentage(percentage)
   end
end

function MechanicalService:_disable_network(network)
   if not network then
      return
   end

   self._networks[network.id] = nil
   for id, entity in pairs(network.entities) do
      self:_disable_entity_in_network(entity, network)
   end
end

function MechanicalService:_disable_entity_in_network(entity, network)
   local id = entity:get_id()
   self:_destroy_entity_listener(id)
   entity:add_component('stonehearth_ace:mechanical'):set_power_percentage(0)
   network.entities[id] = nil
   if not next(network.entities) then
      self._networks[id] = nil
   end
end

function MechanicalService:_on_entity_changed(entity)
   for id, network in pairs(self:_get_networks_by_entity(entity:get_id())) do
      self:_update_network(id)
   end
end

function MechanicalService:_create_entity_listener(entity)
   local id = entity:get_id()
   if not self._entity_listeners[id] then
      self._entity_listeners[id] = radiant.events.listen(entity, 'stonehearth_ace:mechanical:changed', self, self._on_entity_changed)
   end
end

function MechanicalService:_destroy_entity_listener(id)
   if self._entity_listeners[id] then
      self._entity_listeners[id]:destroy()
      self._entity_listeners[id] = nil
   end
end

return MechanicalService
