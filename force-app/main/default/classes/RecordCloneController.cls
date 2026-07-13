/**
 * Lightning controller for Deep Clone for Salesforce.
 *
 * Thin @AuraEnabled wrapper over RecordCloneService: it delegates all logic to
 * the service and translates errors into AuraHandledException so the LWC can
 * surface friendly messages.
 */
public with sharing class RecordCloneController {
  /**
   * Clones a record and any related records configured for its object.
   *
   * @param recordId Id of the record to clone.
   * @return Id of the newly created clone (for client-side navigation).
   */
  @AuraEnabled
  public static Id doClone(Id recordId) {
    try {
      return RecordCloneService.cloneRecord(recordId);
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  /**
   * Returns a summary of what the deep clone will do for an object, for the
   * confirmation UI.
   *
   * @param objectApiName API name of the object (for example, Account).
   * @return A CloneConfigView describing configured children and exclusions.
   */
  @AuraEnabled(cacheable=true)
  public static RecordCloneService.CloneConfigView getConfig(
    String objectApiName
  ) {
    try {
      return RecordCloneService.getConfigView(objectApiName);
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }
}
