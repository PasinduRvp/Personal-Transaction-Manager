package com.finora.finora

import io.flutter.embedding.android.FlutterFragmentActivity

/**
 * `FlutterFragmentActivity`, not `FlutterActivity`.
 *
 * `local_auth` shows the system biometric prompt through `BiometricPrompt`,
 * which is a fragment and so needs a `FragmentActivity` to attach to. Under
 * plain `FlutterActivity` the plugin throws at the moment the prompt would
 * appear — that is, only once a user actually tries to unlock, and never at
 * build time. Hence this comment: the base class is load-bearing.
 */
class MainActivity : FlutterFragmentActivity()
