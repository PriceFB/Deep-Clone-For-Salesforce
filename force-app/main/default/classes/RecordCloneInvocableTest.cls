/**
 * Tests for RecordCloneInvocable happy, empty, and error paths.
 */
@isTest
private class RecordCloneInvocableTest {
  @TestSetup
  static void setup() {
    List<Account> accounts = TestDataFactory.createAccounts(1, true);
    TestDataFactory.createContacts(1, accounts, true);
  }

  @isTest
  static void shouldCloneRecords_WhenValidRequests() {
    TestDataFactory.applyStandardConfig();
    Account account = [SELECT Id FROM Account LIMIT 1];
    RecordCloneInvocable.CloneRequest request = new RecordCloneInvocable.CloneRequest();
    request.recordId = account.Id;

    Test.startTest();
    List<RecordCloneInvocable.CloneResult> results = RecordCloneInvocable.cloneRecords(
      new List<RecordCloneInvocable.CloneRequest>{ request }
    );
    Test.stopTest();

    Assert.areEqual(1, results.size(), 'One result per request is expected');
    Assert.isTrue(results[0].isSuccess, 'The clone should succeed');
    Assert.isNotNull(
      results[0].clonedRecordId,
      'A cloned record id should be returned'
    );
  }

  @isTest
  static void shouldReturnEmpty_WhenNoRequests() {
    Test.startTest();
    List<RecordCloneInvocable.CloneResult> results = RecordCloneInvocable.cloneRecords(
      new List<RecordCloneInvocable.CloneRequest>()
    );
    Test.stopTest();

    Assert.areEqual(0, results.size(), 'No requests should yield no results');
  }

  @isTest
  static void shouldReturnError_WhenNullRecordId() {
    RecordCloneInvocable.CloneRequest request = new RecordCloneInvocable.CloneRequest();
    request.recordId = null;

    Test.startTest();
    List<RecordCloneInvocable.CloneResult> results = RecordCloneInvocable.cloneRecords(
      new List<RecordCloneInvocable.CloneRequest>{ request }
    );
    Test.stopTest();

    Assert.areEqual(1, results.size(), 'One result per request is expected');
    Assert.isFalse(results[0].isSuccess, 'A null record id should not succeed');
    Assert.isNotNull(
      results[0].errorMessage,
      'An error message should be populated'
    );
  }
}
