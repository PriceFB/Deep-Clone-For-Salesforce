/**
 * Tests for RecordCloneService. Relies on the shipped sample Clone_Config__mdt
 * (Account -> Contacts, excluding AccountNumber/Sic on the parent and Email on
 * the child, with a "Copy of " name prefix).
 */
@isTest
private class RecordCloneServiceTest {
  @TestSetup
  static void setup() {
    List<Account> accounts = TestDataFactory.createAccounts(1, true);
    TestDataFactory.createContacts(2, accounts, true);
  }

  @isTest
  static void shouldDeepCloneAccountWithContacts_WhenConfigured() {
    TestDataFactory.applyStandardConfig();
    Account original = [
      SELECT Id
      FROM Account
      WHERE Name = 'Test Account 0'
      LIMIT 1
    ];

    Test.startTest();
    Id newId = RecordCloneService.cloneRecord(original.Id);
    Test.stopTest();

    Assert.isNotNull(newId, 'A clone id should be returned');
    Account cloned = [
      SELECT Id, Name, Website, Phone, Description, Industry
      FROM Account
      WHERE Id = :newId
    ];
    Assert.areEqual(
      'Copy of Test Account 0',
      cloned.Name,
      'The name prefix should be applied'
    );
    Assert.isNull(
      cloned.Website,
      'Excluded field Website should not be copied'
    );
    Assert.isNull(cloned.Phone, 'Excluded field Phone should not be copied');
    Assert.areEqual(
      'Original description 0',
      cloned.Description,
      'Non-excluded fields should be copied'
    );
    Assert.areEqual(
      'Technology',
      cloned.Industry,
      'Non-excluded fields should be copied'
    );

    List<Contact> clonedContacts = [
      SELECT Id, LastName, Email
      FROM Contact
      WHERE AccountId = :newId
    ];
    Assert.areEqual(
      2,
      clonedContacts.size(),
      'Both child contacts should be cloned'
    );
    for (Contact clonedContact : clonedContacts) {
      Assert.isNull(
        clonedContact.Email,
        'Child excluded field Email should not be copied'
      );
    }
  }

  @isTest
  static void shouldCloneAllRecords_WhenBulk() {
    TestDataFactory.applyStandardConfig();
    List<Account> accounts = TestDataFactory.createAccounts(201, true);
    TestDataFactory.createContacts(1, accounts, true);
    Set<Id> accountIds = new Map<Id, Account>(accounts).keySet();

    Test.startTest();
    List<Id> newIds = RecordCloneService.cloneRecords(accountIds);
    Test.stopTest();

    Assert.areEqual(
      201,
      newIds.size(),
      'Every parent account should be cloned'
    );
    Integer clonedContactCount = [
      SELECT COUNT()
      FROM Contact
      WHERE AccountId IN :newIds
    ];
    Assert.areEqual(
      201,
      clonedContactCount,
      'Each cloned account should have its contact cloned'
    );
  }

  @isTest
  static void shouldCloneParentOnly_WhenNoConfig() {
    TestDataFactory.applyStandardConfig();
    Contact original = [SELECT Id, LastName, Email FROM Contact LIMIT 1];

    Test.startTest();
    Id newId = RecordCloneService.cloneRecord(original.Id);
    Test.stopTest();

    Assert.isNotNull(
      newId,
      'A clone should be created for an object without configuration'
    );
    Contact cloned = [
      SELECT Id, LastName, Email
      FROM Contact
      WHERE Id = :newId
    ];
    Assert.areEqual(
      original.LastName,
      cloned.LastName,
      'LastName should be copied'
    );
    Assert.areEqual(
      original.Email,
      cloned.Email,
      'With no config, no fields are excluded'
    );
  }

  @isTest
  static void shouldThrowException_WhenNullId() {
    Test.startTest();
    try {
      RecordCloneService.cloneRecord(null);
      Assert.fail('Expected a RecordCloneException for a null id');
    } catch (RecordCloneService.RecordCloneException e) {
      Assert.isTrue(
        e.getMessage().contains('required'),
        'Message should mention a required id'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void shouldReturnEmpty_WhenEmptyInput() {
    Test.startTest();
    List<Id> result = RecordCloneService.cloneRecords(new Set<Id>());
    Test.stopTest();

    Assert.areEqual(0, result.size(), 'Empty input should yield empty output');
  }

  @isTest
  static void shouldReturnEnabledView_WhenAccountConfigured() {
    TestDataFactory.applyStandardConfig();
    Test.startTest();
    RecordCloneService.CloneConfigView view = RecordCloneService.getConfigView(
      'Account'
    );
    Test.stopTest();

    Assert.isTrue(
      view.deepCloneEnabled,
      'Account should be deep-clone enabled'
    );
    Assert.isTrue(
      view.childRelationshipNames.contains('Contacts'),
      'Contacts should be listed as a child'
    );
    Assert.areEqual(
      'Copy of ',
      view.namePrefix,
      'The name prefix should match the config'
    );
    Assert.isTrue(
      view.excludedFields.contains('Website'),
      'Excluded fields should include Website'
    );
  }

  @isTest
  static void shouldReturnDisabledView_WhenNoConfig() {
    TestDataFactory.applyStandardConfig();
    Test.startTest();
    RecordCloneService.CloneConfigView view = RecordCloneService.getConfigView(
      'Lead'
    );
    Test.stopTest();

    Assert.isFalse(
      view.deepCloneEnabled,
      'Lead has no configuration and should be disabled'
    );
  }

  @isTest
  static void shouldReturnDisabledView_WhenBlankObject() {
    Test.startTest();
    RecordCloneService.CloneConfigView view = RecordCloneService.getConfigView(
      ''
    );
    Test.stopTest();

    Assert.isFalse(
      view.deepCloneEnabled,
      'A blank object name should yield a disabled view'
    );
  }

  @isTest
  static void shouldRespectFls_WhenRunAsStandardUser() {
    User standardUser = TestDataFactory.createStandardUser();
    TestDataFactory.applyStandardConfig();

    System.runAs(standardUser) {
      List<Account> accounts = TestDataFactory.createAccounts(1, true);
      TestDataFactory.createContacts(1, accounts, true);

      Test.startTest();
      Id newId = RecordCloneService.cloneRecord(accounts[0].Id);
      Test.stopTest();

      Assert.isNotNull(
        newId,
        'Clone should succeed in user mode for a user with access'
      );
      List<Contact> clonedContacts = [
        SELECT Id
        FROM Contact
        WHERE AccountId = :newId
      ];
      Assert.areEqual(
        1,
        clonedContacts.size(),
        'The child contact should be cloned under user mode'
      );
    }
  }
}
