// ACE: added some dynamic tooltips
App.StonehearthBaseBulletinDialog = App.View.extend({
   closeOnEsc: true,
   uriProperty: 'model',

   components: {
      "i18n_data" : {
         "boss" : {
            "stonehearth:unit_info": {}
         },
         "entity" : {
            "stonehearth:unit_info": {},
            "stonehearth:job" : {}
         }
      }
   },

   SHOULD_DESTROY_ON_HIDE_DIALOG: false,

   didInsertElement: function() {
      var self = this;
      self._super();

      self._isHidingDialog = false;

      self.dialog = self.$('.bulletinDialog');

      this._wireButtonToCallback('#okButton',      'ok_callback');
      this._wireButtonToCallback('#nextButton',    'next_callback', true);    // Keep the dialog around on next
      this._wireButtonToCallback('#acceptButton',  'accepted_callback');
      this._wireButtonToCallback('#declineButton', 'declined_callback');

      var cssClass = self.get('model.data.cssClass');
      if (cssClass) {
         self.dialog.addClass(cssClass);
      }

      self._calledOpenCallback = false;
      
      self.createDynamicTooltips();
   },

   _watchModelToCallOpenedCallback: function () {
      if (this.get('model') && !this._calledOpenCallback) {
         this._callCallback('opened_callback');
         this._calledOpenCallback = true;
      }
   }.observes('model'),

   destroy: function () {
      if (!this._isHidingDialog) {
         this._callCallback('closed_callback');
      }
      this._super();
   },

   isHidingDialog: function() {
      return this._isHidingDialog;
   },

   hideByDestroying: function() {
      this._isHidingDialog = true;
      this.destroy();
   },

   // if the ui_view value changes while we're up, ask App.bulletinBoard
   // to re-create a new view and destroy us when that view becomes visible.
   _checkView : function() {
      var self = this;
      var bulletin = self.get('model')
      var viewClassName = String(self.constructor);
      if ('App.' + bulletin.ui_view != viewClassName) {
         // set a flag to prevent calling back into the bulletin board
         // on destroy.  Otherwise, the board gets confused when it tries
         // to make sure it creates the new view for this bulletin before
         // this one has a chance to die (see recreateDialogVIew)
         self._dontNotifyDestroy = true;
         App.bulletinBoard.recreateDialogView(bulletin);
      }
   }.observes('model.ui_view'),

   _updateI18nData: function() {
      var self = this;
      var data = self.get('model.i18n_data.req_1');

      Ember.run.scheduleOnce('afterRender', function() {
         if (!data) {
            self.$('.numCached').addClass('.noCache');
         }
      });
   }.observes('model.i18n_data'),

   _callCallback: function(callback_key) {
      var self = this;
      var bulletin = self.get('model');
      if (!bulletin) {
         return;
      }
      var instance = bulletin.callback_instance;
      var method = bulletin.data[callback_key];

      if (method) {
         radiant.call_obj(instance, method)
            .done(function(response) {
               if (response.trigger_event) {
                  $(top).trigger(response.trigger_event.event_name, response.trigger_event.event_data);
               }
            });
      }
   },

   _wireButtonToCallback: function(buttonid, callback, keepAround) {
      var self = this
      self.dialog.on('click', buttonid, function() {
         if ($(this).hasClass('disabled')) {
            return;
         }
         self._callCallback(callback);
         if (!keepAround) {
            self._autoDestroy();
         }
      });

   },

   _autoDestroy: function() {
      var self = this;
      var bulletin = self.get('model');
      if (bulletin && !bulletin.keep_open) {
         App.bulletinBoard.markBulletinHandled(bulletin);
         self.destroy();
      }
   },

   willDestroyElement: function() {
      var self = this;

      App.guiHelper.removeDynamicTooltip(self.$('.window'), '.questItemsCached');
      App.guiHelper.removeDynamicTooltip(self.$('.window'), '.numCached');

      if (!self._dontNotifyDestroy && !self._isHidingDialog) {
         var bulletin = self.get('model');
         if (bulletin) {  // The trace might not have resolved yet.
            App.bulletinBoard.onDialogViewDestroyed(bulletin);
         }
      }
      this._super();
   },

   createDynamicTooltips: function() {
      var self = this;

      App.guiHelper.removeDynamicTooltip(self.$('.window'), '.questItemsCached');
      App.guiHelper.removeDynamicTooltip(self.$('.window'), '.numCached');

      App.guiHelper.createDynamicTooltip(self.$('.window'), '.questItemsCached', function() {
         if (self.$('.window .questItemsCached').hasClass('fullyCached')) {
            return $(App.tooltipHelper.createTooltip(null, i18n.t(`stonehearth_ace:ui.game.bulletin.generic.fully_cached`)));
         }
      });
      App.guiHelper.createDynamicTooltip(self.$('.window'), '.numCached', function() {
         return $(App.tooltipHelper.createTooltip(null, i18n.t(`stonehearth_ace:ui.game.bulletin.generic.num_cached`)));
      });
   },
});
