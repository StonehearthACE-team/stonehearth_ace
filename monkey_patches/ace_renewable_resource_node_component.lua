local LootTable = require 'stonehearth.lib.loot_table.loot_table'
local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'
local util = require 'stonehearth_ace.lib.util'
local log = radiant.log.create_logger('renewable_resource_node')

local Point3 = _radiant.csg.Point3
local rng = _radiant.math.get_default_rng()

local RenewableResourceNodeComponent = require 'stonehearth.components.renewable_resource_node.renewable_resource_node_component'
local AceRenewableResourceNodeComponent = class()

local HARVEST_ACTION = 'stonehearth:harvest_renewable_resource'
local RENEWED_MODEL_NAME = 'stonehearth:renewable_resource_node:renewed'
local HALF_RENEWED_MODEL_NAME = 'stonehearth:renewable_resource_node:half_renewed'

function AceRenewableResourceNodeComponent:create()
   self._is_create = true
end

AceRenewableResourceNodeComponent._ace_old_activate = RenewableResourceNodeComponent.activate
function AceRenewableResourceNodeComponent:activate()
   self._renewal_time_multipliers = {}
   log:debug('%s RRN:activate() current model: %s', self._entity, self._entity:get_component('render_info'):get_model_variant())
   self:_ace_old_activate()
   if self._sv.half_renew_timer and self._sv.half_renew_timer.bind then
      self._sv.half_renew_timer:bind(function()
            self:_set_model_half_renewed()
         end)
   end

   if self._is_create and self._sv.harvestable then
      self:_reset_model()
   end
end

--AceRenewableResourceNodeComponent._ace_old_post_activate = RenewableResourceNodeComponent.post_activate
function AceRenewableResourceNodeComponent:post_activate()
   if not self._json then
      --self._entity:remove_component('stonehearth:renewable_resource_node')
      return
   end

   if self._json.biomes then
      -- if there are special biome modifiers to be applied, make sure we do so
      local biome_uri = stonehearth.world_generation:get_biome_alias()
      local modifiers = self._json.biomes[biome_uri]
      if modifiers then
         self:_apply_modifiers('biome', modifiers)
      end
   end

   -- if the world is being generated, don't try to set up renewal stuff yet (season isn't properly set)
   if self._json.seasons and not stonehearth.game_creation:is_world_created() then
      self._world_created_listener = radiant.events.listen_once(stonehearth.game_creation, 'stonehearth:world_generation_complete', function()
         self._season_change_listener = radiant.events.listen_once(stonehearth.seasons, 'stonehearth:seasons:initial_set', self, self._create_listeners)
      end)
   else
      self:_create_listeners()
   end

   local loot_table_filter_script = self._json.loot_table_filter_script
   if loot_table_filter_script == nil then
      self._loot_table_filter_script = 'stonehearth_ace:loot_table:filter_scripts:items_with_property_value'
   else
      self._loot_table_filter_script = loot_table_filter_script
      self._loot_table_filter_args = self._json.loot_table_filter_args
   end

   log:debug('%s RRN:post_activate() current model: %s', self._entity, self._entity:get_component('render_info'):get_model_variant())
end

AceRenewableResourceNodeComponent._ace_old_destroy = RenewableResourceNodeComponent.__user_destroy
function AceRenewableResourceNodeComponent:destroy()
   self:_destroy_listeners()
   self:_destroy_added_to_world_listener()

   self:_ace_old_destroy()
end

function AceRenewableResourceNodeComponent:_create_listeners()
   if self._json.seasons then
      self._season_change_listener = radiant.events.listen(stonehearth.seasons, 'stonehearth:seasons:changed', function()
         self:_check_season()
         self:_update_renew_timer(true)
      end)

      self:_check_season()
   end

   self:_initialize_renewal()
end

