local Entity = _radiant.om.Entity
local rng = _radiant.math.get_default_rng()

local MIN_RANGE_SQUARED = 200

local Work = class()

Work.name = 'merchant work'
Work.does = 'stonehearth_ace:merchant:work'
Work.args = {
   stall = {
      type = Entity,
      default = stonehearth.ai.NIL
   }
}
Work.priority = 1

function Work:run(ai, entity, args)
   local merchant_component = entity:get_component('stonehearth_ace:merchant')
   local at_stall
   local stall_location
   if args.stall and args.stall:is_valid() then
      stall_location = radiant.entities.get_world_grid_location(args.stall)
      if stall_location then
         at_stall = true
         
         --local stall_component = args.stall:get_component('stonehearth_ace:market_stall')
         if merchant_component:set_up_at_stall(args.stall) then
            radiant.entities.turn_to_face(entity, args.stall)
            ai:execute('stonehearth:run_effect', { effect = 'fiddle' })
         end
      end
   end

   local player_id = merchant_component:get_player_id()
   local location = radiant.entities.get_world_location(entity)
   local mercantile_constants = stonehearth.constants.mercantile

   -- do a "work" thing a few times, then finish the action and allow for resetting
   local num_times = rng:get_int(3, 5)
   for i = 1, num_times do
      if merchant_component:should_depart() then
         break
      end

      -- also check to make sure the stall setup hasn't changed
      if stall_location and stall_location ~= radiant.entities.get_world_grid_location(args.stall) then
         break
      end

      local turned = false
      -- turn to face a nearby hearthling or just away from the stall
      if not at_stall or rng:get_real(0, 1) <= mercantile_constants.MERCHANT_CITIZEN_FOCUS then
         local citizen = self:_get_close_citizen(player_id, location, MIN_RANGE_SQUARED)
         if citizen and _physics:has_line_of_sight(entity, citizen) then
            ai:execute('stonehearth:turn_to_face_entity', {entity = citizen})
            turned = true
         end
      end

      if at_stall and not turned then
         -- select the point opposite the merchant from the closest stall point
         local stall_point = radiant.entities.get_facing_point(entity, args.stall)
         ai:execute('stonehearth:turn_to_face_point', {point = stall_point * 2 - location})
      end

      ai:execute('stonehearth:idle', {hold_position = at_stall})
   end
end

-- get the closest citizen to a location (or one of the first three within min_range_squared)
function Work:_get_close_citizen(player_id, location, min_range_squared)
   local closest_citizen, closest_distance
   local close_citizens = {}
   local pop = stonehearth.population:get_population(player_id)
   local citizens = pop:get_citizens()
   for id, citizen in citizens:each() do
      -- make sure the citizen is not suspended (away or disconnected)
      if not radiant.entities.is_entity_suspended(citizen) then
         if citizen:is_valid() then
            local pass = true
            
            local citizen_location = citizen:add_component('mob'):get_world_location()
            if citizen_location then
               local distance_squared = (location - citizen_location):length_squared()
               if not closest_distance or distance_squared < closest_distance then
                  closest_citizen = citizen
                  closest_distance = distance_squared
               end

               if distance_squared <= min_range_squared then
                  table.insert(close_citizens, citizen)
                  if #close_citizens > 2 then
                     -- if we've found three, go ahead and just return one of them
                     return close_citizens[rng:get_int(1, 3)]
                  end
               end
            end
         end
      end
   end

   return closest_citizen
end

return Work
