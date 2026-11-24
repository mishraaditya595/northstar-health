// Single source for facts repeated across pages. Keep it to what the
// shipped app actually does (see docs/PRIVACY_POLICY_INPUTS.md).
export const SITE = {
  name: 'BeyondRep',
  url: 'https://beyondrep.in',
  tagline: 'The offline-first strength log that keeps your data yours.',
  appId: 'in.beyondrep.app',
  // Public role addresses on the project domain. Never a personal email.
  contactEmail: 'hello@beyondrep.in',
  privacyEmail: 'privacy@beyondrep.in',
  // Store links stay null until the app is publicly listed; pages then
  // show the store buttons instead of the "coming soon" note.
  appStoreUrl: null as string | null,
  playStoreUrl: null as string | null,
  // The legal pages are drafts until the open questions in
  // docs/PRIVACY_POLICY_INPUTS.md section 10 are answered.
  legalDraft: true,
  legalLastUpdated: '2026-11-25',
};
