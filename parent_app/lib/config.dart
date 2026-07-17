/// App-wide configuration for the admin / host account model.
///
/// The admin is bootstrapped by email: whoever signs in with
/// [kBootstrapAdminEmail] is granted the `admin` role on first sign-in (this is
/// also enforced in the Firestore security rules). Change this value (here and
/// in `backend/firestore.rules`) to hand the admin role to a real address.
library;

const String kBootstrapAdminEmail = 'admin@maryada.app';

/// Default number of children a new host may add until an admin changes it.
const int kDefaultMaxChildren = 5;

/// When true, any signed-in email can become a host on first sign-in (open
/// self-signup). When false, only invited emails become hosts. Kept open for
/// now so existing accounts and demos keep working.
const bool kOpenHostSignup = true;
