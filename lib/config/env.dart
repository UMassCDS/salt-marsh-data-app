// --flavor sets FLUTTER_APP_FLAVOR, so one flag picks the app id, name and API
const kFlavor = String.fromEnvironment('FLAVOR', defaultValue: String.fromEnvironment('FLUTTER_APP_FLAVOR', defaultValue: 'prod'));
const kIsDevFlavor = kFlavor == 'dev';
const kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: kIsDevFlavor ? 'https://dev.saltmarshdata.org' : 'https://saltmarshdata.org',
);
