local BossDeathScript = class()

--When the camp departs, no matter how the player interacted with these goblins, 
--set amenity for all goblins back to hostile. 
-- [ACE] Remove the sheep despawn

function BossDeathScript:start(ctx)
   stonehearth.player:set_neutral_to_everyone(ctx.npc_player_id, false)

   if ctx.goblin_raiding_camp_1 and ctx.goblin_raiding_camp_1.citizens and ctx.goblin_raiding_camp_1.citizens.sheep then
      local boss_sheep = ctx.goblin_raiding_camp_1.citizens.sheep
      if boss_sheep:is_valid() then
         radiant.entities.set_player_id(boss_sheep, 'animals')
         --radiant.entities.add_buff(boss_sheep, 'stonehearth:buffs:despawn:after_day')
      end
   end
end

return BossDeathScript