// =====================================================================
// Serve one built Angular application and proxy its API calls, on a
// host where nginx cannot be configured without root.
//
//   node web.native.mjs <dist/browser dir> <port> <api port>
//
// This exists because deploy/server/hbh.nginx.conf needs a root install
// and this account has none. It does the three things that file does
// and nothing else, so that swapping back to nginx changes no
// behaviour the browser can see:
//
//   1. static files, with the hashed bundles cached and index.html not
//   2. any unknown path returns index.html - the Angular router owns it
//   3. /api/ and /healthz reach the service on the SAME origin, which
//      is what an empty apiBaseUrl in the build requires
//
// No dependencies on purpose: node's own http module is on the server
// already, and a package fetched at deploy time is a moving part that
// would have to be trusted on a machine holding a clinical record.
// =====================================================================
import http from 'node:http';
import https from 'node:https';
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(process.argv[2] ?? '.');
const PORT = Number(process.argv[3] ?? 8091);
const API = Number(process.argv[4] ?? 8090);
const TLS_PORT = Number(process.argv[5] ?? 0);
const TLS_DIR = process.argv[6] ?? '';

// Does an unknown path belong to a client-side router?
//
// For the two Angular apps, yes: /children/7 is a route the server has
// never heard of and index.html is the correct answer. For the plain
// site it is the opposite - it has real pages, and answering 200 with
// the homepage for anything missing hides every broken reference in it.
// That is not hypothetical: assets/team-introduction.mp4 is referenced
// by the site, absent from the directory, and answered 200 with 49KB of
// HTML. A browser asks for a video, is handed a web page, and shows
// nothing - with no error anywhere to say why.
const MODE = process.argv[7] ?? 'spa';
const SPA = MODE !== 'static';

// Which API calls this origin will carry.
//
//   spa     everything - the portal and console talk to the whole API
//   static  nothing - the public site needs no API at all
//   apply   ONE call, by exact method and path
//
// 'apply' exists so hbhskills.com can offer the enrolment form without
// offering the sign-in behind it. POST /api/v1/enrolments is the only
// anonymous route in the service - server.go says so where it is
// registered - and every other path answers 404 here, including
// /api/v1/auth/otp/request. That endpoint is why the portal is not
// published: OTP_ECHO returns the login code in the response body.
//
// The list is an ALLOWLIST and not a set of blocked paths, because the
// leak this file already caused was a proxy that carried everything by
// default. A rule that has to name what it permits cannot be widened by
// forgetting something.
const ALLOWED = MODE === 'apply'
  ? [{ method: 'POST', path: '/api/v1/enrolments' }]
  : null;

function apiAllowed(req, url) {
  if (MODE === 'static') return false;
  if (MODE === 'spa') return true;
  return ALLOWED.some((r) => r.method === req.method && r.path === url);
}

// Reaching the public interface takes an explicit variable, and neither
// has a default. Publishing is the one mistake here that cannot be taken
// back once somebody has looked: a wrong bind address produces no error,
// no log line and no visible difference - the page simply answers people
// it was never meant to.
//
// The two are separate variables rather than one, because they are not
// the same decision. HBH_PUBLIC serves TLS. HBH_PUBLIC_HTTP serves the
// same pages in the clear: the login code, the bearer token and every
// answer about a child cross the network readable by anything on the
// path. That is a defensible choice for an instance whose database holds
// only fixtures, and it stops being defensible the day it holds a real
// family - so it must never be reachable by typing the wrong one.
const PUBLIC_TLS = process.env.HBH_PUBLIC === '1' && TLS_PORT > 0;
const PUBLIC_HTTP = process.env.HBH_PUBLIC_HTTP === '1';
const HTTP_BIND = PUBLIC_HTTP ? '0.0.0.0' : '127.0.0.1';

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.ico': 'image/x-icon',
  '.webp': 'image/webp',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.map': 'application/json; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
  // Derived from the schema, not from the page: hbh.site_team_media holds
  // a VIDEO row waiting to be published, and site/ already carries the
  // file. Left out of the list, the first publish from that screen would
  // 404 on the only thing it showed.
  '.mp4': 'video/mp4',
  '.webm': 'video/webm',
};

