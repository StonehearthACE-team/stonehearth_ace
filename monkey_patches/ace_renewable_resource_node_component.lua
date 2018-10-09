local RenewableResourceNodeComponent = radiant.mods.require('stonehearth.components.renewable_resource_node.renewable_resource_node_component')
local AceRenewableResourceNodeComponent = class()

local ENABLE_AUTO_HARVEST_COMMAND = 'stonehearth_ace:commands:enable_auto_harvest'
local DISABLE_AUTO_HARVEST_COMMAND = 'stonehearth_ace:commands:disable_auto_harvest'

AceRenewableResourceNodeComponent._old_post_activate = RenewableResourceNodeComponent.post_activate
function AceRenewableResourceNodeComponent:post_activate()
   self:_old_post_activate()
   
   if self._sv.auto_harvest == nil then
      local json = radiant.entities.get_json(self)
      self._sv.auto_harvest = (json and json.auto_harvest) or radiant.util.get_config('auto_enable_auto_harvest', false)
      self.__saved_variables:mark_changed()
      self:_update_auto_harvest_commands()
   end

   if self._sv.harvestable then
      self:_auto_request_harvest()
   end
end

function AceRenewableResourceNodeComponent:_auto_request_harvest()
   local auto_harvest = self:get_auto_harvest_enabled()
   if auto_harvest then
      local player_id = self._entity:get_player_id()
      -- if a player has moved or harvested this item, that player has gained ownership of it
      -- if they haven't, there's no need to request it to be harvested because it's just growing in the wild with no owner
      if player_id ~= '' then
         self:request_harvest(player_id)
      end
   end
end

function AceRenewableResourceNodeComponent:get_auto_harvest_enabled()
   return self._sv.auto_harvest
end

function AceRenewableResourceNodeComponent:set_auto_harvest_enabled(enabled)
   if self._sv.auto_harvest ~= enabled then
      self._sv.auto_harvest = enabled
      self.__saved_variables:mark_changed()

      self:_update_auto_harvest_commands()
   end
end

AceRenewableResourceNodeComponent._old_renew = RenewableResourceNodeComponent.renew
function AceRenewableResourceNodeComponent:renew()
   self:_old_renew()

   self:_auto_request_harvest()
end

function AceRenewableResourceNodeComponent:_update_auto_harvest_commands()
   local enabled = self:get_auto_harvest_enabled()

   local commands = self._entity:add_component('stonehearth:commands')
   commands:remove_command(ENABLE_AUTO_HARVEST_COMMAND)
   commands:remove_command(DISABLE_AUTO_HARVEST_COMMAND)
   if enabled then
      commands:add_command(DISABLE_AUTO_HARVEST_COMMAND)
   else
      commands:add_command(ENABLE_AUTO_HARVEST_COMMAND)
   end
end

return AceRenewableResourceNodeComponent
