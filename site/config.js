/* =====================================================================
 * Deploy-time configuration for the public site.
 *
 * This file is READ, NOT BUILT. It is a separate file from app.js on
 * purpose: the site ships as plain files, and whoever deploys it has to
 * be able to point it at a portal without editing application code or
 * running a build. Overwrite this one file per environment.
 *
 * It must never hold a secret. Everything here is served to the open
 * internet, and this is the one surface in this project that is meant
 * to be - see site/README.md.
 * ===================================================================== */
window.HBH_SITE = {
  // Visible team cards: desktop 1–5, tablet 1–3, mobile 1–2.
  teamCarousel: { desktop: 5, tablet: 2, mobile: 1 },
  /**
   * Origin of the parent portal, with NO trailing slash.
   *
   * The site links to two of its routes and no others:
   *   /apply  the enrolment form - the portal's only unauthenticated
   *           route, and the destination of every "طلب التحاق" button
   *   /login  sign-in for a family that already has a file
   *
   * WHEN THIS IS EMPTY the buttons do not break and do not 404: they
   * fall back to the contact section and the site says, in Arabic, that
   * applications are taken by phone for now. That is a tested state,
   * not a gap - and a WRONG value here is worse than an empty one,
   * because the page looks finished either way.
   *
   * Set it to the portal's real origin, per environment:
   *
   *   portalBaseUrl: 'https://portal.example.eg'
   *
   * WHETHER IT SHOULD BE FILLED AT ALL IS NOT A DEPLOYMENT DETAIL, and
   * the answer with its conditions is in deploy/server/PORTAL-LINK.md.
   * Read that before changing this line. It is deliberately not repeated
   * here: this file is served to every visitor, and the reasoning names
   * what is not yet finished about signing in.
   */
  portalBaseUrl: 'https://portal.hbhskills.com',
  // Used only when this website runs on localhost or a loopback address.
  developmentPortalBaseUrl: 'http://localhost:4210',

  /**
   * Where the enrolment form lives, when it is published somewhere the
   * sign-in is not.
   *
   * The two used to share portalBaseUrl and they cannot, because the
   * two are published under different conditions - the conditions are
   * in deploy/server/PORTAL-LINK.md, with the rest of the reasoning.
   *
   * What this origin IS: the same Angular bundle with exactly one API
   * call allowed through it, POST /api/v1/enrolments - the only route
   * the service answers without a session - and every other path
   * refused, sign-in included.
   *
   * Empty means fall back to portalBaseUrl, which is how it behaved
   * before this existed.
   */
  applyBaseUrl: 'https://apply.hbhskills.com',

  /**
   * OWNER: the centre's real contact details. These are shown on the
   * page and used by the tel: and WhatsApp links.
   *
   * The mobile is eleven digits starting 01, which is what the rest of
   * the system validates. whatsapp is the same number in international
   * form without a plus, because that is what wa.me takes.
   */
  phone: '',            // OWNER: '01XXXXXXXXX'
  whatsapp: '',         // OWNER: '201XXXXXXXXX'
  email: '',            // OWNER
  addressAr: '',        // OWNER
  addressEn: '',        // OWNER
  mapUrl: '',           // OWNER: link to open in a map app. Not an iframe.
};
