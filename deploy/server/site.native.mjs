// =====================================================================
// ⚠ THIS FILE IS NOT WHAT SERVES hbhskills.com. MEASURED 2026-09-19.
//
// The apps list in web.native.sh reads
//
//     site:8093:8445:site:static
//
// so on the deployed host the public site is served by web.native.mjs,
// while stack.native.sh still starts THIS file on the same port 8093.
// Two declarations, one port, and only one of them wins - whichever
// started first.
//
// A SERVING RULE WRITTEN ONLY HERE IS NOT IN FORCE. It cost exactly
// that: the allow list below (servable(), the TYPES table) was added
// here on 2026-09-11 to stop /README.md being handed out, the local
// audit went green because the container was running THIS program, and
// hbhskills.com/README.md answered 200 for eight more days. The green
// was the measuring tool, not the property - it proved the wrong server.
//
// So: write a serving rule in web.native.mjs, then mirror it here if
// this file is still wanted. And an audit is only evidence when it is
// pointed at the ORIGIN, never at a local copy of a server that may not
// be the deployed one:
//
//     bash deploy/server/site.native.sh audit https://hbhskills.com
//
// It is the same lesson CLAUDE.md records about hbh.nginx.conf - a rule
// written in the config that does not run - repeating with new names.
// Whether this pair should exist at all is the Administrator's call,
// since deploy/ is theirs; until then it stays, and it says this.
// =====================================================================
// Serve the public site.
//
//   node site.native.mjs <site dir> <http port> [https port] [tls dir]
//
// WHY THIS IS A SEPARATE FILE FROM web.native.mjs
//
// That one proxies /api/ and /healthz to the service on 8090, because
// the portal and the console need the page and its API on one origin.
// This one must NOT, and the difference is the whole point.
//
// The site is the one surface here meant to be published. Serving it
// with a program that also forwards /api/ would publish the API along
// with it - including /api/v1/auth, on a service running OTP_ECHO=true,
// which returns the login code in the response body. Anyone who knew a
// parent's mobile number would sign in as that parent and read a
// child's clinical record. Nobody would have decided to publish the
// API; it would have arrived attached to the marketing page.
//
// So there is no proxy in this file at all, and adding one back is not
// a refactor - it is a decision to publish the service.
//
// The second difference is smaller and still worth keeping: an unknown
// path here returns 404, not index.html. This is a set of pages, not a
// single-page application, and answering every typo with the home page
// hides broken links from anyone testing them.
// =====================================================================
import http from 'node:http';
import https from 'node:https';
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(process.argv[2] ?? '.');
const PORT = Number(process.argv[3] ?? 8093);
const TLS_PORT = Number(process.argv[4] ?? 0);
const TLS_DIR = process.argv[5] ?? '';

// Public is the default here, unlike everywhere else in this deploy
// directory, and that is deliberate rather than an oversight: a
// marketing page nobody outside can reach is not doing its job. What
// makes it safe is above - this program has no route to the API and no
// route to the database, and every byte under ROOT is written to be
// read by strangers.
//
// Set HBH_SITE_BIND=127.0.0.1 to keep it on loopback while working.
const BIND = process.env.HBH_SITE_BIND || '0.0.0.0';

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8',
  // hbh.site_team_media.kind is VIDEO or PHOTO, and there is a VIDEO row
  // in the table today pointing at an .mp4 in site/assets. It is still a
  // draft, so nothing on the page asks for it yet - which is exactly how
  // an allow list turns into a trap: the day somebody publishes that row
  // from the console the page would ask for a file this server refuses,
  // and the only symptom would be a member's video that does not play.
  // These two are here because the site already has the feature.
  '.mp4': 'video/mp4',
  '.webm': 'video/webm',
};

// config.js carries the deployment's portal URL and the centre's phone
// number. It is rewritten per environment and keeps its name, so a
// cached copy is a page pointing at the previous portal. The images and
// the stylesheet keep their names too, so they revalidate rather than
// being stored for a year - this site has no hashed filenames at all,
// which is the price of not having a build step.
function cacheControl(file) {
  const base = path.basename(file);
  // content.js joins config.js for the same reason: it is generated by
  // scripts/site-export.sh and keeps its name across deployments, so a
  // cached copy is a site quietly serving the previous release's phone
  // number, questions and team - with no error anywhere to notice.
  if (base === 'config.js' || base === 'content.js' || base.endsWith('.html')) return 'no-store';
  return 'no-cache';
}

function send(res, status, body, type) {
  res.writeHead(status, { 'content-type': type ?? 'text/plain; charset=utf-8' });
  res.end(body);
}

// A FILE WITH NO TYPE IN THE TABLE ABOVE IS NOT SERVED, and this is a
// rule about what the folder is, not about MIME.
//
// The handler resolves any path under ROOT and sent whatever it found,
// falling back to application/octet-stream for an extension it did not
// know. That fallback is what published site/README.md and
// site/CONTENT-AUDIT.md - two documents that sit next to the page
// because they document it, and that between them name every table
// behind the site, the permission that gates publishing, the migration
// numbers, which console screens are broken, and which testimonials are
// unpublished for want of a family's consent. `curl .../CONTENT-AUDIT.md`
// returned all of it with a 200.
//
// Nothing linked to them. That is not a control: a folder listing is not
// needed to guess README.md, and both names are ordinary.
//
// The allow list is the TYPES table itself, so adding a servable kind of
// file is one entry in one place and forgetting to is a 404 rather than
// a quiet publication. THE TEST IS THE ONE THE DEPLOY LESSON ALREADY
// NAMES: ask for what must not be answered. site.native.sh audit does.
function servable(file) {
  return Object.prototype.hasOwnProperty.call(TYPES, path.extname(file).toLowerCase());
}

