local constants = require 'stonehearth.constants'
local ace_constants = {}

ace_constants.food_quality_thoughts = constants.food_quality_thoughts
ace_constants.food_quality_thoughts[constants.food_qualities.INTOLERABLE] = { constants.thoughts.food_quality.INTOLERABLE }
ace_constants.food_quality_thoughts[constants.food_qualities.LOVELY] = { constants.thoughts.food_quality.LOVELY }


ace_constants.drink_quality_priorities = {}
ace_constants.drink_quality_priorities[constants.drink_qualities.INTOLERABLE] = -1
ace_constants.drink_quality_priorities[constants.drink_qualities.UNPALATABLE] = 0
ace_constants.drink_quality_priorities[constants.drink_qualities.RAW_BLAND] = 1
ace_constants.drink_quality_priorities[constants.drink_qualities.RAW_AVERAGE] = 2
ace_constants.drink_quality_priorities[constants.drink_qualities.RAW_TASTY] = 3
ace_constants.drink_quality_priorities[constants.drink_qualities.PREPARED_BLAND] = 4
ace_constants.drink_quality_priorities[constants.drink_qualities.PREPARED_AVERAGE] = 5
ace_constants.drink_quality_priorities[constants.drink_qualities.PREPARED_TASTY] = 6
ace_constants.drink_quality_priorities[constants.drink_qualities.LOVELY] = 7

ace_constants.drink_quality_thoughts = {}
ace_constants.drink_quality_thoughts[constants.drink_qualities.INTOLERABLE] = {			constants.thoughts.drink_quality.INTOLERABLE}
ace_constants.drink_quality_thoughts[constants.drink_qualities.UNPALATABLE] = {			constants.thoughts.drink_quality.UNPALATABLE}
ace_constants.drink_quality_thoughts[constants.drink_qualities.RAW_BLAND] = { 			constants.thoughts.drink_quality.RAW,
																													constants.thoughts.drink_quality.BLAND}
ace_constants.drink_quality_thoughts[constants.drink_qualities.RAW_AVERAGE] = { 			constants.thoughts.drink_quality.RAW}
ace_constants.drink_quality_thoughts[constants.drink_qualities.RAW_TASTY] = { 			constants.thoughts.drink_quality.RAW,		
																													constants.thoughts.drink_quality.TASTY}
ace_constants.drink_quality_thoughts[constants.drink_qualities.PREPARED_BLAND] = { 		constants.thoughts.drink_quality.PREPARED,
																													constants.thoughts.drink_quality.BLAND}
ace_constants.drink_quality_thoughts[constants.drink_qualities.PREPARED_AVERAGE] = { 	constants.thoughts.drink_quality.PREPARED}
ace_constants.drink_quality_thoughts[constants.drink_qualities.PREPARED_TASTY] = { 		constants.thoughts.drink_quality.PREPARED,
																													constants.thoughts.drink_quality.TASTY}
ace_constants.drink_quality_thoughts[constants.drink_qualities.LOVELY] = { 				constants.thoughts.drink_quality.LOVELY}

ace_constants.drink_item_quality_thoughts = {}
ace_constants.drink_item_quality_thoughts[constants.item_quality.FINE] = {					constants.thoughts.drink_item_quality.FINE }
ace_constants.drink_item_quality_thoughts[constants.item_quality.EXCELLENT] = {			constants.thoughts.drink_item_quality.EXCELLENT }
ace_constants.drink_item_quality_thoughts[constants.item_quality.MASTERWORK] = {			constants.thoughts.drink_item_quality.MASTERWORK }

return ace_constants