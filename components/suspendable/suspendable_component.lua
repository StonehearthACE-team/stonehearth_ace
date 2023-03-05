local SuspendableComponent = class()

local log = radiant.log.create_logger('suspendable_component')

function SuspendableComponent:initialize()
   self._json = radiant.entities.get_json(self) or {}
   self._player_id = radiant.entities.get_player_id(self._entity)

   -- to add more components to this list, simply mixin to this json and add them to the components field
   -- and make sure town_suspended and town_continued are implemented in those components
   self._components = radiant.resources.load_json('stonehearth_ace:data:suspendable_components').components
end

function SuspendableComponent:restore()
   self._is_restore = true
   self:_register_with_town()
end

function SuspendableComponent:post_activate()
   -- if the owner of this entity can change, listen for that change and re-register with the appropriate town
   if self._json.owner_can_change then
      self._player_id_trace = self._entity:trace_player_id('ACE suspendable component')
                                          :on_changed(function(player_id)
                                                self:_unregister_with_town()
                                                self._player_id = player_id
                                                self:_register_with_town()
                                             end)
   end

   if not self._is_restore then
      self:_register_with_town()
   end
end

function SuspendableComponent:destroy()
   self:_unregister_with_town()

   if self._player_id_trace then
      self._player_id_trace:destroy()
      self._player_id_trace = nil
   end
end

function SuspendableComponent:_register_with_town()
   local town = self._player_id and stonehearth.town:get_town(self._player_id)
   if town and not stonehearth.player:is_player_npc(self._player_id) then
      --log:debug('%s registering suspendable entity with town %s', self._entity, self._player_id)
      town:register_suspendable_entity(self._entity)
   end
end

function SuspendableComponent:_unregister_with_town()
   local town = self._player_id and stonehearth.town:get_town(self._player_id)
   if town and not stonehearth.player:is_player_npc(self._player_id) then
      town:unregister_suspendable_entity(self._entity)
   end
end

-- called from town controller (ace_town.lua) when the registered town is suspended
function SuspendableComponent:town_suspended()
   -- suspend known timer components; any other components that want to be suspended can be specified by monkey-patch
   for component_name, suspendable in pairs(self._components) do
      if suspendable then
         local component = self._entity:get_component(component_name)
         if component and component.town_suspended then
            component:town_suspended()
         end
      end
   end
end

function SuspendableComponent:town_continued()
   for component_name, suspendable in pairs(self._components) do
      if suspendable then
         local component = self._entity:get_component(component_name)
         if component and component.town_continued then
            component:town_continued()
         end
      end
   end
end

return SuspendableComponent
