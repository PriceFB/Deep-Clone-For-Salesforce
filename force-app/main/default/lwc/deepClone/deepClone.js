import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getConfig from "@salesforce/apex/RecordCloneController.getConfig";
import doClone from "@salesforce/apex/RecordCloneController.doClone";

export default class DeepClone extends NavigationMixin(LightningElement) {
  @api recordId;
  @api objectApiName;

  config;
  wireError;
  isCloning = false;

  @wire(getConfig, { objectApiName: "$objectApiName" })
  wiredConfig({ data, error }) {
    if (data) {
      this.config = data;
      this.wireError = undefined;
    } else if (error) {
      this.config = undefined;
      this.wireError = this.reduceError(error);
    }
  }

  get isReady() {
    return this.config !== undefined || this.wireError !== undefined;
  }

  get deepCloneEnabled() {
    return !!(this.config && this.config.deepCloneEnabled);
  }

  get hasChildRelationships() {
    return !!(
      this.config &&
      this.config.childRelationshipNames &&
      this.config.childRelationshipNames.length > 0
    );
  }

  get childRelationshipList() {
    return this.hasChildRelationships
      ? this.config.childRelationshipNames.join(", ")
      : "";
  }

  get hasExcludedFields() {
    return !!(
      this.config &&
      this.config.excludedFields &&
      this.config.excludedFields.length > 0
    );
  }

  get excludedFieldList() {
    return this.hasExcludedFields ? this.config.excludedFields.join(", ") : "";
  }

  get hasNamePrefix() {
    return !!(this.config && this.config.namePrefix);
  }

  get summary() {
    if (!this.deepCloneEnabled) {
      return "This will create a copy of this record.";
    }
    if (this.hasChildRelationships) {
      return `This will clone this record and its related ${this.childRelationshipList}.`;
    }
    return "This will clone this record using its deep-clone configuration.";
  }

  async handleClone() {
    this.isCloning = true;
    try {
      const newRecordId = await doClone({ recordId: this.recordId });
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Record cloned",
          message: "The record and its configured related records were cloned.",
          variant: "success"
        })
      );
      if (newRecordId) {
        this[NavigationMixin.Navigate]({
          type: "standard__recordPage",
          attributes: {
            recordId: newRecordId,
            actionName: "view"
          }
        });
      }
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Clone failed",
          message: this.reduceError(error),
          variant: "error",
          mode: "sticky"
        })
      );
    } finally {
      this.isCloning = false;
    }
  }

  reduceError(error) {
    if (!error) {
      return "Unknown error";
    }
    if (Array.isArray(error.body)) {
      return error.body.map((e) => e.message).join(", ");
    }
    if (error.body && typeof error.body.message === "string") {
      return error.body.message;
    }
    if (typeof error.message === "string") {
      return error.message;
    }
    return "Unknown error";
  }
}
