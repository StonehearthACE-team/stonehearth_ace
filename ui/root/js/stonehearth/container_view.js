// management of modal views

// A function for recursively closing all views until the esc menu. Returns true
// If a modal was closed.
var closeAllModalsRecursively = function() {
   var consoleView = App.debugView && App.debugView.getView(App.StonehearthConsoleView);
   consoleView = consoleView ? consoleView.$() : null;

   if (consoleView && consoleView.is(':visible')) {
      consoleView.toggle();
      return true;
   }

   if (App.stonehearth.modalStack.length > 0) {
      // there's a modal. close it
      var modal = App.stonehearth.modalStack.pop();

      // it's possible that the view was destroyed by someone else. If so, just pop it
      while(modal.isDestroyed && App.stonehearth.modalStack.length > 0) {
         modal = App.stonehearth.modalStack.pop();
      }

      if (modal.tryDestroy) {
         // Some modals may want confirmation before closing.
         var originalPosition = App.stonehearth.modalStack.length;
         if (!modal.tryDestroy()) {
            App.stonehearth.modalStack.insertAt(originalPosition, modal);  // Put it back!
         }
      } else if (modal.dismiss) {
         // Some modals want to just be hidden.
         if (modal.dismiss(true)) {
            App.stonehearth.modalStack.push(modal);  // Put it back!
         }
      } else {
         modal.destroy();
      }
      return true;
   }

   if (App.gameMenu && App.gameMenu.getMenu()) {
      // if there's an open menu, close it
      App.gameMenu.hideMenu();
      return true;
   }

   if (App.getGameMode && App.getGameMode() != 'normal') {
      // switch to normal mode
      App.stonehearthClient.deactivateAllTools();
      App.setGameMode('normal');

      return true;
   }
   return false;
}

$(document).ready(function(){
   App.stonehearth.modalStack = []

   $(document).keydown(function(e) {
      if(e.keyCode == 27 && !e.originalEvent.repeat) {  // esc
         var handled = closeAllModalsRecursively();
         if (!handled && App.gameView) {
            App.gameView.addView(App.StonehearthEscMenuView);
         }
      }
   });
});

App.ContainerView = Ember.ContainerView.extend({

   _viewLookup: {},
   _routeLookup: {},

   addView: function(type, options, propagateClicks, insertIndex) {
      // console.log("adding view " + type);

      var modalOverlay;
      var childView = this.createChildView(type, {
         classNames: propagateClicks ? null : ['stonehearth-view']
      });
      childView.setProperties(options);

      if (childView.get('modal')) {
         modalOverlay = this.createChildView(App.StonehearthModalOverlayView, {
            classNames: propagateClicks ? null : ['stonehearth-view'],
            modalView: childView,
         });
         childView.modalOverlay = modalOverlay;
      }

      // Modal stacks are pushed on App.View init now. -yshan 9/28/2015

      this._viewLookup[type] = childView;

      if (modalOverlay) {
         this.pushObject(modalOverlay);
      }
      if (typeof insertIndex == 'number') {
         this.insertAt(insertIndex, childView);
      } else {
         this.pushObject(childView);
      }

      return childView;
   },

   show: function() {
      this.set('isVisible', true);
   },

   hide: function() {
      this.set('isVisible', false);
   },

   childDestroyed: function(type) {
      delete this._viewLookup[type];
   },

   visible: function() {
      return this.get('isVisible');
   },

   hideAllViews: function() {
      var childViews = this.get('childViews');

      $.each(childViews, function(i, childView) {
         childView.hide();
         //childView.set('isVisible', false);
      });
      App.stonehearthClient.hideTip();
   },

   getView: function(type) {
      return this._viewLookup[type];
   },

   addRoutes: function(routeLookup) {
      for (const route in routeLookup) {
         this._routeLookup[route] = routeLookup[route];
      }
   },

   handleRoute: function(route, options) {
      if (!this._routeLookup.hasOwnProperty(route)) {
         return;
      }

      let viewName = this._routeLookup[route];
      let childView = this.getView(App[viewName]);

      if (this._lastViewName) {
         let lastView = this.getView(App[this._lastViewName]).$();
         if (lastView) {
            lastView.hide();
         }
      }
      this._lastViewName = viewName;

      if (childView) {
         childView.$().show();
      } else {
         // Our views are in a global namespace.
         var self = this;
         options = options || {};
         options.childDestroyedCb = function() {
            self.childDestroyed(App[viewName]);
            if (self._lastViewName == viewName) {
               delete self._lastViewName;
            }
         }
         this.addView(App[viewName], options);
      }
   }

});
