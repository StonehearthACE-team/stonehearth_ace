$(document).on('stonehearthReady', function(){
   App.debugDock = App.debugView.addView(App.StonehearthDebugDockView);
});

App.StonehearthDebugDockView = App.ContainerView.extend({
   classNames: ['debugDock'],
   
   init: function() {
      this._super();
      var self = this;

      setInterval(function () {
         self.$().toggleClass('titanstorm', Boolean($('#titanstorm:visible')[0]));
      }, 300);
   },

   didInsertElement: function() {
      var self = this;
      self._super();

      $(top).on('set_debug_ui_visible', function(_, e) {
         self.setVisible(e.shouldShow);
      });

      Ember.run.scheduleOnce('afterRender', this, function() {
         stonehearth_ace.getModConfigSetting('stonehearth_ace', 'show_debugtools_on_load', function(value) {
            self.setVisible(value);
         });
      });
   },

   addToDock: function(ctor) {
      this.addView(ctor)
   },

   setVisible: function(visible) {
      if (visible) {
         this.show();
      }
      else {
         this.hide();
      }
   }
});