function AceRenewableResourceNodeComponent:_initialize_renewal()
   if self._sv.harvestable then
      --If we're harvestable on load, fire the harvestable event again,
      --in case we need to reinitialize tasks and other nonsavables on the event
      radiant.events.trigger(self._entity, 'stonehearth:on_renewable_resource_renewed', {target = self._entity, available_resource = self._resource})

      if self._is_create and self._json.auto_harvest_on_create ~= false then
         self._added_to_world_listener = self._entity:add_component('mob'):trace_parent('transform entity added or removed')
               :on_changed(function(parent)
                  if parent then
                     --log:debug('considering auto_harvest for %s', self._entity)
                     self:_destroy_added_to_world_listener()
                     self:auto_request_harvest()
                  end
               end)
      end
   elseif not self._sv.renew_timer then
      self:_update_renew_timer(true)
   end
end

function AceRenewableResourceNodeComponent:_destroy_added_to_world_listener()
   if self._added_to_world_listener then
      self._added_to_world_listener:destroy()
      self._added_to_world_listener = nil
   end
end

function AceRenewableResourceNodeComponent:_destroy_listeners()
   if self._season_change_listener then
      self._season_change_listener:destroy()
      self._season_change_listener = nil
   end
   if self._world_created_listener then
      self._world_created_listener:destroy()
      self._world_created_listener = nil
   end
end

function AceRenewableResourceNodeComponent:_check_season()
   if not self._entity:is_valid() then
      log:error('RRN destroy function is cached!')
      return
   end

   local season = stonehearth.seasons:get_current_season()
   local modifiers = season and self._json.seasons[season.id]
   --log:debug('%s applying season modifiers for %s: %s', self._entity, tostring(season.id), modifiers and radiant.util.table_tostring(modifiers) or 'NIL')
   self:_apply_modifiers('season', modifiers)
end

function AceRenewableResourceNodeComponent:_apply_modifiers(key, modifiers)
   self._renewal_time_multipliers[key] = modifiers and modifiers.renewal_time_multiplier or 1
   self._disabled = modifiers and modifiers.disable_renewal
   local is_harvestable = self:is_harvestable()
   if modifiers then
      if modifiers.drop_resource and is_harvestable then
         local x_offset = rng:get_int(0, 1) * 2
         local z_offset = (x_offset == 0 and 2) or (rng:get_int(0, 1) * 2)
         local offset = Point3(x_offset * (rng:get_int(0, 1) == 0 and -1 or 1), 0, z_offset * (rng:get_int(0, 1) == 0 and -1 or 1))
         self:spawn_resource(self._entity, radiant.entities.get_world_grid_location(self._entity) + offset, self._entity:get_player_id(), true)
      elseif modifiers.destroy_resource then
         self:_stop_renew_timer()
         if is_harvestable then
            self:_deplete()
         end
      end
   end

   if self._disabled then
      self:_stop_renew_timer()
   end
end

function AceRenewableResourceNodeComponent:auto_request_harvest()
   if not self:is_harvestable() then
      return
   end
   local player_id = self._entity:get_player_id()

   -- only try fully auto-harvesting if there are any inputs
   local output = self._entity:get_component('stonehearth_ace:output')
   if output and output:has_any_input(true) then
      local item = self:spawn_resource(nil, radiant.entities.get_world_grid_location(self._entity), player_id, false)
      if item then
         -- successfully auto-harvested; no need to request a manual harvest
         return
      end
   end

   -- if a player has moved or harvested this item, that player has gained ownership of it
   -- if they haven't, there's no need to request it to be harvested because it's just growing in the wild with no owner
   
   if player_id ~= '' then
      local auto_harvest
      -- if it's a crop, check the farm's harvest setting
      local crop_comp = self._entity:get_component('stonehearth:crop')
      if crop_comp then
         auto_harvest = crop_comp:get_field():is_harvest_enabled()
      else
         -- otherwise check pasture animal settings
         auto_harvest = self:_can_pasture_animal_renewably_harvest()
         -- if it's not a crop or an animal, check general auto harvest settings
         if auto_harvest == nil then
            auto_harvest = self:get_auto_harvest_enabled(player_id)
         end
      end
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

