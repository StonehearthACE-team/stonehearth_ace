App.StonehearthInputPromptView = App.View.extend({
   templateName: 'inputPromptView',
   classNames: ['flex', 'fullScreen'],
   modal: true,

   didInsertElement: function() {
      var self = this;

      self._super();
      var buttons = self.get('buttons');
      var buttonContainer = self.$('#buttons');

      self.set('inputText', self.get('default_value'));

      $.each(buttons, function(i, button) {
         var element = $('<button>');

         element.html(button.label);

         if (button.id) {
            element.attr('id', button.id);
         }

         if (button.click) {
            element.click(function() {
               button.click(self.$('#inputText').val());
               self.destroy();
            })
         } else {
            element.click(function() {
               self.destroy();
            })
         }

         buttonContainer.append(element);
      });
   },

   destroy: function() {
      if (this.onDestroy && !this.isDestroyed && !this.isDestroying) {
         this.onDestroy();
      }

      this._super();
   }
});
