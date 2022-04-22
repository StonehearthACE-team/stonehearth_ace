local constants = require 'stonehearth.constants'
local ace_constants = {}

ace_constants.ACE_USE_MERGE_INTO_TABLE = true

ace_constants.food_quality_thoughts = constants.food_quality_thoughts
ace_constants.food_quality_thoughts[constants.food_qualities.RAW_TASTY] = { constants.thoughts.food_quality.TASTY }                                                                       
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
ace_constants.drink_quality_thoughts[constants.drink_qualities.RAW_AVERAGE] = { 			constants.thoughts.drink_quality.RAW,
																													constants.thoughts.drink_quality.AVERAGE}
ace_constants.drink_quality_thoughts[constants.drink_qualities.RAW_TASTY] = { 			constants.thoughts.drink_quality.RAW,		
																													constants.thoughts.drink_quality.TASTY}
ace_constants.drink_quality_thoughts[constants.drink_qualities.PREPARED_BLAND] = { 		constants.thoughts.drink_quality.PREPARED,
																													constants.thoughts.drink_quality.BLAND}
ace_constants.drink_quality_thoughts[constants.drink_qualities.PREPARED_AVERAGE] = { 	constants.thoughts.drink_quality.PREPARED,
																													constants.thoughts.drink_quality.AVERAGE}
ace_constants.drink_quality_thoughts[constants.drink_qualities.PREPARED_TASTY] = { 		constants.thoughts.drink_quality.PREPARED,
																													constants.thoughts.drink_quality.TASTY}
ace_constants.drink_quality_thoughts[constants.drink_qualities.LOVELY] = { 				constants.thoughts.drink_quality.LOVELY}

ace_constants.drink_item_quality_thoughts = {}
ace_constants.drink_item_quality_thoughts[constants.item_quality.FINE] = 					constants.thoughts.drink_item_quality.FINE 
ace_constants.drink_item_quality_thoughts[constants.item_quality.EXCELLENT] = 			constants.thoughts.drink_item_quality.EXCELLENT 
ace_constants.drink_item_quality_thoughts[constants.item_quality.MASTERWORK] = 			constants.thoughts.drink_item_quality.MASTERWORK 

ace_constants.conversation = constants.conversation
ace_constants.conversation.MEDIUM_STAGES = {
   order = {
      constants.conversation.stages.GREETING,
      constants.conversation.stages.MOVE,
      constants.conversation.stages.SUBJECT,
      constants.conversation.stages.REACTION,
      constants.conversation.stages.CONCLUSION
   },
   steps = {
      [constants.conversation.stages.GREETING] = "num_participants",
      [constants.conversation.stages.MOVE] = 0,
      [constants.conversation.stages.SUBJECT] = 1,
      [constants.conversation.stages.REACTION] = 1,
      [constants.conversation.stages.CONCLUSION] = "num_participants",
   },
}

ace_constants.conversation.SHORT_STAGES = {
   order = {
      constants.conversation.stages.GREETING,
      constants.conversation.stages.CONCLUSION
   },
   steps = {
      [constants.conversation.stages.GREETING] = "num_participants",
      [constants.conversation.stages.CONCLUSION] = "num_participants",
   },
}

ace_constants.conversation.RENOWN_THOUGHTS = {
   [constants.conversation.renown_thresholds.LOW] = 'stonehearth:thoughts:social:talk_with_low_renown',
   [constants.conversation.renown_thresholds.MEDIUM] = 'stonehearth:thoughts:social:talk_with_medium_renown',
   [constants.conversation.renown_thresholds.HIGH] = 'stonehearth:thoughts:social:talk_with_high_renown',
   [constants.conversation.renown_thresholds.VERY_HIGH] = 'stonehearth:thoughts:social:talk_with_very_high_renown',
}

return ace_constants