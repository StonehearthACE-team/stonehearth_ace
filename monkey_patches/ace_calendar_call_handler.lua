local validator = radiant.validator

local AceCalendarCallHandler = class()

function AceCalendarCallHandler:set_start_day(session, request, day_of_epoch, start_year)
   validator.expect_argument_types({'number', validator.optional('number')}, day_of_epoch, start_year)
   stonehearth.calendar:set_start_day(day_of_epoch, start_year)
   return true
end

return AceCalendarCallHandler
