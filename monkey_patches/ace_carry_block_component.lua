local CarryBlock = radiant.mods.require('stonehearth.components.carry_block.carry_block_component')
local Point3 = _radiant.csg.Point3
local log = radiant.log.create_logger('carry_block')

local AceCarryBlock = class()

function AceCarryBlock:set_carrying(new_item, opt_relative_orientation)
   if not new_item or not new_item:is_valid() then
      log:info('%s set_carrying to nil or invalid item', self._entity)
      self:_remove_carrying()
      return
   end

   if new_item == self._sv._carried_item then
      return
   end
	
	-- ACE: This part fixes the issue of characters with backpacks carrying people in their backpacks (Dani)
	if new_item:get_component('stonehearth:incapacitation') then 
		radiant.entities.set_posture(self._entity, 'stonehearth:carrying')
	end

   if self._sv._carried_item then
      self:_destroy_carried_item_trace()
   else
      radiant.entities.add_buff(self._entity, 'stonehearth:buffs:carrying')
   end

   self._sv._carried_item = new_item
   self._is_carrying_cache = true
   --self.__saved_variables:mark_changed()

   log:info('%s adding %s to carry bone', self._entity, new_item)

   self._entity:add_component('entity_container')
                     :add_child_to_bone(new_item, 'carry')
   radiant.entities.move_to_grid_aligned(new_item, Point3.zero)

   -- ACE: update the basic inventory tracker to properly display in the town inventory
   -- maybe this should reconsider all trackers? with inventory:update_item_container(new_item:get_id(), nil, true)
   local inventory = stonehearth.inventory:get_inventory(new_item:get_player_id())
   inventory:get_item_tracker('stonehearth:basic_inventory_tracker'):reevaluate_item(new_item)

   if opt_relative_orientation then
      radiant.entities.turn_to(new_item, opt_relative_orientation)
   end

   self:_create_carried_item_trace()
   radiant.events.trigger_async(self._entity, 'stonehearth:carry_block:carrying_changed')
end

AceCarryBlock._ace_old__remove_carrying = CarryBlock._remove_carrying
function CarryBlock:_remove_carrying()
   if self._sv._carried_item and self._sv._carried_item:get_component('stonehearth:incapacitation') then
		radiant.entities.unset_posture(self._entity, 'stonehearth:carrying')
   end
	
	self:_ace_old__remove_carrying()
end

return AceCarryBlock
