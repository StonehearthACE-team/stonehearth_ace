local OrchestratedPeriodicInteractionTaskGroup = class()
OrchestratedPeriodicInteractionTaskGroup.name = 'orchestrated periodic interaction'
OrchestratedPeriodicInteractionTaskGroup.does = 'stonehearth_ace:periodic_interaction'
OrchestratedPeriodicInteractionTaskGroup.priority = 0

return stonehearth.ai:create_task_group(OrchestratedCraftingTaskGroup)
         :declare_task('stonehearth_ace:periodically_interact', 0.0)
