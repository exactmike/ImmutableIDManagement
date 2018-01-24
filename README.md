# ImmutableIDManagement

## Description

Helps manage ImmutableIDs in AD / Azure AD synchronization scenarios.

## Public Functions Included

* Set-IIDAttributeValue
  * Description: Copies a value from a source attribute to a target attribute for specified objects (via -Identity parameter), an entire AD domain subtree, an entire domain, or an entire forest.  Can ignore objects that already have a value in the target attribute. When processing a subtree, domain, or forest the function processes AD objects which are in objectcategory person or group.
  * Details: Parameters control the following behaviors of Set-IIDAttributeValue
    * Process Individual Identities, Subtrees, an entire Domain, an entire Forest
    * Only update items which have a null target attribute
    * Only report on items which need to be updated (per your specified parameters)
    * Export CSV files of results or reports to a specified output folder
    * Log operations and errors to a specified output folder
    * supports common parameters and risk mitigation parameters (like -whatif)
* Set-TargetObjectFromSourceObjectCrossForest (In Development)
    * Description: 'Joins' 2 objects from separate AD Forests by applying a specified value from a source object to a specified target attribute on a specified target object in another AD forest so that Azure AD synchronization tools can join these objects in the metaverse.