/**
 * Shared test data builders for the Deep Clone for Salesforce test suite.
 * Uses only standard objects to keep the package generic and org-agnostic.
 */
@isTest
public class TestDataFactory {
  /**
   * Builds (and optionally inserts) Accounts with fields that exercise the
   * sample Clone_Config__mdt (AccountNumber and Sic are excluded there).
   *
   * @param count Number of accounts to build.
   * @param doInsert Whether to insert the records.
   * @return The built accounts.
   */
  public static List<Account> createAccounts(Integer count, Boolean doInsert) {
    List<Account> accounts = new List<Account>();
    for (Integer i = 0; i < count; i++) {
      accounts.add(
        new Account(
          Name = 'Test Account ' + i,
          // A full billing address keeps the data valid in orgs that
          // require one; harmless everywhere else.
          BillingStreet = '1 Market St',
          BillingCity = 'San Francisco',
          BillingState = 'CA',
          BillingPostalCode = '94105',
          BillingCountry = 'USA',
          Website = 'https://example.com/' + i,
          Phone = '4155550100',
          Industry = 'Technology',
          Description = 'Original description ' + i
        )
      );
    }
    if (doInsert) {
      insert accounts;
    }
    return accounts;
  }

  /**
   * Builds (and optionally inserts) contacts under each provided account.
   *
   * @param countPerAccount Contacts to create per account.
   * @param accounts Parent accounts.
   * @param doInsert Whether to insert the records.
   * @return The built contacts.
   */
  public static List<Contact> createContacts(
    Integer countPerAccount,
    List<Account> accounts,
    Boolean doInsert
  ) {
    List<Contact> contacts = new List<Contact>();
    for (Account account : accounts) {
      for (Integer i = 0; i < countPerAccount; i++) {
        contacts.add(
          new Contact(
            FirstName = 'Test',
            LastName = 'Contact ' + i,
            Email = 'contact' + i + '@example.com',
            AccountId = account.Id
          )
        );
      }
    }
    if (doInsert) {
      insert contacts;
    }
    return contacts;
  }

  /**
   * Injects the standard Account -> Contacts sample configuration into the
   * service under test, mirroring the shipped Clone_Config__mdt record so tests
   * do not depend on deployed custom metadata.
   */
  public static void applyStandardConfig() {
    RecordCloneService.configOverride = new List<Clone_Config__mdt>{
      new Clone_Config__mdt(
        Label = 'Account Deep Clone',
        Object_API_Name__c = 'Account',
        Child_Relationship_Names__c = 'Contacts',
        Excluded_Fields__c = 'Website,Phone',
        Child_Excluded_Fields__c = '{"Contacts":["Email"]}',
        Name_Prefix__c = 'Copy of ',
        Active__c = true
      )
    };
  }

  /**
   * Creates a Standard User for field-level-security tests.
   *
   * @return The inserted user.
   */
  public static User createStandardUser() {
    Profile standardProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];
    String unique =
      String.valueOf(DateTime.now().getTime()) +
      String.valueOf(Math.round(Math.random() * 100000));
    User user = new User(
      FirstName = 'Deep',
      LastName = 'CloneTester',
      Email = 'deep.clone.' + unique + '@example.com',
      Username = 'deep.clone.' + unique + '@example.com.rsc',
      Alias = 'dclone',
      TimeZoneSidKey = 'America/Los_Angeles',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = standardProfile.Id
    );
    insert user;
    return user;
  }
}
