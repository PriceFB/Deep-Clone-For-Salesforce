/**
 * Tests for RecordCloneController happy and error paths.
 */
@isTest
private class RecordCloneControllerTest {
  @TestSetup
  static void setup() {
    List<Account> accounts = TestDataFactory.createAccounts(1, true);
    TestDataFactory.createContacts(1, accounts, true);
  }

  @isTest
  static void shouldReturnClonedId_WhenDoClone() {
    TestDataFactory.applyStandardConfig();
    Account account = [SELECT Id FROM Account LIMIT 1];

    Test.startTest();
    Id newId = RecordCloneController.doClone(account.Id);
    Test.stopTest();

    Assert.isNotNull(newId, 'The controller should return the new record id');
  }

  @isTest
  static void shouldThrowAuraException_WhenNullId() {
    Test.startTest();
    try {
      RecordCloneController.doClone(null);
      Assert.fail('Expected an AuraHandledException for a null id');
    } catch (AuraHandledException e) {
      Assert.isNotNull(e, 'An AuraHandledException should be thrown');
    }
    Test.stopTest();
  }

  @isTest
  static void shouldReturnConfig_WhenGetConfig() {
    TestDataFactory.applyStandardConfig();
    Test.startTest();
    RecordCloneService.CloneConfigView view = RecordCloneController.getConfig(
      'Account'
    );
    Test.stopTest();

    Assert.isTrue(
      view.deepCloneEnabled,
      'Account should be reported as deep-clone enabled'
    );
  }
}
