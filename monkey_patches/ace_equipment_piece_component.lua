local catalog_lib = require 'stonehearth.lib.catalog.catalog_lib'
local EquipmentPieceComponent = require 'stonehearth.components.equipment_piece.equipment_piece_component'
local AceEquipmentPieceComponent = class()
local log = radiant.log.create_logger('equipment_piece')

AceEquipmentPieceComponent.EQUIPMENT_PREFERENCE_MULTIPLIER = 10

function AceEquipmentPieceComponent:get_required_job_level(job)
   return (job and self._json.required_job_levels and self._json.required_job_levels[job]) or self._json.required_job_level or 0
end

function AceEquipmentPieceComponent:is_upgrade_for(unit)
   -- upgradable items have a slot.  if there's not slot (e.g. the job outfits that
   -- just contain abilities), there's no possibility for upgrade
   local slot = self:get_slot()
   if not slot then
      return false
   end

   -- if the unit can't wear equipment, obviously not an upgrade!  similarly, if the
   -- unit has no job, we can't figure out if it can wear this
   local equipment_component = unit:get_component('stonehearth:equipment')
   local job_component = unit:get_component('stonehearth:job')
   if not equipment_component or not job_component then
      return false
   end

   -- if we're not suitable for the unit, bail. (if we don't have a job, bail)
   local job_roles = job_component:get_roles()
   if not job_roles or not self:suitable_for_roles(job_roles) then
      return false
   end

   if self:get_required_job_level(job_component:get_job_uri()) > job_component:get_current_job_level() then
      -- not high enough level to equip this
      return false
   end

   -- even if we don't have something equipped in this slot, if this item would have a negative value, don't equip it
   local this_value = self:get_value(job_component)
   if not this_value or this_value < 0 then
      return false
   end

   -- if we're not better than what's currently equipped, bail
   local equipped = equipment_component:get_item_in_slot(slot)
   if equipped and equipped:is_valid() then
      local current_value = equipped:get_component('stonehearth:equipment_piece'):get_value(job_component)
      if not current_value or current_value >= this_value then
         -- if current value is nil, that means the item is not unequippable. It's linked to another item
         return false
      end
   end

   -- finally!!!  this is good.  use it!
   return true
end

-- returns nil if the item is not unequippable; returns a numeric value otherwise
function AceEquipmentPieceComponent:get_value(job_component)
	-- evaluate the value of this item for the purposes of comparing to others for upgrading
	local value = self:get_ilevel()
	-- if current ilevel is < 0, that means the item is *probably* not unequippable. It's linked to another item
	if value < 0 and not self:get_can_unequip() then
		return nil
	end

	local conditional_types = self._json.conditional_values
	for condition_type, conditional_values in pairs(conditional_types or {}) do
		for condition, conditional_value in pairs(conditional_values) do
			value = value + self:_get_conditional_value(condition_type, condition, conditional_value)
		end
	end

   local equipment_types = self:_get_equipment_types()
   local job_equip_prefs = job_component and job_component:get_equipment_preferences()
   if job_equip_prefs then
      for _, pref_type in ipairs(job_equip_prefs.types) do
         if equipment_types[pref_type] then
            value = value * (job_equip_prefs.multiplier or AceEquipmentPieceComponent.EQUIPMENT_PREFERENCE_MULTIPLIER)
            break
         end
      end
   end

	return value
end

function AceEquipmentPieceComponent:_get_conditional_value(condition_type, condition, conditional_value)
	if condition_type == 'season' then
      local season = stonehearth.seasons:get_current_season()
		if season and condition == season.id then
			return conditional_value
		end
	end

	return 0
end

function AceEquipmentPieceComponent:_get_equipment_types()
   if not self._equipment_types then
      self._equipment_types = catalog_lib.get_equipment_types(self._json)
   end

   return self._equipment_types
end

function AceEquipmentPieceComponent:_get_injected_ai()
	return (self._injected_ai and self._injected_ai._injected) or {}
end

function AceEquipmentPieceComponent:has_ai_action(action_uri)
	local injected = self:_get_injected_ai()
	return injected.actions and injected.actions[action_uri]
end

function AceEquipmentPieceComponent:has_ai_pack(pack_uri)
	local ai_packs = (self._json and self._json.injected_ai and self._json.injected_ai.ai_packs) or {}
	for _, ai_pack in ipairs(ai_packs) do
		if ai_pack == pack_uri then
			return true
		end
	end
	return false
end

function AceEquipmentPieceComponent:has_ai_task_group(task_group_uri)
	local injected = self:_get_injected_ai()
	return injected.task_groups and injected.task_groups[task_group_uri]
end

function AceEquipmentPieceComponent:get_can_unequip()
   return self:get_ilevel() >= 0 or self._json.can_unequip == true
end

function AceEquipmentPieceComponent:_remove_buffs()
   if self._json.injected_buffs then
      for _, buff in ipairs(self._json.injected_buffs) do
         radiant.entities.remove_buff(self._sv.owner, buff, false);
      end
   end
end

return AceEquipmentPieceComponent
