local Mission = require 'stonehearth.services.server.game_master.controllers.missions.mission'
local AceRaidCropsMission = class()

function AceRaidCropsMission:can_start(ctx, info)
   if not Mission.can_start(self, ctx, info) then
      return false
   end
   --Only do this if the players are hostile to each other
   if ctx.npc_player_id and ctx.player_id and
      not stonehearth.player:are_player_ids_hostile(ctx.npc_player_id, ctx.player_id) then
      return false
   end

   assert(ctx)
   assert(ctx.enemy_location)
   assert(info)
   assert(ctx.npc_player_id)

   --Check if there are farms that are growing things. If there are no farms, don't do this
   local town = stonehearth.town:get_town(ctx.player_id)
   local farms = town:get_farms()
   if farms then
      for _, farm in ipairs(farms) do
         local field_component = farm:get_component('stonehearth:farmer_field')
         if field_component and field_component:has_crops() then
            -- if specific farm field types are required, check if this is one of those types
            if not info.required_field_type or info.required_field_type[field_component:get_field_type()] then
               return true
            end
         end
      end
   end

   --If we get here there were no fields w/ crops
   return false
end

function AceRaidCropsMission:_find_closest_farm()
   local ctx = self._sv.ctx
	local info = self._sv.info
   local town = stonehearth.town:get_town(ctx.player_id)
   local farms = town:get_farms()

   if not farms then
      return nil
   end

   local best_dist, best_farm
   for id, farm in pairs(farms) do
      local location = radiant.entities.get_world_grid_location(farm)
      local farm_component = farm:get_component('stonehearth:farmer_field')
		if not info.required_field_type or info.required_field_type[farm_component:get_field_type()] then
         if farm_component:has_crops() then
            local cube = farm_component:get_bounds()
            local dist = cube:distance_to(ctx.enemy_location)
            if not best_dist or dist < best_dist then
               best_dist = dist
               best_farm = farm
            end
         end
		end
   end
   
   return best_farm
end

function AceRaidCropsMission:destroy()
   Mission.__user_destroy(self)
   self:stop()
end

return AceRaidCropsMission
