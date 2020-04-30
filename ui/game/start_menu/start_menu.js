App.StonehearthStartMenuView.reopen({
   init: function() {
      var self = this;

      self.menuActions.box_harvest_and_replant = function(){
         self.boxHarvestAndReplant();
      };
      self.menuActions.box_move = function(){
         self.boxMove();
      };
      self.menuActions.box_undeploy = function(){
         self.boxUndeploy();
      };
      self.menuActions.box_cancel_placement = function(){
         self.boxCancelPlacement();
      };
      self.menuActions.box_enable_auto_harvest = function(){
         self.boxEnableAutoHarvest();
      };
      self.menuActions.box_disable_auto_harvest = function(){
         self.boxDisableAutoHarvest();
      };
      self.menuActions.box_hunt = function(){
         self.boxHunt();
      };
      self.menuActions.build_well = function(){
         self.buildWell();
      };
      self.menuActions.build_fence = function(){
         //self.buildFence();
      };
      self.menuActions.create_farm = function(nodeData) {
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
      self.menuActions.create_field = function(nodeData) {
         App.stonehearthClient.createFarm(nodeData.field_type);
      }

      self._super();

      App.waitForStartMenuLoad().then(() => {
         // this is a call to a global function stored in task_manager.js
         _updateProcessingMeterShown();
      });
   },

   _trackJobs: function() {
      // find all the jobs in the population
      var self = this;
      self._super();

      var pop = App.population.getPopulationData();
      radiant.each(pop.unlocked_abilities, function(ability, unlocked) {
         if (unlocked) {
            self.$('#startMenu').stonehearthMenu('unlockItem', 'unlocked_ability', ability);
         }
      });
   },

   // just override this function to add the population change call
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

   boxHarvestAndReplant: function() {
      var self = this;

      var tip = App.stonehearthClient.showTip('stonehearth_ace:ui.game.menu.harvest_menu.items.harvest_and_replant.tip_title',
            'stonehearth_ace:ui.game.menu.harvest_menu.items.harvest_and_replant.tip_description', {i18n : true});

      return App.stonehearthClient._callTool('boxHarvestAndReplant', function() {
         return radiant.call('stonehearth_ace:box_harvest_and_replant_resources')
            .done(function(response) {
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} );
               self.boxHarvestAndReplant();
            })
            .fail(function(response) {
               App.stonehearthClient.hideTip(tip);
            });
      });
   },

   boxMove: function() {
      var self = this;
      var tip = App.stonehearthClient.showTip('stonehearth_ace:ui.game.menu.harvest_menu.items.box_move.tip_title',
            'stonehearth_ace:ui.game.menu.harvest_menu.items.box_move.tip_description', {i18n : true});

      return App.stonehearthClient._callTool('boxMove', function() {
         return radiant.call('stonehearth_ace:box_move')
            .done(function(response) {
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} );
               self.boxMove();
            })
            .fail(function(response) {
               App.stonehearthClient.hideTip(tip);
            });
      });
   },

   boxUndeploy: function() {
      var self = this;
      var tip = App.stonehearthClient.showTip('stonehearth_ace:ui.game.menu.harvest_menu.items.box_undeploy.tip_title',
            'stonehearth_ace:ui.game.menu.harvest_menu.items.box_undeploy.tip_description', {i18n : true});

      return App.stonehearthClient._callTool('boxUndeploy', function() {
         return radiant.call('stonehearth_ace:box_undeploy')
            .done(function(response) {
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} );
               self.boxUndeploy();
            })
            .fail(function(response) {
               App.stonehearthClient.hideTip(tip);
            });
      });
   },

   boxCancelPlacement: function() {
      var self = this;
      var tip = App.stonehearthClient.showTip('stonehearth_ace:ui.game.menu.harvest_menu.items.box_cancel_placement.tip_title',
            'stonehearth_ace:ui.game.menu.harvest_menu.items.box_cancel_placement.tip_description', {i18n : true});

      return App.stonehearthClient._callTool('boxCancelPlacement', function() {
         return radiant.call('stonehearth_ace:box_cancel_placement')
            .done(function(response) {
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} );
               self.boxCancelPlacement();
            })
            .fail(function(response) {
               App.stonehearthClient.hideTip(tip);
            });
      });
   },

   boxEnableAutoHarvest: function() {
      var self = this;
      var tip = App.stonehearthClient.showTip('stonehearth_ace:ui.game.menu.harvest_menu.items.box_enable_auto_harvest.tip_title',
            'stonehearth_ace:ui.game.menu.harvest_menu.items.box_enable_auto_harvest.tip_description', {i18n : true});

      return App.stonehearthClient._callTool('boxEnableAutoHarvest', function() {
         return radiant.call('stonehearth_ace:box_enable_auto_harvest')
            .done(function(response) {
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} );
               self.boxEnableAutoHarvest();
            })
            .fail(function(response) {
               App.stonehearthClient.hideTip(tip);
            });
      });
   },

   boxDisableAutoHarvest: function() {
      var self = this;
      var tip = App.stonehearthClient.showTip('stonehearth_ace:ui.game.menu.harvest_menu.items.box_disable_auto_harvest.tip_title',
            'stonehearth_ace:ui.game.menu.harvest_menu.items.box_disable_auto_harvest.tip_description', {i18n : true});

      return App.stonehearthClient._callTool('boxDisableAutoHarvest', function() {
         return radiant.call('stonehearth_ace:box_disable_auto_harvest')
            .done(function(response) {
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} );
               self.boxDisableAutoHarvest();
            })
            .fail(function(response) {
               App.stonehearthClient.hideTip(tip);
            });
      });
   },

   boxHunt: function() {
      var self = this;

      var tip = App.stonehearthClient.showTip('stonehearth_ace:ui.game.menu.harvest_menu.items.box_hunt.tip_title',
            'stonehearth_ace:ui.game.menu.harvest_menu.items.box_hunt.tip_description', {i18n : true});

      return App.stonehearthClient._callTool('boxHunt', function() {
         return radiant.call('stonehearth_ace:box_hunt')
            .done(function(response) {
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} );
               self.boxHunt();
            })
            .fail(function(response) {
               App.stonehearthClient.hideTip(tip);
            });
      });
   },

   buildWell: function() {
      var self = this;

      var tip = App.stonehearthClient.showTip('stonehearth_ace:ui.game.menu.build_menu.items.build_well.tip_title', 'stonehearth_ace:ui.game.menu.build_menu.items.build_well.tip_description',
         {i18n: true});

      App.setGameMode('place');
      return App.stonehearthClient._callTool('buildWell', function() {
         return radiant.call('stonehearth_ace:place_buildable_entity', 'stonehearth_ace:construction:simple:water_well_ghost')
            .done(function(response) {
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
               self.buildWell();
            })
            .fail(function(response) {
               App.stonehearthClient.hideTip(tip);
            });
      });
   },

   buildFence: function() {
      var self = this;

      var tip = App.stonehearthClient.showTip('stonehearth_ace:ui.game.menu.build_menu.items.build_fence.tip_title', 'stonehearth_ace:ui.game.menu.build_menu.items.build_fence.tip_description',
         {i18n: true});

      //App.setGameMode('fence');
      //App.stonehearthClient.showBuildFenceView();
      return App.stonehearthClient._callTool('buildFence', function() {
         // TODO: make fence pieces customizable
         var fencePieces = [
            'stonehearth:construction:picket_fence:end',
            'stonehearth:construction:picket_fence:bar:single',
            'stonehearth:construction:picket_fence:bar:double'
         ];
         return radiant.call('stonehearth_ace:choose_fence_location_command', fencePieces)
            .done(function(response) {
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
               self.buildFence();
            })
            .fail(function(response) {
               App.stonehearthClient.hideTip(tip);
            });
      });
   },

   buildFishTrap: function() {
      var self = this;

      var tip = App.stonehearthClient.showTip('stonehearth_ace:ui.game.menu.build_menu.items.build_well.tip_title', 'stonehearth_ace:ui.game.menu.build_menu.items.build_well.tip_description',
         {i18n: true});

      App.setGameMode('place');
      return App.stonehearthClient._callTool('buildFishTrap', function() {
         return radiant.call('stonehearth_ace:place_buildable_entity', 'stonehearth_ace:trapper:fish_trap_anchor_ghost')
            .done(function(response) {
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
               self.buildFishTrap();
            })
            .fail(function(response) {
               App.stonehearthClient.hideTip(tip);
            });
      });
   }
});