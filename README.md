# ImmutableIDManagement

## Description

Helps manage ImmutableIDs in AD / Azure AD synchronization scenarios.

## Public Functions Included

* Set-IIDAttributeValue
  * Description: Copies a value from a source attribute to a target attribute for specified objects (via -Identity parameter), an entire AD domain subtree, an entire domain, or an entire forest.  Can ignore objects that already have a value in the target attribute. When processing a subtree, domain, or forest the function processes AD objects which are in objectcategory person or group.
* Set-TargetObjectFromSourceObjectCrossForest (In Development)
    * Description: 'Joins' 2 objects from separate AD Forests by applying a specified value from a source object to a specified target attribute on a specified target object in another AD forest so that Azure AD synchronization tools can join these objects in the metaverse.