// True for a NUL byte, any C0 control character, or DEL.
//
// Written as arithmetic rather than a regex class on purpose - the
// reason is at the call site. Nothing in this function can be damaged by
// a tool that re-encodes the file, because there is not one unprintable
// character in it.
function hasControlChar(value) {
  for (let i = 0; i < value.length; i++) {
    const code = value.charCodeAt(i);
    if (code < 32 || code === 127) return true;
  }
  return false;
}

function sendFile(res, file) {
  if (!servable(file)) return send(res, 404, 'not found');
  res.writeHead(200, {
    'content-type': TYPES[path.extname(file).toLowerCase()],
    'cache-control': cacheControl(file),
    // The page loads nothing of its own from anywhere but Google Fonts.
    // Stating that here means an injected <script src> from a CDN does
    // not run, whatever put it in the markup.
    'content-security-policy': [
      "default-src 'self'",
      "script-src 'self'",
      "style-src 'self' https://fonts.googleapis.com",
      "font-src https://fonts.gstatic.com",
      "img-src 'self' data: https://tile.openstreetmap.org",
      // No embedded third-party documents; the map uses image tiles.
      "frame-src 'none'",
      "frame-ancestors 'none'",
      "form-action 'none'",
    ].join('; '),
    'x-content-type-options': 'nosniff',
    'referrer-policy': 'strict-origin-when-cross-origin',
  });
  fs.createReadStream(file).pipe(res);
}

function handler(req, res) {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return send(res, 405, 'method not allowed');
  }

  const url = (req.url ?? '/').split('?')[0];

  // Resolve inside ROOT and check it stayed there: a request for
  // ../../.env is otherwise a request this happily answers.
  let target;
  try {
    const decoded = decodeURIComponent(url);

    // THE PATH IS JUDGED BY WHAT IT CONTAINS, BEFORE ANYTHING USES IT.
    //
    // This try used to wrap the decode alone, and that was not a guard:
    // decodeURIComponent('%00') does not throw - it returns a string
    // holding a null byte - so the catch was never reached. The throw
    // came one line later and OUTSIDE the try, from fs.stat, which
    // rejects a path with a null byte synchronously:
    //
    //   TypeError [ERR_INVALID_ARG_VALUE]: The argument 'path' must be
    //   a string, Uint8Array, or URL without null bytes.
    //
    // Nothing catches a synchronous throw inside a request handler, so
    // the PROCESS EXITED. GET /%00 - eleven bytes, no account, no
    // knowledge of this system - took the public site down. Measured on
    // this file: /index.html 200, then /%00, then /index.html with no
    // reply and the container exit code 1. Found by the Security
    // Engineer; reproduced here before it was changed.
    //
    // WHY A CHECK AND NOT A BIGGER try. Wrapping fs.stat would fix this
    // call and leave the next one: the fault is that a byte no URL
    // should carry reached a filesystem API at all, and every later user
    // of `target` inherits it. So it is refused once, at the only place
    // the request becomes a path - the same reason TYPES is an allow
    // list rather than a list of names to block.
    //
    // Control characters are refused for the same reason, not for
    // tidiness: a newline in a path is how a log line gets forged.
    //
    // NO REGEX CHARACTER CLASS, AND THAT IS THE POINT. This was first
    // written as a class of two escaped code points, and the escapes did
    // not survive being written to disk: the file came back holding the
    // RAW bytes, grep started answering "Binary file matches", and the
    // class became invisible to anyone reviewing it - the comment that
    // explained it was mangled too. It still worked, which is what makes
    // it dangerous: the next tool to re-encode this file could change
    // what it matches with nothing on screen to show for it.
    //
    // A numeric comparison cannot be mangled by anything, reads the same
    // in every editor, and greps. The cost is a loop over a path, which
    // no request will ever notice.
    if (hasControlChar(decoded)) {
      return send(res, 400, 'bad request');
    }

    target = path.resolve(ROOT, '.' + decoded);
  } catch {
    // Still needed: a malformed escape like /%E0%A4%A DOES throw here.
    return send(res, 400, 'bad request');
  }
  if (target !== ROOT && !target.startsWith(ROOT + path.sep)) {
    return send(res, 403, 'forbidden');
  }

  fs.stat(target, (err, st) => {
    if (!err && st.isDirectory()) {
      const index = path.join(target, 'index.html');
      return fs.stat(index, (e) => (e ? send(res, 404, 'not found') : sendFile(res, index)));
    }
    if (!err && st.isFile()) return sendFile(res, target);

    // /privacy also finds privacy.html, so the footer link can be
    // written without the extension if anyone prefers it that way.
    const withHtml = target + '.html';
    fs.stat(withHtml, (e2, s2) => {
      if (!e2 && s2.isFile()) return sendFile(res, withHtml);
      send(res, 404, 'not found');
    });
  });
}

http.createServer(handler).listen(PORT, BIND, () => {
  console.log(`site http ${BIND}:${PORT} ${ROOT}  (no api proxy)`);
});

if (TLS_PORT > 0 && TLS_DIR) {
  const cert = fs.readFileSync(path.join(TLS_DIR, 'cert.pem'));
  const key = fs.readFileSync(path.join(TLS_DIR, 'key.pem'));
  https.createServer({ cert, key }, handler).listen(TLS_PORT, '0.0.0.0', () => {
    console.log(`site https 0.0.0.0:${TLS_PORT} ${ROOT}`);
  });
}
