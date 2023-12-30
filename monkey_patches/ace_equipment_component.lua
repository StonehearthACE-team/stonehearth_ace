local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'
local Entity = _radiant.om.Entity
local rng = _radiant.math.get_default_rng()
local log = radiant.log.create_logger('equipment_component')

local EquipmentComponent = require 'stonehearth.components.equipment.equipment_component'
local AceEquipmentComponent = class()

AceEquipmentComponent._ace_old_activate = EquipmentComponent.activate
function AceEquipmentComponent:activate()
   self:_ace_old_activate()

   if not self._sv.cached_equipment then
      self._sv.cached_equipment = {}
   end
   if not self._sv.caches then
      self._sv.caches = {}
   end
end

AceEquipmentComponent._ace_old_destroy = EquipmentComponent.__user_destroy
function AceEquipmentComponent:destroy()
   if self._menace_modifier then
      self._menace_modifier:destroy()
      self._menace_modifier = nil
   end

   self:_ace_old_destroy()
end

-- ACE override to make sure the placement point is pathable and takes into account mounting
function AceEquipmentComponent:drop_item(item)
   local ep = item:get_component('stonehearth:equipment_piece')
   if ep and (not ep:get_should_drop() or ep:should_destroy_on_drop()) then
      radiant.entities.destroy_entity(item)
      return
   end
   local parent = radiant.entities.get_parent(self._entity)
   local mount_component = parent and parent:get_component('stonehearth:mount')
   local location = mount_component and mount_component:get_dismount_location() or radiant.entities.get_world_grid_location(self._entity)
   if not location then
      radiant.entities.destroy_entity(item)
      return
   end

   local player_id = radiant.entities.get_player_id(self._entity)
   local town = stonehearth.town:get_town(player_id)
   local town_center_entity = town and (town:get_banner() or town:get_hearth())
   
   local placement_point = radiant.terrain.find_placement_point(location, 1, 4, nil, nil, town_center_entity or true)
   local placed_item = radiant.terrain.place_entity(item, placement_point)

   local inventory = stonehearth.inventory:get_inventory(player_id)
   if inventory then
      inventory:add_item(placed_item)
   end

   stonehearth.ai:reconsider_entity(placed_item, 'dropping equipment piece')
end