function AceRenewableResourceNodeComponent:spawn_resource(harvester_entity, location, owner_player_id, spill_items)
   if not self._json.spawn_resource_immediately or self:_can_pasture_animal_renewably_harvest() ~= false then
      local singular_item = self:_do_spawn_resource(harvester_entity, location, owner_player_id, spill_items ~= false)

      self:_update_renew_timer(true)

      return singular_item
   end
end

function AceRenewableResourceNodeComponent:_do_spawn_resource(harvester_entity, location, owner_player_id, spill_items)
   self:_cancel_harvest_request()
   local json = self._json

   local player_id = owner_player_id or radiant.entities.get_player_id(harvester_entity)
   local spawned_resources, singular_item = self:_place_spawned_items(json, harvester_entity, player_id, location, self._sv.durability and self._sv.durability <= 1, spill_items)

   if not spawned_resources then
      -- items weren't spawned; perhaps an attempt at auto-harvesting with no valid output
      return
   end

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
   if self._sv.durability then
      self._sv.durability = self._sv.durability - 1
      if self._sv.durability <= 0 then
         self._sv.harvestable = false
         radiant.entities.destroy_entity(self._entity)
         return singular_item
      end
   end

   --start the countdown to respawn.
   self:_deplete()
end

function AceRenewableResourceNodeComponent:_deplete()
   self:_set_model_depleted()

   --Change the description
   if self._json.unripe_description then
      radiant.entities.set_description(self._entity, self._json.unripe_description)
   end

   self._sv.harvestable = false
   self._sv._prev_rate_modifier = 1
   self.__saved_variables:mark_changed()
end

function AceRenewableResourceNodeComponent:_set_model_depleted()
   if self._json.half_renewed_model then
      self._entity:add_component('stonehearth_ace:models'):remove_model(HALF_RENEWED_MODEL_NAME)
	end
   if self._json.renewed_model then
      self._entity:add_component('stonehearth_ace:models'):remove_model(RENEWED_MODEL_NAME)	
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
   self:_destroy_half_renew_timer()
end

--- Reset the model to the default. Also, stop listening for effects
function AceRenewableResourceNodeComponent:_reset_model()
	if self._json.half_renewed_model then
      self._entity:add_component('stonehearth_ace:models'):remove_model(HALF_RENEWED_MODEL_NAME)
	end
   if self._json.renewed_model then
      self._entity:add_component('stonehearth_ace:models'):add_model(RENEWED_MODEL_NAME, self._json.renewed_model)
   else
      local render_info = self._entity:add_component('render_info')
      local seasonal_model_switcher = self._entity:get_component('stonehearth:seasonal_model_switcher')
      render_info:set_model_variant(seasonal_model_switcher and seasonal_model_switcher:get_last_applied_variant() or '')
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

   self:auto_request_harvest()
end

function AceRenewableResourceNodeComponent:_update_renew_timer(create_if_no_timer)
   if self._sv.paused or self._disabled then
      -- Do not update the timer if paused or disabled.
      return
   end

   local renewal_time = self._renewal_time
   local half_renewal_time = renewal_time / 2
   if self._sv.renew_timer then
      renewal_time = stonehearth.calendar:get_remaining_time(self._sv.renew_timer)
   elseif self:is_harvestable() or not create_if_no_timer then
      return
   end

   if self._sv.half_renew_timer then
      half_renewal_time = stonehearth.calendar:get_remaining_time(self._sv.half_renew_timer)
   end

   --Calculate renewal time based on stats
   local prev_modifier = self._sv._prev_rate_modifier or 1
   local modifier = 1
   for _, multiplier in pairs(self._renewal_time_multipliers) do
      modifier = modifier * multiplier
   end
   local attributes = self._entity:get_component('stonehearth:attributes')
   if attributes then
      modifier = modifier * attributes:get_attribute('renewable_resource_rate_multiplier', 1)
   end
   self._sv._prev_rate_modifier = modifier
   renewal_time = radiant.math.round(renewal_time * modifier / prev_modifier)
   half_renewal_time = radiant.math.round(half_renewal_time * modifier / prev_modifier)

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
   log:debug('%s set renew timer for duration %s', self._entity, renewal_time)

   if self._json.half_renewed_model or self._json.half_renewed_model_variant and half_renewal_time >= 1 then
      self._sv.half_renew_timer = stonehearth.calendar:set_persistent_timer("RenewableResourceNodeComponent half-renew", half_renewal_time,
         function ()
            self:_set_model_half_renewed()
         end
      )
      log:debug('%s set half-renewed timer for duration %s', self._entity, half_renewal_time)
   end

   self.__saved_variables:mark_changed()
