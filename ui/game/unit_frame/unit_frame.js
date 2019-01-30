var _selectionHasComponentInfo = false;

var _selectionHasComponentInfoChanged = function() {
   if (_selectionHasComponentInfo) {
      $('#componentInfoButton').show().css('display', 'inline-flex');
   }
   else {
      $('#componentInfoButton').hide();
   }
};

$(top).on("selection_has_component_info_changed", function (_, e) {
   _selectionHasComponentInfo = e.has_component_info;
   _selectionHasComponentInfoChanged();
});

$(top).on('stonehearthReady', function (cc) {
   if (!App.gameView) {
      return;
   }
   var unitFrameExtras = App.gameView.getView(App.UnitFrameExtrasView);
   if (!unitFrameExtras) {
      App.gameView.addView(App.UnitFrameExtrasView, {});
   }
});

App.UnitFrameExtrasView = App.View.extend({
   templateName: 'unitFrameExtras'
});

App.StonehearthUnitFrameView.reopen({
   didInsertElement: function() {
      var self = this;
      self._super();

      var div = self.$('#componentInfoButton');
      if (div.length < 1) {
         var div = $("#componentInfoButton");
         div.insertAfter(self.$("#nametag"));
         App.hotkeyManager.makeTooltipWithHotkeys(div,
            i18n.t('stonehearth_ace:ui.game.unit_frame.toggle_component_info.tooltip_title'),
            i18n.t('stonehearth_ace:ui.game.unit_frame.toggle_component_info.tooltip_description'));
         div.on('click', self.toggleComponentInfo);
      }

      div = self.$('#descriptionDiv');
      div.on('click', function() {
         self.showPromotionTree();
      });

      _selectionHasComponentInfoChanged();
   },

   toggleComponentInfo: function() {
      $(top).trigger('component_info_toggled', {});
   },

   _canPromoteSelectedEntity: function() {
      var self = this;
      return self.get('model.stonehearth:job') && self.get('model.player_id') == App.stonehearthClient.getPlayerId();
   },

   showPromotionTree: function() {
      var self = this;
      if (self._canPromoteSelectedEntity()) {
         // do we need to do a click sound here? the promotion tree window makes a "paper" sound when it comes up
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} );
         App.stonehearthClient.showPromotionTree(self.get('uri'));
      }
   },

   _clearItemQualityIndicator: function() {
      var self = this;
      if (self.$('#qualityGem')) {
         if (self.$('#qualityGem').hasClass('tooltipstered')) {
            self.$('#qualityGem').tooltipster('destroy');
         }
         self.$('#qualityGem').removeClass();
      }
      if (self.$('#nametag')) {
         self.$('#nametag').removeClass();
      }
      self.set('qualityItemCreationDescription', null);
   },

   _updatePromotionTooltip: function() {
      var self = this;
      var div = self.$('#descriptionDiv');
      
      // not sure why this happens...?
      if (!div || div.length < 1) {
         return;
      }

      if (div.hasClass('tooltipstered')) {
         div.tooltipster('destroy');
      }
      if (self._canPromoteSelectedEntity()) {
         div.attr('hotkey_action', 'ui:show_promotion_tree');
         App.hotkeyManager.makeTooltipWithHotkeys(div,
            i18n.t('stonehearth_ace:ui.game.unit_frame.show_promotion_tree.tooltip_title'),
            i18n.t('stonehearth_ace:ui.game.unit_frame.show_promotion_tree.tooltip_description'));
      }
   }.observes('model.uri')
});
