App.StonehearthNotificationContainer = App.View.extend({
   templateName: 'notificationContainer',

   init: function() {
      var self = this;
      this._super();
      self.set('alerts', []);
      self.set('bulletins', []);
      self.set('alertPosition', '');
   },

   didInsertElement: function() {
      var self = this;
      this._super();
   },

   _recalcBulletinHeight: function() {
      var self = this;
      // Move alert notification position depending on whether there
      // is a bulletin notification being displayed
      var top = self.isShowingBulletinNotification() ? -106 : 0;
      self.set('alertPosition', 'top: ' + top + 'px');
   }.observes('bulletins.@each'),

   _getKeyName: function(notification) {
   return /^alert(_.*)?$/.test(notification.type)
      ? 'alerts'
      : 'bulletins';
   },

   addNotificationView: function(notification) {
      var self = this;
      if(!notification) {
         return;
      }
      var key = self._getKeyName(notification);
      var array = self.get(key);
      array.pushObject(notification);
   },

   removeNotificationView: function(notification) {
      var self = this;
      if(!notification) {
         return;
      }
      var key = self._getKeyName(notification);
      var notifications = self.get(key);

      // Can't just do -> notifications.removeObject(notification);
      // instead of below loop because notification is not the same object
      // as the one with matching id in the array
      for (var i = 0; i < notifications.length; i++) {
         if (notifications[i].id === notification.id) {
            notifications.removeAt(i);
            break;
         }
      }
   },

   isShowingBulletinNotification: function() {
      var self = this;
      var bulletins = self.get('bulletins');
      return bulletins && bulletins.length > 0;
   },

   destroyMissingViews: function(notifications, key) {
      var self = this;
      if (!notifications || !key) {
         return;
      }

      var viewNotifications = self.get(key);

      for (var i = 0; i < viewNotifications.length; i++) {
         var notification = viewNotifications[i];
         if (!notification || !notification.id) {
            continue;
         }
         if (!notifications[notification.id]) {
            self.removeNotificationView(notification);
         }
      }
   },

   willDestroyElement: function() {
      var self = this;
      this._super();
   }
});

// Parent of base notification and alert notification views
App.StonehearthBaseBulletinNotification = App.View.extend({
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

   init: function() {
      this._super();
   },

   destroy: function() {
      this._super();
      this._callCallback('notification_closed_callback');
   },

   didInsertElement: function() {
      var self = this;
      this._super();
      this._bulletinDataShown = false;
   },

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

   // Views that inherit from this must override this function
   // Ex: return '.alertNotification'
   // _getTemplateDivClass: function() {
   //    return null;
   // },

   // if the ui_view value changes while we're up, ask App.bulletinBoard
   // to re-create a new view and destory us when that view becomes visible.
   _bulletinDataUpdated : function() {
      Ember.run.scheduleOnce('afterRender', this, '_updateBulletin');
   }.observes('model'),

   _updateBulletin: function() {
      var self = this;
      var templateDivClass = self._getTemplateDivClass();

      if (!self.get('model') || self._bulletinDataShown || !self.$(templateDivClass)) {
         return;
      }

      self._bulletinDataShown = true;
      var bulletinNotificationDuration = 4000;
      var bulletinNotificationFadeTime = 500;

      self._pulsing = true;
      self.$(templateDivClass).pulse();

      var bulletin = self.get('model');

      if (!bulletin.sticky) {
         setTimeout(function() {
            var element = self.$(templateDivClass);

            // make sure element still exists
            if (element) {
               element.fadeOut(bulletinNotificationFadeTime, function() {
                  // make sure to remove notification view from notification view if
                  // notification no longer exists
                  var notificationContainerView = App.bulletinBoard.notificationContainerView;
                  if (notificationContainerView) {
                     notificationContainerView.removeNotificationView(bulletin);
                  }
                  self.destroy();
               });
            }
         }, bulletinNotificationDuration);
      }

      if (/^alert(_.*)?$/.test(self.get('model.type'))) {
         radiant.call('radiant:play_sound', { 'track' : 'stonehearth:sounds:ui:scenarios:alert' });
      } else {
         radiant.call('radiant:play_sound', { 'track' : 'stonehearth:sounds:ui:scenarios:caravan' });
      }
   },

   willDestroyElement: function() {
      var self = this;
      var bulletin = self.get('model');
      var templateDivClass = self._getTemplateDivClass();

      if (this._pulsing) {
         this.$(templateDivClass).pulse('destroy');
      }

      this.$(templateDivClass).off('click');
   }
});

App.StonehearthAlertNotificationView = App.StonehearthBaseBulletinNotification.extend({
   templateName: 'alertNotification',

   didInsertElement: function() {
      var self = this;
      this._super();

      self.$('.alertNotification').click(function() {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:page_down'});
         var bulletin = self.get('model');
         App.bulletinBoard.zoomToLocation(bulletin);
         App.bulletinBoard.markBulletinHandled(bulletin);
         self.destroy();
      });

      self.$('.alertNotification').on('contextmenu', function() {
         self.destroy();
      });
   },

   _getTemplateDivClass: function() {
      return '.alertNotification';
   },

   willDestroyElement: function() {
      var self = this;
      this._super();

      var bulletin = self.get('model');
      App.bulletinBoard.onAlertViewDestroyed(bulletin);
   }
});

App.StonehearthBulletinNotificationView = App.StonehearthBaseBulletinNotification.extend({
   templateName: 'bulletinNotification',

   didInsertElement: function() {
      var self = this;
      this._super();

      self._bindClick();

      self.$('.bulletinNotification').on('contextmenu', function() {
         self.destroy();
      });
   },

   _bindClick: function () {
      var self = this;
      if (!self.$() || !self.get('model') || self._isClickBound) return;
      self.$('.bulletinNotification').click(function () {
         radiant.call('radiant:play_sound', { 'track': 'stonehearth:sounds:ui:start_menu:page_down' });
         var bulletin = self.get('model');
         App.bulletinBoard.zoomToLocation(bulletin);
         App.bulletinBoard.showDialogView(bulletin);
         // Note: don't need to call self.destroy() because showDialogView will try to do that for us.
      });
      self._isClickBound = true;
   }.observes('model'),

   _getTemplateDivClass: function() {
      return '.bulletinNotification';
   },

   willDestroyElement: function() {
      var self = this;
      var bulletin = self.get('model');

      this._super();
      App.bulletinBoard.onNotificationViewDestroyed(bulletin);
   }
});
