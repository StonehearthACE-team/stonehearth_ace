local MerchantTaskGroup = class()
MerchantTaskGroup.name = 'merchant'
MerchantTaskGroup.does = 'stonehearth:top'
MerchantTaskGroup.priority = {0.05, 0.3}

return stonehearth.ai:create_task_group(MerchantTaskGroup)
         :declare_permanent_task('stonehearth_ace:merchant:depart', {}, 1.0)
         :declare_permanent_task('stonehearth_ace:merchant:work_at_stall', {}, 0.5)
         :declare_permanent_task('stonehearth_ace:merchant:work_by_hearth', {}, 0.0)
