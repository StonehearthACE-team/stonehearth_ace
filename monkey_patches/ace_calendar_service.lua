local CONSTANTS = radiant.resources.load_json('/stonehearth/data/calendar/calendar_constants.json')
local CalendarService = require 'stonehearth.services.server.calendar.calendar_service'

local AceCalendarService = class()

local log = radiant.log.create_logger('calendar_service')

function AceCalendarService:get_start_year()
   return CONSTANTS.start.year
end

function AceCalendarService:set_start_day(day_since_epoch, start_year)
   self._sv.absolute_start_time = {}
   local start_date = self:_day_since_epoch_to_date(day_since_epoch)
   for unit, value in pairs(start_date) do
      self._sv.date[unit] = value
      self._sv.start_time[unit] = value
      self._sv.absolute_start_time[unit] = value
   end
   self._sv.date.year = self._sv.date.year + CONSTANTS.start.year + (start_year or 0)
   self._sv.start_time.year = self._sv.date.year
   self._sv.absolute_start_time.year = self._sv.date.year
   radiant.events.trigger_async(radiant, 'stonehearth:start_date_set')
end

function AceCalendarService:get_elapsed_days()
   local date = self._sv.date
   local start_date = self._sv.absolute_start_time or  self._sv.start_time or CONSTANTS.start
   local days = date.day - start_date.day
   local months = date.month - start_date.month
   local years = date.year - start_date.year

   local days_elapsed = days + months * CONSTANTS.days_per_month + years * CONSTANTS.months_per_year * CONSTANTS.days_per_month
   return days_elapsed
end

return AceCalendarService