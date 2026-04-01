-- Based on BrunoSupremo's awesome Beast Master traps
local TrapBuff = class()

function TrapBuff:on_buff_added(entity, buff)
   self._tuning = buff:get_json().script_info
   self._entity = entity
   local buff_uri = buff:get_uri()
   self._buff_uri = buff_uri
   local trap_owner = self._tuning.trap_owner == 'self' and entity:get_player_id() or self._tuning.trap_owner or ''
   local facing = self._tuning.facing or radiant.entities.get_facing(entity)
   local equip_when_added = self._tuning.equip_when_added
   local only_in_combat = self._tuning.only_in_combat
   
   if not self._tuning.trap_uri then
      return
   end

   if equip_when_added then
      local equipment = entity:get_component('stonehearth:equipment')
      if equipment then
         equipment:equip_item(equip_when_added)
      end
   end
   
   self._trap = radiant.entities.create_entity(self._tuning.trap_uri, { owner = trap_owner} )
   
   local unit_info = entity:get_component('stonehearth:unit_info')
   if unit_info and self._tuning.inherit_target_name then
      local custom_name = unit_info:get_custom_name()
      if custom_name then
         local trap_unit_info = self._trap:add_component('stonehearth:unit_info')
         if trap_unit_info then
            trap_unit_info:set_custom_name(custom_name)
         end
      end
   end
   
   if self._tuning.scale_with_target ~= false then
      local radius = radiant.entities.get_entity_data(entity, 'stonehearth:entity_radius')
      if not radius then
         radius = entity:get_component("render_info"):get_scale() * self._tuning.scale_multiplier or 2
      else
         radius = radius/4
      end
      if radius < 0.1 then radius = 0.1 end
      if radius > 1 then radius = 1 end
      self._trap:get_component("render_info"):set_scale(radius)
   end
   
   local location = radiant.entities.get_world_location(entity)
   radiant.terrain.place_entity_at_exact_location(self._trap, location)
   if facing then
      radiant.entities.turn_to(self._trap, facing)
   end

   -- Create listener for changing combat state
   if only_in_combat then
		self._combat_battery_listener = radiant.events.listen(self._entity, 'stonehearth:combat:in_combat_changed', self, self._in_combat_changed)
   end
   
   -- Create listeners for removing the buff if the trap is destroyed (if it can be destroyed)
   self._trap_killed_listener = radiant.events.listen(self._trap, 'stonehearth:kill_event', function()
      self._trap = nil
      radiant.entities.remove_buff(entity, buff_uri)
   end)

   -- Finally, create listeners for the buff to remove itself if the entity has the incapacitation component and goes incapacitated
   if entity:get_component("stonehearth:incapacitation") then
      self._entity_incapacitated_listener = radiant.events.listen(entity, 'stonehearth:entity:became_incapacitated', function()
         radiant.entities.kill_entity(self._trap)
         radiant.entities.remove_buff(entity, buff_uri)
      end)
   end
end

function TrapBuff:_in_combat_changed(context)
	if context.in_combat then
      return
	else
		radiant.entities.remove_buff(self._entity, self._buff_uri)
	end
end

function TrapBuff:on_buff_removed(entity, buff)
   if self._trap then
      radiant.entities.destroy_entity(self._trap)
   end

   if self._tuning.equip_when_removed then
      local incapacitated_comp = entity:get_component("stonehearth:incapacitation")
      if incapacitated_comp and not incapacitated_comp:is_incapacitated() then
         local equipment = entity:get_component('stonehearth:equipment')
         if equipment then
            equipment:equip_item(self._tuning.equip_when_removed)
         end
      end
   end

   if self._tuning.kill_on_expire and buff and buff:is_duration_expired() then
      local resources = entity:get_component('stonehearth:expendable_resources')
      if resources then
         -- Can't just kill them because for hearthlings we want incapacitation, not permanent death
         local max_health = resources:get_max_value('health')
         if max_health then
            radiant.entities.modify_health(entity, -(max_health))
         end
      end    
   end

   if self._combat_battery_listener then
      self._combat_battery_listener:destroy()
      self._combat_battery_listener = nil
   end
   
   if self._trap_killed_listener then
      self._trap_killed_listener:destroy()
      self._trap_killed_listener = nil
   end

   if self._entity_incapacitated_listener then
      self._entity_incapacitated_listener:destroy()
      self._entity_incapacitated_listener = nil
   end
end

return TrapBuff