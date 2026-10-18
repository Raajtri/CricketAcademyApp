# Cricket Academy app: setup

One Flutter codebase gives you an **Android APK** and an **iPhone web app** (installed from Safari).
Both read the same Firebase database, so attendance, fees and live scores sync between all devices.

## 1. Create the Firebase project (about 5 minutes, free plan is enough)

1. Go to <https://console.firebase.google.com> > **Add project** (any name, Analytics not needed).
2. **Build > Authentication > Get started > Sign-in method > Email/Password > Enable.**
3. **Build > Firestore Database > Create database** > pick a nearby region (e.g. `asia-south1`) > **Production mode**.
4. Firestore > **Rules** tab > replace everything with the contents of `firestore.rules` > **Publish**.

## 2. Register the apps and copy the keys

In **Project settings (gear icon) > General > Your apps**:

- **Add app > Web (`</>`)**, nickname anything. Copy the `firebaseConfig` values.
- **Add app > Android**, package name exactly `com.academy.cricket_academy`. Skip the other steps; from the
  downloaded `google-services.json` you only need `mobilesdk_app_id` (that is the Android `appId`) and `current_key` (the `apiKey`).

Paste them into `lib/firebase_options.dart` (replace every `YOUR_...`):

| Field            | Web                    | Android                                  |
|------------------|------------------------|------------------------------------------|
| `apiKey`         | `apiKey`               | `current_key`                            |
| `appId`          | `appId`                | `mobilesdk_app_id`                       |
| `messagingSenderId` | `messagingSenderId` | `project_number`                         |
| `projectId`      | `projectId`            | `project_id`                             |

(Alternatively run `dart pub global activate flutterfire_cli` then `flutterfire configure`, which overwrites that file for you.)

## 3. Build

```
flutter build apk --release     # build\app\outputs\flutter-apk\app-release.apk  -> send to Android phones
flutter build web --release     # build\web                                      -> host this for iPhone
```

Android: copy the APK to the phone and open it (allow "install unknown apps" once).

## 4. Host the web app (needed for iPhone)

Easiest with Firebase Hosting (same project):

```
npm install -g firebase-tools
firebase login
firebase init hosting      # public directory: build/web, single-page app: Yes, don't overwrite index.html
firebase deploy
```

You get a URL like `https://your-project.web.app`.
**iPhone:** open that URL in **Safari** > Share button > **Add to Home Screen**. It opens full-screen like an app.

## 5. First launch

1. Open the app > **First time setup (admin only)** > create the admin account. Do this straight away; it only works once.
2. As admin: **Home > menu > Batches** (add batches), **Coaches & staff** (add coach logins).
3. Add students, then start using Attendance, Money (Fees and Shop) and Cricket.

## Who can do what

| | Admin | Coach |
|---|---|---|
| Students, attendance, cricket scoring | yes | yes |
| Batches, coaches, fees, shop & stock | yes | no |

## Scoring and wagon wheel

- **Cricket > New match**: team names, overs, who bats first, players (type names or pick from students).
- The scoring screen follows the CricHeroes layout: run keypad (0-6), **WD / NB / BYE / LB**, **OUT** (with fielder), **UNDO**.
- With **Mark shot direction** switched on, each scoring shot asks you to tap where the ball went (bowler's end is at the top).
- **Wagon wheel**: open a match > *Wagon wheel* tab > pick a team, then **Whole team** or any single player.
  A player's wheel across all matches is under **Cricket > Players > (player)**.
