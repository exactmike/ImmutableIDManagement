# ImmutableIDManagement
Helps manage ImmutableIDs in AD / Azure AD synchronization scenarios
Includes the Set-IIDAttributeValue which allows you to copy from a source attribute to another attribute to be used as your ImmutableID source attribute.
Allows you to do this per identified object, to an entire SearchBase (DistinguishedName location in AD), to an entire domain, or to an entire forest.  
Entire* options will update all person and group type objects (users, Contacts, Groups)