// THE LIST ABOVE IS THE ALLOW LIST. An extension that is not in it is not
// served, exactly as if the file were not there.
//
// This table used to end in `?? 'application/octet-stream'`, which serves
// ANY file under the root to anyone who names it. That is how /README.md
// and /CONTENT-AUDIT.md were handed out on hbhskills.com - the tables
// behind the site, the publishing permissions, the migration numbers, and
// any family testimonial withheld for want of consent.
//
// It was fixed once, in site.native.mjs, which grew a servable() exactly
// like this one. But the site is served by THIS file - the apps list in
// web.native.sh reads `site:8093:8445:site:static` - so the fix went into
// the file that does not run, and README.md answered 200 again today.
// That is the lesson in CLAUDE.md about hbh.nginx.conf, repeating with
// different names: the rule is written where it executes, or not at all.
//
// A deny list cannot do this job. Nothing linked to either file, and a
// name nobody would guess is not a control: README.md.
function servable(file) {
  return Object.prototype.hasOwnProperty.call(TYPES, path.extname(file).toLowerCase());
}

const indexFile = path.join(ROOT, 'index.html');

// A URL path may not carry a control byte. `%00` decodes to a NUL - it does
// NOT throw in decodeURIComponent - and fs.stat() then throws synchronously
// on a path containing it, killing an unsupervised process.
//
// Written as codepoints, not a regex with the literal bytes in the source.
// The byte form works, but it turns the file binary to grep, and an editor,
// a reformat, or a heredoc copy can swallow the bytes with NO visible change
// in review - leaving a guard that is present in shape and matches nothing,
// and the process dies again. charCodeAt against 0x20 is plain ASCII and
// survives any copy; there is nothing here for a tool to eat.
function hasControlByte(s) {
  for (let i = 0; i < s.length; i++) {
    if (s.charCodeAt(i) < 0x20) return true;
  }
  return false;
}

