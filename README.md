<h1>Update Test Flight Build Release Notes</h1>
<h2>Setup</h2>

1. Go to https://appstoreconnect.apple.com/access/api and create your own key. This is also the page to find the private key ID and the issuer ID.
2. Update configs in **AppConfigs.swift** and remove error line
3. Run the app
4. There are 2 different setups for release notes.
  - Using AppStoreconnectSDK (https://github.com/AvdLee/appstoreconnect-swift-sdk)
  - Using Spine Api (https://github.com/json-api-ios/Spine.git) by calling https://developer.apple.com/documentation/appstoreconnectapi manually
5. To change App_StoreApp.swift update the View 


<h2>Limitations</h2>

1. Fetching only 10 apps for any teams
2. Fetching only 5 recent versions from testflight
3. Fetching only 10 recent buidss from any app versions
