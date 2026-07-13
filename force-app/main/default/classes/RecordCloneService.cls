/**
 * Deep Clone for Salesforce - core, configuration-driven clone engine.
 *
 * Clones a parent record and, optionally, its configured child records using
 * dynamic describe so that no per-object Apex is required. Which child
 * relationships to clone, which fields to skip, and an optional name prefix are
 * all driven by the Clone_Config__mdt custom metadata type.
 *
 * Field copying is field-level-security safe: only fields that are both
 * accessible and createable for the running user are read and written, and all
 * SOQL/DML runs in user mode.
 */
public with sharing class RecordCloneService {
  /** Thrown when a clone request cannot be completed. */
  public class RecordCloneException extends Exception {
  }

  /**
   * Serializable summary of what a deep clone will do for a given object.
   * Consumed by the Lightning confirmation UI and Flow.
   */
  public class CloneConfigView {
    @AuraEnabled
    public String objectApiName;
    @AuraEnabled
    public Boolean deepCloneEnabled;
    @AuraEnabled
    public List<String> childRelationshipNames;
    @AuraEnabled
    public List<String> excludedFields;
    @AuraEnabled
    public String namePrefix;
  }

  // Describe-derived, transaction-scoped caches to avoid redundant work.
  private static final Map<String, CopyableFields> COPYABLE_BY_TYPE = new Map<String, CopyableFields>();
  private static final Map<String, Clone_Config__mdt> CONFIG_BY_OBJECT = new Map<String, Clone_Config__mdt>();
  private static Boolean configIndexLoaded = false;

  // Test seam: when set, these configurations are used instead of the custom
  // metadata deployed in the org, so tests do not depend on org state.
  @TestVisible
  private static List<Clone_Config__mdt> configOverride;

  /**
   * Clones a single record and any related records configured for its object.
   *
   * @param recordId Id of the record to clone.
   * @return Id of the newly created clone, or null if nothing was cloned.
   * @throws RecordCloneException if recordId is null or the clone fails.
   * @example
   * Id newAccountId = RecordCloneService.cloneRecord(account.Id);
   */
  public static Id cloneRecord(Id recordId) {
    if (recordId == null) {
      throw new RecordCloneException('A record Id is required to clone.');
    }
    return cloneRecordsMapped(new Set<Id>{ recordId }).get(recordId);
  }

  /**
   * Bulk-safe deep clone for a set of records. The set may span multiple object
   * types; each type is resolved to its own Clone_Config__mdt configuration.
   *
   * @param recordIds Ids of the records to clone.
   * @return Ids of the newly created parent clones.
   * @throws RecordCloneException if the clone fails.
   */
  public static List<Id> cloneRecords(Set<Id> recordIds) {
    return new List<Id>(cloneRecordsMapped(recordIds).values());
  }

  /**
   * Bulk-safe deep clone that returns a map of each source record Id to its new
   * clone Id, so callers can correlate inputs to outputs (used by the Flow
   * invocable).
   *
   * @param recordIds Ids of the records to clone.
   * @return Map of original record Id to newly created clone Id.
   * @throws RecordCloneException if the clone fails.
   */
  public static Map<Id, Id> cloneRecordsMapped(Set<Id> recordIds) {
    Map<Id, Id> newIdByOriginalId = new Map<Id, Id>();
    if (recordIds == null || recordIds.isEmpty()) {
      return newIdByOriginalId;
    }
    Map<SObjectType, Set<Id>> idsByType = groupByType(recordIds);
    for (SObjectType sObjType : idsByType.keySet()) {
      newIdByOriginalId.putAll(cloneForType(sObjType, idsByType.get(sObjType)));
    }
    return newIdByOriginalId;
  }

  /**
   * Returns a summary of the deep-clone behavior configured for an object,
   * for use in confirmation UIs. Never throws for an unknown object; instead
   * returns a view with deepCloneEnabled = false.
   *
   * @param objectApiName API name of the object (for example, Account).
   * @return A CloneConfigView describing configured children and exclusions.
   */
  public static CloneConfigView getConfigView(String objectApiName) {
    CloneConfigView view = new CloneConfigView();
    view.objectApiName = objectApiName;
    view.childRelationshipNames = new List<String>();
    view.excludedFields = new List<String>();
    view.deepCloneEnabled = false;
    if (String.isBlank(objectApiName)) {
      return view;
    }
    Clone_Config__mdt config = getActiveConfig(objectApiName);
    if (config == null) {
      return view;
    }
    view.deepCloneEnabled = true;
    view.namePrefix = config.Name_Prefix__c;
    view.childRelationshipNames = splitCsv(config.Child_Relationship_Names__c);
    view.excludedFields = splitCsv(config.Excluded_Fields__c);
    return view;
  }

  private static Map<SObjectType, Set<Id>> groupByType(Set<Id> recordIds) {
    Map<SObjectType, Set<Id>> idsByType = new Map<SObjectType, Set<Id>>();
    for (Id recordId : recordIds) {
      SObjectType sObjType = recordId.getSObjectType();
      if (!idsByType.containsKey(sObjType)) {
        idsByType.put(sObjType, new Set<Id>());
      }
      idsByType.get(sObjType).add(recordId);
    }
    return idsByType;
  }

  private static Map<Id, Id> cloneForType(
    SObjectType sObjType,
    Set<Id> originalIds
  ) {
    Schema.DescribeSObjectResult objDescribe = sObjType.getDescribe();
    String objectApiName = objDescribe.getName();
    Clone_Config__mdt config = getActiveConfig(objectApiName);

    Set<String> excludedFields = toLowerSet(
      splitCsv(config == null ? null : config.Excluded_Fields__c)
    );
    CopyableFields fieldInfo = getCopyableFields(sObjType);

    List<SObject> originals = queryRecords(
      objectApiName,
      fieldInfo.apiNames,
      'Id',
      originalIds
    );

    List<SObject> parentClones = new List<SObject>();
    List<Id> orderedOriginalIds = new List<Id>();
    String namePrefix = config == null ? null : config.Name_Prefix__c;
    for (SObject original : originals) {
      SObject cloned = buildClone(
        sObjType,
        original,
        fieldInfo,
        excludedFields
      );
      applyNamePrefix(cloned, fieldInfo, namePrefix);
      parentClones.add(cloned);
      orderedOriginalIds.add((Id) original.get('Id'));
    }

    insertRecords(parentClones);

    Map<Id, Id> newIdByOldId = new Map<Id, Id>();
    for (Integer i = 0; i < parentClones.size(); i++) {
      newIdByOldId.put(orderedOriginalIds[i], (Id) parentClones[i].get('Id'));
    }

    if (config != null && !newIdByOldId.isEmpty()) {
      cloneChildren(objDescribe, config, newIdByOldId);
    }
    return newIdByOldId;
  }

  private static void cloneChildren(
    Schema.DescribeSObjectResult parentDescribe,
    Clone_Config__mdt config,
    Map<Id, Id> newIdByOldId
  ) {
    Set<String> childRelNames = toLowerSet(
      splitCsv(config.Child_Relationship_Names__c)
    );
    if (childRelNames.isEmpty()) {
      return;
    }
    Map<String, Set<String>> excludedByChildRel = parseChildExcluded(
      config.Child_Excluded_Fields__c
    );

    // One query per configured child relationship (bounded by config, not data
    // volume). Clones are grouped by type so each child object is inserted once.
    Map<String, List<SObject>> childClonesByType = new Map<String, List<SObject>>();
    for (
      Schema.ChildRelationship rel : parentDescribe.getChildRelationships()
    ) {
      String relName = rel.getRelationshipName();
      if (
        String.isBlank(relName) ||
        !childRelNames.contains(relName.toLowerCase())
      ) {
        continue;
      }
      SObjectType childType = rel.getChildSObject();
      String childApiName = childType.getDescribe().getName();
      String relFieldName = rel.getField().getDescribe().getName();
      CopyableFields childFieldInfo = getCopyableFields(childType);
      Set<String> excludedChildFields = excludedByChildRel.containsKey(
          relName.toLowerCase()
        )
        ? excludedByChildRel.get(relName.toLowerCase())
        : new Set<String>();

      List<String> selectFields = new List<String>(childFieldInfo.apiNames);
      if (!containsIgnoreCase(selectFields, relFieldName)) {
        selectFields.add(relFieldName);
      }

      List<SObject> children = queryRecords(
        childApiName,
        selectFields,
        relFieldName,
        newIdByOldId.keySet()
      );
      if (children.isEmpty()) {
        continue;
      }
      if (!childClonesByType.containsKey(childApiName)) {
        childClonesByType.put(childApiName, new List<SObject>());
      }
      for (SObject child : children) {
        Id oldParentId = (Id) child.get(relFieldName);
        Id newParentId = newIdByOldId.get(oldParentId);
        if (newParentId == null) {
          continue;
        }
        SObject childClone = buildClone(
          childType,
          child,
          childFieldInfo,
          excludedChildFields
        );
        childClone.put(relFieldName, newParentId);
        childClonesByType.get(childApiName).add(childClone);
      }
    }
    for (String childApiName : childClonesByType.keySet()) {
      insertRecords(childClonesByType.get(childApiName));
    }
  }

  private static SObject buildClone(
    SObjectType sObjType,
    SObject source,
    CopyableFields fieldInfo,
    Set<String> excludedFields
  ) {
    SObject cloned = sObjType.newSObject();
    for (String fieldName : fieldInfo.apiNames) {
      if (excludedFields.contains(fieldName.toLowerCase())) {
        continue;
      }
      cloned.put(fieldName, source.get(fieldName));
    }
    return cloned;
  }

  private static void applyNamePrefix(
    SObject cloned,
    CopyableFields fieldInfo,
    String prefix
  ) {
    if (String.isBlank(prefix) || String.isBlank(fieldInfo.nameField)) {
      return;
    }
    Object current = cloned.get(fieldInfo.nameField);
    String newName = prefix + (current == null ? '' : String.valueOf(current));
    if (
      fieldInfo.nameFieldLength != null &&
      newName.length() > fieldInfo.nameFieldLength
    ) {
      newName = newName.left(fieldInfo.nameFieldLength);
    }
    cloned.put(fieldInfo.nameField, newName);
  }

  private static List<SObject> queryRecords(
    String objectApiName,
    List<String> fieldApiNames,
    String filterField,
    Set<Id> ids
  ) {
    if (
      ids == null ||
      ids.isEmpty() ||
      fieldApiNames == null ||
      fieldApiNames.isEmpty()
    ) {
      return new List<SObject>();
    }
    Set<String> selectSet = new Set<String>(fieldApiNames);
    selectSet.add('Id');
    // Object, field, and filter names are all schema-derived (never user input),
    // and the id set is passed as a bind variable, so this is injection-safe.
    String soql =
      'SELECT ' +
      String.join(new List<String>(selectSet), ', ') +
      ' FROM ' +
      objectApiName +
      ' WHERE ' +
      filterField +
      ' IN :ids';
    Map<String, Object> binds = new Map<String, Object>{ 'ids' => ids };
    return Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
  }

  private static void insertRecords(List<SObject> records) {
    if (records == null || records.isEmpty()) {
      return;
    }
    try {
      // Fields written are pre-filtered to those createable by the running
      // user; USER_MODE additionally enforces object CRUD and sharing.
      Database.insert(records, AccessLevel.USER_MODE);
    } catch (DmlException e) {
      throw new RecordCloneException(
        'Failed to insert cloned records: ' + e.getMessage(),
        e
      );
    }
  }

  private static Clone_Config__mdt getActiveConfig(String objectApiName) {
    if (String.isBlank(objectApiName)) {
      return null;
    }
    loadConfigIndex();
    return CONFIG_BY_OBJECT.get(objectApiName.toLowerCase());
  }

  private static void loadConfigIndex() {
    if (configIndexLoaded) {
      return;
    }
    if (configOverride != null) {
      for (Clone_Config__mdt config : configOverride) {
        indexConfig(config);
      }
    } else {
      // getAll returns Text and Checkbox fields (used to find active configs);
      // getInstance is then required to load the Long Text Area fields.
      for (Clone_Config__mdt summary : Clone_Config__mdt.getAll().values()) {
        if (
          summary.Active__c == true &&
          String.isNotBlank(summary.Object_API_Name__c)
        ) {
          indexConfig(Clone_Config__mdt.getInstance(summary.DeveloperName));
        }
      }
    }
    configIndexLoaded = true;
  }

  private static void indexConfig(Clone_Config__mdt config) {
    if (
      config.Active__c == true && String.isNotBlank(config.Object_API_Name__c)
    ) {
      CONFIG_BY_OBJECT.put(config.Object_API_Name__c.toLowerCase(), config);
    }
  }

  private static CopyableFields getCopyableFields(SObjectType sObjType) {
    String key = sObjType.getDescribe().getName();
    if (COPYABLE_BY_TYPE.containsKey(key)) {
      return COPYABLE_BY_TYPE.get(key);
    }
    CopyableFields result = new CopyableFields();
    for (
      Schema.SObjectField field : sObjType.getDescribe()
        .fields.getMap()
        .values()
    ) {
      Schema.DescribeFieldResult dfr = field.getDescribe();
      if (dfr.isCreateable() && dfr.isAccessible()) {
        result.apiNames.add(dfr.getName());
      }
      if (dfr.isNameField()) {
        result.nameField = dfr.getName();
        result.nameFieldLength = dfr.getLength();
      }
    }
    COPYABLE_BY_TYPE.put(key, result);
    return result;
  }

  private static Map<String, Set<String>> parseChildExcluded(String jsonMap) {
    Map<String, Set<String>> result = new Map<String, Set<String>>();
    if (String.isBlank(jsonMap)) {
      return result;
    }
    try {
      Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(
        jsonMap
      );
      for (String relName : raw.keySet()) {
        Set<String> fields = new Set<String>();
        for (Object fieldName : (List<Object>) raw.get(relName)) {
          fields.add(String.valueOf(fieldName).toLowerCase());
        }
        result.put(relName.toLowerCase(), fields);
      }
    } catch (Exception e) {
      throw new RecordCloneException(
        'Invalid JSON in Child_Excluded_Fields__c: ' + e.getMessage(),
        e
      );
    }
    return result;
  }

  private static List<String> splitCsv(String csv) {
    List<String> result = new List<String>();
    if (String.isBlank(csv)) {
      return result;
    }
    for (String part : csv.split(',')) {
      String trimmed = part.trim();
      if (String.isNotBlank(trimmed)) {
        result.add(trimmed);
      }
    }
    return result;
  }

  private static Set<String> toLowerSet(List<String> values) {
    Set<String> result = new Set<String>();
    for (String value : values) {
      result.add(value.toLowerCase());
    }
    return result;
  }

  private static Boolean containsIgnoreCase(
    List<String> values,
    String target
  ) {
    for (String value : values) {
      if (value.equalsIgnoreCase(target)) {
        return true;
      }
    }
    return false;
  }

  /** Describe-derived field metadata used when building clones. */
  private class CopyableFields {
    public List<String> apiNames = new List<String>();
    public String nameField;
    public Integer nameFieldLength;
  }
}
