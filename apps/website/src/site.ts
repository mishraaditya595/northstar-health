// Single source for facts repeated across pages. Keep it to what the
// shipped app actually does (see docs/PRIVACY_POLICY_INPUTS.md).
export const SITE = {
  name: 'BeyondRep',
  url: 'https://beyondrep.in',
  tagline: 'The offline-first strength log that keeps your data yours.',
  appId: 'in.beyondrep.app',
  // Public role addresses on the project domain. privacyEmail is the owner's
  // mailbox, at the owner's request, until privacy@ email routing is set up.
  contactEmail: 'hello@beyondrep.in',
  privacyEmail: 'theadityamishra12@zohomail.in',
  // The data fiduciary (controller) named in the privacy policy.
  controllerName: 'Aditya Mishra',
  controllerLocation: 'Brahmapur, Odisha, India',
  minimumAge: 13,
  // Store links stay null until the app is publicly listed; pages then
  // show the store buttons instead of the "coming soon" note.
  appStoreUrl: null as string | null,
  playStoreUrl: null as string | null,
  // Set back to true to show the Draft banner if a legal page has open
  // "to be confirmed" items again (docs/PRIVACY_POLICY_INPUTS.md section 10).
  legalDraft: false,
  legalLastUpdated: '2026-11-26',
};
