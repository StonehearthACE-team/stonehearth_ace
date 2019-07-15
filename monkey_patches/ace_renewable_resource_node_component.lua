local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'
local log = radiant.log.create_logger('renewable_resource_node')

local RenewableResourceNodeComponent = radiant.mods.require('stonehearth.components.renewable_resource_node.renewable_resource_node_component')
local AceRenewableResourceNodeComponent = class()

local RENEWED_MODEL_NAME = 'stonehearth:renewable_resource_node:renewed'
local HALF_RENEWED_MODEL_NAME = 'stonehearth:renewable_resource_node:half_renewed'

function AceRenewableResourceNodeComponent:create()
   self._is_create = true
end

AceRenewableResourceNodeComponent._ace_old_activate = RenewableResourceNodeComponent.activate
function AceRenewableResourceNodeComponent:activate()
   self:_ace_old_activate()
   if self._sv.half_renew_timer then
      self._sv.half_renew_timer:bind(function()
            self:_set_model_half_renewed()
         end)
   end

   if self._sv.harvestable then
      self:_reset_model()
   end
end

AceRenewableResourceNodeComponent._ace_old_post_activate = RenewableResourceNodeComponent.post_activate
function AceRenewableResourceNodeComponent:post_activate()
   if not self._json then
      --self._entity:remove_component('stonehearth:renewable_resource_node')
      return
   end
   
   self:_ace_old_post_activate()
   if self._sv.harvestable and self._is_create and self._json.auto_harvest_on_create ~= false then
      self._added_to_world_listener = self._entity:add_component('mob'):trace_parent('transform entity added or removed')
            :on_changed(function(parent)
               if parent then
                  --log:debug('considering auto_harvest for %s', self._entity)
                  self:_destroy_added_to_world_listener()
                  self:_auto_request_harvest()
               end
            end)
   end
end

AceRenewableResourceNodeComponent._ace_old_destroy = RenewableResourceNodeComponent.destroy
function AceRenewableResourceNodeComponent:destroy()
   self:_ace_old_destroy()
   self:_destroy_added_to_world_listener()
end

function AceRenewableResourceNodeComponent:_destroy_added_to_world_listener()
   if self._added_to_world_listener then
      self._added_to_world_listener:destroy()
      self._added_to_world_listener = nil
   end
end

function AceRenewableResourceNodeComponent:_auto_request_harvest()
   local player_id = self._entity:get_player_id()
   -- if a player has moved or harvested this item, that player has gained ownership of it
   -- if they haven't, there's no need to request it to be harvested because it's just growing in the wild with no owner
   
   if player_id ~= '' then
      local auto_harvest = self:get_auto_harvest_enabled(player_id) or self:_can_pasture_animal_renewably_harvest()
      if auto_harvest then
         --log:debug('requesting auto harvest for %s', self._entity)
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

function AceRenewableResourceNodeComponent:spawn_resource(harvester_entity, location, owner_player_id)
   if not self._json.spawn_resource_immediately or self:_can_pasture_animal_renewably_harvest() ~= false then
      self:_cancel_harvest_request()
      local json = self._json

      local will_destroy_entity = false
      -- if we have a durability and we've run out, destroy the entity
      if self._sv.durability then
         self._sv.durability = self._sv.durability - 1
         if self._sv.durability <= 0 then
            self._sv.harvestable = false
            will_destroy_entity = true
         end
      end

      local player_id = owner_player_id or radiant.entities.get_player_id(harvester_entity)
      local spawned_resources, singular_item = self:_place_spawned_items(json, player_id, location, will_destroy_entity)

      for id, item in pairs(spawned_resources) do
         if not json.skip_owner_inventory then
            -- add it to the inventory of the owner
            local inventory = stonehearth.inventory:get_inventory(player_id)
            if inventory then
               inventory:add_item_if_not_full(item)
            end
         end
      end

      if json.resource_spawn_effect then
         local proxy = radiant.entities.create_entity('stonehearth:object:transient', { debug_text = 'spawn effect effect anchor' })
         local location = radiant.entities.get_world_grid_location(self._entity)
         radiant.terrain.place_entity_at_exact_location(proxy, location)
         local effect = radiant.effects.run_effect(proxy, json.resource_spawn_effect)
         effect:set_finished_cb(function()
            radiant.entities.destroy_entity(proxy)
         end)
      end

      -- if we have a durability and we've run out, destroy the entity
      if will_destroy_entity then
         radiant.entities.destroy_entity(self._entity)
         return singular_item
      end

      --start the countdown to respawn.
      self:_set_model_depleted()

      self:_update_renew_timer()

      --Change the description
      if json.unripe_description then
         radiant.entities.set_description(self._entity, json.unripe_description)
      end

      self._sv.harvestable = false
      self.__saved_variables:mark_changed()

      return singular_item
   end
end

function AceRenewableResourceNodeComponent:_set_model_depleted()
   if self._json.renewed_model or self._json.half_renewed_model then
      self._entity:add_component('stonehearth_ace:models'):remove_model(RENEWED_MODEL_NAME)
      self._entity:add_component('stonehearth_ace:models'):remove_model(HALF_RENEWED_MODEL_NAME)
   else
      local render_info = self._entity:add_component('render_info')
      render_info:set_model_variant('depleted')
   end
end

