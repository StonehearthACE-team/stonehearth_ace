local Entity = _radiant.om.Entity
local ConsumablesLib = require 'stonehearth.ai.lib.consumables_lib'

local UseEquippedConsumable = radiant.class()
UseEquippedConsumable.name = 'use equipped consumable'
UseEquippedConsumable.does = 'stonehearth:top'
UseEquippedConsumable.args = {}
UseEquippedConsumable.think_output = {}
UseEquippedConsumable.priority = 0.96   -- TODO: figure out an appropriate priority for this; it should take priority over most/all non-compelled behavior

local log = radiant.log.create_logger('use_equipped_consumable')

function UseEquippedConsumable:start_thinking(ai, entity, args)
   self._ai = ai
   self._entity = entity
   self._ready = false
   
   self._usable_listener = radiant.events.listen(entity, 'stonehearth_ace:equipped_consumable:usable', self, self._on_equipped_consumable_usable)
   self._incapacitate_listener = radiant.events.listen(entity, 'stonehearth:entity:incapacitate_state_changed', self, self._on_incapacitate_state_changed)
end

function UseEquippedConsumable:_on_equipped_consumable_usable(recheck_fn)
   log:debug('_on_equipped_consumable_usable')
   local consumable_changed = self:_update_equipped_consumable()
   self._recheck_fn = recheck_fn

   -- the equipped consumable may have changed (these are async events so they may have swapped to a new one that can't be used yet)
   -- if so, we need to check if the new one is usable; if not, unready
   if consumable_changed then
      if not recheck_fn() then
         self:_unready_up()
         return
      end
   end

   if not self:_is_incapacitated() then
      self:_ready_up()
   end
end

function UseEquippedConsumable:_on_incapacitate_state_changed()
   self:_update_equipped_consumable()

   if not self:_is_incapacitated() then
      log:debug('no longer incapacitated; rechecking if usable')
      if self._recheck_fn and self._recheck_fn() then
         self:_ready_up()
      else
         self:_unready_up()
      end
   end
end

-- returns true if the consumable has changed (but not from nil)
function UseEquippedConsumable:_update_equipped_consumable()
   local prev_equipped = self._equipped_consumable
   self._equipped_consumable = self:_get_equipped_consumable()
   if not self._equipped_consumable then
      self._recheck_fn = nil
      self._ignore_incapacitate = nil
      return prev_equipped ~= nil
   end

   local different = prev_equipped and (not prev_equipped:is_valid() or prev_equipped:get_id() ~= self._equipped_consumable:get_id())

   if not prev_equipped or different then
      local consumable_data = self._equipped_consumable and ConsumablesLib.get_consumable_data(self._equipped_consumable)
      self._ignore_incapacitate = consumable_data and consumable_data.usable_while_incapacitated
   end

   if different then
      self._recheck_fn = nil
      return true
   end
end

function UseEquippedConsumable:_ready_up()
   log:debug('ready up! (was %s)', tostring(self._ready))
   if not self._ready then
      self._ready = true
      self._ai:set_think_output({})
   end
end

function UseEquippedConsumable:_unready_up()
   log:debug('UNready up! (was %s)', tostring(self._ready))
   if self._ready then
      self._ready = false
      self._ai:clear_think_output()
   end
end

function UseEquippedConsumable:_is_incapacitated()
   if not self._ignore_incapacitate then
      local incapacitation = self._entity:get_component('stonehearth:incapacitation')
      return incapacitation and incapacitation:is_incapacitated()
   end
end

function UseEquippedConsumable:_get_equipped_consumable()
   local equipment_comp = self._entity:get_component('stonehearth:equipment')
   return equipment_comp and equipment_comp:get_item_in_slot('consumable')
end

function UseEquippedConsumable:stop_thinking(ai, entity)
   self:_destroy_listeners()
end

function UseEquippedConsumable:stop(ai, entity)
   self:_destroy_listeners()
end

function UseEquippedConsumable:_destroy_listeners()
   if self._usable_listener then
      self._usable_listener:destroy()
      self._usable_listener = nil
   end
   if self._incapacitate_listener then
      self._incapacitate_listener:destroy()
      self._incapacitate_listener = nil
   end
end

function UseEquippedConsumable:run(ai, entity, args)
   local equipment_comp = entity:get_component('stonehearth:equipment')
   local consumable = equipment_comp and equipment_comp:get_item_in_slot('consumable')
   if consumable then
      if ConsumablesLib.use_consumable(consumable, entity, entity) then
         local data = ConsumablesLib.get_consumable_data(consumable)
         if data.use_effect then
            ai:execute('stonehearth:run_effect', { effect = data.use_effect })
         end
         radiant.entities.destroy_entity(consumable)
      end
   end
end

return UseEquippedConsumable
