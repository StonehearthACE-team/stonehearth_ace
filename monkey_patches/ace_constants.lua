local constants = require 'stonehearth.constants'
local ace_constants = {}

ace_constants.food_quality_thoughts = constants.food_quality_thoughts
ace_constants.food_quality_thoughts[constants.food_qualities.INTOLERABLE] = { constants.thoughts.food_quality.INTOLERABLE }
ace_constants.food_quality_thoughts[constants.food_qualities.LOVELY] = { constants.thoughts.food_quality.LOVELY }

return ace_constants