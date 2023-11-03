local game_master_lib = require 'stonehearth.lib.game_master.game_master_lib'
local rng = _radiant.math.get_default_rng()
local TrickedScript = class()

function TrickedScript:start(ctx, data)
   self._sv.ctx = ctx
   self._sv.data = data
   self._sv.bulletin = nil

   if data.bulletin then
      self:create_bulletin(data.bulletin)
   end

   if data.spawn_visitors then
      self:spawn_visitors(data.spawn_visitors.visitors, data.spawn_visitors.stay or '2h+50m')
   end

   if data.frog_rain then
      self:frog_rain()
   end

   if data.buff_citizens then
      self:buff_citizens()
   end

   if data.destroy_crops then
      self:destroy_crops(data.destroy_crops.chance or 0.5)
   end

   if data.decay_items then
      self:decay_items(data.decay_items.material, data.decay_items.chance or 0.5)
   end
end

function TrickedScript:create_bulletin(bulletin)
   local bulletin_data = {
      title = bulletin.title,
      notification_closed_callback = '_on_closed'
   }
   
   self._sv.bulletin = stonehearth.bulletin_board:post_bulletin(self._sv.ctx.player_id)
         :set_callback_instance(self)
         :set_type(bulletin.type or "alert")
         :set_sticky(true)
         :set_data(bulletin_data)
end

function TrickedScript:spawn_visitors(visitors, stay)
   local player_id = self._sv.ctx.player_id
   local town = stonehearth.town:get_town(player_id)
   self._sv.visitors = {}

   if town then
      local town_landing_location = town:get_landing_location()
      local pop = stonehearth.population:get_population('human_npcs')

      for citizen, gender in pairs(visitors) do
         local visitor = pop:create_new_citizen(citizen, gender)
         local adjusted_location = radiant.terrain.find_placement_point(town_landing_location, 15, 50)
         radiant.terrain.place_entity(visitor, adjusted_location)
         stonehearth.ai:inject_ai(visitor, { task_groups = { "stonehearth:task_groups:solo:conversation" } })
         radiant.effects.run_effect(visitor, 'stonehearth:effects:spawn_entity')
         table.insert(self._sv.visitors, visitor)
      end

      self._sv.despawn_timer = stonehearth.calendar:set_persistent_timer('despawn visitors', stay, radiant.bind(self, '_despawn_visitors'))
   end
end

function TrickedScript:_despawn_visitors()
	for _, visitor in ipairs(self._sv.visitors) do
		if radiant.entities.exists(visitor) then
			visitor:get_component('stonehearth:ai')
					 :get_task_group('stonehearth:task_groups:solo:unit_control')
					 :create_task('stonehearth:depart_visible_area', { give_up_after = '1h' })
                :start()
		end
	end
end

function TrickedScript:frog_rain()
   local player_id = self._sv.ctx.player_id
   self._frog_spawn_interval = stonehearth.calendar:set_interval('frog spawn', '8m+8m', function()
         self:_spawn_frog()
      end)
   self:_spawn_frog()
end

function TrickedScript:_spawn_frog()
   local bounds = stonehearth.terrain:get_territory(self._sv.ctx.player_id):get_region():get_bounds()
   local x = rng:get_int(bounds.min.x, bounds.max.x)
   local z = rng:get_int(bounds.min.y, bounds.max.y)
   local location = radiant.terrain.get_point_on_terrain(_radiant.csg.Point3(x, 0, z))
   location.y = location.y + 50
   local frog = radiant.entities.create_entity('stonehearth_ace:candledark:frog')
   radiant.terrain.place_entity_at_exact_location(frog, location)
end

function TrickedScript:buff_citizens()
   local population = stonehearth.population:get_population(self._sv.ctx.player_id)
   for _, citizen in population:get_citizens():each() do
      radiant.entities.add_buff(citizen, self._sv.data.buff_citizens)
   end
end

function TrickedScript:destroy_crops(chance)
   for _, entity in pairs(_radiant.sim.get_all_entities()) do
      if entity:get_component('stonehearth:crop') then
         if rng:get_real(0, 1) <= chance then
            radiant.entities.kill_entity(entity)
         end
      end
   end
end

function TrickedScript:decay_items(material, chance)
   local inventory = stonehearth.inventory:get_inventory(self._sv.ctx.player_id)
   local sellable_item_tracker = inventory:get_item_tracker('stonehearth:sellable_item_tracker')
   local tracking_data = sellable_item_tracker:get_tracking_data()
   local item_uris = tracking_data:get_keys()

   for _, uri in pairs(item_uris) do
      local items = tracking_data:get(uri)
      if stonehearth.catalog:is_material(uri, material) then
         for id, entity in pairs(items.items) do
            if rng:get_real(0, 1) <= chance then
               stonehearth.food_decay:debug_decay_to_next_stage(entity)
               -- make sure the food hasn't already decayed out of existence
               if entity:is_valid() and rng:get_real(0, 1) <= (chance * 0.5) then
                  stonehearth.food_decay:debug_decay_to_next_stage(entity)
               end
            end
         end
      end
   end
end

function TrickedScript:destroy()
   if self._sv.bulletin then
      self._sv.bulletin:destroy()
      self._sv.bulletin = nil
   end

   if self._sv.despawn_timer then
      self._sv.despawn_timer:destroy()
      self._sv.despawn_timer = nil
      self:_despawn_visitors()
   end

   if self._frog_spawn_interval then
      self._frog_spawn_interval:destroy()
      self._frog_spawn_interval = nil
   end
end

return TrickedScript
