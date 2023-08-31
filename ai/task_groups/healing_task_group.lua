local HealingTaskGroup = class()
HealingTaskGroup.name = 'healing'
HealingTaskGroup.does = 'stonehearth:work'
HealingTaskGroup.priority = 0.87

return stonehearth.ai:create_task_group(HealingTaskGroup)
         :work_order_tag("job")
         :declare_permanent_task('stonehearth:healing', {}, 1)                -- properly treat a wounded hearthling
         :declare_multiple_tasks('stonehearth:combat:heal_after_cooldown', 0) -- just use a non-combat version of combat healing
