App.StonehearthConfirmView = App.View.extend({
   templateName: 'confirmView',
   classNames: ['flex', 'fullScreen'],
   modal: true,

   didInsertElement: function() {
      var self = this;

      this._super();
      var buttons = this.get('buttons');
      var buttonContainer = this.$('#buttons');

      $.each(buttons, function(i, button) {
         var element = $('<button>');

         element.html(button.label);

         if (button.id) {
            element.attr('id', button.id);
         }

         if (button.click) {
            element.click(function() {
               button.click(button.args);
               self.destroy();
            })
         } else {
            element.click(function() {
               self.destroy();
            })
         }

         buttonContainer.append(element);
      });

      // add tooltips to buttons if present
      App.guiHelper.createDynamicTooltip(self.$('#buttons'), 'button', function($el) {
         var id = $el.attr('id');
         for (var i = 0; i < buttons.length; i++) {
            if (buttons[i].id == id) {
               if (buttons[i].tooltip) {
                  return $(App.tooltipHelper.createTooltip(
                     buttons[i].label,
                     i18n.t(buttons[i].tooltip)));
               }
            }
         }
      }, {delay: 500});
   },

   destroy: function() {
      App.guiHelper.removeDynamicTooltip(this.$('#buttons'), 'button');
      if (this.onDestroy && !this.isDestroyed && !this.isDestroying) {
         this.onDestroy();
      }

      this._super();
   }
});

// TODO: Merge this into the above. This one uses an implicit controller
//       and is used for modal-modals like save and settings confirms.
App.ConfirmView = App.View.extend({
   classNames: ['flex', 'fullScreen'],
   modal: true,

   destroy: function() {
      if (this.get('controller.onDestroy') && !this.isDestroyed && !this.isDestroying) {
         this.get('controller.onDestroy')();
      }

      this._super();
   },

   actions: {
      clickButton: function(buttonData) {
         if (buttonData && buttonData.click) {
            buttonData.click();
         }
         this.destroy();
      }
   }
});
