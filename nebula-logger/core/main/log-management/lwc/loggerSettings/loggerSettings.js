/*************************************************************************************************
 * This file is part of the Nebula Logger project, released under the MIT License.               *
 * See LICENSE file or go to https://github.com/jongpie/NebulaLogger for full license details.   *
 ************************************************************************************************/

// UI
import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// LoggerSettings__c metadata
import LOGGER_SETTINGS_SCHEMA from './loggerSettingsSchema';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import canUserModifyLoggerSettings from '@salesforce/apex/LoggerSettingsController.canUserModifyLoggerSettings';
import getPicklistOptions from '@salesforce/apex/LoggerSettingsController.getPicklistOptions';
import getOrganization from '@salesforce/apex/LoggerSettingsController.getOrganization';
import searchForSetupOwner from '@salesforce/apex/LoggerSettingsController.searchForSetupOwner';

// LoggerSettings__c data
import getRecords from '@salesforce/apex/LoggerSettingsController.getRecords';
import createRecord from '@salesforce/apex/LoggerSettingsController.createRecord';
import saveRecord from '@salesforce/apex/LoggerSettingsController.saveRecord';
import deleteRecord from '@salesforce/apex/LoggerSettingsController.deleteRecord';

export default class LoggerSettings extends LightningElement {
    // UI
    title = 'Logger Settings';
    columns;
    isReadOnlyMode = true;
    showLoadingSpinner = false;
    showRecordModal = false;
    showDeleteModal = false;
    isNewOrganizationRecord = false;
    showSetupOwnerLookup = false;
    showSetupOwnerDropdown = false;
    setupOwnerSearchTerm;
    setupOwnerSearchResults;
    showDropdown = false;
    showPill = false;

    // LoggerSettings__c metadata
    canUserModifyLoggerSettings;
    loggerSettingsPicklistOptions;
    _loggerSettingsFields;

    // LoggerSettings__c data
    records;
    selectedSetupOwner;
    _currentRecord;

    connectedCallback() {
        document.title = this.title;
        this.showLoadingSpinner = true;

        Promise.all([getOrganization(), getPicklistOptions()])
            .then(([organization, loggerSettingsPicklistOptions]) => {
                this.organization = organization;
                this.loggerSettingsPicklistOptions = loggerSettingsPicklistOptions;
            })
            .catch(this._handleError);

        this.loadSettingsRecords();
        this.showLoadingSpinner = false;
    }

    @wire(getObjectInfo, { objectApiName: LOGGER_SETTINGS_SCHEMA.sobject })
    getLoggerSettingsObjectInfo({ data }) {
        if (data) {
            this._loggerSettingsFields = data.fields;
            canUserModifyLoggerSettings().then(result => {
                this.canUserModifyLoggerSettings = result;
                this._loadTableColumns();
            });
        }
    }

    loadSettingsRecords() {
        this.showLoadingSpinner = true;
        getRecords()
            .then(settingsRecords => {
                for (let i = 0; i < settingsRecords.length; i++) {
                    const record = { ...settingsRecords[i], ...settingsRecords[i].record };
                    settingsRecords[i] = record;
                }
                this.records = settingsRecords;
                this._currentRecord = null;
                this.setupOwnerSearchTerm = null;
                this.showSetupOwnerLookup = false;
                this.setupOwnerSearchResults = null;
                this.selectedSetupOwner = null;
                this.showDropdown = false;
                this.showPill = false;

                this.closeRecordModal();
                this.closeDeleteModal();
                this.showLoadingSpinner = false;
            })
            .catch(this._handleError);
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        /* eslint-disable-next-line default-case */
        switch (actionName) {
            case 'view':
                this.viewCurrentRecord(row);
                break;
            case 'edit':
                this.editCurrentRecord(row);
                break;
            case 'delete':
                this.deleteCurrentRecord(row);
                break;
        }
    }

    handleSetupOwnerTypeFieldChange(event) {
        this.selectedSetupOwner = null;
        this.showPill = false;
        this.handleFieldChange(event);
    }

    handleFieldChange(event) {
        let value;
        if (event.target.type === 'checkbox' || event.target.type === 'checkbox-button' || event.target.type === 'toggle') {
            value = event.target.checked;
        } else {
            value = event.target.value;
        }
        this._currentRecord[event.target.dataset.id] = value;

        this._setIsNewOrganizationRecord();
        this._setShowSetupOwnerLookup();
    }

    handleRecordSearch(event) {
        this.showDropdown = false;
        this.setupOwnerSearchTerm = event.detail.value;
        if (this.setupOwnerSearchTerm && this.setupOwnerSearchTerm.length >= 2) {
            searchForSetupOwner({
                setupOwnerType: this._currentRecord.setupOwnerType,
                searchTerm: this.setupOwnerSearchTerm
            })
                .then(results => {
                    this.setupOwnerSearchResults = results;
                    this.showDropdown = true;
                })
                .catch(this._handleError);
        }
    }

    handleRecordSearchBlur() {
        this.showDropdown = false;
    }

