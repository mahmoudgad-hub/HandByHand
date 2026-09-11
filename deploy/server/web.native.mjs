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
};

const indexFile = path.join(ROOT, 'index.html');

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

function sendFile(res, file, isIndex) {
  const ext = path.extname(file).toLowerCase();
  const immutable = !isIndex && HASHED.test(path.basename(file));
  res.writeHead(200, {
    'content-type': TYPES[ext] ?? 'application/octet-stream',
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
  fs.createReadStream(file).pipe(res);
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
    const target = path.resolve(ROOT, '.' + decodeURIComponent(url));
    if (!target.startsWith(ROOT)) {
      res.writeHead(403).end('forbidden');
      return;
    }

    fs.stat(target, (err, st) => {
      if (!err && st.isFile()) {
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

http.createServer(handler).listen(PORT, HTTP_BIND, () => {
  console.log(`http  ${HTTP_BIND}:${PORT}  ${ROOT}  /api -> 127.0.0.1:${API}`);
  if (PUBLIC_HTTP) {
    console.log('      PUBLIC IN THE CLEAR - login codes and tokens are readable on the wire');
  }
});

// And over TLS when asked for.
if (PUBLIC_TLS) {
  const cert = fs.readFileSync(path.join(TLS_DIR, 'cert.pem'));
  const key = fs.readFileSync(path.join(TLS_DIR, 'key.pem'));
  https.createServer({ cert, key }, handler).listen(TLS_PORT, '0.0.0.0', () => {
    console.log(`https 0.0.0.0:${TLS_PORT} PUBLIC - reachable from the internet`);
  });
}
