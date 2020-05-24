local Entity = _radiant.om.Entity
local ConsumablesLib = require 'stonehearth.ai.lib.consumables_lib'

local UseEquippedConsumable = radiant.class()
UseEquippedConsumable.name = 'use equipped consumable'
UseEquippedConsumable.does = 'stonehearth:top'
UseEquippedConsumable.args = {}
UseEquippedConsumable.think_output = {}
UseEquippedConsumable.priority = 0.5   -- TODO: figure out an appropriate priority for this; it should take priority over most/all non-compelled behavior

local log = radiant.log.create_logger('use_equipped_consumable')

function UseEquippedConsumable:start_thinking(ai, entity, args)
   self._ai = ai
   self._entity = entity
   self._ready = false
   
   self._usable_listener = radiant.events.listen(entity, 'stonehearth_ace:equipped_consumable:usable', self, self._on_equipped_consumable_usable)
   self._incapacitate_listener = radiant.events.listen(entity, 'stonehearth:entity:incapacitate_state_changed', self, self._on_incapacitate_state_changed)
end

function UseEquippedConsumable:_on_equipped_consumable_usable(recheck_fn)
   self._recheck_fn = recheck_fn

   log:debug('consumable is usable; checking incapacitated')
   if not self:_is_incapacitated() then
      self:_ready_up()
   end
end

function UseEquippedConsumable:_on_incapacitate_state_changed()
   if not self:_is_incapacitated() then
      log:debug('no longer incapacitated; rechecking if usable')
      if self._recheck_fn and self._recheck_fn() then
         self:_ready_up()
      else
         self:_unready_up()
      end
   end
end

function UseEquippedConsumable:_ready_up()
   log:debug('ready up! (%s)', tostring(self._ready))
   if not self._ready then
      self._ready = true
      self._ai:set_think_output({})
   end
end

function UseEquippedConsumable:_unready_up()
   log:debug('UNready up! (%s)', tostring(self._ready))
   if self._ready then
      self._ready = false
      self._ai:clear_think_output()
   end
end

function UseEquippedConsumable:_is_incapacitated()
   local incapacitation = self._entity:get_component('stonehearth:incapacitation')
   return incapacitation and incapacitation:is_incapacitated()
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
