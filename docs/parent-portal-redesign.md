# Parent portal redesign

Implemented 14 September 2026. Existing authentication, child access, payment and scheduling rules remain the source of truth.

## Experience

- Desktop: persistent labeled navigation at 1100px and above. Content grows with the viewport up to a readable 1680px canvas. No fixed phone-width layout on tablets.
- Mobile/tablet: full-width content with a fixed-size header, independently scrolling content and five bottom destinations. More opens billing, requests, notifications and child switching.
- Each screen has a clear title, a short purpose statement on desktop and a consistent child selector with the existing photo/fallback logic. Back sits beside the child on desktop and in the mobile header.
- Home leads with the next session and available actions, followed by updates and today's activity. Wider screens split upcoming appointments, balance and shortcuts into a second column.
- Schedule separates upcoming/past appointments from support actions. Reschedule and cancellation links open the corresponding request form; they never alter an appointment directly.
- Progress retains goals, reports and session notes in one destination. Wide screens compare goals in two columns.
- Home activities use readable instructions and an explicit completion action. Completed titles remain readable rather than struck through.
- Billing retains separate package and invoice frames, including invoice payment breakdowns. They sit side by side on desktop and stack on mobile. Family billing scope remains explicit.
- Requests place composition beside previous family requests on desktop; mobile follows a single reading order. The messages tab remains available and drafts retain the existing persistence behavior.
- Profile and notifications share the card system, typography, focus treatment and responsive gutters.

## Verification

Used an isolated build with the existing FixtureAuthApi and FixturePortalApi. Non-asset HTTP calls were blocked in that preview. No live appointment, payment, activity or message was submitted.

Inspected desktop, tablet and mobile layouts and exercised navigation, More, schedule scope switching, report tabs and request expansion. Existing portal navigation and request tests: 9 passed. Production build is verified separately.

Login and avatar/attendance changes from the preceding work are retained. This is a visual and interaction redesign of the parent portal; it does not change backend permissions, clinical interpretation, payment collection or request approval rules.
