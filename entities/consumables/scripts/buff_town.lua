local BuffTown = class()

function BuffTown.use(consumable, consumable_data, player_id, target_entity)
   -- Item buffs the entire town

   -- ACE: check if single buff and make it a table if so
   if type(consumable_data.buff) == 'string' then
      consumable_data.buff = { consumable_data.buff }
   end

   local population = stonehearth.population:get_population(player_id)
   for _, buff in ipairs(consumable_data.buff) do
      for _, citizen in population:get_citizens():each() do
         radiant.entities.add_buff(citizen, buff)
      end
   end
   return true      
end

return BuffTown