local ClearHostiles = class()

function ClearHostiles:start(ctx, data)
   for kingdom, check in pairs(data.kingdoms) do
      local population = stonehearth.population:get_population(kingdom)

      if population then
         for _, citizen in population:get_citizens():each() do
            if radiant.entities.exists(citizen) then
               citizen:get_component('stonehearth:ai')
                      :get_task_group('stonehearth:task_groups:solo:unit_control')
                      :create_task('stonehearth:depart_visible_area', { give_up_after = '3h' })
                      :start()
            end
         end
      end
   end
end

return ClearHostiles