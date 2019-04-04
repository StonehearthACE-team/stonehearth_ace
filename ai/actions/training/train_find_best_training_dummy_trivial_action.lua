local Point3 = _radiant.csg.Point3
local FindBestTrainingDummyTrivial = class()

FindBestTrainingDummyTrivial.name = 'train'
FindBestTrainingDummyTrivial.status_text_key = 'stonehearth_ace:ai.actions.status_text.train'
FindBestTrainingDummyTrivial.does = 'stonehearth_ace:find_training_dummy'
FindBestTrainingDummyTrivial.args = {}
FindBestTrainingDummyTrivial.priority = 1

function FindBestTrainingDummyTrivial:start_thinking(ai, entity, args)
   local target = entity:get_component('stonehearth:job'):get_training_target()
   if target then
      ai:set_think_output({dummy = target})
   end
end

return FindBestTrainingDummyTrivial
