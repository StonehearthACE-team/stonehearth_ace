local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'

local RenewableResourceNodeComponent = radiant.mods.require('stonehearth.components.renewable_resource_node.renewable_resource_node_component')
local AceRenewableResourceNodeComponent = class()

function AceRenewableResourceNodeComponent:create()
   self._is_create = true
end

AceRenewableResourceNodeComponent._old_post_activate = RenewableResourceNodeComponent.post_activate
function AceRenewableResourceNodeComponent:post_activate()
   self:_old_post_activate()

   if self._sv.harvestable and self._is_create then
      self:_auto_request_harvest()
   end
end

function AceRenewableResourceNodeComponent:_auto_request_harvest()
   local player_id = self._entity:get_player_id()
   -- if a player has moved or harvested this item, that player has gained ownership of it
   -- if they haven't, there's no need to request it to be harvested because it's just growing in the wild with no owner
   
   if player_id ~= '' then
      local auto_harvest = self:get_auto_harvest_enabled(player_id)
      if auto_harvest then
         self:request_harvest(player_id)
      end
   end
end

function AceRenewableResourceNodeComponent:get_auto_harvest_enabled(player_id)
   player_id = player_id or self._entity:get_player_id()
   if player_id ~= '' then
      return stonehearth.client_state:get_client_gameplay_setting(player_id, 'stonehearth_ace', 'enable_auto_harvest', false)
   end
end

AceRenewableResourceNodeComponent._old_spawn_resource = RenewableResourceNodeComponent.spawn_resource
function AceRenewableResourceNodeComponent:spawn_resource(harvester_entity, location, owner_player_id)
   if not self._json.spawn_resource_immediately or not owner_player_id or owner_player_id == '' or
         stonehearth.client_state:get_client_gameplay_setting(owner_player_id, 'stonehearth_ace', 'enable_auto_harvest_animals', true) then
      self:_old_spawn_resource(harvester_entity, location, owner_player_id)
   end
end

AceRenewableResourceNodeComponent._old_renew = RenewableResourceNodeComponent.renew
function AceRenewableResourceNodeComponent:renew()
   self:_old_renew()

   self:_auto_request_harvest()
end

AceRenewableResourceNodeComponent._old__place_spawned_items = RenewableResourceNodeComponent._place_spawned_items
function AceRenewableResourceNodeComponent:_place_spawned_items(json, owner, location, will_destroy_entity)
   local spawned_items, item = self:_old__place_spawned_items(json, owner, location, will_destroy_entity)

   local quality = radiant.entities.get_item_quality(self._entity)
   if quality > 1 then
      for id, item in pairs(spawned_items) do
         self:_set_quality(item, quality)
      end
   end

   return spawned_items, item
end

function AceRenewableResourceNodeComponent:_set_quality(item, quality)
   item_quality_lib.apply_quality(item, quality)
end

return AceRenewableResourceNodeComponent
