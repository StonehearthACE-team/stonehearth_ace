// ACE: because of the way this is implemented, the simplest way to patch it is just to override the whole file
// need to change unlocked job roles to actually work properly and only consider jobs with at least one member
var StonehearthJobController;

(function () {
   StonehearthJobController = SimpleClass.extend({

      _components: {
         "jobs": {
            "*": {}
         }
      },

      init: function(initCompletedDeferred) {
         var self = this;
         self._initCompleteDeferred = initCompletedDeferred;
         self._crafterJobs = null;
         self._combatJobs = null;
         self._jobControllerData = {};
         self._jobMemberCounts = {};
         self._unlockedJobRoles = {};

         self._numWorkers = 0;
         self._numCrafters = 0;
         self._numSoldiers = 0;

         self._callbacks = {};

         radiant.call_obj('stonehearth.job', 'get_job_controller_command')
            .done(function(response) {
               self._jobControllerUri = response.job_controller;
               self._initCompleteDeferred.resolve();
               self._createGetterTrace();
            });
      },

      addChangeCallback: function(name, callback_fn, call_fn_immediately) {
         if (!this._callbacks[name]) {
            this._callbacks[name] = callback_fn;
            if (call_fn_immediately) {
               callback_fn();
            }
         } else {
            console.log("attempting to add already registered '" + name + "' callback to App.jobController");
         }
      },

      removeChangeCallback: function(name) {
         delete this._callbacks[name];
      },

      getJobControllerData: function() {
         return this._jobControllerData;
      },

      getNumWorkers: function() {
         return this._numWorkers;
      },

      getNumCrafters: function() {
         return this._numCrafters;
      },

      getNumSoldiers: function() {
         return this._numSoldiers;
      },

      getUri: function() {
         return this._jobControllerUri;
      },

      getComponents: function() {
         return this._components;
      },

      jobHasMembers: function(jobAlias) {

         if (!this._jobMemberCounts[jobAlias]) {
            return false;
         }

         return this._jobMemberCounts[jobAlias] > 0;
      },

      getJobMemberCounts: function(){
         return this._jobMemberCounts;
      },

      getUnlockedJobRoles: function() {
         return this._unlockedJobRoles;
      },

      onJobControllerDataChanged: function() {
         var self = this;

         // get jobs with crafter role
         if (!self._crafterJobs) {
            self._crafterJobs = radiant.getJobsForRole('crafter');
         }
         if (!self._combatJobs) {
            self._combatJobs = radiant.getJobsForRole('combat');
         }

         self._numWorkers = 0;
         self._numCrafters = 0;
         self._numSoldiers = 0;
         self._jobMemberCounts = {};
         self._unlockedJobRoles = {};

         radiant.each(self._jobControllerData.jobs, function(jobAlias, job) {
            var num_members = job.num_members;
            self._jobMemberCounts[jobAlias] = num_members;
            if (self._crafterJobs[jobAlias]) {
               self._numCrafters += num_members;
            } else if (self._combatJobs[jobAlias]) {
               self._numSoldiers += num_members;
            } else {
               self._numWorkers += num_members;
            }

            if (num_members > 0) {
               var roles = job.roles;
               radiant.each(roles, function(roleName, _) {
                  self._unlockedJobRoles[roleName] = true;
               });
            }
         });

         radiant.each(self._callbacks, function(name, callback) {
            if (callback) {
               callback();
            }
         });
      },

      // easy, instant access to some commonly used variables (e.g. when we need to save a game).
      // NOT useful for implementing a reactive ui!  make your own trace for that!!
      _createGetterTrace: function() {
         var self = this;
         self._getterTrace = new RadiantTrace(self._jobControllerUri, self._components)
            .progress(function(job_controller) {
               if (self._jobControllerData) {
                  radiant.each(self._jobControllerData.jobs, function(jobName, jobObject) {
                     self._jobControllerData.jobs.removeObserver(jobName, self, self.onJobControllerDataChanged);
                  });
               }
               self._jobControllerData = job_controller;
               self.onJobControllerDataChanged(self);

               radiant.each(self._jobControllerData.jobs, function(jobName, jobObject) {
                  self._jobControllerData.jobs.addObserver(jobName, self, self.onJobControllerDataChanged);
               });
            });
      }
   });

})();
