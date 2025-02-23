//------------------------------------------------------------------------------------------------//
// This file is part of the Nebula Logger project, released under the MIT License.                //
// See LICENSE file or go to https://github.com/jongpie/NebulaLogger for full license details.    //
//------------------------------------------------------------------------------------------------//

/**
 * @group Log Management
 * @description Processes `LogEntryEvent__e` platform events and normalizes the data into `Log__c` and `LogEntry__c` records
 */
@SuppressWarnings('PMD.ApexCrudViolation, PMD.AvoidDebugStatements, PMD.CognitiveComplexity, PMD.CyclomaticComplexity')
public without sharing class LogEntryEventHandler extends LoggerSObjectHandler {
    @TestVisible
    private static final String DEFAULT_STORAGE_LOCATION_NAME = 'CUSTOM_OBJECTS';
    private static final Database.DmlOptions DML_OPTIONS = createDmlOptions();
    private static final Map<String, Log__c> TRANSACTION_ID_TO_LOG = new Map<String, Log__c>();
    @TestVisible
    private static final List<LogEntryTagRule__mdt> TAG_ASSIGNMENT_RULES = getTagAssignmentRules();

    @TestVisible
    private List<LogEntryEvent__e> logEntryEvents;

    private List<LogEntry__c> logEntries = new List<LogEntry__c>();
    private Map<String, List<String>> logEntryEventUuidToTagNames = new Map<String, List<String>>();
    private Set<String> tagNames = new Set<String>();

    /**
     * @description Default constructor, used by the trigger `LogEntryEvent.trigger`
     */
    public LogEntryEventHandler() {
        super();
    }

    /**
     * @description Returns SObject Type that the handler is responsible for processing
     * @return      The instance of `SObjectType`
     */
    public override SObjectType getSObjectType() {
        return Schema.LogEntryEvent__e.SObjectType;
    }

    protected override void executeAfterInsert(List<SObject> triggerNew) {
        this.logEntryEvents = this.filterLogEntryEventsToSave((List<LogEntryEvent__e>) triggerNew);

        if (this.logEntryEvents.isEmpty() == false) {
            this.upsertLogs();
            this.insertLogEntries();
            this.appendRuleBasedTags();
            this.insertLogEntryTags();
        }
    }

    private List<LogEntryEvent__e> filterLogEntryEventsToSave(List<LogEntryEvent__e> newLogEntryEvents) {
        List<LogEntryEvent__e> logEntryEventsToSave = new List<LogEntryEvent__e>();
        for (LogEntryEvent__e logEntryEvent : newLogEntryEvents) {
            User loggingUser = new User(Id = logEntryEvent.LoggedById__c, ProfileId = logEntryEvent.ProfileId__c);
            LoggerSettings__c loggingUserSettings = Logger.getUserSettings(loggingUser);
            if (loggingUserSettings.DefaultPlatformEventStorageLocation__c == DEFAULT_STORAGE_LOCATION_NAME) {
                logEntryEventsToSave.add(logEntryEvent);
            }
        }
        return logEntryEventsToSave;
    }

    private void upsertLogs() {
        // To avoid making a callout for every log for details retrieved from api.status.salesforce.com,
        // try to query recent logs first to see if there is a recent log with the details already populated
        Log__c recentLogWithApiReleaseDetails = getRecentLogWithApiReleaseDetails();

        for (LogEntryEvent__e logEntryEvent : this.logEntryEvents) {
            // The LogEntryEvent__e object stores a denormalized version of Log__c & LogEntry__c data
            // In case the list contains entries tied to multiple transactions, use the TRANSACTION_ID_TO_LOG map to create 1 Log__c per transaction ID
            if (TRANSACTION_ID_TO_LOG.containsKey(logEntryEvent.TransactionId__c) == true) {
                continue;
            }

            Log__c parentLog = new Log__c(TransactionId__c = logEntryEvent.ParentLogTransactionId__c);
            Log__c log = new Log__c();

            // Guest users cannot own records, so keep the log owner as the current user (Automated Process)
            String guestUserLicenseName = 'Guest User License';
            Id logOwnerId;
            if (logEntryEvent.UserLicenseName__c == guestUserLicenseName || String.isBlank(logEntryEvent.CreatedById)) {
                logOwnerId = UserInfo.getUserId();
            } else {
                logOwnerId = logEntryEvent.CreatedById;
            }

            if (recentLogWithApiReleaseDetails != null) {
                log.ApiReleaseNumber__c = recentLogWithApiReleaseDetails.ApiReleaseNumber__c;
                log.ApiReleaseVersion__c = recentLogWithApiReleaseDetails.ApiReleaseVersion__c;
            }

            log.ApiVersion__c = logEntryEvent.ApiVersion__c;
            log.Locale__c = logEntryEvent.Locale__c;
            log.LoggedBy__c = logEntryEvent.LoggedById__c;
            log.LoggedByUsername__c = logEntryEvent.LoggedByUsername__c;
            log.LoggerVersionNumber__c = logEntryEvent.LoggerVersionNumber__c;
            log.LoginApplication__c = logEntryEvent.LoginApplication__c;
            log.LoginBrowser__c = logEntryEvent.LoginBrowser__c;
            log.LoginDomain__c = logEntryEvent.LoginDomain__c;
            log.LoginHistoryId__c = logEntryEvent.LoginHistoryId__c;
            log.LoginPlatform__c = logEntryEvent.LoginPlatform__c;
            log.LoginType__c = logEntryEvent.LoginType__c;
            log.LogoutUrl__c = logEntryEvent.LogoutUrl__c;
            log.NetworkId__c = logEntryEvent.NetworkId__c;
            log.NetworkLoginUrl__c = logEntryEvent.NetworkLoginUrl__c;
            log.NetworkLogoutUrl__c = logEntryEvent.NetworkLogoutUrl__c;
            log.NetworkName__c = logEntryEvent.NetworkName__c;
            log.NetworkSelfRegistrationUrl__c = logEntryEvent.NetworkSelfRegistrationUrl__c;
            log.NetworkUrlPathPrefix__c = logEntryEvent.NetworkUrlPathPrefix__c;
            log.OrganizationDomainUrl__c = logEntryEvent.OrganizationDomainUrl__c;
            log.OrganizationEnvironmentType__c = logEntryEvent.OrganizationEnvironmentType__c;
            log.OrganizationId__c = logEntryEvent.OrganizationId__c;
            log.OrganizationInstanceName__c = logEntryEvent.OrganizationInstanceName__c;
            log.OrganizationName__c = logEntryEvent.OrganizationName__c;
            log.OrganizationNamespacePrefix__c = logEntryEvent.OrganizationNamespacePrefix__c;
            log.OrganizationType__c = logEntryEvent.OrganizationType__c;
            log.OwnerId = logOwnerId;
            log.ParentLog__r = logEntryEvent.ParentLogTransactionId__c == null ? null : parentLog;
            log.ProfileId__c = logEntryEvent.ProfileId__c;
            log.ProfileName__c = logEntryEvent.ProfileName__c;
            log.Scenario__c = logEntryEvent.Scenario__c;
            log.SessionId__c = logEntryEvent.SessionId__c;
            log.SessionSecurityLevel__c = logEntryEvent.SessionSecurityLevel__c;
            log.SessionType__c = logEntryEvent.SessionType__c;
            log.SourceIp__c = logEntryEvent.SourceIp__c;
            log.SystemMode__c = logEntryEvent.SystemMode__c;
            log.ThemeDisplayed__c = logEntryEvent.ThemeDisplayed__c;
            log.TimeZoneId__c = logEntryEvent.TimeZoneId__c;
            log.TimeZoneName__c = logEntryEvent.TimeZoneName__c;
            log.TransactionId__c = logEntryEvent.TransactionId__c;
            log.UserLicenseDefinitionKey__c = logEntryEvent.UserLicenseDefinitionKey__c;
            log.UserLicenseId__c = logEntryEvent.UserLicenseId__c;
            log.UserLicenseName__c = logEntryEvent.UserLicenseName__c;
            log.UserLoggingLevel__c = logEntryEvent.UserLoggingLevel__c;
            log.UserLoggingLevelOrdinal__c = logEntryEvent.UserLoggingLevelOrdinal__c;
            log.UserRoleId__c = logEntryEvent.UserRoleId__c;
            log.UserRoleName__c = logEntryEvent.UserRoleName__c;
            log.UserType__c = logEntryEvent.UserType__c;

            TRANSACTION_ID_TO_LOG.put(log.TransactionId__c, log);
        }

        List<Database.UpsertResult> upsertResults = LoggerDataStore.getDatabase()
            .upsertRecords(TRANSACTION_ID_TO_LOG.values(), Schema.Log__c.TransactionId__c, System.Test.isRunningTest());
        LoggerEmailSender.sendErrorEmail(Schema.Log__c.SObjectType, upsertResults);

        // If no recent logs have the details, and there is not another instance of the job in progress, then start a new one
        // TODO this probably should be moved to LogHandler instead of here
        if (LoggerParameter.CALL_STATUS_API == true && recentLogWithApiReleaseDetails == null && getCountOfOpenJobs() == 0) {
            setStatusApiDetails();
        }
    }

    private void insertLogEntries() {
        for (LogEntryEvent__e logEntryEvent : this.logEntryEvents) {
            // Workaround field for platform issue w/ accurate datetimes
            Datetime timestamp = String.isNotBlank(logEntryEvent.TimestampString__c)
                ? Datetime.valueOf(Long.valueOf(logEntryEvent.TimestampString__c))
                : logEntryEvent.Timestamp__c;

            LogEntry__c logEntry = new LogEntry__c(
                ComponentType__c = logEntryEvent.ComponentType__c,
                DatabaseResultCollectionSize__c = logEntryEvent.DatabaseResultCollectionSize__c,
                DatabaseResultCollectionType__c = logEntryEvent.DatabaseResultCollectionType__c,
                DatabaseResultJson__c = logEntryEvent.DatabaseResultJson__c,
                DatabaseResultType__c = logEntryEvent.DatabaseResultType__c,
                EpochTimestamp__c = logEntryEvent.EpochTimestamp__c,
                EventUuid__c = logEntryEvent.EventUuid,
                ExceptionMessage__c = logEntryEvent.ExceptionMessage__c,
                ExceptionStackTrace__c = logEntryEvent.ExceptionStackTrace__c,
                ExceptionType__c = logEntryEvent.ExceptionType__c,
                HttpRequestBody__c = logEntryEvent.HttpRequestBody__c,
                HttpRequestBodyMasked__c = logEntryEvent.HttpRequestBodyMasked__c,
                HttpRequestCompressed__c = logEntryEvent.HttpRequestCompressed__c,
                HttpRequestEndpoint__c = logEntryEvent.HttpRequestEndpoint__c,
                HttpRequestMethod__c = logEntryEvent.HttpRequestMethod__c,
                HttpResponseBody__c = logEntryEvent.HttpResponseBody__c,
                HttpResponseBodyMasked__c = logEntryEvent.HttpResponseBodyMasked__c,
                HttpResponseHeaderKeys__c = logEntryEvent.HttpResponseHeaderKeys__c,
                HttpResponseStatus__c = logEntryEvent.HttpResponseStatus__c,
                HttpResponseStatusCode__c = logEntryEvent.HttpResponseStatusCode__c,
                LimitsAggregateQueriesMax__c = logEntryEvent.LimitsAggregateQueriesMax__c,
                LimitsAggregateQueriesUsed__c = logEntryEvent.LimitsAggregateQueriesUsed__c,
                LimitsAsyncCallsMax__c = logEntryEvent.LimitsAsyncCallsMax__c,
                LimitsAsyncCallsUsed__c = logEntryEvent.LimitsAsyncCallsUsed__c,
                LimitsCalloutsMax__c = logEntryEvent.LimitsCalloutsMax__c,
                LimitsCalloutsUsed__c = logEntryEvent.LimitsCalloutsUsed__c,
                LimitsCpuTimeMax__c = logEntryEvent.LimitsCpuTimeMax__c,
                LimitsCpuTimeUsed__c = logEntryEvent.LimitsCpuTimeUsed__c,
                LimitsDmlRowsMax__c = logEntryEvent.LimitsDmlRowsMax__c,
                LimitsDmlRowsUsed__c = logEntryEvent.LimitsDmlRowsUsed__c,
                LimitsDmlStatementsMax__c = logEntryEvent.LimitsDmlStatementsMax__c,
                LimitsDmlStatementsUsed__c = logEntryEvent.LimitsDmlStatementsUsed__c,
                LimitsEmailInvocationsMax__c = logEntryEvent.LimitsEmailInvocationsMax__c,
                LimitsEmailInvocationsUsed__c = logEntryEvent.LimitsEmailInvocationsUsed__c,
                LimitsFutureCallsMax__c = logEntryEvent.LimitsFutureCallsMax__c,
                LimitsFutureCallsUsed__c = logEntryEvent.LimitsFutureCallsUsed__c,
                LimitsHeapSizeMax__c = logEntryEvent.LimitsHeapSizeMax__c,
                LimitsHeapSizeUsed__c = logEntryEvent.LimitsHeapSizeUsed__c,
                LimitsMobilePushApexCallsMax__c = logEntryEvent.LimitsMobilePushApexCallsMax__c,
                LimitsMobilePushApexCallsUsed__c = logEntryEvent.LimitsMobilePushApexCallsUsed__c,
                LimitsPublishImmediateDmlStatementsMax__c = logEntryEvent.LimitsPublishImmediateDmlStatementsMax__c,
                LimitsPublishImmediateDmlStatementsUsed__c = logEntryEvent.LimitsPublishImmediateDmlStatementsUsed__c,
                LimitsQueueableJobsMax__c = logEntryEvent.LimitsQueueableJobsMax__c,
                LimitsQueueableJobsUsed__c = logEntryEvent.LimitsQueueableJobsUsed__c,
                LimitsSoqlQueriesMax__c = logEntryEvent.LimitsSoqlQueriesMax__c,
                LimitsSoqlQueriesUsed__c = logEntryEvent.LimitsSoqlQueriesUsed__c,
                LimitsSoqlQueryLocatorRowsMax__c = logEntryEvent.LimitsSoqlQueryLocatorRowsMax__c,
                LimitsSoqlQueryLocatorRowsUsed__c = logEntryEvent.LimitsSoqlQueryLocatorRowsUsed__c,
                LimitsSoqlQueryRowsMax__c = logEntryEvent.LimitsSoqlQueryRowsMax__c,
                LimitsSoqlQueryRowsUsed__c = logEntryEvent.LimitsSoqlQueryRowsUsed__c,
                LimitsSoslSearchesMax__c = logEntryEvent.LimitsSoslSearchesMax__c,
                LimitsSoslSearchesUsed__c = logEntryEvent.LimitsSoslSearchesUsed__c,
                Log__c = TRANSACTION_ID_TO_LOG.get(logEntryEvent.TransactionId__c).Id,
                LoggingLevel__c = logEntryEvent.LoggingLevel__c,
                LoggingLevelOrdinal__c = logEntryEvent.LoggingLevelOrdinal__c,
                Message__c = logEntryEvent.Message__c,
                MessageMasked__c = logEntryEvent.MessageMasked__c,
                MessageTruncated__c = logEntryEvent.MessageTruncated__c,
                Name = null, // Salesforce will auto-set the record ID as the name when null
                OriginLocation__c = logEntryEvent.OriginLocation__c,
                OriginType__c = logEntryEvent.OriginType__c,
                RecordCollectionSize__c = logEntryEvent.RecordCollectionSize__c,
                RecordCollectionType__c = logEntryEvent.RecordCollectionType__c,
                RecordId__c = logEntryEvent.RecordId__c,
                RecordJson__c = logEntryEvent.RecordJson__c,
                RecordJsonMasked__c = logEntryEvent.RecordJsonMasked__c,
                RecordSObjectClassification__c = logEntryEvent.RecordSObjectClassification__c,
                RecordSObjectType__c = logEntryEvent.RecordSObjectType__c,
                RecordSObjectTypeNamespace__c = logEntryEvent.RecordSObjectTypeNamespace__c,
                StackTrace__c = logEntryEvent.StackTrace__c,
                Timestamp__c = timestamp,
                TransactionEntryNumber__c = logEntryEvent.TransactionEntryNumber__c,
                TriggerIsExecuting__c = logEntryEvent.TriggerIsExecuting__c,
                TriggerOperationType__c = logEntryEvent.TriggerOperationType__c,
                TriggerSObjectType__c = logEntryEvent.TriggerSObjectType__c
            );

            this.logEntries.add(logEntry);
            if (logEntryEvent.Tags__c != null) {
                List<String> logEntryTagNames = getTagNames(logEntryEvent.Tags__c);

                this.tagNames.addAll(logEntryTagNames);
                this.logEntryEventUuidToTagNames.put(logEntry.EventUuid__c, logEntryTagNames);
            }
        }

        List<Database.SaveResult> saveResults = LoggerDataStore.getDatabase().insertRecords(this.logEntries, DML_OPTIONS);
        LoggerEmailSender.sendErrorEmail(Schema.LogEntry__c.SObjectType, saveResults);
    }

    private void appendRuleBasedTags() {
        if (LoggerParameter.TAGGING_IS_ENABLED == false || TAG_ASSIGNMENT_RULES.isEmpty() == true) {
            return;
        }

        for (LogEntry__c logEntry : this.logEntries) {
            for (LogEntryTagRule__mdt rule : TAG_ASSIGNMENT_RULES) {
                Boolean ruleCriteriaMet = ruleCriteriaMet(logEntry, rule);

                if (ruleCriteriaMet == true) {
                    List<String> configuredTagNames = getTagNames(rule.Tags__c);
                    this.tagNames.addAll(configuredTagNames);
                    List<String> logEntryTags = logEntryEventUuidToTagNames.get(logEntry.EventUuid__c);
                    if (logEntryTags == null) {
                        logEntryTags = new List<String>();
                    }
                    logEntryTags.addAll(configuredTagNames);

                    this.logEntryEventUuidToTagNames.put(logEntry.EventUuid__c, logEntryTags);
                    this.tagNames.addAll(logEntryTags);
                }
            }
        }
    }

    private void insertLogEntryTags() {
        if (LoggerParameter.TAGGING_IS_ENABLED == false || this.tagNames.isEmpty()) {
            return;
        }

        // Orgs can be configured to either use LoggerTag__c & LogEntryTag__c (default), or use Topic & TopicAssignment
        Schema.SObjectType tagSObjectType = LoggerParameter.TAG_USING_TOPICS == true ? Topic.SObjectType : LoggerTag__c.SObjectType;
        Map<String, Id> tagNameToId = getTagNameToId(tagSObjectType);
        this.tagNames.addAll(tagNameToId.keySet());

        // Assign the tags to the records
        Schema.SObjectType tagAssignmentSObjectType;
        Set<SObject> tagAssignments = new Set<SObject>();
        for (LogEntry__c logEntry : this.logEntries) {
            List<String> logEntryTagNames = this.logEntryEventUuidToTagNames.get(logEntry.EventUuid__c);
            if (logEntryTagNames == null || logEntryEventUuidToTagNames.isEmpty()) {
                continue;
            }

            for (String tagName : logEntryTagNames) {
                if (LoggerParameter.TAG_USING_TOPICS == true) {
                    // Add the topic for the LogEntry__c & the parent Log__c
                    tagAssignmentSObjectType = Schema.TopicAssignment.SObjectType;
                    tagAssignments.add(new TopicAssignment(EntityId = logEntry.Id, TopicId = tagNameToId.get(tagName)));
                    tagAssignments.add(new TopicAssignment(EntityId = logEntry.Log__c, TopicId = tagNameToId.get(tagName)));
                } else {
                    // Add a LogEntryTag__c record that links to the LogEntry__c - the handler class will also related it to the parent Log__c
                    tagAssignmentSObjectType = Schema.LogEntryTag__c.SObjectType;
                    tagAssignments.add(new LogEntryTag__c(LogEntry__c = logEntry.Id, Tag__c = tagNameToId.get(tagName)));
                }
            }
        }

        List<Database.SaveResult> saveResults = LoggerDataStore.getDatabase().insertRecords(new List<SObject>(tagAssignments), DML_OPTIONS);
        LoggerEmailSender.sendErrorEmail(tagAssignmentSObjectType, saveResults);
    }

    private Map<String, Id> getTagNameToId(Schema.SObjectType tagSObjectType) {
        Map<String, Id> tagNameToId = new Map<String, Id>();

        String tagQuery = 'SELECT Id, Name FROM ' + tagSObjectType + ' WHERE Name IN :tagNames';
        for (SObject tag : Database.query(String.escapeSingleQuotes(tagQuery))) {
            tagNameToId.put((String) tag.get('Name'), (Id) tag.get('Id'));
        }
        tagNameToId.putAll(this.insertMissingTags(tagSObjectType, tagNameToId));

        return tagNameToId;
    }

    private Map<String, Id> insertMissingTags(Schema.SObjectType tagSObjectType, Map<String, Id> existingTagNameToId) {
        Map<String, Id> missingTagNameToId = new Map<String, Id>();

        List<SObject> missingTagsToCreate = new List<SObject>();
        for (String tagName : this.tagNames) {
            if (existingTagNameToId.containsKey(tagName) == false) {
                SObject tag = tagSObjectType.newSObject();
                tag.put('Name', tagName);
                missingTagsToCreate.add(tag);
            }
        }

        if (!missingTagsToCreate.isEmpty()) {
            List<Database.SaveResult> saveResults = LoggerDataStore.getDatabase().insertRecords(missingTagsToCreate, DML_OPTIONS);
            LoggerEmailSender.sendErrorEmail(tagSObjectType, saveResults);
            for (SObject tag : missingTagsToCreate) {
                missingTagNameToId.put((String) tag.get('Name'), (Id) tag.get('Id'));
            }
        }

        return missingTagNameToId;
    }

    // Private static methods
    private static Database.DmlOptions createDmlOptions() {
        Database.DmlOptions dmlOptions = new Database.DmlOptions();
        dmlOptions.AllowFieldTruncation = true;
        dmlOptions.OptAllOrNone = System.Test.isRunningTest();
        return dmlOptions;
    }

    private static List<String> getTagNames(String tagsString) {
        List<String> cleanedTagNames = new List<String>();

        for (String tagName : tagsString.split('\n')) {
            if (String.isNotBlank(tagName) == true) {
                cleanedTagNames.add(tagName.trim());
            }
        }

        return cleanedTagNames;
    }

    private static List<LogEntryTagRule__mdt> getTagAssignmentRules() {
        List<LogEntryTagRule__mdt> tagAssignmentRules = [
            SELECT Id, SObjectField__r.QualifiedApiName, ComparisonType__c, ComparisonValue__c, Tags__c
            FROM LogEntryTagRule__mdt
            WHERE IsEnabled__c = TRUE AND SObjectType__r.DeveloperName = 'LogEntry'
        ];
        for (LogEntryTagRule__mdt rule : tagAssignmentRules) {
            rule.SObjectField__c = rule.SObjectField__r.QualifiedApiName;
        }
        if (System.Test.isRunningTest() == true) {
            // During tests, only use mock records - tests can add mock records using LogEntryEventHandler.TAG_ASSIGNMENT_RULES.add()
            tagAssignmentRules.clear();
        }
        return tagAssignmentRules;
    }

    private static Boolean ruleCriteriaMet(LogEntry__c logEntry, LogEntryTagRule__mdt rule) {
        Boolean ruleCriteriaMet = false;
        String logEntryFieldValue = String.valueOf(logEntry.get(rule.SObjectField__c));
        String ruleComparisonValue = rule.ComparisonValue__c;

        switch on rule?.ComparisonType__c.toUpperCase() {
            when 'CONTAINS' {
                ruleCriteriaMet = logEntryFieldValue.containsIgnoreCase(ruleComparisonValue);
            }
            when 'EQUALS' {
                ruleCriteriaMet = logEntryFieldValue == ruleComparisonValue;
            }
            when 'MATCHES_REGEX' {
                ruleCriteriaMet = Pattern.compile(ruleComparisonValue).matcher(logEntryFieldValue).matches();
            }
            when 'STARTS_WITH' {
                ruleCriteriaMet = logEntryFieldValue.startsWith(ruleComparisonValue);
            }
        }

        return ruleCriteriaMet;
    }

    private static Log__c getRecentLogWithApiReleaseDetails() {
        // Query for recent logs created only today - the status API should be called
        // at least once per day to make sure that status details are still accurate.
        // This query should make a callout approximately every 4 hours.
        Datetime fourHoursAgo = System.now().addMinutes(-4 * 60);

        List<Log__c> logs = [
            SELECT Id, ApiReleaseNumber__c, ApiReleaseVersion__c
            FROM Log__c
            WHERE CreatedDate >= :fourHoursAgo AND CreatedDate = TODAY AND ApiReleaseNumber__c != NULL
            ORDER BY StartTime__c DESC
            LIMIT 1
        ];

        if (logs.isEmpty()) {
            return null;
        } else {
            return logs.get(0);
        }
    }

    private static Integer getCountOfOpenJobs() {
        return [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE
                ApexClass.Name = :LogEntryEventHandler.class.getName()
                AND MethodName = 'setStatusApiDetails'
                AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
        ];
    }

    @future(callout=true)
    private static void setStatusApiDetails() {
        if (LoggerParameter.ENABLE_SYSTEM_MESSAGES == true) {
            Logger.debug('Logger - Calling Status API for org details');
        }

        Organization organization = [SELECT InstanceName FROM Organization];
        String statusApiEndpoint = 'https://api.status.salesforce.com/v1/instances/' + organization.InstanceName + '/status';

        HttpRequest request = new HttpRequest();
        request.setEndpoint(statusApiEndpoint);
        request.setMethod('GET');

        HttpResponse response = new Http().send(request);

        if (response.getStatusCode() >= 400) {
            String errorMessage =
                'Callout failed for ' +
                statusApiEndpoint +
                '\nReceived request status code ' +
                response.getStatusCode() +
                ', status message: ' +
                response.getStatus();
            throw new CalloutException(errorMessage);
        }

        StatusApiResponse statusApiResponse = (StatusApiResponse) JSON.deserialize(response.getBody(), StatusApiResponse.class);
        if (LoggerParameter.ENABLE_SYSTEM_MESSAGES == true) {
            Logger.debug('Logger - Status API response: ' + statusApiResponse);
        }

        List<Log__c> logsToUpdate = new List<Log__c>();
        for (Log__c log : [
            SELECT Id
            FROM Log__c
            WHERE CreatedDate = TODAY AND ApiReleaseNumber__c = NULL
            ORDER BY CreatedDate
            LIMIT :Limits.getLimitDmlRows()
        ]) {
            log.ApiReleaseNumber__c = statusApiResponse.releaseNumber;
            log.ApiReleaseVersion__c = statusApiResponse.releaseVersion;

            logsToUpdate.add(log);
        }

        if (LoggerParameter.ENABLE_SYSTEM_MESSAGES == true) {
            Logger.debug('Logger - logs to update: ' + logsToUpdate);
        }

        LoggerDataStore.getDatabase().updateRecords(logsToUpdate);
        Logger.saveLog();
    }

    // Private class for handling the response from api.status.salesforce.com
    @TestVisible
    private class StatusApiResponse {
        /**
         * @description String containing the release number.
         */
        public String releaseNumber { get; set; }

        /**
         * @description String containing the release version.
         */
        public String releaseVersion { get; set; }
    }
}
