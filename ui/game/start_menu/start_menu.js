App.StonehearthStartMenuView.reopen({
   init: function() {
      var self = this;

      self.menuActions.create_underfarm = function(){
         self.createUnderfarm();
      };
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

      self._super();
   },

   createUnderfarm: function() {
      var self = this;

      App.setGameMode('zones');
      var tip = App.stonehearthClient.showTip('stonehearth_ace:ui.game.menu.zone_menu.items.create_underfarm.tip_title',
            'stonehearth_ace:ui.game.menu.zone_menu.items.create_underfarm.tip_description', { i18n: true });

      return App.stonehearthClient._callTool('createUnderfarm', function(){
         return radiant.call('stonehearth_ace:choose_new_underfield_location')
         .done(function(response) {
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
            radiant.call('stonehearth:select_entity', response.underfield);
         })
         .fail(function(response) {
            App.stonehearthClient.hideTip(tip);
            console.log('new underfield created!');
         });
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
   }
});