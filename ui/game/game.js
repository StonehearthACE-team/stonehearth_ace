App.StonehearthGameUiView = App.ContainerView.extend({
   init: function() {
      this._super();
      this.views = {
         initial: [
            "StonehearthVersionView",
            ],
         complete: [
            "StonehearthCalendarView",
            'StonehearthStartMenuView',
            'StonehearthTaskManagerView',
            'StonehearthGameSpeedWidget',
            'StonehearthTerrainVisionWidget',
            'StonehearthUnitFrameView',
            'StonehearthMpStatusTextWidget',
            'StonehearthChatButtonView',
            'StonehearthOffscreenSignalIndicatorWidget',
            'StonehearthTitanstormView',
         ]
      };

      this._addViews(this.views.initial);

      // xxx, move the calendar to a data service like population

      App.waitForGameLoad().then(() => {
         this._traceCalendar();
         this._traceGameSpeed();
      });

      // ACE: also handle game-wide hotkeys that don't require menu items or certain views open
      var self = this;
      $.getJSON('/stonehearth_ace/ui/data/game_hotkeys.json', function(data) {
         var hotkeys = [];
         radiant.each(data, function(k, v) {
            if (v) {
               v.key = k;
               hotkeys.push(v);
            }
         });

         self.set('gameHotKeys', hotkeys);
      });
   },

   didInsertElement: function () {
      var self = this;
      self._insertedElement = true;
      self._setupHotkeys();
   },

   _setupHotkeys: function () {
      var self = this;
      if (!self._insertedElement) return;

      var gameHotKeys = self.get('gameHotKeys');
      if (!gameHotKeys) return;

      gameHotKeys.forEach(keyData => {
         var key = keyData.key;
         var btn = $(`<button style="display: none" hotkey_action="${key}">${key}</button>`);
         self.$().append(btn);
         btn.click(function(e) {
            if (keyData.event) {
               $(top).trigger(keyData.event, keyData.eventArgs)
            }
         });
      });

      var toggleUiButton = $('<button style="display: none" hotkey_action="ui:toggle">Toggle UI</button>');
      this.$().append(toggleUiButton);
      toggleUiButton.click(function () {
         App.gameView.$().toggle();
         App.debugView.$().toggle();
      });
      App.hotkeyManager.bindActionsWithin(this.$());
   }.observes('gameHotKeys'),

   destroy: function() {
      this._super();

      if (this.trace) {
         this.trace.destroy();
         this.trace = null;
      }

      if (this._gameSpeedTrace) {
         this._gameSpeedTrace.destroy();
         this._gameSpeedTrace = null;
      }
   },

   getDateTime: function() {
      // returns a date adjusted for the start of the game date and month
      return this._dateTime;
   },

   getGameSpeedData: function() {
      return this._gameSpeedData;
   },

   // ACE: also preload mercantile view
   addCompleteViews: function() {
      this._addViews(this.views.complete);

      // Preconstruct these views as well
      // Wait until a delay period after start menu load
      // so that we can offset some of the load time until later
      App.waitForStartMenuLoad().then(() => {
         setTimeout(() => {
            App.stonehearthClient.showSettings(true); // true for hide
            App.stonehearthClient.showSaveMenu(true);
            App.stonehearthClient.showCitizenManager(true);
            App.stonehearthClient.showMercantileView(true);
            App.stonehearthClient.showMultiplayerMenu(true);
         }, 500);
      });
   },

   _addViews: function(views) {
      var views = views || [];
      var self = this;
      $.each(views, function(i, name) {
         var ctor = App[name]
         if (ctor) {
            self.addView(ctor);
         }
      });
   },

   _traceCalendar: function() {
      var self = this;
      radiant.call('stonehearth:get_clock_object')
         .done(function(o) {
            self.trace = radiant.trace(o.clock_object)
               .progress(function(date) {
                  var dateAdjustedForStart = {
                     day : date.day + 1,
                     month : date.month + 1,
                     year : date.year,
                     hour : date.hour,
                     minute : date.minute
                  };
                  self._dateTime = dateAdjustedForStart;
               })
               .fail(function(e) {
                  console.error('could not trace clock_object', e)
               });
         })
         .fail(function(e) {
            console.error('could not get clock_object', e)
         });
   },

   _traceGameSpeed: function() {
      var self = this;
      radiant.call('stonehearth:get_game_speed_service')
         .done(function(response){
            var uri = response.game_speed_service;
            self._gameSpeedTrace = new RadiantTrace(uri)
               .progress(function(o) {
                  self._gameSpeedData = o;
               })
         });
   },
});