    handleSearchResultSelection(event) {
        if (event.currentTarget.dataset.key) {
            this._currentRecord.SetupOwnerId = event.currentTarget.dataset.key;
            this._currentRecord.setupOwnerName = event.currentTarget.dataset.label;

            let index = this.setupOwnerSearchResults.findIndex(x => x.recordId === event.currentTarget.dataset.key);
            if (index !== -1) {
                this.selectedSetupOwner = this.setupOwnerSearchResults[index];
                this.showDropdown = false;
                this.showPill = true;
            }
        }
    }

    handleRemoveSetupOwner() {
        this.showPill = false;
        this.selectedSetupOwner = '';
        this.setupOwnerSearchTerm = '';
    }

    handleKeyDown(event) {
        if (event.code === 'Escape') {
            this.closeRecordModal();
            this.closeDeleteModal();
        } else if (event.ctrlKey === true && event.code === 'KeyS') {
            this.saveCurrentRecord();
        }
    }

    closeRecordModal() {
        this.showRecordModal = false;
    }

    closeDeleteModal() {
        this.showDeleteModal = false;
    }

    get isExistingRecord() {
        let isExistingRecord = false;
        if (this._currentRecord.Id) {
            isExistingRecord = true;
        }
        return isExistingRecord;
    }

    // Getters for each LoggerSettings__c field describes & data - these handle dealing with using a namespace for the package
    get createdByIdField() {
        return this._loadField(LOGGER_SETTINGS_SCHEMA.fields.CreatedById, 'createdByUsername');
    }
    get createdDateField() {
        return this._loadField(LOGGER_SETTINGS_SCHEMA.fields.CreatedDate);
    }

    get defaultLogShareAccessLevelField() {
        return this._loadField(LOGGER_SETTINGS_SCHEMA.fields.DefaultLogShareAccessLevel__c);
    }

    get defaultNumberOfDaysToRetainLogsField() {
        return this._loadField(LOGGER_SETTINGS_SCHEMA.fields.DefaultNumberOfDaysToRetainLogs__c);
    }

    get defaultSaveMethodField() {
        return this._loadField(LOGGER_SETTINGS_SCHEMA.fields.DefaultSaveMethod__c);
    }

    get isAnonymousModeEnabledField() {
        return this._loadField(LOGGER_SETTINGS_SCHEMA.fields.IsAnonymousModeEnabled__c);
    }

    get isApexSystemDebugLoggingEnabledField() {
        return this._loadField(LOGGER_SETTINGS_SCHEMA.fields.IsApexSystemDebugLoggingEnabled__c);
    }

    get isDataMaskingEnabledField() {
        return this._loadField(LOGGER_SETTINGS_SCHEMA.fields.IsDataMaskingEnabled__c);
    }

    get isEnabledField() {
        return this._loadField(LOGGER_SETTINGS_SCHEMA.fields.IsEnabled__c);
    }

    get isJavaScriptConsoleLoggingEnabledField() {
        return this._loadField(LOGGER_SETTINGS_SCHEMA.fields.IsJavaScriptConsoleLoggingEnabled__c);
    }

    get lastModifiedByIdField() {
        return this._loadField(LOGGER_SETTINGS_SCHEMA.fields.LastModifiedById, 'lastModifiedByUsername');
    }

    get lastModifiedDateField() {
        return this._loadField(LOGGER_SETTINGS_SCHEMA.fields.LastModifiedDate);
    }

    get loggingLevelField() {
        return this._loadField(LOGGER_SETTINGS_SCHEMA.fields.LoggingLevel__c);
    }

    get setupOwnerNameField() {
        return this._loadField('setupOwnerName', 'setupOwnerName', 'Setup Owner');
    }

    get setupOwnerTypeField() {
        return this._loadField('setupOwnerType', 'setupOwnerType', 'Setup Location');
    }

    get stripInaccessibleRecordFieldsField() {
        return this._loadField(LOGGER_SETTINGS_SCHEMA.fields.StripInaccessibleRecordFields__c);
    }

    createNewRecord() {
        createRecord()
            .then(result => {
                this._currentRecord = result;
                this.selectedSetupOwner = null;
                this.isNewOrganizationRecord = false;
                this.isReadOnlyMode = false;
                this.showPill = false;
                this.showRecordModal = true;
                this.showSetupOwnerLookup = false;
            })
            .catch(this._handleError);
    }

    viewCurrentRecord(currentRow) {
        this._currentRecord = currentRow;
        this.isReadOnlyMode = true;
        this.showRecordModal = true;
    }

    editCurrentRecord(currentRow) {
        this._currentRecord = currentRow;
        this.isReadOnlyMode = false;
        this.showRecordModal = true;
    }

