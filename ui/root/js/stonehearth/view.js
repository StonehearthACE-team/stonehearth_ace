App.View = Ember.View.extend({

   //the components to retrieve from the object
   components: {},

   init: function() {
      // close all other windows with the "exclusive" class set. Only one such window
      // can be on screen at one time
      this._closeOpenExclusiveWindows();
      this._super();

      if (this.get('modal') || this.get('closeOnEsc')) {
         App.stonehearth.modalStack.push(this);
      }
   },

   destroy: function() {
      this._destroyRootTrace();
      this._destroyRadiantTrace();

      if (this.modalOverlay) {
         this.modalOverlay.destroy();
      }

      // if there's an input on the view, unconditionally re-enable
      // hotkeys, in case the input handler code didn't do it
      // properly.
      if (this.get('concreteView')) {
         var input = this.$('input');
         if (input && input.length > 0) {
            radiant.call('radiant:set_hotkeys_enabled', true);
         }
      }

      // if we're on the mobal stack, remove us from it
      var index = App.stonehearth.modalStack.indexOf(this)
      if (index > -1) {
         App.stonehearth.modalStack.splice(index, 1);
      }

      this._super();

      if (this.childDestroyedCb) {
         this.childDestroyedCb();
      }
   },

   willDestroyElement: function () {
      this._unbindHotkeys();
   },

   didInsertElement: function() {
      var position = this.get('position');

      if (position) {
         this.$().children().position(position);
      }

      if (this.$()) {
         this._addHotkeys();
      }
   },

   show: function () {
      if (this.isDestroying || this.isDestroyed) {
         return;
      }
      this._closeOpenExclusiveWindows();
      this.set('isVisible', true);
   },

   hide: function () {
      if (this.isDestroying || this.isDestroyed) {
         return;
      }
      this.set('isVisible', false);
   },

   _reactToVisibilityChanged: function () {
      var self = this;
      if (self.get('skipInvisibleUpdates') && self.get('isVisible')) {
         var modelProperty = self.uriProperty ? self.uriProperty : 'context';
         self.set(modelProperty, self._model);
      }
   }.observes('isVisible'),

   visible: function() {
      return this.get('isVisible');
   },

   invokeDestroy: function() {
      if (this._state == 'preRender') {
         Ember.run.scheduleOnce('afterRender', this, this.destroy);
      } else {
         this.destroy();
      }
   },

   _closeOpenExclusiveWindows: function() {
      var self = this;

      if (self.classNames && self.classNames.contains('exclusive')) {
         $('.exclusive').each(function(i, el) {
            var view = self._getClosestEmberView($(el));
            if (view) {
               view.dismiss ? view.dismiss() : view.destroy();
            }
         })
      }
   },

   _addHotkeys: function () {
      // hotkey_action attributes get automatically looked up and an automatic key->click handler is bound for them.
      App.hotkeyManager.bindActionsWithin(this.$());
   },

   _unbindHotkeys: function () {
      App.hotkeyManager.unbindActionsWithin(this.$());
   },

   _destroyRadiantTrace: function() {
      if (this._radiantTrace) {
         this._radiantTrace.destroy();
         this._radiantTrace = null;
      }
   },

   _destroyRootTrace: function() {
      if (this._rootTrace) {
         if (this._rootTrace.destroy) {
            this._rootTrace.destroy();
         }
         this._rootTrace = null;
      }
   },

   _setRootTrace: function(trace) {
      var self = this;

      this._destroyRootTrace();
      this._rootTrace = trace;

      if (this._rootTrace) {
         this._rootTrace.progress(function(eobj) {
            self._setModel(eobj);
         });
      } else {
         self._setModel({});
      }
   },

   _setModel: function (model) {
      var self = this;
      var modelProperty = self.uriProperty ? self.uriProperty : 'context';
      self._model = model;
      var firstUpdate = true;
      if (!firstUpdate && self.get('skipInvisibleUpdates') && !self.get('isVisible')) {
         // Skipped!
      } else {
         var firstUpdate = false;
         self.set(modelProperty, model);
      }
   },

   // `trace` is an object returned from radiant.trace(), radiant.call(), etc.
   _updatedTrace : function() {
      this._destroyRadiantTrace();

      var trace = null;
      if (this._rootTrace) {
         // console.log("setting view context to deferred object");
         var radiantTrace = new RadiantTrace()
         radiantTrace.userTrace(this.trace, this.components);
      }
      this._setRootTrace(trace);
   }.observes('trace'),

   // `uri` is a string that's valid to pass to radiant.trace()
   _updatedUri: function() {
      this._destroyRadiantTrace();

      var trace = null;
      if (this.uri) {
         // console.log("setting view context for " + this.uri);
         this._radiantTrace = new RadiantTrace()
         trace = this._radiantTrace.traceUri(this.uri, this.components);
      }
      // if both traces are null, don't call _setRootTrace...
      if (this._rootTrace || trace) {
         this._setRootTrace(trace);
      }
   }.observes('uri').on('init'),

   _getClosestEmberView: function(el) {
     var id = el.closest('.ember-view').attr('id');
     if (!id) return;
     if (Ember.View.views.hasOwnProperty(id)) {
       return Ember.View.views[id];
     }
   },

});
