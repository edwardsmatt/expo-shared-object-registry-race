# SharedObjectRegistry race repro (Android, Expo SDK 54)

This app shows a thread race in `expo-modules-core` on Android. A live shared object is sometimes reported as already released. With `expo-sqlite`, a valid `getAllAsync` call fails with this error:

```
Call to function 'NativeDatabase.prepareAsync' has been rejected.
→ Caused by: The 2nd argument cannot be cast to type expo.modules.sqlite.NativeStatement (received class java.lang.Integer)
→ Caused by: Cannot use shared object that was already released
```

The app is the `blank-typescript` SDK 54 template plus `expo-sqlite`. It has one screen with one button, **Run stress**. The button opens a database, creates a table with 3 rows, and then runs 400 rounds of 50 concurrent `db.getAllAsync('SELECT * FROM items')` calls (20,000 calls). The screen shows the number of rejections that contain "already released" (`failures`), the total number of calls, and any other rejections (`otherErrors`). The app logs each rejection to the console.

All of the code is in `App.tsx`.

## Run it

You need Node 20 or later, pnpm, JDK 17 or 21, and the Android SDK with an Android emulator. An Expo Go build does not work, because the app needs a development build.

1. Install the dependencies:

   ```sh
   pnpm install
   ```

2. Start an Android emulator. We used an API 35 Google APIs arm64 image.
3. Build and start the development build:

   ```sh
   npx expo run:android
   ```

4. In the app, tap **Run stress**. Wait about 10 seconds for the status line to change to `failures=… calls=20000 otherErrors=…`.
5. To get a fresh process, force-stop the app, open it again, and tap **Run stress** again.

Expected result: `failures=0 calls=20000 otherErrors=0`.

Actual result: on most launches, `failures` is between 1 and 5.

`scripts/run-launches.sh <launches> <label>` repeats steps 4 and 5 with `adb`. It force-stops the app, opens it, taps the button, and prints each launch's result. It expects Metro on port 8082 (`npx expo run:android --port 8082`). Change the `adb reverse` line to use another port.

## Apply the fix

`patches/expo-modules-core.patch` is the proposed upstream fix. In `SharedObjectRegistry.kt`, it reads the map under the registry lock in `toNativeObject` (with its `ensureWasNotRelease` check) and in `toNativeObjectOrNull(js)`. pnpm does not apply it by default, so that a fresh install shows the bug. To apply it:

1. Add these lines to `pnpm-workspace.yaml`:

   ```yaml
   patchedDependencies:
     expo-modules-core: patches/expo-modules-core.patch
   ```

2. Run `pnpm install`.
3. Rebuild with `npx expo run:android`. The fix is in native code, so a JavaScript reload is not enough.

## Results

We used an Android emulator (Android 15, API 35, Google APIs arm64-v8a) on an Apple Silicon Mac. Each launch is a fresh process with one tap of **Run stress** (20,000 calls).

| Build | Launches | Calls | "already released" | Other rejections |
| --- | --- | --- | --- | --- |
| Stock `expo-modules-core` 3.0.30 | 10 | 200,000 | 25 | 1 |
| With the patch | 10 | 200,000 | 0 | 0 |

Per launch, the stock build failed 1, 3, 4, 0, 3, 1, 3, 5, 1 and 4 times. The patched build is `patches/expo-modules-core.patch` as it is in this repo, and every launch had 0 failures.

The 1 other rejection had the same cause. Its message was `Cannot convert provided JavaScriptObject to the SharedObject, because it doesn't contain valid id` (`InvalidSharedObjectIdException`). In that case, the unlocked `pairs.contains` check found the entry, but the unlocked `pairs[id]` read that followed it missed the entry.

## Environment

`npx expo-env-info`:

```
  expo-env-info 2.1.0 environment info:
    System:
      OS: macOS 26.7
      Shell: 5.9 - /bin/zsh
    Binaries:
      Node: 24.17.0 - ~/.nvm/versions/node/v24.17.0/bin/node
      Yarn: 1.22.22 - ~/.nvm/versions/node/v24.17.0/bin/yarn
      npm: 11.13.0 - ~/.nvm/versions/node/v24.17.0/bin/npm
    SDKs:
      Android SDK:
        API Levels: 35, 36
        Build Tools: 35.0.0, 36.0.0
        System Images: android-35 | Google APIs ARM 64 v8a
    IDEs:
      Xcode: /undefined - /usr/bin/xcodebuild
    npmPackages:
      expo: ~54.0.36 => 54.0.37
      react: 19.1.0 => 19.1.0
      react-native: 0.81.5 => 0.81.5
    Expo Workflow: bare
```

The resolved native versions are `expo-modules-core` 3.0.30 and `expo-sqlite` 16.0.10. We used pnpm 11.8.0 with `nodeLinker: hoisted`.

`npx expo-doctor@latest`: `18/18 checks passed. No issues detected!`
