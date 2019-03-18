var unit_info_property = 'stonehearth:unit_info';
var root_unit_info_property = 'stonehearth:iconic_form.root_entity.stonehearth:unit_info';

// spiegg's solution here: https://stackoverflow.com/questions/6491463/accessing-nested-javascript-objects-with-string-key
function interpretPropertyString(s, obj) {
   var properties = Array.isArray(s) ? s : s.split('.')
   return properties.reduce((prev, curr) => prev && prev[curr], obj)
}

// need to add support for titles and other custom data to name localization
var stonehearth_translate = function(key, options) {
   if (typeof key != 'string' || key == '') {
      // If there's nothing to translate, bail.
      return "";
   }

   if (key.indexOf('i18n(') == 0 && key.charAt(key.length-1) == ')' && key.charAt(6) != '_') {
      key = key.substr(5, key.length-6);
   }

   options = options || {};
   var originalLang = options.lng;
   options.postProcess = "localizeEntityName";
   if (key.indexOf(i18n.options.nsseparator) > -1) {
      var parts = key.split(i18n.options.nsseparator);
      var namespace = parts[0];
      var currentLang = i18n.lng();
      if (!i18n.hasResourceBundle(currentLang, namespace)) { // If no data for namespace, supply a fallback locale
         var moduleData = App.getModuleData();
         var mod = moduleData ? moduleData[namespace] : null;
         if (mod && mod.default_locale) {
            options.lng = mod.default_locale;
         }
      }
   }
   if (options.escapeHTML) {
      options.escapeInterpolation = true;
   }
   var translatedToken = i18n.translate(key, options);

   // if "self.stonehearth:unit_info" is specified, check whether the root form's unit_info should be used instead
   if (typeof translatedToken == 'string' && translatedToken.indexOf(i18n.options.interpolationPrefix + 'self.' + unit_info_property) >= 0) {
      var root_unit_info = interpretPropertyString('self.' + root_unit_info_property, options);
      if (root_unit_info && (root_unit_info.custom_name || root_unit_info.custom_data)) {
         translatedToken = translatedToken.split(i18n.options.interpolationPrefix + 'self.' + unit_info_property)
                                          .join(i18n.options.interpolationPrefix + 'self.' + root_unit_info_property);
         translatedToken = i18n.translate(translatedToken, options);
      }
   }

   options.lng = originalLang;
   return translatedToken;
}

i18n.t = stonehearth_translate;

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

         opts['self'] = {};
         opts.self['stonehearth:unit_info'] = unit_info;
         if (!opts.self['stonehearth:unit_info']) {
            opts.self['stonehearth:unit_info'] = {
               'custom_name': customName,
               'custom_data': interpretPropertyString(tokenWithoutSymbols + '_custom_data', opts) || {}
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