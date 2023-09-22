App.StonehearthStartMenuView = App.View.extend({
   templateName: 'stonehearthStartMenu',
   //classNames: ['flex', 'fullScreen'],

   _foundjobs : {},
   CHANGE_CALLBACK_NAME: 'start_menu',

   menuActions: {
      harvest: function () {
         App.stonehearthClient.boxHarvestResources();
      },
      clear_item: function () {
         App.stonehearthClient.boxClearItem();
      },
      cancel_task: function () {
         App.stonehearthClient.boxCancelTask();
      },
      create_stockpile: function () {
         App.stonehearthClient.createStockpile();
      },
      create_quest_storage: function () {
         App.stonehearthClient.createQuestStorage();
      },
      // ACE: handle different kinds of farm field types
      create_farm: function(nodeData) {
         // if there's only one type of farm unlocked, go ahead and click that type
         var unlocked = null;
         radiant.each(nodeData.items, function(key, _) {
            var el = self.$('#startMenu').find(`[id="${key}"]`);
            if (!el.hasClass('locked')) {
               if (unlocked == null) {
                  unlocked = el;
               }
               else {
                  unlocked = false;
               }
            }
         });
         if (unlocked) {
            unlocked.click();
         }
      },
      create_field: function(nodeData) {
         App.stonehearthClient.createFarm(nodeData.field_type);
      },
      create_trapping_grounds : function () {
         App.stonehearthClient.createTrappingGrounds();
      },
      create_pasture : function () {
         App.stonehearthClient.createPasture();
      },
      mine_basic: function () {
         App.stonehearthClient.mineBasic();
      },
      mine_custom: function () {
         App.stonehearthClient.mineCustom();
      },
      building_templates: function () {
         $(top).trigger('stonehearth_building_templates');
      },
      custom_building: function() {
         $(top).trigger('stonehearth_building_designer');
      },
      custom_building_new: function() {
         $(top).trigger('stonehearth_building_designer_new');
      },
      place_item: function () {
         $(top).trigger('stonehearth_place_item');
      },
      build_ladder: function () {
         App.stonehearthClient.buildLadder();
      },
      build_simple_room: function () {
         App.stonehearthClient.buildRoom();
      },
      loot_item : function () {
         App.stonehearthClient.boxLootItems();
      },
      party_1 : function () {
         App.stonehearthClient.select_combat_party('party_1');
      },
      party_2 : function () {
         App.stonehearthClient.select_combat_party('party_2');
      },
      party_3 : function () {
         App.stonehearthClient.select_combat_party('party_3');
      },
      party_4 : function () {
         App.stonehearthClient.select_combat_party('party_4');
      },
      town_overview: function() {
         App.stonehearthClient.showTownMenu();
      },
      citizen_manager: function() {
         App.stonehearthClient.showCitizenManager();
      },
      tasks_manager: function() {
         App.stonehearthClient.showTasksManager();
      },
      bulletin_manager: function() {
         App.bulletinBoard.toggleListView();
      },
      town_alert: function () {
         App.stonehearthClient.enableAlertMode();
      },
      show_crafter_ui: function (nodeData) {
         App.workshopManager.toggleWorkshop(nodeData.required_job);
      },
      multiplayer_menu: function() {
         App.stonehearthClient.showMultiplayerMenu();
      },
      // ACE: added start menu options
      mercantile_view: function(){
         App.stonehearthClient.showMercantileView();
      },
      pet_manager: function(){
         App.stonehearthClient.showPetManager();
      },
      box_harvest_and_replant: function(){
         App.stonehearthClient.boxHarvestAndReplant();
      },
      box_move: function(){
         App.stonehearthClient.boxMove();
      },
      box_undeploy: function(){
         App.stonehearthClient.boxUndeploy();
      },
      box_cancel_placement: function(){
         App.stonehearthClient.boxCancelPlacement();
      },
      box_enable_auto_harvest: function(){
         App.stonehearthClient.boxEnableAutoHarvest();
      },
      box_disable_auto_harvest: function(){
         App.stonehearthClient.boxDisableAutoHarvest();
      },
      box_hunt: function(){
         App.stonehearthClient.boxHunt();
      },
      build_well: function(){
         App.stonehearthClient.buildWell();
      },
      build_fence: function(){
         //self.buildFence();
         // this actually gets shown by changing the ui mode
      },
      box_forage: function() {
         App.stonehearthClient.boxForage();
      }
   },

   hideConditions: {
      multiplayer_disabled: function () {
         return !App.stonehearthClient.isMultiplayerEnabled();
      },
      custom_mining_tool_disabled: function () {
         return !this._enable_custom_mining_tool
      }
   },

   init: function() {
      this._super();
      var self = this;
   },

   didInsertElement: function() {
      this._super();

      var self = this;

      if (!this.$()) {
         return;
      }

      // $(top).on("show_processing_meter_changed.start_menu", function (_, e) {
      //    if (e.value) {
      //       self.$('#startMenu .stonehearthMenu').removeClass('meter-hidden');
      //    }
      //    else {
      //       self.$('#startMenu .stonehearthMenu').addClass('meter-hidden');
      //    }
      // });

      // // make sure it initializes properly
      // Ember.run.scheduleOnce('afterRender', this, function() {
      //    stonehearth_ace.getModConfigSetting('stonehearth_ace', 'show_processing_meter', function(value) {
      //       if (!value) {
      //          self.$('#startMenu .stonehearthMenu').addClass('meter-hidden');
      //       }
      //    });
      // });

      $('#startMenuTrigger').click(function() {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:trigger_click'} );
      });

      App.stonehearth.startMenu = self.$('#startMenu');

      radiant.call('radiant:get_config', 'mods.stonehearth.enable_custom_mining_tool')
         .done(function (response) {
            self._enable_custom_mining_tool = response['mods.stonehearth.enable_custom_mining_tool'];
            // Build start menu
            $.get('/stonehearth/data/ui/start_menu.json')
               .done(function(json) {
                  self._buildMenu(json);
                  self._addHotkeys();
                  self._tracePopulation();

                  // Add badges for notifications
                  App.bulletinBoard.getTrace()
                     .progress(function(result) {
                        var bulletins = result.bulletins;
                        var alerts = result.alerts;
                        var numBulletins = bulletins ? Object.keys(bulletins).length : 0;
                        var numAlerts = alerts ? Object.keys(alerts).length : 0;

                        if (numBulletins > 0 || numAlerts > 0) {
                           //self.$('#bulletin_manager').pulse();
                           self.$('#bulletin_manager').addClass('active');
                        } else {
                           self.$('#bulletin_manager').removeClass('active');
                        }
                        self._updateBulletinCount(numBulletins + numAlerts);
                     });

                  // Add badges for number of players connected
                  var presenceCallback = function(presenceData) {
                     var numConnected = 0;
                     radiant.each(presenceData, function(playerId, data) {
                        var connectionStates = App.constants.multiplayer.connection_state;
                        if (data.connection_state == connectionStates.CONNECTED || data.connection_state == connectionStates.CONNECTING) {
                           numConnected++;
                        }
                     });

                     self._updateConnectedPlayerCount(numConnected);
                  };

                  App.presenceClient.addChangeCallback(self.CHANGE_CALLBACK_NAME, presenceCallback, true);
                  self._presenceCallbackName = self.CHANGE_CALLBACK_NAME;

                  App.resolveStartMenuLoad();
               });
         });

      /*
      $('#startMenu').on( 'mouseover', 'a', function() {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:action_hover'});
      });

      $('#startMenu').on( 'mousedown', 'li', function() {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:action_click'});
      });
      */
   },

   destroy: function() {
      if (this._popTrace) {
         this._popTrace.destroy();
         this._popTrace = null;
      }
      if (this._jobTrace) {
         this._jobTrace.destroy();
         this._jobTrace = null;
      }
      if (this._presenceCallbackName) {
         App.presenceClient.removeChangeCallback(this._presenceCallbackName);
      }

      $(top).off("show_processing_meter_changed.start_menu");

      this._super();
   },

   _trackJobs: function() {
      // find all the jobs in the population
      var self = this;
      self.$('#startMenu').stonehearthMenu('lockAllItems');

      radiant.each(App.jobController.getJobMemberCounts(), function(jobAlias, num_members) {
         if (num_members > 0) {
            var alias = jobAlias.split(":").join('\\:');
            self.$('#startMenu').stonehearthMenu('unlockItem', 'job', alias);
         }
      });

      var jobRoles = App.jobController.getUnlockedJobRoles();
      radiant.each(jobRoles, function(role, someVar) {
         self.$('#startMenu').stonehearthMenu('unlockItem', 'job_role', role);
      });

      // ACE: also track population unlocked abilities
      var pop = App.population.getPopulationData();
      radiant.each(pop.unlocked_abilities, function(ability, unlocked) {
         if (unlocked) {
            self.$('#startMenu').stonehearthMenu('unlockItem', 'unlocked_ability', ability);
         }
      });
   },

   _updateConnectedPlayerCount: function(num) {
      if (this.$('#multiplayer_menu')) {
         if (num > 1) {
            this.$('#multiplayer_menu .badgeNum').text(num);
            this.$('#multiplayer_menu .badgeNum').show();
         } else {
            this.$('#multiplayer_menu .badgeNum').hide();
         }
      }
   },

   // ACE: show citizen count on the town menu now since citizens is a sub-menu
   _updateCitizensCount: function(num_citizens) {
      var self = this;
      self.$('#town_menu .badgeNum').text(num_citizens);
      self.$('#town_menu .badgeNum').show();
   },

   _updateBulletinCount: function(num_bulletins) {
      var self = this;
      if (num_bulletins > 0) {
         self.$('#bulletin_manager .badgeNum').text(num_bulletins);
         self.$('#bulletin_manager .badgeNum').show();
      } else {
         self.$('#bulletin_manager .badgeNum').hide();
      }
   },

   _updateInventoryState: function(inventory_state) {
      var self = this;
      if (inventory_state == "full" && !self._townMenuStatus) {
         self.$('#startMenu').stonehearthMenu('setWarning', '#town_menu', 'stonehearth:ui.game.menu.warnings.town_inventory_full');
         self._townMenuStatus = App.statusHelper.addStatus(self.$('#town_menu'), 'error_icon.png', -15, 0, true);
      } else {
         App.statusHelper.removeStatus(self._townMenuStatus);
         self.$('#startMenu').stonehearthMenu('setWarning', '#town_menu', null);
         self._townMenuStatus = null;
      }
   },

    _countParties: function(parties) {
      if (parties) {
         radiant.each(parties, function(party_name, party_size){
            if (party_size > 0) {
               self.$('#' + party_name + ' .badgeNum').text(party_size);
               self.$('#' + party_name + ' .badgeNum').show();
            } else {
               self.$('#' + party_name + ' .badgeNum').hide();
            }
         });
      }
   },

   _buildMenu : function(data) {
      var self = this;

      this.$('#startMenu').stonehearthMenu({
         data : data,
         click : function (id, nodeData) {
            self._onMenuClick(id, nodeData);
         },
         shouldHide : function (id, nodeData) {
            return self._shouldHide(id, nodeData)
         },
      });

   },

   // create a trace to enable and disable menu items based on the jobs
   // in the population
   // ACE: add the population change call
   _tracePopulation: function() {
      var self = this;

      App.population.addChangeCallback(self.CHANGE_CALLBACK_NAME, function() {
         var pop = App.population.getPopulationData();
         if (pop.citizens && pop.citizens.size != null) {
            self._updateCitizensCount(pop.citizens.size);
         }
         self._countParties(pop.party_member_counts);
         self._updateInventoryState(pop.inventory_state);
         self._trackJobs();
      }, true);

      App.jobController.addChangeCallback(self.CHANGE_CALLBACK_NAME, function(){
         self._trackJobs();
      }, true);
   },

   _onMenuClick: function(menuId, nodeData) {
      var menuAction = nodeData.menu_action? this.menuActions[nodeData.menu_action] : this.menuActions[menuId];
      // do the menu action
      if (menuAction) {
         menuAction(nodeData);
      }
   },

   _shouldHide: function (menuId, nodeData) {
      var shouldHideFn = nodeData.hide_condition ? this.hideConditions[nodeData.hide_condition] : null;
      if (shouldHideFn) {
         return shouldHideFn.call(this, nodeData);
      }
      return false;
   }

});
