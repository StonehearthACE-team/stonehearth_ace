local BluebellOutcomesScript = class()

function BluebellOutcomesScript:start(ctx, data)
   stonehearth.player:set_neutral_to_everyone(ctx.npc_player_id, false)

   if ctx.goblin_raiding_camp_1 and ctx.goblin_raiding_camp_1.citizens and ctx.goblin_raiding_camp_1.citizens.sheep then
      local boss_sheep = ctx.goblin_raiding_camp_1.citizens.sheep

      if boss_sheep:is_valid() then
         if data.outcome == 'adopt' then       
            local pet_component = boss_sheep:add_component('stonehearth:pet')
            pet_component:convert_to_pet(ctx.player_id)

            local town = stonehearth.town:get_town(ctx.player_id)
            local citizens = town:get_citizens()

            local min_distance = radiant.math.INFINITY
            local min_citizen = nil

            for _, citizen in citizens:each() do
               local distance = radiant.entities.distance_between(boss_sheep, citizen)
               if not min_citizen or distance < min_distance then
                  min_citizen = citizen
                  min_distance = distance
               end
            end

            pet_component:set_owner(min_citizen)
         elseif data.outcome == 'leave_be' then
            radiant.entities.set_player_id(boss_sheep, 'animals')
         elseif data.outcome == 'let_go' then
            radiant.entities.set_player_id(boss_sheep, 'animals')
            radiant.entities.add_buff(boss_sheep, 'stonehearth:buffs:despawn:after_day')
         else
            return
         end
      end
   end
end

return BluebellOutcomesScript