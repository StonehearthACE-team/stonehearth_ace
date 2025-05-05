local transform_firstbloom_egg_hunt = {}

function transform_firstbloom_egg_hunt.transform(entity, transformed_form)
   radiant.events.trigger(stonehearth.game_master, 'firstbloom:egg_hunt', { entity = entity, transformed_form = transformed_form })
end

return transform_firstbloom_egg_hunt