    saveCurrentRecord() {
        const inputsAreValid = [...this.template.querySelectorAll('lightning-input, lightning-combobox')].reduce((validSoFar, inputField) => {
            inputField.reportValidity();
            return validSoFar && inputField.checkValidity();
        }, true);

        if (inputsAreValid === false) {
            return;
        }

        this.showLoadingSpinner = true;

        saveRecord({ settingsRecord: this._currentRecord })
            .then(() => {
                this.loadSettingsRecords();
                const setupOwnerName = this.selectedSetupOwner ? this.selectedSetupOwner.label : this._currentRecord.setupOwnerName;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: this.title + ' record for ' + setupOwnerName + ' successfully saved',
                        variant: 'success'
                    })
                );
                this.closeRecordModal();
                this.showLoadingSpinner = false;
            })
            .catch(this._handleError);
    }

    deleteCurrentRecord(currentRow) {
        this.showDeleteModal = true;
        this._currentRecord = currentRow;
    }

    confirmDeleteCurrentRecord() {
        this.showLoadingSpinner = true;
        const setupOwnerName = this._currentRecord.setupOwnerName;
        deleteRecord({ settingsRecord: this._currentRecord })
            .then(() => {
                this.loadSettingsRecords();
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: this.title + ' record for ' + setupOwnerName + ' successfully deleted',
                        variant: 'success'
                    })
                );
                this.showLoadingSpinner = false;
            })
            .catch(this._handleError);
    }

    // Private functions
    _loadTableColumns() {
        // The columns setupOwnerType and setupOwnerName are not true fields
        // They're flattened versions of SetupOwner.Type and SetupOwner.Name, so object API info isn't used here
        this.columns = [
            { fieldName: 'setupOwnerType', label: 'Setup Location', type: 'text' },
            { fieldName: 'setupOwnerName', label: 'Setup Owner', type: 'text' }
        ];

        // For all other fields, use object API info to dynamically get field details
        // TODO - make this array configurable by storing in LoggerParameter__mdt
        const tableColumnNames = [
            LOGGER_SETTINGS_SCHEMA.fields.IsEnabled__c,
            LOGGER_SETTINGS_SCHEMA.fields.LoggingLevel__c,
            LOGGER_SETTINGS_SCHEMA.fields.IsDataMaskingEnabled__c,
            LOGGER_SETTINGS_SCHEMA.fields.DefaultSaveMethod__c,
            LOGGER_SETTINGS_SCHEMA.fields.DefaultNumberOfDaysToRetainLogs__c,
            LOGGER_SETTINGS_SCHEMA.fields.DefaultLogShareAccessLevel__c
        ];
        for (let i = 0; i < tableColumnNames.length; i++) {
            const field = this._loggerSettingsFields[tableColumnNames[i]];
            const column = {
                fieldName: field.apiName,
                label: field.label,
                type: field.dataType?.toLowerCase()
            };
            if (column.type === 'string') {
                column.type = 'text';
            }
            this.columns.push(column);
        }

        // Finally, add the row-level actions
        let tableRowActions = [{ label: 'View', name: 'view' }];
        if (this.canUserModifyLoggerSettings === true) {
            tableRowActions = tableRowActions.concat([
                { label: 'Edit', name: 'edit' },
                { label: 'Delete', name: 'delete' }
            ]);
        }
        this.columns.push({
            type: 'action',
            typeAttributes: {
                rowActions: tableRowActions,
                menuAlignment: 'auto'
            }
        });
    }

    _loadField(fieldApiName, recordFieldApiName, recordFieldLabel) {
        if (!recordFieldApiName) {
            recordFieldApiName = fieldApiName;
        }

        let fieldDescribe;
        if (fieldApiName && this._loggerSettingsFields[fieldApiName]) {
            fieldDescribe = { ...this._loggerSettingsFields[fieldApiName] };
        } else {
            fieldDescribe = { apiName: fieldApiName };
        }

        if (this._currentRecord) {
            fieldDescribe.value = this._currentRecord[recordFieldApiName];
        }

        if (recordFieldLabel) {
            fieldDescribe.label = recordFieldLabel;
        }

        return fieldDescribe;
    }

    _setIsNewOrganizationRecord() {
        console.warn('checking _setIsNewOrganizationRecord', this._currentRecord);
        this.isNewOrganizationRecord = this.isExistingRecord === false && this._currentRecord?.setupOwnerType === 'Organization';
        if (this.isNewOrganizationRecord === true) {
            this._currentRecord.SetupOwnerId = this.organization.Id;
            this._currentRecord.setupOwnerName = this.organization.Name;
        }
        console.warn('checking _setIsNewOrganizationRecord again', this._currentRecord);
    }

    _setShowSetupOwnerLookup() {
        this.showSetupOwnerLookup = this.isExistingRecord === false && this._currentRecord?.setupOwnerType !== 'Organization';
    }

    _handleError = error => {
        const errorMessage = error.body ? error.body.message : error.message;
        /* eslint-disable-next-line no-console */
        console.error(errorMessage, error);
        this.dispatchEvent(
            new ShowToastEvent({
                mode: 'sticky',
                title: errorMessage,
                variant: 'error'
            })
        );
        this.showLoadingSpinner = false;
    };
}
