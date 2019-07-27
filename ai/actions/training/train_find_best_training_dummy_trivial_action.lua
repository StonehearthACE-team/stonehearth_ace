local Point3 = _radiant.csg.Point3
local FindBestTrainingDummyTrivial = class()

FindBestTrainingDummyTrivial.name = 'train'
FindBestTrainingDummyTrivial.status_text_key = 'stonehearth_ace:ai.actions.status_text.train'
FindBestTrainingDummyTrivial.does = 'stonehearth_ace:find_training_dummy'
FindBestTrainingDummyTrivial.args = {}
FindBestTrainingDummyTrivial.priority = 1

function FindBestTrainingDummyTrivial:start_thinking(ai, entity, args)
   local job_comp = entity:get_component('stonehearth:job')
   local job_uri = job_comp:get_job_uri()
   local job_level = job_comp:get_current_job_level()
   local target = job_comp:get_training_target()

   if target and target:get_component('stonehearth_ace:training_dummy'):can_train_entity_level(job_uri) >= job_level then
      ai:set_think_output({dummy = target})
   end
end

return FindBestTrainingDummyTrivial
