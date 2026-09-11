/* =====================================================================
 * Hand By Hand - public site behaviour.
 *
 * Four jobs and no more: point the call-to-action buttons at the parent
 * portal, fill in the centre's contact details from config.js, switch
 * the page between Arabic and English, and open the mobile menu.
 *
 * It calls no API and sends nothing anywhere. The one thing a family
 * types - the enrolment form - lives in the portal, on the portal's own
 * origin, behind the service's own validation and rate limit. A second
 * copy of that form here would be a second set of rules to keep in step
 * with the server's, and the copy that drifts is always the one nobody
 * is testing.
 * ===================================================================== */
(function () {
  'use strict';

  var CONFIG = window.HBH_SITE || {};

  /* ------------------------------------------------------------------
   * Portal links
   *
   * Two routes, named here rather than at each call site so that a
   * change to the portal's routing is one edit:
   *
   *   apply  the enrolment form. The portal's ONLY unauthenticated
   *          route, and the only one a stranger may be sent to.
   *   login  sign-in, for a family that already has a file.
   *
   * When portalBaseUrl is empty the buttons must still do something
   * sensible. They fall back to the contact section and the page says
   * so out loud, because a public page whose main button 404s costs
   * more than one that admits the portal is not published yet.
   * ------------------------------------------------------------------ */
  var ROUTES = { apply: '/apply', login: '/login' };

  function portalBase() {
    var base = typeof CONFIG.portalBaseUrl === 'string' ? CONFIG.portalBaseUrl.trim() : '';
    return base.replace(/\/+$/, '');
  }

  /* The two routes no longer have to live at the same address, because
     applying and signing in are published under different conditions -
     deploy/server/PORTAL-LINK.md has those, and this file is served to
     every visitor, so they are not repeated here. baseFor keeps the
     distinction in one place, so a future edit that publishes the
     portal only has to fill portalBaseUrl in and everything follows. */
  function applyBase() {
    var base = typeof CONFIG.applyBaseUrl === 'string' ? CONFIG.applyBaseUrl.trim() : '';
    base = base.replace(/\/+$/, '');
    return base || portalBase();
  }

  function baseFor(name) {
    return name === 'apply' ? applyBase() : portalBase();
  }

  function wirePortalLinks() {
    var links = document.querySelectorAll('[data-portal]');
    var i, link, route, name, base;

    for (i = 0; i < links.length; i++) {
      link = links[i];
      name = link.getAttribute('data-portal');
      route = ROUTES[name];
      if (!route) { continue; }
      base = baseFor(name);
      if (base) {
        link.setAttribute('href', base + route);
        link.removeAttribute('data-portal-offline');
      } else {
        // Stays #contact, which is what the markup already says, and is
        // marked so the stylesheet or a later change can tell the two
        // states apart.
        link.setAttribute('data-portal-offline', '');
      }
    }

    /* The note is about SIGNING IN, so it asks portalBase() and not the
       loop's last value - which is whichever link happened to come last
       in the document and means nothing. It stays visible while the
       portal is unpublished, even though applying works. */
    var note = document.getElementById('portalNote');
    if (note) { note.hidden = Boolean(portalBase()); }
  }

  /* ------------------------------------------------------------------
   * Contact details
   *
   * A tel: or wa.me link built from an empty string is a link that looks
   * live and does nothing, so each one is only turned into a link when
   * config.js actually has the value. Until then the card keeps its
   * placeholder text and stays inert.
   * ------------------------------------------------------------------ */
  function setContact(id, value, href, dir) {
    var el = document.getElementById(id);
    if (!el || !value) { return; }
    el.textContent = value;
    el.removeAttribute('data-i18n');       // a real value must not be re-translated
    if (dir) { el.setAttribute('dir', dir); }
    if (href && el.tagName === 'A') {
      el.setAttribute('href', href);
    } else if (el.tagName === 'A') {
      el.removeAttribute('href');
    }
  }

  function wireContact() {
    if (CONFIG.phone) {
      setContact('contactPhone', CONFIG.phone, 'tel:' + CONFIG.phone, 'ltr');
      var header = document.getElementById('headerPhone');
      var headerText = document.getElementById('headerPhoneText');
      if (header && headerText) {
        headerText.textContent = CONFIG.phone;
        header.setAttribute('href', 'tel:' + CONFIG.phone);
        header.hidden = false;
      }
    }
    if (CONFIG.whatsapp) {
      setContact('contactWhatsapp', CONFIG.whatsapp, whatsappHref(CONFIG.whatsapp), 'ltr');
    }
    if (CONFIG.email) {
      setContact('contactEmail', CONFIG.email, 'mailto:' + CONFIG.email, 'ltr');
    }
    if (CONFIG.landline) {
      setContact('contactLandline', CONFIG.landline, 'tel:' + CONFIG.landline, 'ltr');
    }

    var mapHref = mapLink(CONFIG.mapUrl);
    if (mapHref) {
      var map = document.getElementById('contactMap');
      if (map) { map.setAttribute('href', mapHref); map.hidden = false; }
    }

    /* The embedded map is driven from the SAME value as the link above.
       It shipped with the coordinates written into the iframe's src in
       index.html as well as stored in site_contact - two copies of one
       fact, and the one nobody edits is the one that ends up pointing at
       the old building. */
    var frameSrc = mapEmbed(CONFIG.mapUrl);
    var frame = document.getElementById('contactMapFrame');
    if (frame && frameSrc) { frame.setAttribute('src', frameSrc); }
    // The address is language-dependent, so applyLanguage owns it from
    // here on. This first call is what puts something there before any
    // toggle happens.
    setAddress('ar');
  }

  /* ------------------------------------------------------------------
   * Normalising what the console stores
   *
   * These two fields are typed by a person into a text box, and the
   * forms they arrive in are the forms people actually write - not the
   * forms wa.me and a map application accept. Both were wrong in the
   * first real row the centre saved, and both failed as a dead link
   * rather than as an error:
   *
   *   whatsapp  "00201095006478"  - wa.me wants bare digits, so the 00
   *                                 prefix makes the link 404.
   *   mapUrl    "30.0011, 31.4818" - a coordinate pair, not a URL. Set
   *                                 as an href it resolves against the
   *                                 site and opens a missing page.
   *
   * Normalising here rather than validating in the console is the right
   * place for it: the console can reject the next one, but this page
   * has to render the rows that already exist.
   * ------------------------------------------------------------------ */
  function whatsappHref(raw) {
    var digits = String(raw).replace(/\D/g, '');
    if (!digits) { return ''; }
    // Leading zeros go either way: "00" is the international prefix, and
    // the single "0" of a local Egyptian number is replaced by the
    // country code on the next line.
    digits = digits.replace(/^0+/, '');
    // 1095006478 -> 201095006478. A number already carrying 20 is left.
    if (/^1\d{9}$/.test(digits)) { digits = '20' + digits; }
    return digits ? 'https://wa.me/' + digits : '';
  }

  /* Accepts a real URL, or a "lat, lng" pair, and nothing else. An
     unusable value returns '' and the link stays hidden rather than
     shipping something that goes nowhere. */
  function mapLink(raw) {
    var value = String(raw || '').trim();
    if (!value) { return ''; }
    if (/^https?:\/\//i.test(value)) { return value; }

    var pair = value.match(/^(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)$/);
    if (pair) {
      // geo: would be more correct and opens nothing on a desktop.
      return 'https://www.google.com/maps/search/?api=1&query='
        + encodeURIComponent(pair[1] + ',' + pair[2]);
    }
    return '';
  }

  /* The embed URL for the same coordinates. Only a "lat, lng" pair can
     become one - a plain map link cannot be reframed as an embed - so a
     URL in that field leaves the iframe on whatever the document
     shipped with, and only the button below it changes. */
  function mapEmbed(raw) {
    var pair = String(raw || '').trim()
      .match(/^(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)$/);
    if (!pair) { return ''; }
    return 'https://maps.google.com/maps?q='
      + encodeURIComponent(pair[1] + ',' + pair[2]) + '&z=16&output=embed';
  }

  /* Directions in the centre's own words. Line breaks are meaningful
     here - each line is one instruction - so they are rendered as
     separate lines and not glued into a paragraph. */
  function renderArrival(lang) {
    var el = document.querySelector('[data-i18n="contact.arrivalText"]');
    if (!el) { return; }
    var c = content().contact;
    var text = c && (lang === 'en'
      ? (c.arrivalEn || c.arrivalAr)
      : (c.arrivalAr || c.arrivalEn));
    if (!text) { return; }

    el.textContent = '';
    el.removeAttribute('data-i18n');
    var lines = String(text).split(/\r?\n/);
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].trim()) { continue; }
      if (el.childNodes.length) { el.appendChild(document.createElement('br')); }
      el.appendChild(document.createTextNode(lines[i].trim()));
    }
  }

  /* The centre writes its own address in both languages, or in one. An
     English page with only an Arabic address shows the Arabic - a
     translated street name is a street name that fails to find the
     building, and an empty card is worse than the wrong alphabet. */
  function setAddress(lang) {
    var el = document.getElementById('contactAddress');
    if (!el) { return; }
    var value = lang === 'en'
      ? (CONFIG.addressEn || CONFIG.addressAr)
      : (CONFIG.addressAr || CONFIG.addressEn);
    if (!value) { return; }
    el.textContent = value;
    el.removeAttribute('data-i18n');
  }

  /* ------------------------------------------------------------------
   * Language
   *
   * Arabic is the page as authored; English is this dictionary applied
   * over it. Only `en` is stored, so a key that has not been translated
   * yet keeps its Arabic text rather than rendering as a raw key - a
   * missing sentence in the wrong language still reads, a bare
   * "why.planText" does not.
   *
   * The address details are NOT here. They come from config.js in the
   * language the centre wrote them, and a translated street name is a
   * street name that fails to find the building.
   * ------------------------------------------------------------------ */
  var EN = {
"contact.landline":"Landline",
"contact.direct":"For direct calls",
"contact.quick":"For quick enquiries",
"contact.arrival":"Getting here",
"contact.arrivalText":"Near El Rehab Bridge and Mohamed Naguib Axis, beside Al Retaj School and Al Enaya Bellah Mosque.",
"contact.mapNote":"The location opens in a new Google Maps tab.",
'loading.message':'Loading the website…',
'benefit.live':'Live follow-up',
'benefit.reports':'Progress reports',
'benefit.home':'Home programme',
"programs.title":"Our additional programmes",
"programs.badge":"More opportunities for all-round development",
"programs.sub":"Every child has different needs. Our specialised programmes and activities support growth in different areas.",
"programs.more":"More details",
"programs.contact":"Contact us to learn more about the programmes",
"programs.ask":"Ask about availability and suitable times",
"programs.languages.title":"Foreign-language speech sessions",
"programs.languages.desc":"Speech sessions in Arabic, English and French to support language and communication.",
"programs.languages.detail":"Arabic · English · French",
"programs.family.title":"Family counselling",
"programs.family.desc":"Support and guidance for families dealing with behavioural and developmental challenges.",
"programs.family.detail":"Family guidance · Behavioural and developmental challenges",
"programs.music.title":"Music therapy",
"programs.music.desc":"Music therapy sessions supporting communication, concentration and social skills.",
"programs.music.detail":"Communication · Concentration · Social skills",
"programs.quran.title":"Quran memorisation and recitation",
"programs.quran.desc":"Quran memorisation and recitation for children through interactive, age-appropriate activities.",
"programs.quran.detail":"Quran memorisation · Recitation skills",
"programs.training.title":"Online learning and specialist training",
"programs.training.desc":"Training courses and specialist preparation in various fields, online and in person.",
"programs.training.detail":"Online training · In-person training",
"programs.arts.title":"Art and music activities",
"programs.arts.desc":"Creative art and music programmes for all children to nurture talents and abilities.",
"programs.arts.detail":"Drawing · Music and creative activities",
"programs.integration.title":"Inclusion and community interaction",
"programs.integration.desc":"Interactive inclusion activities developing social skills in a natural, safe environment.",
"programs.integration.detail":"Inclusion activities · Social interaction",
"programs.sports.title":"Horse riding and swimming",
"programs.sports.desc":"Movement activities supporting confidence, balance and social skills.",
"programs.sports.detail":"Horse riding · Swimming",
"reviews.badge":"Real stories",
"reviews.guardian":"Parent",
"reviews.prev":"Previous review",
"reviews.next":"Next review",
"reviews.trust":"Your trust is our story",
"reviews.text0":"It was the first time I had heard that music could be a form of therapy. With Dr. Nermin we saw a big difference with my daughter, wonderful care and clear attention to every detail of the sessions. Thank you for your support, patience and ongoing follow-up.",
"reviews.person0":"Mother of a child at the centre",
"reviews.text1":"Dr. Mohamed, no words of thanks can describe our appreciation. You worked wonders with my son, treated us with respect, and it is an honour to have been your student. May you be blessed for everything you offer our children.",
"reviews.person1":"Father of a child at the centre",
"reviews.text2":"I am honestly very happy with my son’s progress. I can see results at home and how much Mazen has developed over these two months. My heartfelt thanks to the whole Hand By Hand team.",
"reviews.person2":"Mother of a child at the centre",
"team.quran.name":"Quran Teacher",
"team.quran.role":"Quran sessions for all ages",
"team.quran.f0":"Quran sessions for all ages.",
"team.quran.f1":"Focus on pronunciation, articulation and vocabulary.",
"team.quran.f2":"Activities for attention, concentration and auditory memory.",
"team.quran.details":"View session details",
"team.nermin.name": "Prof. Nermin Hamdy",
"team.nermin.role": "Professor of Music Education and Music Therapy",
"team.nermin.f0": "Professor of Music Education, Faculty of Specific Education, Cairo University.",
"team.nermin.f1": "Music therapy consultant at Cairo University.",
"team.nermin.f2": "Accredited fellow of the international arts in medicine fellowship.",
"team.mohamed.name": "Dr. Mohamed Sabra",
"team.mohamed.role": "Lecturer in Mental Health and Psychological Counselling",
"team.mohamed.f0": "Practitioner in speech therapy, skills development and behaviour.",
"team.mohamed.f1": "Over 16 years of practical experience in speech, autism challenges and communication disorders.",
"team.mohamed.f2": "PhD in Education, Mental Health and Psychological Counselling, Ain Shams University.",
"team.amal.name": "Amal Yousry",
"team.amal.role": "Speech and Skills Development Specialist",
"team.amal.f0": "15 years of experience in speech, autism, learning difficulties and skills development.",
"team.amal.f1": "ABAT certified",
"team.amal.f2": "VB-MAPP certified",
"team.amal.f3": "Speech specialist accredited by the psychiatric unit at the Air Force Hospital.",
"team.profile": "View professional profile",
"team.promise": "Working together for a better future for our children",
    'a11y.skip': 'Skip to content',
    'a11y.menu': 'Open menu',

    'nav.services': 'Services',
    'nav.programs': 'Additional programmes',
    'nav.how': 'How to start',
    'nav.why': 'Why us',
    'nav.portal': 'Parent portal',
    'nav.team': 'Our team',
    'nav.faq': 'FAQ',
    'nav.contact': 'Contact',
    'nav.privacy': 'Privacy policy',

    'cta.portal': 'Parent sign-in',
    'cta.apply': 'Apply',
    'cta.applyLong': 'Start an application',
    'cta.contact': 'Contact us',

    'hero.lead': 'Together',
    'hero.title': 'we make a bigger difference',
    'hero.sub': 'A children’s skills and therapy centre in Egypt. One child per session, a written plan with measured goals, and a family that sees what happens as it happens.',

    'benefit.one': 'One child per session',
    'benefit.team': 'Specialist team',
    'benefit.measured': 'Goals that are measured',

    'portal.offline': 'The parent portal is not published yet. Until it is, we take applications by phone and WhatsApp.',

    'services.title': 'Our services',
    'services.sub': 'Eight services. A child’s plan is built from them after the assessment session.',
    'svc.speech': 'Speech and language',
    'svc.speechText': 'Articulation, understanding and expression, and alternative means of communication where they are needed.',
    'svc.ot': 'Occupational therapy',
    'svc.otText': 'Hand skills, fine motor control and independence in everyday tasks.',
    'svc.aba': 'Applied behaviour analysis (ABA)',
    'svc.abaText': 'A behavioural programme with defined goals and repeated measurement of what actually changes.',
    'svc.skills': 'Skills',
    'svc.skillsText': 'Play, attention, self-regulation and getting along with other people.',
    'svc.assess': 'Assessment',
    'svc.assessText': 'The first session, where we understand the child. The plan and the services are decided from it.',
    'svc.music': 'Music therapy',
    'svc.musicText': 'Rhythm and sound as a way into joint attention, communication and regulation.',
    'svc.sensory': 'Sensory integration',
    'svc.sensoryText': 'Measured activities for touch, balance and sensation, matched to each child.',
    'svc.academic': 'Academic and learning difficulties',
    'svc.academicText': 'Reading, writing and arithmetic, alongside what the child is studying at school.',

    'how.title': 'How to start',
    'how.sub': 'Four steps from the first contact to the first session',
    'how.s1': 'Application',
    'how.s1Text': 'You fill in a short form about you, the child, and what worries you. It does not open a file for the child; it waits for the centre to read it.',
    'how.s2': 'A call from the centre',
    'how.s2Text': 'We ring you at the time you chose, ask what we still need, and book the assessment.',
    'how.s3': 'Assessment session',
    'how.s3Text': 'A session with the child, attended by the guardian, that gives a clear picture of strengths and needs.',
    'how.s4': 'Therapy plan',
    'how.s4Text': 'A written plan with defined goals and a session schedule, reviewed on the measurements rather than on impressions.',

    'why.title': 'Why Hand By Hand',
    'why.sub': 'Four decisions about how we work, not slogans',
    'why.one': 'One child per session',
    'why.oneText': 'No group sessions and no classes. That is a choice, not a circumstance: the whole session belongs to one child, and the system that runs it was built that way.',
    'why.live': 'Live during the session — and no recording',
    'why.liveText': 'The family watches the session as it happens, from their portal. Nothing is recorded, stored or downloadable: the refusal is enforced in the database itself, not in a policy written on paper.',
    'why.plan': 'Written goals, measured regularly',
    'why.planText': 'Every child has defined goals measured at intervals, and progress reports the guardian reads in their portal.',
    'why.record': 'One complete record',
    'why.recordText': 'Every appointment, session, note and invoice in one file for the child, not scattered across notebooks.',

    'live.title': 'You watch the session as it happens — and nothing is recorded',
    'live.text': 'The stream is live only. There is no recording, no clip library, no download link, and no way to watch a session after it ends. This is not a setting that can be changed later; the system will not store a clip at all.',
    'live.p1': 'The link opens for the guardian alone and ends with the session.',
    'live.p2': 'No camera address or credential appears on any page.',
    'live.p3': 'An important moment is written as a timestamped clinical note, not saved as a clip.',
    'live.badge': 'LIVE',

    'portal.title': 'Parent portal',
    'portal.sub': 'Once a child is registered at the centre, their guardian has an account showing that child’s file and no other.',
    'portal.f1': 'Upcoming appointments',
    'portal.f2': 'Progress against the plan’s goals',
    'portal.f3': 'Therapist reports',
    'portal.f4': 'The home programme',
    'portal.f5': 'Invoices and payments',
    'portal.f6': 'The live stream during a session',
    'portal.privacy': 'A guardian sees their own child’s data only. Permission is checked on the server on every request, and editing the address bar does not change it.',

    'team.title': 'Our team',
    'team.sub': 'Specialists in speech, occupational therapy, behaviour analysis and sensory integration',
    'team.slot': 'A place for a team member',
    'team.role': 'Speciality',

    'reviews.title': 'What parents say',
    'reviews.sub': 'A place for real reviews, published with their authors’ consent',
    'reviews.slot': 'A place for a real review from a guardian.',
    'reviews.by': '— Guardian',

    'band.title': 'Start your child’s journey',
    'band.text': 'Fill in an application and we will call you to book the assessment.',

    'contact.title': 'Contact us',
    'contact.sub': 'We answer during working hours',
    'contact.phone': 'Phone',
    'contact.whatsapp': 'WhatsApp',
    'contact.email': 'Email',
    'contact.hours': 'Working hours',
    'contact.hoursValue': 'Sunday to Thursday',
    'contact.weekend': 'Closed Friday and Saturday',
    'contact.address': 'Address',
    'contact.tbd': 'Coming soon',
    'contact.map': 'Open in maps',

    'faq.title': 'Frequently asked questions',
    'faq.q1': 'Are sessions one to one?',
    'faq.a1': 'Yes. Every session is for one child. There are no group sessions.',
    'faq.q2': 'Is the live stream recorded?',
    'faq.a2': 'No. The stream is live during the session only. It is not recorded, not stored, and cannot be downloaded or watched afterwards.',
    'faq.q3': 'Who can see my child’s data?',
    'faq.a3': 'The child’s guardian, the therapists responsible for them, and centre management within the scope of their work. A guardian cannot reach another child’s data, and the server is what enforces that on every request. Every read of sensitive data is logged.',
    'faq.q4': 'What happens after I send an application?',
    'faq.a4': 'It reaches the centre for review and does not create a file for the child by itself. We call you at the time you chose to complete the details and book the assessment.',
    'faq.q5': 'Is the child’s national ID required?',
    'faq.a5': 'No. Many young children do not have one yet, and the field is entirely optional on the application.',
    'faq.q6': 'How long is a session and what does it cost?',
    'faq.a6': 'The centre sets session length and cost per service. Contact us for the current details.',

    'footer.tag': 'A children’s skills and therapy centre',
    'footer.rights': 'All rights reserved',
  };

  var STORE_KEY = 'hbh-site-lang';
  var current = 'ar';

  /* The Arabic text is read off the page on first run, so there is only
     ever one copy of it and it lives in index.html where it is edited. */
  var AR = null;

  function captureArabic() {
    AR = {};
    var nodes = document.querySelectorAll('[data-i18n]');
    for (var i = 0; i < nodes.length; i++) {
      var key = nodes[i].getAttribute('data-i18n');
      if (!(key in AR)) { AR[key] = nodes[i].textContent; }
    }
  }

  /* ------------------------------------------------------------------
   * content.texts - the console's copy for everything else on the page
   *
   * Every editable string in this document already carries a data-i18n
   * key, so the console does not need a table per section: one map keyed
   * by those same keys reaches all of them, headings and nav and footer
   * included. Shape, as the exporter writes it:
   *
   *   "texts": { "hero.title": { "ar": "...", "en": null }, ... }
   *
   * A key that is not in the map keeps the text written in index.html -
   * the same rule as every other list here. So a half-filled table is a
   * partly-managed page, never a page with holes in it.
   *
   * This runs INSIDE applyLanguage and after the built-in dictionary, so
   * a row from the console overrides the shipped copy rather than
   * fighting it, and the language toggle re-applies it on every switch.
   * ------------------------------------------------------------------ */
  function textsFor(key, lang) {
    var map = content().texts;
    if (!map || typeof map !== 'object') { return null; }
    var row = map[key];
    if (!row || typeof row !== 'object') { return null; }
    var value = lang === 'en' ? (row.en || row.ar) : (row.ar || row.en);
    return (typeof value === 'string' && value !== '') ? value : null;
  }

  function applyLanguage(lang) {
    var dict = lang === 'en' ? EN : AR;
    var nodes = document.querySelectorAll('[data-i18n]');
    for (var i = 0; i < nodes.length; i++) {
      var key = nodes[i].getAttribute('data-i18n');

      /* The console's copy wins over both dictionaries.
       *
       * AND IT MARKS THE NODE. Every other renderer here proves where a
       * string came from by REMOVING data-i18n when it writes - that is
       * how "is this from the database?" gets answered without reading
       * code. This path cannot remove the attribute, because the key is
       * how it finds the node again on the next language switch. So it
       * stamps data-src="db" instead, and the question stays answerable:
       *
       *   document.querySelectorAll('[data-src="db"]').length
       *
       * Without this the page looked 100% hardcoded to an audit while 82
       * of its strings were in fact coming from site_texts. A property
       * that cannot be observed is a property nobody can defend. */
      var managed = textsFor(key, lang);
      if (managed !== null) {
        nodes[i].textContent = managed;
        nodes[i].setAttribute('data-src', 'db');
        continue;
      }
      nodes[i].removeAttribute('data-src');

      var text = dict[key];
      // Untranslated keys keep the Arabic already on the page.
      if (typeof text === 'string') { nodes[i].textContent = text; }
      else if (lang === 'en' && AR[key]) { nodes[i].textContent = AR[key]; }
    }

    // Text from content.js is not in the EN dictionary, so the loop
    // above cannot translate it - those parts are rebuilt instead.
    // (setAddress is inside renderContent.)
    renderContent(lang);

    var html = document.documentElement;
    html.setAttribute('lang', lang === 'en' ? 'en' : 'ar');
    html.setAttribute('dir', lang === 'en' ? 'ltr' : 'rtl');

    var label = document.getElementById('langToggleText');
    if (label) { label.textContent = lang === 'en' ? 'ع' : 'EN'; }

    current = lang;
    try { localStorage.setItem(STORE_KEY, lang); } catch (e) { /* private mode */ }
  }

  function wireLanguage() {
    captureArabic();
    var toggle = document.getElementById('langToggle');

    /* The toggle is hidden or gone: the page is Arabic only.
     *
     * AND THE STORED CHOICE IS CLEARED, which is the part worth keeping.
     * Anyone who picked English before it was hidden has 'en' in their
     * browser; without this they would land in English on a page with no
     * way back to Arabic - trapped by a preference they can no longer
     * reach. Hiding a control means retiring the state it wrote. */
    if (!toggle || toggle.hidden) {
      try { localStorage.removeItem(STORE_KEY); } catch (e) { /* private mode */ }
      applyLanguage('ar');
      return;
    }

    var stored = null;
    try { stored = localStorage.getItem(STORE_KEY); } catch (e) { /* private mode */ }
    if (stored === 'en') { applyLanguage('en'); }

    toggle.addEventListener('click', function () {
      applyLanguage(current === 'en' ? 'ar' : 'en');
    });
  }

  /* ------------------------------------------------------------------ */

  function wireMenu() {
    var btn = document.getElementById('menuBtn');
    var nav = document.getElementById('nav');
    if (!btn || !nav) { return; }

    function close() {
      nav.classList.remove('is-open');
      btn.setAttribute('aria-expanded', 'false');
    }

    btn.addEventListener('click', function () {
      var open = nav.classList.toggle('is-open');
      btn.setAttribute('aria-expanded', open ? 'true' : 'false');
    });

    nav.addEventListener('click', function (event) {
      if (event.target.closest('a')) { close(); }
    });

    document.addEventListener('keydown', function (event) {
      if (event.key === 'Escape') { close(); }
    });
  }

  /* Marks the nav link for the section currently on screen. aria-current
     rather than a class, so it is announced and not only coloured. */
  function wireSectionHighlight() {
    if (!('IntersectionObserver' in window)) { return; }
    var links = {};
    var navLinks = document.querySelectorAll('.nav a[href^="#"]');
    var targets = [];
    var i;

    for (i = 0; i < navLinks.length; i++) {
      var id = navLinks[i].getAttribute('href').slice(1);
      var section = document.getElementById(id);
      if (section) { links[id] = navLinks[i]; targets.push(section); }
    }

    var observer = new IntersectionObserver(function (entries) {
      for (var j = 0; j < entries.length; j++) {
        var link = links[entries[j].target.id];
        if (!link) { continue; }
        if (entries[j].isIntersecting) { link.setAttribute('aria-current', 'true'); }
        else { link.removeAttribute('aria-current'); }
      }
    }, { rootMargin: '-45% 0px -50% 0px' });

    for (i = 0; i < targets.length; i++) { observer.observe(targets[i]); }
  }
  /* ------------------------------------------------------------------
   * Content from content.js
   *
   * That file is GENERATED by scripts/site-export.sh out of the staff
   * console's tables, and its shape is the exporter's, not this file's.
   * Keys are camelCase and each list arrives already ordered, so nothing
   * here re-sorts:
   *
   *   contact  { phone, whatsapp, email, addressAr, addressEn, mapUrl,
   *              hoursAr, hoursEn, weekendAr, weekendEn } or null
   *   faq      [ { id, questionAr, questionEn, answerAr, answerEn } ]
   *   team     [ { id, nameAr, nameEn, roleAr, roleEn } ]
   *   reviews  [ { id, displayName, bodyAr, bodyEn } ]
   *   sections { code: visible }
   *
   * CONSENT IS NOT CHECKED HERE, and that is not an omission. A review
   * or a photograph without a recorded consent cannot be written as
   * PUBLISHED in the database, and the exporter emits published rows
   * only. Two barriers, both upstream. A third one here would be a
   * third copy of the rule, and the copy that drifts is the one nobody
   * tests.
   *
   * THE EMPTY-LIST RULE, which matters more than it looks: an empty or
   * missing list means KEEP THE MARKUP IN index.html, never "empty the
   * section". The tables start empty - the first export ran against
   * empty tables and produced exactly that - and a renderer that took it
   * literally would blank a working site the first time somebody ran the
   * exporter, with no error anywhere. Hiding a section takes an explicit
   * `sections.<code> === false`, which is somebody saying so.
   * ------------------------------------------------------------------ */
  function content() {
    var c = window.HBH_SITE_CONTENT;
    return (c && typeof c === 'object') ? c : {};
  }

  function list(name) {
    var value = content()[name];
    return (Array.isArray(value) && value.length) ? value : null;
  }

  /* Arabic is the page; English falls back to it. An untranslated row
     reads in the wrong language, which beats reading as a blank card. */
  function pick(row, base, lang) {
    var en = row[base + 'En'];
    var ar = row[base + 'Ar'];
    return lang === 'en' ? (en || ar || '') : (ar || en || '');
  }

  function svgTag(tag) {
    return document.createElementNS('http://www.w3.org/2000/svg', tag);
  }

  /* --- sections the console switched off ---------------------------- */

  function applySectionVisibility() {
    var map = content().sections;
    if (!map || typeof map !== 'object') { return; }
    for (var code in map) {
      if (!Object.prototype.hasOwnProperty.call(map, code)) { continue; }
      var section = document.getElementById(code);
      if (section) { section.hidden = (map[code] === false); }
    }
  }

  /* --- contact ------------------------------------------------------ */

  /* Overrides config.js field by field. config.js is what whoever
     deployed the files set; this is what the centre changed afterwards
     without needing them. A null or missing value leaves config.js
     alone, so a half-filled row cannot blank a working phone number. */
  function mergeContact() {
    var c = content().contact;
    if (!c || typeof c !== 'object') { return; }
    var keys = ['phone', 'landline', 'whatsapp', 'email',
                'addressAr', 'addressEn', 'mapUrl'];
    for (var i = 0; i < keys.length; i++) {
      if (c[keys[i]]) { CONFIG[keys[i]] = c[keys[i]]; }
    }
  }

  function renderHours(lang) {
    var c = content().contact;
    if (!c) { return; }
    var hours = lang === 'en' ? (c.hoursEn || c.hoursAr) : (c.hoursAr || c.hoursEn);
    var weekend = lang === 'en' ? (c.weekendEn || c.weekendAr) : (c.weekendAr || c.weekendEn);
    var hoursEl = document.querySelector('[data-i18n="contact.hoursValue"]');
    var weekendEl = document.querySelector('[data-i18n="contact.weekend"]');
    if (hours && hoursEl) { hoursEl.textContent = hours; hoursEl.removeAttribute('data-i18n'); }
    if (weekend && weekendEl) { weekendEl.textContent = weekend.trim() === 'الجمعة' ? 'الجمعة إجازة' : weekend; weekendEl.removeAttribute('data-i18n'); }
  }

  /* --- reviews ------------------------------------------------------ */

  function reviewCard(review, lang) {
    var article = document.createElement('article');
    article.className = 'review-card';

    var quote = document.createElement('span');
    quote.className = 'quote';
    quote.setAttribute('aria-hidden', 'true');
    quote.textContent = '”';
    article.appendChild(quote);

    // textContent, not innerHTML: this is a sentence a parent typed, and
    // an angle bracket in it has to stay a character on a public page.
    var body = document.createElement('p');
    body.textContent = pick(review, 'body', lang);
    article.appendChild(body);

    /* Stars only when the row carries a rating. hbh.site_reviews.rating
       is nullable on purpose - the written cards all showed five stars,
       and a row with no rating must show none rather than inherit that
       five from the markup it replaced. */
    var rating = Math.round(Number(review.rating));
    if (rating >= 1 && rating <= 5) {
      var stars = document.createElement('div');
      stars.className = 'review-stars';
      stars.setAttribute('aria-label', lang === 'en' ? rating + ' out of 5' : rating + ' من 5');
      for (var s = 0; s < rating; s++) {
        var star = svgTag('svg');
        star.setAttribute('viewBox', '0 0 24 24');
        star.setAttribute('aria-hidden', 'true');
        var tip = svgTag('path');
        tip.setAttribute('d', 'm12 2 3 6 7 1-5 5 1 7-6-3-6 3 1-7-5-5 7-1z');
        star.appendChild(tip);
        stars.appendChild(star);
      }
      article.appendChild(stars);
    }

    var author = document.createElement('div');
    author.className = 'review-author';

    var avatar = document.createElement('span');
    avatar.className = 'review-avatar';
    var av = svgTag('svg');
    av.setAttribute('viewBox', '0 0 56 56');
    av.setAttribute('aria-hidden', 'true');
    var ring = svgTag('circle');
    ring.setAttribute('cx', '28'); ring.setAttribute('cy', '28'); ring.setAttribute('r', '28');
    ring.setAttribute('fill', 'currentColor'); ring.setAttribute('opacity', '.13');
    var shoulders = svgTag('path');
    shoulders.setAttribute('d', 'M10 52c0-14 7-22 18-22s18 8 18 22');
    shoulders.setAttribute('fill', 'currentColor');
    av.appendChild(ring); av.appendChild(shoulders);
    avatar.appendChild(av);
    author.appendChild(avatar);

    var names = document.createElement('div');
    var role = document.createElement('strong');
    role.textContent = lang === 'en' ? 'Parent' : 'ولي أمر';
    names.appendChild(role);
    /* displayName is chosen by the author, not derived from their file.
       Shown exactly as given, and never translated. */
    if (review.displayName) {
      var who = document.createElement('small');
      who.textContent = review.displayName;
      names.appendChild(who);
    }
    author.appendChild(names);
    article.appendChild(author);
    return article;
  }

  function renderReviews(lang) {
    var reviews = list('reviews');
    if (!reviews) { return; }

    var section = document.getElementById('reviews');
    var grid = section && section.querySelector('.review-grid');
    if (!grid) { return; }

    grid.textContent = '';
    for (var i = 0; i < reviews.length; i++) {
      grid.appendChild(reviewCard(reviews[i], lang));
    }

    /* Dots follow the real count. They were three <i> in the markup
       against a hardcoded `% 3`, so the first review the centre added
       would have moved the highlight onto a dot that was not there. */
    var dots = section.querySelector('.review-dots');
    if (dots) {
      dots.textContent = '';
      for (var d = 0; d < reviews.length; d++) {
        var dot = document.createElement('i');
        if (d === 0) { dot.className = 'active'; }
        dots.appendChild(dot);
      }
      dots.hidden = reviews.length < 2;
    }
    var arrows = section.querySelectorAll('[data-review-step]');
    for (var a = 0; a < arrows.length; a++) { arrows[a].hidden = reviews.length < 2; }
  }
  /* --- team --------------------------------------------------------- */

  /* A full card now: name, role, photograph, qualification lines and the
     profile link all come from the row.

     The FIRST card in the markup is the template. Cloning it rather than
     building the card from scratch keeps the decorative parts - the art
     shape, the badge, the tick icon on each fact - in one place, the
     document, where a designer can change them without touching this
     file.

     WHAT CLONING DOES NOT CARRY is the per-person crop. reference.css
     positions each portrait by hand (.member-nermin .member-portrait img
     is 430% wide at -31%/-62%), because these are promotional posters
     rather than head-and-shoulders portraits, and each needs its own
     framing. A row from the console cannot know that, so a cloned card
     falls back to plain `cover`. It is worth knowing before somebody
     uploads a poster and wonders why the face sits off-centre. */
  function renderTeam(lang) {
    var team = list('team');
    if (!team) { return; }

    var grid = document.getElementById('teamGrid');
    if (!grid) { return; }

    var template = grid.querySelector('.member-card');
    if (!template) { return; }
    if (!grid.__template) { grid.__template = template.cloneNode(true); }

    var authored = grid.querySelectorAll('.member-card');
    var i;

    /* Reuse the authored cards while they last - they carry the crop
       rules above - and clone for anything past them. */
    for (i = authored.length; i < team.length; i++) {
      var extra = grid.__template.cloneNode(true);
      extra.className = 'member-card';        // drop the .member-<name> crop
      grid.appendChild(extra);
    }

    var cards = grid.querySelectorAll('.member-card');
    for (i = 0; i < cards.length; i++) {
      if (i >= team.length) { cards[i].hidden = true; continue; }
      cards[i].hidden = false;
      fillMemberCard(cards[i], team[i], lang);
    }
  }

  /* team-media.js keys its lists by the .member-<name> class the card
     was authored with. Read, never required: the file may not be there,
     and this returns false rather than throwing when it is not. */
  function hasGalleryMedia(card) {
    var media = window.HBH_TEAM_MEDIA;
    if (!media) { return false; }
    var classes = String(card.className).split(/\s+/);
    for (var i = 0; i < classes.length; i++) {
      var key = classes[i].indexOf('member-') === 0 ? classes[i].slice(7) : '';
      if (key && Array.isArray(media[key]) && media[key].length) { return true; }
    }
    return false;
  }

  function fillMemberCard(card, member, lang) {
    var name = card.querySelector('h3');
    if (name) {
      name.textContent = pick(member, 'name', lang);
      name.removeAttribute('data-i18n');
    }

    var role = card.querySelector('.member-role');
    if (role) {
      role.textContent = pick(member, 'role', lang);
      role.removeAttribute('data-i18n');
    }

    /* The photograph. A row without one keeps whatever the card had,
       rather than blanking the portrait: a card with a name and an empty
       hole reads as broken, and the authored image is at worst the wrong
       person's - which is visible and gets fixed. */
    var img = card.querySelector('.member-portrait img');
    if (img && member.photoPath) {
      img.setAttribute('src', member.photoPath);
      card.classList.toggle('member-custom-portrait', !/^assets\/team-(nermin|mohamed|amal|quran)\.jpeg$/.test(member.photoPath));
      /* The alt text is the person's name, because that is what the
         picture is of. */
      img.setAttribute('alt', pick(member, 'name', lang));
    }

    /* Qualifications, one row each. They are claims about a named
       professional's credentials published under the centre's name, so
       they are rebuilt from the data exactly - never merged with, or
       appended to, whatever the card was showing before. */
    var facts = card.querySelector('.member-facts');
    if (facts && Array.isArray(member.facts)) {
      var tick = facts.querySelector('li svg');
      facts.textContent = '';
      for (var f = 0; f < member.facts.length; f++) {
        var li = document.createElement('li');
        if (tick) { li.appendChild(tick.cloneNode(true)); }
        var span = document.createElement('span');
        span.textContent = pick(member.facts[f], 'text', lang);
        li.appendChild(span);
        facts.appendChild(li);
      }
    }

    renderCertificates(card, member, lang);
    renderIntroVideo(card, member, lang);

    var profile = card.querySelector('.member-profile');
    if (profile) {
      if (member.profileHref) {
        profile.setAttribute('href', member.profileHref);
        profile.hidden = false;
      } else if (hasGalleryMedia(card)) {
        /* No stored document, but team-gallery.js has media for this
           card and opens it from this button. Hiding it here because the
           column is null would remove a control that works. The href is
           left off: the gallery reads its list from HBH_TEAM_MEDIA and
           calls preventDefault, and an href would only matter if it
           fell back to it - which is the case this branch rules out. */
        profile.hidden = false;
      } else {
        /* No document to open. The link is removed rather than left
           pointing at the portrait: "عرض الملف المهني" that opens a
           photograph is a label that promises more than it delivers. */
        profile.hidden = true;
      }
    }
  }

  /* --- certificates -------------------------------------------------

     A strip of thumbnails under the qualification lines. Each opens the
     full scan in a dialog.

     WHAT THESE ARE: photographs of a named professional's certificates,
     published on a public page by the centre's decision. Two things
     follow from that and are implemented rather than left to a policy
     note:

       They render only for a member whose row carries them. There is no
       "guess the file name from the member id" path - a scan appears
       because somebody attached it to that person, not because a file
       happened to be sitting in assets/ under a matching name.

       The caption is the document's own description, never the person's
       name. "شهادة ABAT" and not "شهادات آمال يسري": the heading above
       already says whose card this is, and repeating the name into every
       image alt writes it into places that are read out of context.

     Egyptian certificates commonly carry a national ID and an address.
     Cropping them is the centre's step before upload, not something this
     file can do - but the dialog deliberately shows the image at its own
     size rather than zoomed, so nothing is enlarged that was not meant
     to be read.
     ------------------------------------------------------------------ */
  function renderCertificates(card, member, lang) {
    var certs = Array.isArray(member.certificates) ? member.certificates : [];

    var strip = card.querySelector('.member-certs');
    if (!strip) {
      if (!certs.length) { return; }
      strip = document.createElement('div');
      strip.className = 'member-certs';
      var facts = card.querySelector('.member-facts');
      if (facts && facts.parentNode) {
        facts.parentNode.insertBefore(strip, facts.nextSibling);
      } else {
        card.appendChild(strip);
      }
    }

    strip.textContent = '';
    if (!certs.length) { strip.hidden = true; return; }
    strip.hidden = false;

    var label = document.createElement('span');
    label.className = 'member-certs-label';
    label.textContent = lang === 'en' ? 'Certificates' : 'الشهادات';
    strip.appendChild(label);

    for (var i = 0; i < certs.length; i++) {
      var cert = certs[i];
      if (!cert || !cert.path) { continue; }
      var caption = pick(cert, 'caption', lang);

      /* A button and not a link: it opens a dialog on this page. A link
         would promise a new page and, middle-clicked, give a bare image
         with no caption and no context. */
      var button = document.createElement('button');
      button.type = 'button';
      button.className = 'member-cert';
      button.setAttribute('data-cert-src', cert.path);
      button.setAttribute('data-cert-caption', caption || '');
      button.setAttribute('aria-label', caption || (lang === 'en' ? 'Certificate' : 'شهادة'));

      var thumb = document.createElement('img');
      thumb.setAttribute('src', cert.path);
      thumb.setAttribute('loading', 'lazy');
      /* Empty alt: the button's aria-label already names it, and a
         second copy makes a screen reader say it twice. */
      thumb.setAttribute('alt', '');
      button.appendChild(thumb);
      strip.appendChild(button);
    }
  }

  /* One dialog for the whole page, created on first use and reused.
     Delegated click, so cards rebuilt by a language switch keep working
     without rebinding anything. */
  var certDialog = null;

  /* --- the member's introduction video -------------------------------

     A short film of a member of staff introducing themselves. It is
     rendered on the team card and NOWHERE ELSE, and in particular never
     in or beside the `live` section.

     That is not squeamishness. The centre streams a session to the
     family live and never records it - no recordings table, no clip
     library, and the database refuses a video file - and the `live`
     section on this page says so in as many words. A video player two
     screens away from that sentence is how a visitor concludes the
     sentence is marketing. So: this player sits on a person's card,
     opens from a button that says whose introduction it is, and carries
     no relationship to a child or a session because there is no field
     for one.

     preload="none" and no autoplay: the file is only fetched when
     somebody asks for it, which also keeps the page cheap on a phone.
     ------------------------------------------------------------------ */
  function renderIntroVideo(card, member, lang) {
    var video = member.introVideo;
    var existing = card.querySelector('.member-video');

    if (!video || !video.path) {
      if (existing) { existing.hidden = true; }
      return;
    }

    var button = existing;
    if (!button) {
      button = document.createElement('button');
      button.type = 'button';
      button.className = 'member-video';
      var icon = svgTag('svg');
      icon.setAttribute('viewBox', '0 0 24 24');
      icon.setAttribute('aria-hidden', 'true');
      var tri = svgTag('path');
      tri.setAttribute('d', 'M9 7.5v9l7.5-4.5z');
      var ring = svgTag('circle');
      ring.setAttribute('cx', '12'); ring.setAttribute('cy', '12'); ring.setAttribute('r', '9.2');
      icon.appendChild(ring); icon.appendChild(tri);
      button.appendChild(icon);
      button.appendChild(document.createElement('span'));

      var facts = card.querySelector('.member-facts');
      if (facts && facts.parentNode) {
        facts.parentNode.insertBefore(button, facts.nextSibling);
      } else {
        card.appendChild(button);
      }
    }

    button.hidden = false;
    /* The label names the person, because a bare "شاهد الفيديو" on a page
       that also talks about session streaming is exactly the ambiguity
       worth avoiding. */
    var who = pick(member, 'name', lang);
    var label = lang === 'en' ? 'Introduction — ' + who : 'تعريف ' + who;
    button.querySelector('span').textContent = label;
    button.setAttribute('data-video-src', video.path);
    button.setAttribute('data-video-poster', video.poster || member.photoPath || '');
    button.setAttribute('data-video-caption', pick(video, 'caption', lang) || label);
  }

  /* One dialog, reused for a scan or a film. */
  function ensureDialog() {
    if (certDialog) { return certDialog; }

    certDialog = document.createElement('dialog');
    certDialog.className = 'cert-dialog';

    var close = document.createElement('button');
    close.type = 'button';
    close.className = 'cert-close';
    close.setAttribute('aria-label', 'إغلاق / Close');
    close.textContent = '×';
    close.addEventListener('click', function () { closeDialog(); });

    var img = document.createElement('img');
    img.className = 'cert-image';

    var film = document.createElement('video');
    film.className = 'cert-video';
    film.setAttribute('controls', '');
    film.setAttribute('preload', 'none');
    film.setAttribute('playsinline', '');

    var cap = document.createElement('p');
    cap.className = 'cert-caption';

    certDialog.appendChild(close);
    certDialog.appendChild(img);
    certDialog.appendChild(film);
    certDialog.appendChild(cap);
    document.body.appendChild(certDialog);

    /* Clicking the backdrop closes it. The dialog element itself is the
       backdrop's hit area, so this compares the target. */
    certDialog.addEventListener('click', function (event) {
      if (event.target === certDialog) { closeDialog(); }
    });

    /* Escape closes the dialog without going through either handler
       above, and fires `cancel` before it does. */
    certDialog.addEventListener('cancel', function () { stopFilm(); });

    /* And `close` as well, for anything that closes it by another route.
       NOT relied on: this event did not fire at all in the browser this
       was tested in, which is why the teardown is called explicitly from
       every path rather than hung on it. A video whose src survives its
       dialog keeps downloading, and on a phone that is somebody's data. */
    certDialog.addEventListener('close', function () { stopFilm(); });

    return certDialog;
  }

  /* Stops the film and lets go of the file. Idempotent, so calling it
     from every close path costs nothing. */
  function stopFilm() {
    if (!certDialog) { return; }
    var film = certDialog.querySelector('.cert-video');
    if (!film) { return; }
    film.pause();
    if (film.hasAttribute('src')) {
      film.removeAttribute('src');
      film.load();          // releases the connection, not just the element
    }
  }

  function closeDialog() {
    stopFilm();
    if (certDialog && certDialog.open) { certDialog.close(); }
  }

  function openMedia(kind, src, caption, poster) {
    var dialog = ensureDialog();
    var img = dialog.querySelector('.cert-image');
    var film = dialog.querySelector('.cert-video');

    if (kind === 'video') {
      img.hidden = true;
      film.hidden = false;
      film.setAttribute('src', src);
      if (poster) { film.setAttribute('poster', poster); }
      else { film.removeAttribute('poster'); }
    } else {
      film.hidden = true;
      film.pause();
      img.hidden = false;
      img.setAttribute('src', src);
      img.setAttribute('alt', caption || '');
    }

    var cap = dialog.querySelector('.cert-caption');
    cap.textContent = caption || '';
    cap.hidden = !caption;

    /* showModal gives focus trapping and Escape for free. Older browsers
       without <dialog> fall back to a new tab, which is worse but not
       broken. */
    if (typeof dialog.showModal === 'function') { dialog.showModal(); }
    else { window.open(src, '_blank', 'noopener'); }
  }

  document.addEventListener('click', function (event) {
    if (!event.target.closest) { return; }

    var cert = event.target.closest('.member-cert');
    if (cert) {
      openMedia('image', cert.getAttribute('data-cert-src'), cert.getAttribute('data-cert-caption'));
      return;
    }

    var film = event.target.closest('.member-video');
    if (film) {
      openMedia('video', film.getAttribute('data-video-src'),
                film.getAttribute('data-video-caption'),
                film.getAttribute('data-video-poster'));
    }
  });

  /* --- team carousel -------------------------------------------------

     The arrows scroll the track by one card. They exist because the
     number of members is whatever the console publishes, ordered by
     sort_order, and four is no longer a ceiling.

     THE ARROWS HIDE THEMSELVES when everything already fits. A control
     that does nothing is worse than no control: it reads as broken. So
     the state is recomputed after every render, on resize, and as the
     track scrolls - and the far edge disables its own arrow rather than
     leaving one that no longer moves anything.

     DIRECTION: in RTL the end of the track is at NEGATIVE scrollLeft, so
     "next" is a negative delta. Reading the direction off the document
     rather than assuming keeps this working across the language toggle,
     which flips dir in place without reloading.
     ------------------------------------------------------------------ */
  function teamStep() {
    var grid = document.getElementById('teamGrid');
    if (!grid) { return 0; }
    var card = grid.querySelector('.member-card:not([hidden])');
    if (!card) { return 0; }
    var gap = parseFloat(getComputedStyle(grid).columnGap) || 0;
    return Math.round(card.getBoundingClientRect().width + gap);
  }

  function updateTeamArrows() {
    var grid = document.getElementById('teamGrid');
    var section = document.getElementById('team');
    if (!grid || !section) { return; }

    var options = (window.HBH_SITE || {}).teamCarousel || {};
    var narrow = window.innerWidth <= 600;
    var medium = window.innerWidth <= 1100;
    var requested = Number(narrow ? options.mobile : medium ? options.tablet : options.desktop);
    var fallback = narrow ? 1 : medium ? 2 : 5;
    var count = grid.querySelectorAll('.member-card:not([hidden])').length;
    var columns = Math.max(1, Math.min(narrow ? 2 : medium ? 3 : 5, count || 1, Math.floor(requested) || fallback));
    for (var n = 1; n <= 5; n++) { grid.classList.toggle('team-cols-' + n, n === columns); }
    var prev = section.querySelector('.team-prev');
    var next = section.querySelector('.team-next');
    if (!prev || !next) { return; }

    /* A 1px tolerance: browsers report fractional widths, and an
       overflow of half a pixel is not an overflow. */
    var scrollable = grid.scrollWidth - grid.clientWidth > 1;
    prev.hidden = !scrollable;
    next.hidden = !scrollable;
    if (!scrollable) { return; }

    var rtl = document.documentElement.getAttribute('dir') === 'rtl';
    var pos = Math.abs(grid.scrollLeft);
    var max = grid.scrollWidth - grid.clientWidth;

    // `prev` walks back toward the start, whichever side that is.
    prev.disabled = pos <= 1;
    next.disabled = pos >= max - 1;
    void rtl;   // direction is handled in the scroll, not here
  }

  function wireTeamCarousel() {
    var section = document.getElementById('team');
    var grid = document.getElementById('teamGrid');
    if (!section || !grid) { return; }

    section.addEventListener('click', function (event) {
      var button = event.target.closest ? event.target.closest('[data-team-step]') : null;
      if (!button) { return; }
      var step = Number(button.getAttribute('data-team-step')) || 0;
      var rtl = document.documentElement.getAttribute('dir') === 'rtl';
      grid.scrollBy({ left: step * teamStep() * (rtl ? -1 : 1), behavior: 'smooth' });
    });

    grid.addEventListener('scroll', updateTeamArrows);
    window.addEventListener('resize', updateTeamArrows);
    updateTeamArrows();
  }

  /* --- programmes --------------------------------------------------- */

  /* Same template-clone approach as the team, and for the same reason:
     .program-N in reference.css carries a tint and a crop offset into
     one shared artwork image, and those belong in the stylesheet.

     The class cycles over the eight the stylesheet defines, so a ninth
     programme repeats the first one's colour instead of rendering
     untinted. */
  var PROGRAM_VARIANTS = 8;

  function renderPrograms(lang) {
    var programs = list('programs');
    if (!programs) { return; }

    var grid = document.querySelector('.program-grid');
    if (!grid) { return; }

    var template = grid.querySelector('.program-card');
    if (!template) { return; }
    if (!grid.__template) { grid.__template = template.cloneNode(true); }

    for (var i = grid.querySelectorAll('.program-card').length; i < programs.length; i++) {
      grid.appendChild(grid.__template.cloneNode(true));
    }

    var cards = grid.querySelectorAll('.program-card');
    for (var j = 0; j < cards.length; j++) {
      if (j >= programs.length) { cards[j].hidden = true; continue; }
      cards[j].hidden = false;
      cards[j].className = 'program-card program-' + (j % PROGRAM_VARIANTS);
      fillProgramCard(cards[j], programs[j], lang);
    }
  }

  function fillProgramCard(card, program, lang) {
    var title = card.querySelector('h3');
    if (title) {
      title.textContent = pick(program, 'title', lang);
      title.removeAttribute('data-i18n');
    }

    var desc = card.querySelector('p');
    if (desc) {
      desc.textContent = pick(program, 'desc', lang);
      desc.removeAttribute('data-i18n');
    }

    /* The expandable detail. A programme with no detail loses the
       disclosure entirely rather than opening onto an empty panel. */
    var details = card.querySelector('details');
    var detail = card.querySelector('.program-detail p');
    var text = pick(program, 'detail', lang);
    if (details) {
      if (text) {
        details.hidden = false;
        if (detail) { detail.textContent = text; detail.removeAttribute('data-i18n'); }
      } else {
        details.hidden = true;
      }
    }
  }

  /* --- services ------------------------------------------------------

     `titleAr` here comes from hbh.services - the booking catalogue - and
     not from the marketing table. That is the point of the design: the
     site cannot name a service the centre does not actually offer, and
     the row is refused by the database if it tries.

     ICONS ARE NOT DATA. The eight drawings are inline SVG in
     index.html, so `iconKey` selects one of them rather than carrying
     one. Accepted values are the classes already on the page - i1..i8 -
     and anything else falls back to the icon in that position, because
     a service with the wrong picture still reads, while a service with
     no picture looks broken.
     ------------------------------------------------------------------ */
  function serviceIcons(grid) {
    if (grid.__icons) { return grid.__icons; }
    var map = {};
    var order = [];
    var spans = grid.querySelectorAll('.service-icon');
    for (var i = 0; i < spans.length; i++) {
      var key = String(spans[i].className).split(/\s+/).filter(function (c) {
        return /^i\d+$/.test(c);
      })[0];
      var clone = spans[i].cloneNode(true);
      order.push(clone);
      if (key) { map[key] = clone; }
    }
    grid.__icons = { byKey: map, byIndex: order };
    return grid.__icons;
  }

  function renderServices(lang) {
    var services = list('services');
    if (!services) { return; }

    var grid = document.querySelector('.services-grid');
    if (!grid) { return; }

    var icons = serviceIcons(grid);
    var template = grid.querySelector('article');
    if (!template) { return; }
    if (!grid.__template) { grid.__template = template.cloneNode(true); }

    for (var i = grid.querySelectorAll('article').length; i < services.length; i++) {
      grid.appendChild(grid.__template.cloneNode(true));
    }

    var cards = grid.querySelectorAll('article');
    for (var j = 0; j < cards.length; j++) {
      if (j >= services.length) { cards[j].hidden = true; continue; }
      cards[j].hidden = false;
      fillServiceCard(cards[j], services[j], icons, j, lang);
    }
  }

  function fillServiceCard(card, service, icons, index, lang) {
    var title = card.querySelector('h3');
    if (title) {
      title.textContent = pick(service, 'title', lang);
      title.removeAttribute('data-i18n');
    }

    var blurb = card.querySelector('p');
    if (blurb) {
      blurb.textContent = pick(service, 'blurb', lang);
      blurb.removeAttribute('data-i18n');
    }

    var wanted = icons.byKey[service.iconKey] || icons.byIndex[index % icons.byIndex.length];
    var current = card.querySelector('.service-icon');
    if (wanted && current && current.parentNode) {
      current.parentNode.replaceChild(wanted.cloneNode(true), current);
    }
  }

  /* --- faq ---------------------------------------------------------- */

  function renderFaq(lang) {
    var faq = list('faq');
    if (!faq) { return; }

    var wrap = document.querySelector('.faq-list');
    if (!wrap) { return; }

    wrap.textContent = '';
    for (var i = 0; i < faq.length; i++) {
      var details = document.createElement('details');
      var summary = document.createElement('summary');
      summary.textContent = pick(faq[i], 'question', lang);
      var answer = document.createElement('p');
      answer.textContent = pick(faq[i], 'answer', lang);
      details.appendChild(summary);
      details.appendChild(answer);
      wrap.appendChild(details);
    }
  }

  /* Everything content.js drives, in one call, so the first paint and
     the language toggle go through the same path. */
  function renderContent(lang) {
    applySectionVisibility();
    renderReviews(lang);
    renderTeam(lang);
    updateTeamArrows();
    renderPrograms(lang);
    renderServices(lang);
    renderFaq(lang);
    renderHours(lang);
    renderArrival(lang);
    setAddress(lang);
  }

  mergeContact();
  applySectionVisibility();

  wirePortalLinks();
  wireContact();
  wireLanguage();
  wireMenu();
  wireSectionHighlight();
  wireTeamCarousel();

  renderContent(document.documentElement.lang === 'en' ? 'en' : 'ar');
})();

/* Review carousel.
 *
 * The step count is read from the DOM every click rather than baked in.
 * It used to be a literal `% 3` against three <i> dots written into the
 * markup, so the first review the centre added would have moved the
 * highlight onto a dot that did not exist - and adding a review is the
 * whole point of putting them in content.js. */
(function () {
  var section = document.getElementById('reviews');
  if (!section) { return; }
  var grid = section.querySelector('.review-grid');
  if (!grid) { return; }

  var position = 0;

  function step(direction) {
    var count = grid.children.length;
    if (count < 2) { return; }

    if (direction > 0) { grid.appendChild(grid.firstElementChild); }
    else { grid.prepend(grid.lastElementChild); }

    position = (position + direction + count) % count;

    var dots = section.querySelectorAll('.review-dots i');
    for (var i = 0; i < dots.length; i++) {
      dots[i].classList.toggle('active', i === position);
    }
    grid.scrollLeft = 0;
  }

  // Delegated, because renderReviews replaces the arrows' siblings and a
  // listener bound to a card would go with them.
  section.addEventListener('click', function (event) {
    var button = event.target.closest('[data-review-step]');
    if (button) { step(Number(button.getAttribute('data-review-step'))); }
  });
})();
