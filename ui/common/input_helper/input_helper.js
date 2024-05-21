/***
 * A class for handling inputs. It registers for listening to keyboard enter or input unfocus
 * and gives a callback when either case happens.
 ***/
var StonehearthInputHelper;

(function () {
   StonehearthInputHelper = SimpleClass.extend({

      init: function(inputElement, inputChangedCallback, maxLength = 1024) {
         var self = this;
         var initialValue = App.stonehearth.validator.enforceStringLength(inputElement, maxLength);
         var isCanceling = false;
         inputElement.inputHelper = self;
         inputElement
            .keydown(function (e) {
               isCanceling = false;
               if (e.keyCode == 13 && !e.originalEvent.repeat) {
                  $(this).blur();
               }
               else if (e.keyCode == 27) {
                  isCanceling = true;
               }
            })
            .blur(function (e) {
               if (isCanceling) {
                  $(this).val(initialValue);
                  return;
               }

               var value = App.stonehearth.validator.enforceStringLength($(this), maxLength);
               if (!initialValue || value != initialValue) {
                  inputChangedCallback(value);
               }
            })
            .focus(function (e) {
               initialValue = App.stonehearth.validator.enforceStringLength($(this), maxLength);
            })
            .tooltipster({content: i18n.t('stonehearth:ui.game.common.input_text_tooltip')});

         this._inputElement = inputElement;
      },

      destroy: function() {
         this._inputElement.off('keydown').off('blur').off('focus');

         // It's possible someone destroys our own tooltip, so just be safe and search for it.
         this._inputElement.find('.tooltipstered').tooltipster('destroy');
      }

   });
})();