function AceRenewableResourceNodeComponent:_set_model_half_renewed()
   if self._json.half_renewed_model then
      self._entity:add_component('stonehearth_ace:models'):add_model(HALF_RENEWED_MODEL_NAME, self._json.half_renewed_model)
   else
      local render_info = self._entity:add_component('render_info')
      render_info:set_model_variant('half_renewed')
   end
end

--- Reset the model to the default. Also, stop listening for effects
function AceRenewableResourceNodeComponent:_reset_model()
   if self._json.renewed_model then
      self._entity:add_component('stonehearth_ace:models'):add_model(RENEWED_MODEL_NAME, self._json.renewed_model)
      self._entity:add_component('stonehearth_ace:models'):remove_model(HALF_RENEWED_MODEL_NAME)
   else
      local render_info = self._entity:add_component('render_info')
      render_info:set_model_variant('')
   end

   if self._renew_effect then
      self._renew_effect:set_finished_cb(nil)
                        :set_trigger_cb(nil)
                        :stop()
      self._renew_effect = nil
   end
end

function AceRenewableResourceNodeComponent:_can_pasture_animal_renewably_harvest()
   -- determine if this entity is a pasture animal and if it's currently in a pasture that disables renewable harvesting
   -- what a long chain to unravel!
   -- TODO: set a flag somewhere so we don't have to do this all the time?
   local equipment = self._entity:get_component('stonehearth:equipment')
   local collar = equipment and equipment:has_item_type('stonehearth:pasture_equipment:tag')
   local shepherded = collar and collar:get_component('stonehearth:shepherded_animal')
   local pasture = shepherded and shepherded:get_pasture()
   local shepherd_pasture = pasture and pasture:get_component('stonehearth:shepherd_pasture')
   local return_val
   if shepherd_pasture then
      return_val = shepherd_pasture:get_harvest_animals_renewable()
   end

   --log:debug('pasture animal %s renewably harvest', (return_val and 'CAN') or (return_val == false and 'CANNOT') or 'ISN\'T A PASTURE ANIMAL SO CANNOT')
   return return_val
end

AceRenewableResourceNodeComponent._ace_old_renew = RenewableResourceNodeComponent.renew
function AceRenewableResourceNodeComponent:renew()
   log:debug('attempting to renew entity %s...', self._entity)
   if not self._entity:add_component('render_info') then
      log:debug('failed to add render_info component to %s; rrn json: %s', self._entity, radiant.util.table_tostring(self._json))
      self:_stop_renew_timer()
      return
   end
   self:_ace_old_renew()

   if self._json.buffs_on_renewal then
      for uri, stacks in pairs(self._json.buffs_on_renewal) do
         if stacks then
            if not type(stacks) == 'number' then
               stacks = 1
            end
            radiant.entities.add_buff(self._entity, uri, {stacks = stacks})
         else
            -- don't keep trying; it won't change, and it's not entity-specific
            -- so we can just remove it from the shared cached table
            self._json.buffs_on_renewal[uri] = nil
         end
      end
   end

   self:_auto_request_harvest()
end

function AceRenewableResourceNodeComponent:_update_renew_timer()
   if self._sv.paused then
      -- Do not update the timer if paused.
      return
   end

   local renewal_time = self._renewal_time
   if self._sv.renew_timer then
      renewal_time = stonehearth.calendar:get_remaining_time(self._sv.renew_timer)
   end

   --Calculate renewal time based on stats
   local attributes = self._entity:get_component('stonehearth:attributes')
   if attributes then
      local modifier = attributes:get_attribute('renewable_resource_rate_multiplier', 1)
      renewal_time = radiant.math.round(renewal_time * modifier)
   end

   self:_stop_renew_timer()

   if renewal_time < 1 then
      -- It is possible for renewal time to be negative if the timer tracker falls behind actual game clock
      -- This will sometimes happen on load when we get really large game ticks
      renewal_time = 1
   end

   self._sv.renew_timer = stonehearth.calendar:set_persistent_timer("RenewableResourceNodeComponent renew", renewal_time,
      function ()
         self:renew()
      end
   )

   if self._json.half_renewed_model or self._json.half_renewed_model_variant then
      renewal_time = renewal_time / 2
      if renewal_time >= 1 then
         self._sv.half_renew_timer = stonehearth.calendar:set_persistent_timer("RenewableResourceNodeComponent half-renew", renewal_time,
            function ()
               self:_set_model_half_renewed()
            end
         )
      end
   end
end

AceRenewableResourceNodeComponent._ace_old__stop_renew_timer = RenewableResourceNodeComponent._stop_renew_timer
function AceRenewableResourceNodeComponent:_stop_renew_timer()
   if self._sv.half_renew_timer then
      self._sv.half_renew_timer:destroy()
      self._sv.half_renew_timer = nil
   end

   self:_ace_old__stop_renew_timer()
end

AceRenewableResourceNodeComponent._ace_old__place_spawned_items = RenewableResourceNodeComponent._place_spawned_items
function AceRenewableResourceNodeComponent:_place_spawned_items(json, owner, location, will_destroy_entity)
   local spawned_items, item = self:_ace_old__place_spawned_items(json, owner, location, will_destroy_entity)

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

function AceRenewableResourceNodeComponent:cancel_harvest_request()
   log:debug('canceling auto harvest for %s', self._entity)
   self:_cancel_harvest_request()
end

return AceRenewableResourceNodeComponent