function AceEquipmentComponent:equip_item(item, destroy_old_item, quality_item)
   -- destroy the old item by default, unless explicitly told not to
   destroy_old_item = destroy_old_item ~= false

   -- if someone passes the uri, create an entity
   if not radiant.util.is_a(item, Entity) then
      if type(item) == 'string' then
         item = radiant.entities.create_entity(item)
      elseif type(item) == 'table' then
         -- pick an random item from the array
         item = radiant.entities.create_entity(item[rng:get_int(1, #item)])
      end

      -- if quality_item was specified, apply that
      if quality_item then
         item_quality_lib.copy_quality(quality_item, item)
      end
   end

   --TODO: Because of the current implementation of the shop, it is possible
   --to equip an item bought from the shop, and then sell that item off a
   --person's back. Final solution involves pausing the game while in the shop,
   --keeping track of all shop transactions, and then delivering results before
   --Once done, remove this code, because this mechanism of adding/removing to
   --the inventory is very brittle
   local inventory = stonehearth.inventory:get_inventory(radiant.entities.get_player_id(self._entity))
   if inventory then
      --There may not be an inventory in say, autotests
      inventory:remove_item(item:get_id())
   end

   -- if someone tries to equip a proxy, equip the full-sized item instead
   radiant.check.is_entity(item)
   local proxy = item:get_component('stonehearth:iconic_form')
   if proxy then
      item = proxy:get_root_entity()
   end
   local ep = item:get_component('stonehearth:equipment_piece')
   assert(ep, 'item is not an equipment piece')

   radiant.entities.set_player_id(item, self._entity)

   local slot = ep:get_slot()

   if not slot then
      -- no slot specified, make up a magic slot name
      slot = 'no_slot_' .. self._sv.no_slot_counter
      self._sv.no_slot_counter = self._sv.no_slot_counter + 1
   end

   -- unequip previous item in slot first, then assign the item to the slot
   local unequipped_item = self._sv.equipped_items[slot]
   if unequipped_item then
      local also_unequipped = unequipped_item:get_component('stonehearth:equipment_piece'):get_additional_equipment()
      self:unequip_item(unequipped_item)
      if also_unequipped then
         for unequip_uri, _ in pairs(also_unequipped) do
            local old_item = self:unequip_item(unequip_uri, true) -- Paul: this extra parameter is the only change to this function
            if old_item then
               self:drop_item(old_item)
            end
         end
      end
   end

   local additional_equipment = ep:get_additional_equipment()
   if additional_equipment then
      for uri, should_equip in pairs(additional_equipment) do
         if should_equip then
            local old_item = self:equip_item(uri, false, item)
            if old_item then
               self:drop_item(old_item)
            end
         end
      end
   end

   self._sv.equipped_items[slot] = item

   ep:equip(self._entity)

   if destroy_old_item and unequipped_item then
      radiant.entities.destroy_entity(unequipped_item)
   end

   self.__saved_variables:mark_changed()
   self:_trigger_equipment_changed()

   return unequipped_item, item
end

-- takes an enity or a uri
function AceEquipmentComponent:unequip_item(equipped_item, replace_with_default, cache_key)
   local uri

   if type(equipped_item) == 'string' then
      uri = equipped_item
   else
      uri = equipped_item:get_uri()
   end

   local unequipped_item
   for key, item in pairs(self._sv.equipped_items) do
      local item_uri = item:get_uri()

      if item_uri == uri then
         -- remove the item from the slot
         self._sv.equipped_items[key] = nil

         item:get_component('stonehearth:equipment_piece'):unequip()

         self.__saved_variables:mark_changed()
         self:_trigger_equipment_changed()

         unequipped_item = item
         break
      end
   end

   -- check if there's a default item for the slot that we want to replace it with
   if unequipped_item and replace_with_default then
      local ep_data = radiant.entities.get_component_data(unequipped_item, 'stonehearth:equipment_piece')
      local slot = ep_data.slot

      -- first check if we have an item cached for that slot that we had previously unequipped
      local prev_item = self._sv.cached_equipment[slot]
      if prev_item and prev_item.key == cache_key then
         self._sv.cached_equipment[slot] = nil
         if prev_item.old then
            self:equip_item(prev_item.old)
         end
      else
         local job = self._entity:get_component('stonehearth:job')
         if slot and job then
            -- get the job and see if we have a default equipment item for this slot
            local uris = job:get_job_equipment_uris()
            if uris[slot] then
               self:equip_item(uris[slot])
            end
         end
      end
   end

   return unequipped_item
end

function AceEquipmentComponent:has_cache(key)
   return self._sv.caches[key]
end

function AceEquipmentComponent:cache_equipment(key, add_equipment, unequip_slots)
   if self._sv.caches[key] then
      -- we already have a cache for this key; don't try to apply it again, even if it's from a different source
      return true
   end

   local is_cached = false

   if add_equipment then
      for _, equipment in ipairs(add_equipment) do
         local slot = self:_cache_add_equipment(equipment, key)
         if slot then
            is_cached = true
         end
		end
   end

   if unequip_slots then
      for _, slot in ipairs(unequip_slots) do
         is_cached = is_cached or self:_cache_unequip_slot(slot, key)
		end
   end

   if is_cached then
      self._sv.caches[key] = true
      self.__saved_variables:mark_changed()

      return true
   end
end

function AceEquipmentComponent:_cache_add_equipment(uri, key)
   local ep_data = radiant.entities.get_component_data(uri, 'stonehearth:equipment_piece')
   local slot = ep_data and ep_data.slot

   if slot then
      if not self._sv.cached_equipment[slot] then
         local unequipped, item = self:equip_item(uri, false)
         if item then
            self._sv.cached_equipment[slot] = {
               old = unequipped,
               new = item,
               key = key
            }
            return slot
         end
      end
   end
end

function AceEquipmentComponent:_cache_unequip_slot(slot, key)
   if self._sv.equipped_items[slot] and not self._sv.cached_equipment[slot] then
      self._sv.cached_equipment[slot] = {
         old = self:unequip_item(self._sv.equipped_items[slot]),
         key = key
      }
      return true
   end
end

function AceEquipmentComponent:reset_cached(key)
   for slot, item in pairs(self._sv.cached_equipment) do
      if item.key == key then
         local equipped = self._sv.equipped_items[slot]
         if item.old then
            if not equipped or item.new == equipped then
               self:equip_item(item.old, true)
            else
               -- otherwise, if we're not restoring it, we need to destroy the cached equipment item
               radiant.entities.destroy_entity(item.old)
            end
         elseif equipped and item.new == equipped then
            self:unequip_item(equipped)
            radiant.entities.destroy_entity(equipped)
         end

         self._sv.cached_equipment[slot] = nil
      end
   end

   self._sv.caches[key] = nil
   self.__saved_variables:mark_changed()
end

-- ACE: also update quality-based buff to menace
function AceEquipmentComponent:_update_score()
   local equipment
   local strength_score = 0
   local quality_score = 0
   local quality_lookup = stonehearth.constants.item_quality.bonuses.menace or {}

   for key, item in pairs(self._sv.equipped_items) do
      if item and item:is_valid() then
         local item_piece = item:get_component('stonehearth:equipment_piece')
         assert(item_piece, 'no equipment_piece found on item ' .. tostring(item or '<nil>'))
         strength_score = strength_score + math.floor(item_piece:get_score_contribution())
         quality_score = quality_score + (quality_lookup[radiant.entities.get_item_quality(item)] or 0)
      end
   end

   self:_update_menace(quality_score)
   stonehearth.score:change_score(self._entity, 'military_strength', 'equipment', strength_score)
end

function AceEquipmentComponent:_update_menace(value)
   if self._menace_modifier then
      self._menace_modifier:destroy()
      self._menace_modifier = nil
   end

   if value ~= 0 then
      local attributes_component = self._entity:add_component('stonehearth:attributes')
      self._menace_modifier = attributes_component:modify_attribute('menace', { add = value })
   end
end

return AceEquipmentComponent
