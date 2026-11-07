var RadiantTrace;
(function () {
   var radiantTraceId = 1;

   RadiantTrace = SimpleClass.extend({

      _debug: false,

      init: function (uri, properties, options) {
         this._traces = {};
         this._id = radiantTraceId;
         radiantTraceId = radiantTraceId + 1;

         if (uri) {
            this.traceUri(uri, properties);
         }
      },

      get_id: function () {
         return this._id;
      },

      progress: function (cb) {
         this._top_deferred.progress(cb);
         return this;
      },

      fail: function (cb) {
         this._top_deferred.fail(cb);
         return this;
      },

      done: function (cb) {
         this._top_deferred.done(cb);
         return this;
      },

      always: function (cb) {
         this._top_deferred.always(cb);
         return this;
      },

      destroy: function () {
         this._destroyed = true;
         this._destroyAllTraces();
      },

      traceUri: function (uri, properties) {
         properties = properties == undefined ? {} : properties;
         this._top_deferred = this._expand_uri(uri, properties)[0];
         return this._top_deferred;
      },

      _assert: function (e) {
         if (!e) {
            throw 'assertion failed!';
         }
      },

      _log: function () {
         if (!this._debug) {
            return;
         }
         var args = Array.prototype.slice.call(arguments);
         var level = args[0];
         var str = args[1]
         args.splice(0, 2); // remove 2 elements from index 0

         var indent = '';
         var level = level ? level : 0;
         for (i = 0; i < level; i++) {
            indent += '   ';
         }
         str = indent + str;
         args.splice(0, 0, level, str) // stick level and indented str at the front
         console.log.apply(console, args);
      },

      _destroyAllTraces: function () {
         $.each(this._traces, function (i, trace) {
            trace.destroy();
         });
         this._top_deferred = null;
         this._traces = {};
      },

      // Given any object (object, array, string, etc) and a tree of properties of that object
      // to expand, issues all the GETs necessary to expand the entire model.  May recur.
      _expand_object: function (obj, properties, level) {
         if (obj instanceof Array) {
            return this._expand_array_properties(obj, properties, level)
         } else if (obj instanceof Object) {
            return this._expand_object_properties(obj, properties, level)
         } else if (typeof obj == 'string') {
            return this._expand_uri(obj, properties, level);
         } else {
            return [$.Deferred().notify(obj), []];
         }
      },

      // Performs a GET on the specified uri.  Expects to receive back a json object which contains
      // all sorts of references to other uris.  'Properties' is a tree of objects indicating which
      // keys of the result need to be re-fetched so we can build the entire model.  This recursively
      // expands the object until all the properties have been filled in.
      _expand_uri: function (uri, properties, level) {
         var self = this;

         //Ember.assert("attempting to fetch something that's not a uri " + uri.toString(), toString.call(uri) == '[object String]')

         //self._log(level, 'fetching uri: ' + uri);

         var previousTraces, childDeferred;
         var deferred = $.Deferred();
         var trace = radiant.trace(uri)
            .progress(function (json) {
               // whenever we get an update, expand the entire object and yield the result            
               //self._log(level, 'in progress callback for ' + info.uri  + '.  expanding...');
               if (json) {
                  var tracesToDelete = previousTraces;
                  [childDeferred, previousTraces] = self._expand_object(json, properties, level != undefined ? level + 1 : 0)
                  if (previousTraces) {
                     radiant.each(previousTraces, function (_, t) {
                        self._traces[t.get_id()] = t;
                     });
                  }
                  childDeferred
                     .progress(function (eobj) {
                        //self._log(level, 'notifying deferred that uri at ' + info.uri + ' has changed');
                        deferred.notify(eobj);
                     })
                     .fail(function (o) {
                        //self._log(level, 'expand object trace of ' + info.uri + ' failed', o);
                        deferred.reject(o)
                     });
                  radiant.each(tracesToDelete, function (_, t) {  // Must be after, to avoid uninstalling traces that we may just reinstall immediately.
                     delete self._traces[t.get_id()];
                     t.destroy();
                  });
               } else {
                  // should we notify or fail?
                  deferred.notify(null);
               }
            })
            .fail(function (o) {
               //self._log(level, 'root recursive trace of ' + info.uri + ' failed', o);
               deferred.reject(o);
            });
         self._traces[trace.get_id()] = trace;
         return [deferred, [trace]];
      },

      _expand_object_properties: function (obj, properties, level) {
         var deferred = $.Deferred();
         var self = this;
         var pending = {};
         // We try to use Ember, but if we are loading on an Ember-less page, like a lightweight in-world popup page, we fall back to a regular JS object with compatible API.
         var eobj = window.Ember ? Ember.Object.create() : { get: function (p) { return this[p]; }, set: function (p, v) { this[p] = v } };
         var ok_to_update = false;
         var first_update = true;
         var childTraces = [];

         var notify_update = function () {
            if (ok_to_update && $.isEmptyObject(pending)) {
               //self._log(level, 'notifying parent of progress!');
               // this is the first update.  push the change out immediately
               if (first_update) {
                  deferred.notify(eobj);
                  first_update = false;
               }
            } else {
               //self._log(level, 'not yet notifying parent of progress!', 'ok_to_update:', ok_to_update, 'pending_object_keys', Object.keys(pending));
            }
         };

         $.each(obj, function (k, v) {
            // Ember doesn't like periods. Transform them before using them as a key.
            // If anyone tries to use the transform value to send it back to someone, then
            // they need to do the inverse transform.
            var emberValidKey = k.replace(/\./g, "&#46;");

            var sub_properties = properties[k] || properties['*']
            if (sub_properties == undefined || !v) {
               eobj.set(emberValidKey, v);
            } else {
               //self._log(level, 'fetching child object: ' + k);
               pending[k] = true;

               var update_property = function (value) {
                  //self._log(level, 'child object ' + k + ' resolved to:', value);

                  // Update the object property and check to see if it's time to notify
                  // the parent
                  if (value != undefined) {
                     eobj.set(emberValidKey, value);
                  } else {
                     delete eobj[emberValidKey];
                  }
                  delete pending[k];

                  //self._log(level, 'pending is now (' + Object.keys(pending).length + ') ' + JSON.stringify(pending));
                  notify_update();
               };

               var [elementDeferred, elementTraces] = self._expand_object(v, sub_properties, level + 1);
               elementDeferred
                  .progress(function (child_eobj) {
                     //self._log(level, 'child object ' + k + ' resolved to:', child_eobj);
                     update_property(child_eobj);
                  })
                  .fail(function (o) {
                     //self._log(level, 'trace faild on child object ' + k + '.');
                     update_property(undefined);
                  });
               childTraces = childTraces.concat(elementTraces);
            }
         });

         //self._log(level, 'exiting _expand_object_properties');
         ok_to_update = true;
         notify_update();

         return [deferred, childTraces];
      },

      _expand_array_properties: function (arr, properties, level) {
         var deferred = $.Deferred();
         var self = this;
         // We try to use Ember, but if we are loading on an Ember-less page, like a lightweight in-world popup page, we fall back to a regular JS array.
         var earr = window.Ember ? Ember.A() : [];
         var pending_count = arr.length;
         var ok_to_update = false;
         earr.length = arr.length;
         var childTraces = [];

         var notify_update = function () {
            if (ok_to_update && pending_count == 0) {
               //self._log(level, 'notifying parent of progress!');
               earr = earr.filter(function (item, index, enumeration) {
                  if (item) {
                     return true;
                  }
                  //console.log("Removing undefined value in array expansion at index " + index + " for arr: " + arr);
                  return false;
               });

               deferred.notify(earr);
               ok_to_update = false;
            }
         };

         $.each(arr, function (i, v) {
            //self._log(level, 'fetching child object: ' + i);
            if (v) {
               var update_property = function (value) {
                  var current = earr[i];
                  if (current) {
                     current.destroy();
                  }

                  earr[i] = value;
                  pending_count--;

                  //self._log(level, 'pending is now (' + pending_count + ') ');
                  notify_update();
               };
               var sub_properties = properties.length > 0 ? properties[0] : properties;
               var [elementDeferred, elementTraces] = self._expand_object(v, sub_properties, level + 1);
               elementDeferred
                  .progress(function (child_eobj) {
                     update_property(child_eobj);
                  })
                  .fail(function (o) {
                     //self._log(level, 'failed to trace array entry', i)
                     update_property(undefined);
                  });
               childTraces = childTraces.concat(elementTraces);
            } else {
               earr[i] = null;
            }
         });

         //self._log(level, 'exiting _expand_array_properties');
         ok_to_update = true;
         notify_update();

         return [deferred, childTraces];
      }

   });

})();

