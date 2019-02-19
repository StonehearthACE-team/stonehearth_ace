local constants = require 'stonehearth.constants'
local ace_constants = {}

ace_constants.food_quality_thoughts = constants.food_quality_thoughts
ace_constants.food_quality_thoughts[constants.food_qualities.INTOLERABLE] = { constants.thoughts.food_quality.INTOLERABLE }

return ace_constants