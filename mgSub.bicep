var subId = '104868fd-b35a-4cf7-a13c-c22416b0dadb'
var mg = 'dev'
resource subMove 'Microsoft.Management/managementGroups/subscriptions@2020-05-01' = {
  name: 'mg/subId'
}