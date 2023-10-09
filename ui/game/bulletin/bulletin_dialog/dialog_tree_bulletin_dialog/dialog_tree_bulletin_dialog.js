App.StonehearthDialogTreeBulletinDialog = App.StonehearthBaseBulletinDialog.extend({
   templateName: 'dialogTreeBulletinDialog',

   didInsertElement: function () {
      this._super();
      this._wireButtonToCallback('#collectionPayButton', 'collection_pay_callback');
      this._wireButtonToCallback('#collectionCancelButton', 'collection_cancel_callback');
   },

   _onMessageChanged: function () {
      Ember.run.scheduleOnce('afterRender', this, function () {
         this._stopTextAnimation();
         this._animateText();
      });
   }.observes('model.data.message'),

   _onZoomToEntityChanged: function() {
      if (!this._zoomedToInitial) {
         App.bulletinBoard.zoomToLocation(this.get('model'));
      }
      this._zoomedToInitial = true;
   }.observes('model.data.zoom_to_entity'),

   _onPortraitOffsetChanged: function () {
      var offset = this.get('model.data.portrait_offset') || 0;
      Ember.run.scheduleOnce('afterRender', this, function () {
         if (this.$('#portrait img')) {
            this.$('#portrait img').css('top', offset);
         }
      });
   }.observes('model.data.portrait_offset'),

   _animateText: function () {
      if (!this.$('#content')) return;

      this.$('#buttons').addClass('unrevealed');

      var self = this;
      var textBlocks = self._findTextNodes(self.$('#content')[0]);
      var textBlockWrappers = $(textBlocks).wrap('<span class="unrevealed-text">').parent();
      textBlockWrappers = Array.prototype.slice.call(textBlockWrappers);

      function fadeInNextBlock() {
         if (textBlockWrappers.length && $(textBlockWrappers[0]).hasClass('unrevealed-text')) {
            self.currentTextAnimation = $(textBlockWrappers.shift()).textillate({
               'in': { 'effect': 'fadeIn', 'delay': 15 },
               'callback': fadeInNextBlock
            }).removeClass('unrevealed-text');
         } else {
            self.$('#buttons').removeClass('unrevealed');
         }
      }
      fadeInNextBlock();

      this.$('.window').click(() => this._stopTextAnimation());
   },

   _stopTextAnimation: function () {
      if (this.$('#content .unrevealed-text')) {
         this.$('#content .unrevealed-text').removeClass('unrevealed-text');
         if (this.currentTextAnimation) {
            this.currentTextAnimation.textillate('stopAllAnimations');
            this.$('#buttons').removeClass('unrevealed');
         }
      }
   },

   _findTextNodes: function (el) {
      var result = []
      var walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT, null, false);
      var node;
      while (node = walker.nextNode()) {
         if (node.length && node.textContent.trim().length) {
            result.push(node);
         }
      }
      return result;
   },
   
   _choices: function() {
   	var buttons = [];
      var choices = this.get('model.data.choices');
      if (choices) {
      	buttons = radiant.map_to_array(choices, function(k, v) {
            return {
               id: k,
               text: i18n.t(k),
            }
         });
      }
      this.set('buttons', buttons);
   }.observes('model.data.choices'),

   actions: {
      choose: function(choice) {
         var bulletin = this.get('model');
         var instance = bulletin.callback_instance;
         radiant.call_obj(instance, '_on_dialog_tree_choice', choice);
      }
   },

});
