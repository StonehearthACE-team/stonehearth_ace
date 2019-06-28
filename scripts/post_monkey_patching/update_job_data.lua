return function()
   local job = stonehearth and stonehearth.job
   if job and job._load_kingdom_job_data then
      job:_load_kingdom_job_data()
   else
      radiant.log.write_('stonehearth_ace', 0, 'update_job_data script failed: no stonehearth.job service initialized/patched')
   end
end