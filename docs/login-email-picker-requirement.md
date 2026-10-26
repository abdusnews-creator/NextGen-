# NextGen Login — Email Account Picker Requirement

## Owner request
On Login and Create Account, make it easy for a user to choose an email address already available on their device, where the platform supports a safe account picker.

## Required behavior
- Offer a supported sign-in/account picker (for example, Google Sign-In on Android/web where configured) so the user can select an account without NextGen reading the device's entire email store.
- Also provide a manual email-entry option.
- Verify ownership of the selected email through the identity provider or an email verification flow.
- Request only the permissions required for sign-in. Never request mailbox-reading access just to display email addresses.
- Do not expose email addresses to other users or list all accounts from the device without explicit platform permission and user action.
- If no account picker is available, show the manual email field and explain that the user can enter an address.

## Implementation status
This is a documented requirement only. Authentication, account picker, verification and database are not implemented in the static GitHub Pages prototype yet.