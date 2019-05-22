return function()
   local job = stonehearth and stonehearth.job
   if job and job._load_kingdom_job_data then
      job:_load_kingdom_job_data()
   end
end