function proxy(req, res) {
  const upstream = http.request(
    { host: '127.0.0.1', port: API, path: req.url, method: req.method, headers: req.headers },
    (up) => {
      res.writeHead(up.statusCode ?? 502, up.headers);
      up.pipe(res);
    },
  );
  // A refused connection here means the API is down. Answering 502 with
  // a body the browser can read beats a socket that closes silently and
  // shows up in the console as a CORS error, which it is not.
  upstream.on('error', (e) => {
    res.writeHead(502, { 'content-type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({ error: { code: 'UPSTREAM_UNREACHABLE', detail: e.code } }));
  });
  req.pipe(upstream);
}

// A file may be cached forever only if its NAME changes when its content
// does. Angular hashes the bundles - main-MK5RHSVD.js - so those are safe.
// Everything else under assets/ keeps a stable name across deploys:
// assets/i18n/ar.json is rewritten by every build and called the same
// thing every time.
//
// Marking those immutable is how a browser ends up holding last week's
// translations against this week's markup, and the symptom is not a
// stale page - it is raw keys like login.headlineA rendered where Arabic
// should be, on one machine and not another, which reads as a bug in the
// application and is not one. Cost of getting it wrong: a year, since
// that is what max-age said.
const HASHED = /-[A-Z0-9_]{8,}\.[a-z0-9]+$/;

// =====================================================================
// THE CONTENT SECURITY POLICY, AND IT IS WRITTEN HERE BECAUSE THIS IS
// WHAT RUNS.
//
// hbh.nginx.conf carries the same policy and needs a root install this
// account does not have, so on this machine it is a document. The last
// time a rule lived only in that file, the running server proxied the
// API for an origin the file said must never have one, and the leak was
// on the open internet for eleven minutes. The rule is written where it
// is enforced. Both copies exist; this is the one that decides.
//
// WHY THE PORTAL HAD NO POLICY AT ALL UNTIL NOW: the site block in the
// nginx file has had one since it was written, and the two application
// blocks never did. That was survivable while the applications loaded
// nothing but their own bundles. The consultation screen changes it -
// it fetches a script from a video provider and embeds that provider in
// a frame - so the set of third parties this page may talk to stopped
// being empty, and a set that is not empty has to be written down.
//
// Each entry, and what breaks without it:
//
//   script-src   'self' plus the two provider hosts. The consultation
//                screen appends <script src="https://<domain>/external_api.js">
//                and the component checks the SAME two hosts before it
//                does - the page and the policy agree on purpose, so a
//                provider added to one and not the other fails loudly
//                rather than half-working.
//   frame-src    the provider's conference, which is an iframe. Without
//                it the call is a blank box AND NOTHING IS LOGGED that
//                a person looking at the screen could act on.
//   style-src    'unsafe-inline' is required and not laziness: Angular
//                injects every component's styles as a <style> element
//                at runtime, and index.html carries the boot styles
//                inline so the first paint is not a white page. The
//                alternative is a per-response nonce, which a static
//                file server cannot mint.
//   font-src     the web font the built stylesheet asks gstatic for.
//   connect-src  'self' only. The API is same-origin; the provider's
//                own XHR and WebSocket happen INSIDE its iframe, which
//                is a separate document with its own origin and its own
//                policy, and nothing this header says reaches it.
//   img-src      data: for the inline brand marks.
//
// frame-ancestors says nobody may embed the portal. It is the opposite
// direction from frame-src and both are needed: we frame the provider,
// and nobody frames us.
//
// AND THIS POLICY REQUIRED A BUILD CHANGE, which is recorded here because
// angular.json cannot hold a comment. The production build deferred the
// stylesheet with
//
//     <link rel="stylesheet" href="styles-*.css" media="print"
//           onload="this.media='all'">
//
// and an inline event handler is exactly what script-src refuses. The
// result was 761 CSS rules left on media="print" and never applied -
// with the page still looking correct at the top, because Angular had
// inlined 45 rules of critical CSS above them. A policy that silently
// unstyles everything below the fold is worse than none.
//
// The fix is "inlineCritical": false in web/angular.json for BOTH
// applications, which emits one ordinary blocking <link>. Not
// 'unsafe-inline' in script-src, which would have made the policy
// decorative to buy back a few milliseconds of first paint.
//
// If somebody turns critical-CSS inlining back on, this is what breaks,
// and it breaks looking almost fine.
const PROVIDER_HOSTS = 'https://8x8.vc https://meet.jit.si';
const CSP = [
  "default-src 'self'",
  `script-src 'self' ${PROVIDER_HOSTS}`,
  `frame-src ${PROVIDER_HOSTS}`,
  "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
  'font-src https://fonts.gstatic.com',
  "img-src 'self' data:",
  "connect-src 'self'",
  "base-uri 'self'",
  "frame-ancestors 'none'",
  "form-action 'self'",
].join('; ');

// The site serves no application and frames nobody, so it keeps the
// stricter policy it already had in nginx. Widening it to match the
// portal would hand the one origin that faces the internet permissions
// it has no use for.
const CSP_STATIC = [
  "default-src 'self'",
  "script-src 'self'",
  "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
  'font-src https://fonts.gstatic.com',
  "img-src 'self' data:",
  "frame-ancestors 'none'",
  "form-action 'self'",
].join('; ');

/** The headers every response from this server carries. */
function securityHeaders() {
  return {
    'content-security-policy': SPA ? CSP : CSP_STATIC,
    'x-content-type-options': 'nosniff',
    'referrer-policy': 'strict-origin-when-cross-origin',
  };
}

function sendFile(res, file, isIndex) {
  const ext = path.extname(file).toLowerCase();
  const immutable = !isIndex && HASHED.test(path.basename(file));
  res.writeHead(200, {
    ...securityHeaders(),
    // No `?? 'application/octet-stream'` fallback: servable() has already
    // refused anything not in TYPES, and a fallback here would quietly
    // re-open the hole the moment someone calls sendFile from a new place.
    'content-type': TYPES[ext],
    // index.html is never stored: it is the one file that names all the
    // others, and a stale copy points at bundles that no longer exist.
    // Everything else unhashed is no-cache, which does not mean "do not
    // store" but "ask first" - the browser keeps it and revalidates, so
    // an unchanged asset costs a 304 and not a download.
    'cache-control': isIndex
      ? 'no-store'
      : immutable
        ? 'public, max-age=31536000, immutable'
        : 'no-cache',
  });
  // An unhandled 'error' on a read stream throws, and a throw from this
  // async callback reaches nothing above it - it becomes an uncaught
  // exception and ends the process. The file can vanish between the stat
  // that found it and this read, or be unreadable; on any such error the
  // headers are already sent, so the only honest close is to end the
  // response, not to write a 500 body on top of a 200.
  const stream = fs.createReadStream(file);
  stream.on('error', (e) => {
    console.error('read failed after stat:', file, e && e.code);
    res.destroy();
  });
  stream.pipe(res);
}

function handler(req, res) {
    const url = (req.url ?? '/').split('?')[0];

    // The proxy belongs to the two applications and to nothing else.
    //
    // It used to run for every origin this file serves, including the
    // public site - and the site is the one thing published on a real
    // domain. So hbhskills.com carried /api/ straight to the service,
    // and because OTP_ECHO returns the login code in the response body,
    // POST /api/v1/auth/otp/request on the public domain handed anyone
    // who knew a parent's mobile number that parent's login code. It
    // answered 200 for eleven minutes before it was caught.
    //
    // The site needs no API at all: the enrolment form lives in the
    // portal, and that is why deploy/server/hbh.nginx.conf gives the
    // site block no proxy_pass and says so in its header. This is the
    // same rule, in the server that actually runs today.
    if (url.startsWith('/api/') || url === '/healthz') {
      if (apiAllowed(req, url)) return proxy(req, res);
      // Refused here, not forwarded and refused there: the service never
      // sees the request, so nothing it might answer can leak out.
      res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' })
         .end('404 ' + url);
      return;
    }

    // Resolve inside ROOT and verify it stayed there: a path of
    // ../../.env would otherwise be served to anyone who asks.
    // decodeURIComponent THROWS on a malformed escape, and an exception
    // thrown inside this handler is not caught by anything: node prints
    // the stack and the PROCESS EXITS. `GET /%E0%A4%A` - eleven bytes -
    // takes down whichever origin receives it, and these run under nohup
    // with nothing to restart them. Reproduced in a container: the server
    // answered 200, then the malformed request, then nothing at all.
    //
    // It is one request, from anyone, needing no account and no knowledge
    // of the system. site.native.mjs guards the identical call; this file
    // did not, and this file is the one serving all four origins.
    // Wrapping decodeURIComponent was not enough. `%E0%A4%A` throws in the
    // decode and the catch handles it - but `%00` does NOT throw: it
    // decodes to a NUL byte, sails past this try, and then fs.stat() below
    // throws SYNCHRONOUSLY on a path containing \0 and takes the process
    // down anyway. Enumerating throwers is a losing game - the next one
    // throws in a third place. So the decoded path is checked against an
    // ALLOW rule and rejected before it is used at all: no NUL, no control
    // byte. What a URL path may legitimately contain is the small set;
    // what can crash a downstream call is open-ended.
    let target;
    try {
      const decoded = decodeURIComponent(url);
      if (hasControlByte(decoded)) {
        res.writeHead(400, { 'content-type': 'text/plain; charset=utf-8' })
           .end('400 bad request');
        return;
      }
      target = path.resolve(ROOT, '.' + decoded);
    } catch {
      res.writeHead(400, { 'content-type': 'text/plain; charset=utf-8' })
         .end('400 bad request');
      return;
    }
    // ROOT + separator, not ROOT alone: a bare prefix test also accepts a
    // sibling whose name merely STARTS with the root's - "/srv/site-old"
    // passes `startsWith("/srv/site")` - so it would serve a directory
    // nobody meant to publish. Equality is allowed separately because the
    // root itself is a legitimate target.
    if (target !== ROOT && !target.startsWith(ROOT + path.sep)) {
      res.writeHead(403).end('forbidden');
      return;
    }

    fs.stat(target, (err, st) => {
      if (!err && st.isFile()) {
        // Checked here, where the path is known to be a real file on
        // disk, and not earlier: a client-side route may carry a dot
        // ("/child/1.2"), and an extension test in front of the SPA
        // fallback would answer 404 for a page that works today.
        if (!servable(target)) {
          res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' })
             .end('404 ' + url);
          return;
        }
        return sendFile(res, target, url === '/index.html' || url === '/');
      }
      // A directory means its index.html - including "/" itself. The SPA
      // path happened to cover this by falling back to index.html for
      // everything; static mode does not, and without this the home page
      // of the site answers 404 while every other page works.
      if (!err && st.isDirectory()) {
        const dirIndex = path.join(target, 'index.html');
        if (fs.existsSync(dirIndex)) return sendFile(res, dirIndex, true);
      }
      // Not a file. Either a client-side route, or a genuine 404.
      if (!SPA) {
        res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' })
           .end('404 ' + url);
        return;
      }
      fs.stat(indexFile, (e2) => {
        if (e2) { res.writeHead(404).end('no index.html under ' + ROOT); return; }
        sendFile(res, indexFile, true);
      });
    });
}

// The whole handler behind a guard, not any single statement in it. Three
// separate throws in this one function have taken the process down -
// decodeURIComponent on a bad escape, fs.stat on a NUL byte, a read stream
// erroring after the stat - and each was fixed at its own site while the
// NEXT one waited. This catches the synchronous class wherever it lands:
// nothing this handler throws should end a process that has no supervisor
// to restart it.
function safeHandler(req, res) {
  try {
    handler(req, res);
  } catch (e) {
    console.error('handler threw:', e && e.stack ? e.stack : e);
    try {
      if (!res.headersSent) {
        res.writeHead(500, { 'content-type': 'text/plain; charset=utf-8' });
      }
      res.end('500');
    } catch { /* response already gone */ }
  }
}

// And the process-level backstop, because the async half - a throw inside a
// callback or a timer - never reaches the try above, and there is no
// supervisor (HBH-113 criterion 3, still the owner's call). For a static
// file server holding no shared mutable state between requests, staying up
// on an unforeseen error is safer than dying under nohup.
//
// Every hit is COUNTED and printed with a fixed prefix. The real danger of
// keep-alive is not the exception, it is what it becomes: "the site answers
// sometimes" reads as a bug somewhere unrelated and burns weeks. `UNCAUGHT`
// turns that into a number anyone can ask for - `grep -c UNCAUGHT log`. And
// a count that stays 0 (the expectation, after the three guards above) is
// itself the evidence to hand the owner with criterion 3: the backstop was
// never reached, so the supervisor loop is an improvement, not a rescue.
let uncaughtCount = 0;
process.on('uncaughtException', (e) => {
  console.error(`UNCAUGHT #${++uncaughtCount} exception (kept alive, no supervisor):`,
    e && e.stack ? e.stack : e);
});
process.on('unhandledRejection', (e) => {
  console.error(`UNCAUGHT #${++uncaughtCount} rejection (kept alive):`,
    e && e.stack ? e.stack : e);
});

http.createServer(safeHandler).listen(PORT, HTTP_BIND, () => {
  console.log(`http  ${HTTP_BIND}:${PORT}  ${ROOT}  /api -> 127.0.0.1:${API}`);
  if (PUBLIC_HTTP) {
    console.log('      PUBLIC IN THE CLEAR - login codes and tokens are readable on the wire');
  }
});

// And over TLS when asked for.
if (PUBLIC_TLS) {
  const cert = fs.readFileSync(path.join(TLS_DIR, 'cert.pem'));
  const key = fs.readFileSync(path.join(TLS_DIR, 'key.pem'));
  https.createServer({ cert, key }, safeHandler).listen(TLS_PORT, '0.0.0.0', () => {
    console.log(`https 0.0.0.0:${TLS_PORT} PUBLIC - reachable from the internet`);
  });
}