end

AceRenewableResourceNodeComponent._ace_old__stop_renew_timer = RenewableResourceNodeComponent._stop_renew_timer
function AceRenewableResourceNodeComponent:_stop_renew_timer()
   self:_destroy_half_renew_timer()
   self:_ace_old__stop_renew_timer()
end

function AceRenewableResourceNodeComponent:_destroy_half_renew_timer()
   if self._sv.half_renew_timer then
      self._sv.half_renew_timer:destroy()
      self._sv.half_renew_timer = nil
   end
end

-- this can be called when a harvester entity (e.g., hearthling) tries to harvest, when season change or maturity triggers dropping resources,
-- or when an auto-harvest is attempted (in which case spilling is disabled)
-- in the latter case, if an item should've been created for harvest but there wasn't a place for it, cancel the harvest process (by just returning nil)
function AceRenewableResourceNodeComponent:_place_spawned_items(json, harvester, owner, location, will_destroy_entity, spill_items)
   local quality = radiant.entities.get_item_quality(self._entity)

   local spawned_items
   local item
   local failed
   local options = {
      owner = owner,
      inputs = harvester,
      output = self._entity,
      spill_fail_items = spill_items,
   }

   if json.resource_loot_table then
      local filter_args = self._loot_table_filter_args or (self._loot_table_filter_script and util.get_current_conditions_loot_table_filter_args())
      local uris = LootTable(json.resource_loot_table, quality, self._loot_table_filter_script, filter_args):roll_loot()
      if next(uris) then
         local output_items = radiant.entities.output_items(uris, location, 1, 3, options)
         spawned_items = output_items.spilled
         item = (next(spawned_items) and spawned_items[next(spawned_items)]) or (next(output_items.succeeded) and output_items.succeeded[next(output_items.succeeded)])
         failed = not item
      else
         spawned_items = {}
      end
   else
      spawned_items = {}
   end

   local resource = json.resource
   if resource then
      local uris = {[json.resource] = {[quality] = 1}}
      local items = radiant.entities.output_items(uris, location, 0, 2, options)
      --Create the harvested entity and put it on the ground
      item = (next(items.spilled) and items.spilled[next(items.spilled)]) or (next(items.succeeded) and items.succeeded[next(items.succeeded)])

      if item then
         -- only place it in a specific place if it wasn't pushed into an input
         if will_destroy_entity then
            radiant.terrain.place_entity_at_exact_location(item, location)
         end

         spawned_items[item:get_id()] = item
      else
         failed = true
      end
   end

   if not failed then
      return spawned_items, item
   end
end

function AceRenewableResourceNodeComponent:_set_quality(item, quality)
   item_quality_lib.apply_quality(item, quality)
end

function AceRenewableResourceNodeComponent:is_harvest_requested()
   local task_tracker_component = self._entity:get_component('stonehearth:task_tracker')
   if task_tracker_component and task_tracker_component:is_activity_requested(HARVEST_ACTION) then
      return true
   end
end

function AceRenewableResourceNodeComponent:cancel_harvest_request()
   log:debug('canceling auto harvest for %s', self._entity)
   self:_cancel_harvest_request()
end

return AceRenewableResourceNodeComponent
