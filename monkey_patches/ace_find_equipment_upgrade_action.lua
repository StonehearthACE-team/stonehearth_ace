local FindEquipmentUpgrade = require 'stonehearth.ai.actions.upgrade_equipment.find_equipment_upgrade_action'
local AceFindEquipmentUpgrade = radiant.class()

function AceFindEquipmentUpgrade:start_thinking(ai, entity, args)
   self._ai = ai
   self._entity = entity
   self._ready = false
   self._inventory = stonehearth.inventory:get_inventory(radiant.entities.get_player_id(entity))

   if self._inventory then
      self._tracker = self._inventory:add_item_tracker('stonehearth:equipment_tracker')
      self:_check_all_tracker_equipment()
      self._added_listener = radiant.events.listen(self._tracker, 'stonehearth:inventory_tracker:item_added', self, self._on_equipment_item_added)
      self._job_changed_listener = radiant.events.listen(self._entity, 'stonehearth:job_changed', self, self._on_job_changed)
      self._job_level_changed_listener = radiant.events.listen(self._entity, 'stonehearth:level_up', self, self._on_job_changed)
      
      -- added for ACE:
      self._role_changed_listener = radiant.events.listen(self._entity, 'stonehearth_ace:equipment_role_changed', self, self._on_job_changed)
   end
end

AceFindEquipmentUpgrade._ace_old_destroy = FindEquipmentUpgrade.destroy
function AceFindEquipmentUpgrade:destroy()
   self:_ace_old_destroy()

   if self._role_changed_listener then
      self._role_changed_listener:destroy()
      self._role_changed_listener = nil
   end
end

return AceFindEquipmentUpgrade
