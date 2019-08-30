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

      self._super();

      App.waitForStartMenuLoad().then(() => {
         // this is a call to a global function stored in task_manager.js
         _updateProcessingMeterShown();
      });
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
   }
});