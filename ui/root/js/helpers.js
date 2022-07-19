var unit_info_property = 'stonehearth:unit_info';
var root_unit_info_property = 'stonehearth:iconic_form.root_entity.stonehearth:unit_info';

// spiegg's solution here: https://stackoverflow.com/questions/6491463/accessing-nested-javascript-objects-with-string-key
function interpretPropertyString(s, obj) {
   var properties = Array.isArray(s) ? s : s.split('.')
   return properties.reduce((prev, curr) => prev && prev[curr], obj)
}

i18n.addPostProcessor("localizeEntityName", function(value, key, isFound, opts) {
   //i18n(__i18n_data.entity_display_name__, {\"self.stonehearth:unit_info.custom_name\":\"__i18n_data.entity_custom_name__\"})

   var nameHelperPrefix = '[name(';
   var nameHelperSuffix = ')]';
   var replacementCounter = 0;
   var maxRecursion = 4;

   opts.postProcess = null;

   function localizeName(translated, options) {
     while (translated.indexOf(nameHelperPrefix) != -1) {
         replacementCounter++;
         if (replacementCounter > maxRecursion) {
            break;
         } // safety net for too much recursion
         var indexOfOpening = translated.lastIndexOf(nameHelperPrefix);
         var indexOfEndOfClosing = translated.indexOf(nameHelperSuffix, indexOfOpening) + nameHelperSuffix.length;
         var token = translated.substring(indexOfOpening, indexOfEndOfClosing);
         var tokenWithoutSymbols = token.replace(nameHelperPrefix, '').replace(nameHelperSuffix, '');

         if (indexOfEndOfClosing <= indexOfOpening) {
             f.error('there is a missing closing in following translation value', translated);
             return '';
         }

         // if [entity]_custom_name doesn't work, assume it's a full entity passed to us
         var customNameKey = i18n.options.interpolationPrefix + tokenWithoutSymbols + "_custom_name" + i18n.options.interpolationSuffix;
         var customName = i18n.applyReplacement(customNameKey, opts);
         var isFullEntity = false;

         // prefer the unit info for this entity, unless custom_name or custom_data is specified for root entity
         var tokenData = interpretPropertyString(tokenWithoutSymbols, opts);
         var ui_property = unit_info_property;
         var unit_info = interpretPropertyString(unit_info_property, tokenData);
         var root_unit_info = interpretPropertyString(root_unit_info_property, tokenData);
         if (root_unit_info && (root_unit_info.custom_name || root_unit_info.custom_data)) {
            ui_property = root_unit_info_property;
            unit_info = root_unit_info;
         }
         
         if (customName == customNameKey) {
            isFullEntity = true;
            customNameKey = i18n.options.interpolationPrefix + tokenWithoutSymbols + "." + ui_property + ".custom_name" + i18n.options.interpolationSuffix;
            customName = i18n.applyReplacement(customNameKey, opts);
         }

         var newToken = i18n.options.interpolationPrefix + tokenWithoutSymbols + (isFullEntity ? "." + ui_property + ".display_name" : "_display_name") + i18n.options.interpolationSuffix;
         var replacedToken = i18n.applyReplacement(newToken, opts);

         var customData = interpretPropertyString(tokenWithoutSymbols + '_custom_data', opts) || {};
         opts['self'] = {};
         opts.self['stonehearth:unit_info'] = unit_info;
         if (!opts.self['stonehearth:unit_info'] || !isFullEntity) {
            opts.self['stonehearth:unit_info'] = {
               'custom_name': customName,
               'custom_data': customData
            };
         }
         opts.defaultValue = i18n.t("stonehearth:ui.game.entities.unknown_name");
         var translatedToken = i18n.t(replacedToken, opts);
         if (options.escapeHTML) {
            translatedToken = Ember.Handlebars.Utils.escapeExpression(translatedToken);
         }
         translated = translated.replace(token, translatedToken);
     }
     return translated;
   }

   if (value.indexOf("[name(") >= 0) {
      var newValue = localizeName(value, opts);
      newValue = i18n.applyReplacement(newValue, opts);
      return newValue;
   }

   if (value == key && !isFound) {
      return undefined;
   }


   return value;
});