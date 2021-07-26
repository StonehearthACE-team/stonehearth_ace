local SeasonCheck = class()

local log = radiant.log.create_logger('season_check')

function SeasonCheck:start(ctx, info)
   local season = stonehearth.seasons:get_current_season()
   
   if not season then
      log:debug('could not get a season')
      return false
   end

   if info.forbidden_seasons then
      for _, forbidden_season in ipairs(info.forbidden_seasons) do
         if forbidden_season == season.id then
            log:debug('current season is forbidden')
            return false
         end
      end
   end
   
   if info.required_seasons then
      for _, required_season in ipairs(info.required_seasons) do
         if required_season == season.id then 
            return true
         end
      end
      log:debug('current season is not a required season')
      return false
   end
   
   return true
end

return SeasonCheck