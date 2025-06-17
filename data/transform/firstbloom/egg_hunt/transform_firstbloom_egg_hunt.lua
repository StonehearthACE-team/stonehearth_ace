local transform_firstbloom_egg_hunt = {}

function transform_firstbloom_egg_hunt.transform(entity, transformed_form, ...)
   local args = {...}
   local transformer_entity = args[3] or nil
   
   radiant.events.trigger(stonehearth.game_master, 'firstbloom:egg_hunt', { entity = entity, transformed_form = transformed_form, citizen = transformer_entity })
end

return transform_firstbloom_egg_hunt
