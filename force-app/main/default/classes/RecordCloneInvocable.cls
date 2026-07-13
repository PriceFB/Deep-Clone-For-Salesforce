/**
 * Flow-invocable entry point for Deep Clone for Salesforce.
 *
 * Bulkified: all incoming record Ids are cloned in a single service call, then
 * results are mapped back to each request. Errors are returned on the response
 * (rather than thrown) so a Flow can branch on failure without hitting the
 * fault path for every record.
 */
public with sharing class RecordCloneInvocable {
  /** A single deep-clone request. */
  public class CloneRequest {
    @InvocableVariable(
      label='Record Id'
      description='Id of the record to deep clone.'
      required=true
    )
    public Id recordId;
  }

  /** The outcome of a single deep-clone request. */
  public class CloneResult {
    @InvocableVariable(
      label='Cloned Record Id'
      description='Id of the newly created clone.'
    )
    public Id clonedRecordId;

    @InvocableVariable(
      label='Is Success'
      description='True when the record was cloned successfully.'
    )
    public Boolean isSuccess;

    @InvocableVariable(
      label='Error Message'
      description='Populated when the clone fails.'
    )
    public String errorMessage;

    @InvocableVariable(
      label='Error Type'
      description='Apex type name of the failure.'
    )
    public String errorType;
  }

  /**
   * Clones each requested record and its configured related records.
   *
   * @param requests One CloneRequest per record to clone.
   * @return One CloneResult per request, in the same order.
   */
  @InvocableMethod(
    label='Deep Clone Record'
    description='Clones a record and its configured related records (Deep Clone for Salesforce).'
    category='Deep Clone'
  )
  public static List<CloneResult> cloneRecords(List<CloneRequest> requests) {
    List<CloneResult> results = new List<CloneResult>();
    if (requests == null || requests.isEmpty()) {
      return results;
    }

    Set<Id> recordIds = new Set<Id>();
    for (CloneRequest request : requests) {
      if (request != null && request.recordId != null) {
        recordIds.add(request.recordId);
      }
    }

    try {
      Map<Id, Id> newIdByOriginalId = RecordCloneService.cloneRecordsMapped(
        recordIds
      );
      for (CloneRequest request : requests) {
        CloneResult result = new CloneResult();
        Id sourceId = request == null ? null : request.recordId;
        Id clonedId = sourceId == null ? null : newIdByOriginalId.get(sourceId);
        result.clonedRecordId = clonedId;
        result.isSuccess = clonedId != null;
        if (clonedId == null) {
          result.errorMessage = 'No clone was created for the provided record Id.';
          result.errorType = RecordCloneService.RecordCloneException.class
            .getName();
        }
        results.add(result);
      }
    } catch (Exception e) {
      for (Integer i = 0; i < requests.size(); i++) {
        CloneResult result = new CloneResult();
        result.isSuccess = false;
        result.errorMessage = e.getMessage();
        result.errorType = e.getTypeName();
        results.add(result);
      }
    }
    return results;
  }
}
