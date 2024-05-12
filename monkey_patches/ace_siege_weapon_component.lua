local SiegeWeaponComponent = require 'stonehearth.components.siege_weapon.siege_weapon_component'
local Point3 = _radiant.csg.Point3
local AceSiegeWeaponComponent = class()

AceSiegeWeaponComponent._ace_old_activate = SiegeWeaponComponent.activate
function AceSiegeWeaponComponent:activate()
   self:_ace_old_activate()

   if self._json.passive_refill and not self._interval_listener then
      local interval = self._json.passive_refill.interval or "30m"
      local amount = self._json.passive_refill.amount or 1
      self._interval_listener = stonehearth.calendar:set_interval("Siege Weapon passive refilling "..self._entity:get_id().." interval", interval, 
            function()
               self:_on_interval(amount)
            end)
   end
end

function AceSiegeWeaponComponent:_on_interval(amount)
   if not self:needs_refill() then
      return
   end

   self:refill_uses(amount)
end

-- Subtract from num uses when target is hit with ammo
-- When no more uses, run destroy animation and destroy self
function AceSiegeWeaponComponent:_on_target_hit(context)
   local json = self._json or radiant.entities.get_json(self)
   local disposable = json and json.disposable or false
   local num_uses = self._sv.num_uses - 1
   if num_uses <= 0 then
      if disposable then
         radiant.entities.kill_entity(self._entity)
      end
      self._out_of_ammo = true
   end
   self._sv.num_uses = num_uses
   if self:needs_refill() and not self._json.passive_refill then
      radiant.events.trigger(self._entity, 'stonehearth:siege_weapon:needs_refill')
   end
   self.__saved_variables:mark_changed()
end

function AceSiegeWeaponComponent:_on_kill_event(args)
   local kill_data = args.kill_data
   local player_id = radiant.entities.get_player_id(self._entity)
   if kill_data and kill_data.source_id == player_id or self._json.ignore_replacing then
      return -- don't replace with ghost if destroyed/cleared by the user or if there should be no replacing
   end
   local town = stonehearth.town:get_town(player_id)
   local limit_data = radiant.entities.get_entity_data(self._entity:get_uri(), 'stonehearth:item_placement_limit') or nil
   if town and limit_data then
      if town:is_placeable(limit_data) then
         local location = radiant.entities.get_world_grid_location(self._entity)
         local parent = radiant.entities.get_parent(self._entity)
         if location and parent and radiant.terrain.is_standable(self._entity, location) then -- make sure location is valid
            local placement_info = {
                  location = location,
                  normal = Point3(0, 1, 0),
                  rotation = self._sv._original_rotation or 0,
                  structure = parent,
               }
            local ghost_entity = town:place_item_type(self._entity:get_uri(), nil, placement_info)
         end
      end
   elseif town then
      local location = radiant.entities.get_world_grid_location(self._entity)
      local parent = radiant.entities.get_parent(self._entity)
      if location and parent and radiant.terrain.is_standable(self._entity, location) then
         local placement_info = {
               location = location,
               normal = Point3(0, 1, 0),
               rotation = self._sv._original_rotation or 0,
               structure = parent,
            }
         local ghost_entity = town:place_item_type(self._entity:get_uri(), nil, placement_info)
      end
   end
end

function AceSiegeWeaponComponent:_register_with_town(register)
   local player_id = radiant.entities.get_player_id(self._entity)
   local town = stonehearth.town:get_town(player_id)
   local limit_data = radiant.entities.get_entity_data(self._entity:get_uri(), 'stonehearth:item_placement_limit') or nil
   if town and limit_data then
      if register then
         town:register_limited_placement_item(self._entity, self._siege_type)
      else
         town:unregister_limited_placement_item(self._entity, self._siege_type)
      end
   end
end

AceSiegeWeaponComponent._ace_old__destroy_traces = SiegeWeaponComponent._destroy_traces
function AceSiegeWeaponComponent:_destroy_traces()
   if self._interval_listener then
      self._interval_listener:destroy()
      self._interval_listener = nil
   end

   self:_ace_old__destroy_traces()
end

return AceSiegeWeaponComponent
