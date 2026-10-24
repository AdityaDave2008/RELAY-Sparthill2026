// Crypto polyfills must load before anything that touches crypto (aws-amplify,
// and @relay/core's createMessage / encodeTransfer).
// 1. getRandomValues (native-backed) from react-native-get-random-values.
// 2. randomUUID, which that package does NOT provide and Hermes lacks.
import 'react-native-get-random-values';
import './src/polyfills/randomUUID';
import { registerRootComponent } from 'expo';

import App from './src/App';

// registerRootComponent calls AppRegistry.registerComponent('main', () => App)
// and sets up the environment for both Expo Go dev builds and native builds.
registerRootComponent(App);
