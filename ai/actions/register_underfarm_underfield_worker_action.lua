local Entity = _radiant.om.Entity

local RegisterUnderfarmUnderfieldWorker = radiant.class()

RegisterUnderfarmUnderfieldWorker.name = 'register underfarm underfield worker'
RegisterUnderfarmUnderfieldWorker.does = 'stonehearth_ace:register_underfarm_underfield_worker'
RegisterUnderfarmUnderfieldWorker.args = {
   underfield_layer = Entity
}
RegisterUnderfarmUnderfieldWorker.priority = 0

function RegisterUnderfarmUnderfieldWorker:start(ai, entity, args)
   args.field_layer:get_component('stonehearth_ace:grower_underfield_layer'):get_grower_underfield():add_worker(entity)
end

function RegisterUnderfarmUnderfieldWorker:stop(ai, entity, args)
   if radiant.entities.exists(args.underfield_layer) then -- When the game is shutting down, entities may be destroyed before AI.
      args.underfield_layer:get_component('stonehearth_ace:grower_underfield_layer'):get_grower_underfield():remove_worker(entity)
   end
end

return RegisterUnderfarmUnderfieldWorker
