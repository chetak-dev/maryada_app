/// App-wide configuration for the site-admin / org-admin account model.
///
/// The site admin is bootstrapped by email: whoever signs in with
/// [kBootstrapAdminEmail] is granted the `siteAdmin` role on first sign-in
/// (this is also enforced in the Firestore security rules). Change this value
/// (here and in `backend/firestore.rules`) to hand the site-admin role to a
/// different address.
library;

const String kBootstrapAdminEmail = 'chetakkumarpradhan@gmail.com';

/// Default number of children a new org admin may add until the site admin
/// changes it.
const int kDefaultMaxChildren = 5;

/// Only emails the site admin has granted access to may become org admins.
/// Everyone else who signs in becomes a blocked `user` until granted. Kept
/// false so access is pre-authorised by the site admin.
const bool kOpenHostSignup = false;

/// Shown wherever the app names its own version. Keep the numbers in step with
/// `version:` in pubspec.yaml (name, then build).
const String kAppVersionName = '1.0.0';
const String kAppBuild = '0';
const String kAppVersionLabel = 'v$kAppVersionName($kAppBuild)';
