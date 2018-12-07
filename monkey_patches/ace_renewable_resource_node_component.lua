local RenewableResourceNodeComponent = radiant.mods.require('stonehearth.components.renewable_resource_node.renewable_resource_node_component')
local AceRenewableResourceNodeComponent = class()

--[[
local HARVEST_ACTION = 'stonehearth:harvest_renewable_resource'
local ENABLE_AUTO_HARVEST_COMMAND = 'stonehearth_ace:commands:enable_auto_harvest'
local DISABLE_AUTO_HARVEST_COMMAND = 'stonehearth_ace:commands:disable_auto_harvest'

AceRenewableResourceNodeComponent._old_post_activate = RenewableResourceNodeComponent.post_activate
function AceRenewableResourceNodeComponent:post_activate()
   self:_old_post_activate()
   
   local json = radiant.entities.get_json(self)
   self._sv.default_auto_harvest = json and json.auto_harvest
   self.__saved_variables:mark_changed()
   self:_update_auto_harvest_commands()

   if self._sv.harvestable then
      --self:_auto_request_harvest()
   end

   self._player_id_listener = 
         radiant.events.listen(self._entity, 'stonehearth:player_id_changed', self, self._on_player_id_changed)
   self:_setup_auto_harvest_setting_listener()
end

AceRenewableResourceNodeComponent._old_destroy = RenewableResourceNodeComponent.destroy
function AceRenewableResourceNodeComponent:destroy()
   self:_old_destroy()

   if self._player_id_listener then
      self._player_id_listener:destroy()
      self._player_id_listener = nil
   end

   if self._auto_harvest_setting_update_listener then
      self._auto_harvest_setting_update_listener:destroy()
      self._auto_harvest_setting_update_listener = nil
   end
end

function AceRenewableResourceNodeComponent:_setup_auto_harvest_setting_listener()
   if self._entity:get_player_id() ~= '' and not self._auto_harvest_setting_update_listener then
      self._auto_harvest_setting_update_listener = 
         radiant.events.listen(stonehearth_ace, 'stonehearth_ace:auto_harvest_setting_update', self, self._on_auto_harvest_setting_update)
   elseif self._auto_harvest_setting_update_listener then
      self._auto_harvest_setting_update_listener:destroy()
      self._auto_harvest_setting_update_listener = nil
   end
end

function AceRenewableResourceNodeComponent:_on_player_id_changed(args)
   if args.player_id == '' then
      -- if it's back to nothing, clear out auto-harvest settings
      self._sv.manual_auto_harvest = nil
   end
   self:_setup_auto_harvest_setting_listener()
   self:_update_auto_harvest_commands()
end

function AceRenewableResourceNodeComponent:_on_auto_harvest_setting_update(player_id)
   if player_id == self._entity:get_player_id() and self._sv.manual_auto_harvest == nil and self._sv.default_auto_harvest == nil then
      self:_update_auto_harvest_commands()
   end
end
]]

function AceRenewableResourceNodeComponent:_auto_request_harvest()
   local player_id = self._entity:get_player_id()
   -- if a player has moved or harvested this item, that player has gained ownership of it
   -- if they haven't, there's no need to request it to be harvested because it's just growing in the wild with no owner
   
   if player_id ~= '' then
      local auto_harvest = self:get_auto_harvest_enabled()
      if auto_harvest then
         self:request_harvest(player_id)
      end
   end
end

function AceRenewableResourceNodeComponent:get_auto_harvest_enabled()
   local player_id = self._entity:get_player_id()
   if player_id ~= '' then
      return stonehearth.client_state:get_client_gameplay_setting(player_id, 'stonehearth_ace', 'enable_auto_harvest', false)
   end
end

AceRenewableResourceNodeComponent._old_renew = RenewableResourceNodeComponent.renew
function AceRenewableResourceNodeComponent:renew()
   self:_old_renew()

   self:_auto_request_harvest()
end

--[[
function AceRenewableResourceNodeComponent:set_auto_harvest_enabled(enabled)
   local changed = enabled ~= self:get_auto_harvest_enabled()
   if self._sv.manual_auto_harvest ~= enabled then
      self._sv.manual_auto_harvest = enabled
      self.__saved_variables:mark_changed()
   end
   if changed then
      self:_update_auto_harvest_commands()
   end
end

function AceRenewableResourceNodeComponent:_cancel_harvest_request()
   local task_tracker_component = self._entity:get_component('stonehearth:task_tracker')
   if task_tracker_component and task_tracker_component:is_activity_requested(HARVEST_ACTION) then
      task_tracker_component:cancel_current_task(true, true)
   end
end

function AceRenewableResourceNodeComponent:_update_auto_harvest_commands()
   local enabled = self:get_auto_harvest_enabled()

   local commands = self._entity:add_component('stonehearth:commands')
   if enabled then
      commands:remove_command(ENABLE_AUTO_HARVEST_COMMAND)
      commands:add_command(DISABLE_AUTO_HARVEST_COMMAND)
   elseif enabled == false then
      commands:remove_command(DISABLE_AUTO_HARVEST_COMMAND)
      commands:add_command(ENABLE_AUTO_HARVEST_COMMAND)
   end
end
]]

return AceRenewableResourceNodeComponent
