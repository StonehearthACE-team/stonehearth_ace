App.StonehearthSelectGameStoryView = App.View.extend({
   templateName: 'stonehearthSelectGameStory',
   i18nNamespace: 'stonehearth',
   classNames: ['flex', 'fullScreen', 'newGameFlowBackground'],
   _options: {
      game_mode : "stonehearth:game_mode:normal",
      starting_kingdom: "stonehearth:kingdoms:ascendancy",
      biome_src: 'stonehearth:biome:temperate',
      starting_items : {
      },
      starting_pets: [
      ],
      starting_gold: 0,
   },
   multiplayerOptions: {},
   biomeUriToData : {},
   kingdomUriToData : {},
   gameModeUriToData: {},
   kingdomComponents: {
      "kingdoms": {
         "*": {}
      }
   },
   "gameModeComponents": {
      "game_modes": {
         "*": {}
      }
   },
   biomeComponents: {
      "biomes": {
         "*": {}
      }
   },

   storySteps: {
      "kingdomStart": 1,
      "waitToSelectKingdom": 2,
      "postKingdomSelect": 3,
      "biomeStart": 4,
      "waitToSelectBiome": 5,
      "postSelectBiome": 6,
      "waitToSelectGameMode": 7,
      "postSelectGameMode": 8
   },

   init: function() {
      this._super();
      var self = this;
      self._currentSoundId = 0;
      self._existing_options = {};

      self._biomeTrace  = new StonehearthDataTrace('stonehearth:biome:index', self.biomeComponents)
         .progress(function(response) {
            // Process the response
            radiant.each(response.biomes, function(k, v) {
               self.biomeUriToData[v.__self] = v;
            })
            var biomeArr = radiant.map_to_array(response.biomes);
            self.set('allBiomes', biomeArr);
      });

      self._kingdomTrace  = new StonehearthDataTrace('stonehearth:playable_kingdom_index', self.kingdomComponents)
         .progress(function(response) {
            // Process the response
            radiant.each(response.kingdoms, function(k, v) {
               self.kingdomUriToData[v.__self] = v;
            })

            var kingdomArr = radiant.map_to_array(response.kingdoms);
            kingdomArr.sort(function (a, b) { return a.ordinal < b.ordinal ? -1 : 1; });
            self.set('allKingdoms', kingdomArr);
         });

      self._gameModeTrace  = new StonehearthDataTrace('stonehearth:game_mode:index', self.gameModeComponents)
         .progress(function(response) {
            radiant.each(response.game_modes, function(type, gameMode_data) {
               self.gameModeUriToData[gameMode_data.alias] = gameMode_data;
               self.gameModeUriToData[gameMode_data.alias].__self = gameMode_data.alias;
            });
            var gameModeArr = radiant.map_to_array(self.gameModeUriToData);
            gameModeArr.sort(function(a, b){
               var aOrdinal = a.ordinal ? a.ordinal : 1000;
                var bOrdinal = b.ordinal ? b.ordinal : 1000;
                return aOrdinal - bOrdinal;
            });
            self.set('allGameModes', gameModeArr);
         });

      self._isHostPlayer =  true;
      self.set('isHostPlayer', true);
      radiant.call_obj('stonehearth.session', 'is_host_player_command')
         .done(function(e) {
            self._isHostPlayer = e.is_host;
            self.set('isHostPlayer', e.is_host);
         });

      radiant.call_obj('stonehearth.game_creation', 'get_game_world_options_commands')
         .done(function(response) {
            self._existing_options = response;
         });
   },

   didInsertElement: function() {
      this._super();
      var self = this;

      radiant.each(self.multiplayerOptions, function(key, value) {
         self._options[key] = value;
      });

      self.goToStoryStep("kingdomStart");
      self.$("#biomeWarning").hide();

      // input handlers
      $(document).keyup(function(e) {
         self._cancelCurrentTextillate();
      });

      $(document).click(function(e) {
         self._cancelCurrentTextillate();
      });
      
      // Allow horizontal scroll with mousewheel in biome, etc. pickers.
      $('.storyPicker').on('mousewheel', function(e, delta) {
         $(this).scrollLeft(this.scrollLeft - event.wheelDeltaY);
         e.preventDefault();
      });
   },

   goToStoryStep: function(stepName) {
      var self = this;
      var currentStep = self.storySteps[self._currentStoryStep];
      var requestedStep = self.storySteps[stepName];
      if (requestedStep <= currentStep) {
         console.log("skipping goToStoryStep. requestedStep: " + stepName + " is behind or already at current step: " + self._currentStoryStep);
         return false;
      }

      self._currentStoryStep = stepName;
      switch(stepName) {
         case "kingdomStart":
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:game_story_menu:ui_writing_01'})
               .done(function(response) {
                  self._currentSoundId = response.sound_id;
               });

            self._startTextillate(self.$("#selectKingdom"), function () {
               radiant.call('radiant:stop_sound', {'sound_id' : self._currentSoundId});
                  self._currentTextillate = null;
                  self.$("#kingdomPicker").show();
                  self.goToStoryStep("waitToSelectKingdom");
            });
            break;
         case "postKingdomSelect":
            self.$("#storyPictureCitizens").fadeIn(1500);
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:small_click'})
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:game_story_menu:ui_writing_02'})
            .done(function(response) {
                  self._currentSoundId = response.sound_id;
               });

            self._startTextillate(self.$("#postSelectKingdom"), function (isCancelled) {
               self._currentTextillate = null;
               if (isCancelled) {
                  radiant.call('radiant:stop_sound', {'sound_id' : self._currentSoundId});
                  self.$("#selectBiome").css('visibility', 'visible');
                  if (self._isHostPlayer) {
                     self.$("#biomePicker").show();
                     self.goToStoryStep("waitToSelectBiome");
                  } else {
                     self._selectBiome(self._existing_options.biome);
                  }
               } else {
                  self.goToStoryStep("biomeStart");
               }
            });
            break;
         case "biomeStart":
            self._startTextillate(self.$("#selectBiome"), function () {
               self._currentTextillate = null;
               radiant.call('radiant:stop_sound', {'sound_id' : self._currentSoundId});
               if (self._isHostPlayer) {
                  self.$("#biomePicker").show();
                  self.goToStoryStep("waitToSelectBiome");
               } else {
                  self._selectBiome(self._existing_options.biome);
               }
            });
            break;
         case "postSelectBiome":
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:small_click'})
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:game_story_menu:ui_writing_03'})
            .done(function(response) {
                  self._currentSoundId = response.sound_id;
               });
            self.$("#storyPictureBackground").fadeIn(1500);
            self.$("#storyPictureCitizens").addClass("somewhatFadedTransition")
                                           .removeClass("reallyFaded");

            self._startTextillate(self.$("#selectGameMode"), function () {
               radiant.call('radiant:stop_sound', {'sound_id' : self._currentSoundId});
               self._currentTextillate = null;
               if (self._isHostPlayer) {
                  self.$("#gameModePicker").show();
                  self.goToStoryStep("waitToSelectGameMode");
               } else {
                  self._selectGameMode(self._existing_options.game_mode);
               }
            });
            break;
         case "postSelectGameMode":
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:small_click'})
            self.$("#storyPictureBackground").removeClass("somewhatFaded")
                                             .addClass("noFilter");
            self.$("#storyPictureCitizens").removeClass("somewhatFadedTransition")
                                           .addClass("noFilter");
            self.$("#storyPictureMonsters").fadeIn(1500);
            self.$("#beginStoryButton").fadeIn();
            break;
      }
      return true;
   },

   _startTextillate: function(el, cb) {
      var self = this;
      if (self._currentTextillate != null) {
         self._onTextillateAlreadyExists();
      }

      self._currentTextillate = el.textillate({
         callback: function (isCancelled) {
            if (cb) {
               cb(isCancelled);
            }
         }
      });

      console.log('current textillate running for ' + el.selector);
   },

   _cancelCurrentTextillate: function() {
      var self = this;
      if (self._currentTextillate) {
         self._currentTextillate.textillate('stopAllAnimations');
      }
   },

   _onTextillateAlreadyExists: function() {
      var self = this;
      console.log("Select game story " + self._currentStoryStep + " Attempting to replace textillate that is not null!!");
      self._cancelCurrentTextillate();
   },

   _selectBiome : function(biomeUri) {
      var self = this;
      self._selectedBiomeData = self.biomeUriToData[biomeUri];
      self.set("selectedBiome", self._selectedBiomeData);

      var random =  Math.floor(Math.random() * self._selectedBiomeData.random_location_names.length);
      self.set("selectedBiomeRandomName", self._selectedBiomeData.random_location_names[random]);

      self.$("#biomePicker").hide();

      if (self._selectedGameModeData) {
         // If we have a game mode selected, change monster image to match biome
         var src = "";
         var gameModeUri = self._selectedGameModeData.__self;
         if (self._selectedBiomeData.game_mode_images && self._selectedBiomeData.game_mode_images[gameModeUri]) {
            src = self._selectedBiomeData.game_mode_images[gameModeUri];
         }
         self.set('selectedBiomeMonsterPicture', src);
      }

      Ember.run.scheduleOnce('afterRender', this, function() {
         self.goToStoryStep("postSelectBiome");
      });
   },

   _selectKingdom: function(kingdomUri) {
      var self = this;
      var kingdomData = self.kingdomUriToData[kingdomUri];
      self._selectedKingdomData = kingdomData;
      self.set("selectedKingdom", kingdomData);
      self.$("#kingdomPicker").hide();

      // Mark the favorite biome.
      if (kingdomData.favored_biome) {
         var allBiomes = radiant.map_to_array(self.biomeUriToData);
         var swapIndex = -1;
         for (var i = 0; i < allBiomes.length; ++i) {
            allBiomes[i].set('is_favored', allBiomes[i].alias == kingdomData.favored_biome);
         }
         self.set('allBiomes', allBiomes);
      }

      //self.$("#postSelectKingdom").empty();
      var postSelectText = i18n.t(self._selectedKingdomData.post_selection_description);
      self.$("#postSelectKingdom").text(postSelectText);

      Ember.run.scheduleOnce('afterRender', this, function() {

         //self.$("#postSelectKingdom").html(i18n.t(self.get('selectedKingdom.post_selection_description')));
         if (!self.goToStoryStep("postKingdomSelect")) {
            // make sure the kingdom text still exists.
            self.$("#postSelectKingdom").css('visibility', 'visible');
         }
      });
   },

   _selectGameMode: function(gameModeUri) {
      var self = this;
      self._selectedGameModeData = self.gameModeUriToData[gameModeUri];
      self.$("#gameModePicker").hide();
      self.set('selectedGameMode', self._selectedGameModeData);

      // Look up biome difficulty image
      var src = "";
      if (self._selectedBiomeData.game_mode_images && self._selectedBiomeData.game_mode_images[gameModeUri]) {
         src = self._selectedBiomeData.game_mode_images[gameModeUri];
      }
      self.set('selectedBiomeMonsterPicture', src);

      Ember.run.scheduleOnce('afterRender', this, function() {
         self.goToStoryStep("postSelectGameMode");
      });
   },

   actions: {
      selectKingdom: function(kingdomUri) {
         this._selectKingdom(kingdomUri);
      },

      selectBiome: function(biomeUri) {
         this._selectBiome(biomeUri);
      },

      selectGameMode: function(gameModeUri) {
         this._selectGameMode(gameModeUri);
      },

      beginStory: function() {
         var self = this;
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:embark'});
         self._options.starting_kingdom = self._selectedKingdomData.__self;
         self._options.starting_items = {
            [self._selectedKingdomData.starting_talisman] : 1
         };
         self._options.game_mode = self._selectedGameModeData.__self;
         self._options.biome_src = self._selectedBiomeData.__self;
         self._options.loadouts = self._selectedKingdomData.loadouts;

         // if selected biome isn't the favored biome of this kingdom, warn the player since
         // the game is more difficult to play in non-matching biomes
         var biomeMod = self._options.biome_src.split(':')[0];
         if (biomeMod == 'stonehearth' && self._options.biome_src !== self._selectedKingdomData.favored_biome) {
            self.send('showBiomeWarning'); // call the action
         } else {
            self.send('continueSelection');
         }
      },
      continueSelection: function() {
         var self = this;
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:action_click' });
         radiant.call_obj('stonehearth.game_creation', 'set_custom_game_info_command', {
               biome_name : self.get('selectedBiome').display_name,
               translated_biome_name : i18n.t(self.get('selectedBiome').display_name),
               biome_random_name : self.get('selectedBiomeRandomName'),
               translated_biome_random_name : i18n.t(self.get('selectedBiomeRandomName')),
               game_mode : self.get('selectedGameMode').display_name,
               translated_game_mode : i18n.t(self.get('selectedGameMode').display_name)
            });
         radiant.call_obj('stonehearth.game_creation', 'select_player_kingdom', self._options.starting_kingdom)
            .done(function(e) {
               App.navigate('shell/select_roster', {_options: self._options});
               self.destroy();
            })
            .fail(function(e) {
               console.error('selecting a kingdom failed:', e)
            });
      },

      cancelSelection: function() {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:action_click' });
         this.$("#biomeWarning").hide();
      },

      showKingdomSelection: function() {
         if (this._currentStoryStep == "postSelectGameMode") {
            this.$(".storyPicker").hide();
            this.$("#kingdomPicker").show();
         }
      },

      showBiomeSelection: function() {
         if (this._currentStoryStep == "postSelectGameMode" && this._isHostPlayer) {
            this.$(".storyPicker").hide();
            this.$("#biomePicker").show();
         }
      },

      showGameModeSelection: function() {
         if (this._currentStoryStep == "postSelectGameMode" && this._isHostPlayer) {
            this.$(".storyPicker").hide();
            this.$("#gameModePicker").show();
         }
      },

      showBiomeWarning: function() {
         if (this._currentStoryStep == "postSelectGameMode") {
            var favoredBiome = this.biomeUriToData[this._selectedKingdomData.favored_biome];
            this.set('warningText', i18n.t('stonehearth:ui.shell.select_game_story.biome_warning_text', {
               kingdom : this._selectedKingdomData.display_name,
               preferred_biome: favoredBiome ? favoredBiome.display_name : '???',
            }));

            this.$(".storyPicker").hide();
            this.$("#biomeWarning").show();
         }
      },

      quitToMainMenu: function() {
         App.stonehearthClient.quitToMainMenu('shellView', this);
      }
   },

   destroy: function() {
      if (this._kingdomTrace) {
         this._kingdomTrace.destroy();
         this._kingdomTrace = null;
      }
      if (this._biomeTrace) {
         this._biomeTrace.destroy();
         this._biomeTrace = null;
      }
      if (this._gameModeTrace) {
         this._gameModeTrace.destroy();
         this._gameModeTrace = null;
      }
      this._super();
   },
});
