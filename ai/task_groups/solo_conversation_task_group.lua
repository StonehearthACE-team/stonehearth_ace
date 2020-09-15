local SoloConversationTaskGroup = class()
SoloConversationTaskGroup.name = 'solo conversation'
SoloConversationTaskGroup.does = 'stonehearth:top'
SoloConversationTaskGroup.priority = 0.205

return stonehearth.ai:create_task_group(SoloConversationTaskGroup)
         :declare_permanent_task('stonehearth:conversation:initiate', {}, {0.0, 1.0})
         :declare_task('stonehearth:conversation:idle', 0.94)
         :declare_task('stonehearth:conversation:move_into_position', 1.0)
         :declare_task('stonehearth:conversation:talk', 1.0)
