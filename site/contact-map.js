/* A small tile map: no third-party iframe or API key.
 *
 * WHAT THE VALUE MAY BE, AND WHY THIS FILE HAD TO LEARN IT
 *
 * hbh.site_contact.map_url is one free-text field, and the console calls
 * it a link - resource-spec.ts names it site.mapUrl and its comment says
 * "a link that OPENS a map application". app.js mapLink() has always
 * accepted BOTH shapes: an http(s) URL as-is, or a "lat, lng" pair it
 * converts. This file accepted the pair only, and answered anything else
 * with a bare `return`.
 *
 * So half the page took a pasted Google Maps link and half refused it -
 * silently. The button worked; the panel sat on "جارٍ تحميل الخريطة…"
 * for ever, because that text is authored in index.html and was only
 * ever cleared inside a tile's onload. No error, nothing in the console,
 * and the centre's own value happens to be a coordinate pair - so it
 * looked perfect and would have broken on the first edit from the
 * screen. Reported by tester - dev, who read both code paths rather than
 * the one that was working.
 *
 * THE LESSON IS ALREADY WRITTEN ABOVE mapLink IN app.js: normalising
 * belongs on the page, because the console can refuse the NEXT value and
 * the page has to draw the rows that already exist. This file did not
 * take it. It does now, and from the same input it accepts the same
 * shapes.
 *
 * WHAT IT DOES NOT DO: resolve a short link. goo.gl/maps/xxx and a place
 * URL with no numbers in it carry no coordinates, and finding out would
 * mean this page making a request to Google about a visitor reading a
 * children's therapy page - which is the whole reason the embedded
 * iframe was removed on 2026-09-10. Those values hide the panel and
 * leave the button, which still opens the link the centre pasted.
 */
(function () {
  'use strict';
  var host = document.getElementById('contactMapCanvas');
  if (!host) return;

  var tiles = host.querySelector('.contact-map-tiles');
  var status = host.querySelector('.contact-map-status');
  var plus = host.querySelector('[data-map-zoom="1"]');
  var minus = host.querySelector('[data-map-zoom="-1"]');

  /* "جارٍ تحميل الخريطة…" is authored in the markup so it is there
     before this script runs. It is hidden HERE, first thing, and shown
     again only at the moment tiles are actually requested.

     That one move closes every "loading for ever" path at once - an
     unusable value, a zero-width canvas, an observer that never fires -
     rather than one of them. A status that is true only sometimes is
     worse than no status: it names a state the page is not in. */
  if (status) status.hidden = true;

  /* Coordinates, or null. Null is a decision, never a silent exit.

     The three URL shapes are the ones a Google Maps link actually
     carries numbers in, and !3d/!4d is tried FIRST on purpose: on a
     place link @lat,lng is where the map was centred and !3d/!4d is
     where the place IS, and those differ by the width of the viewport. */
  function coordsFrom(raw) {
    var value = String(raw || '').trim();
    if (!value) return null;

    var m = value.match(/^(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)$/);
    if (m) return usable(m[1], m[2]);

    if (!/^https?:\/\//i.test(value)) return null;

    m = value.match(/!3d(-?\d{1,3}(?:\.\d+)?)!4d(-?\d{1,3}(?:\.\d+)?)/);
    if (m) return usable(m[1], m[2]);

    /* /@30.001,31.481,16z  and  ?q= / ?query= / &ll= / &center= / &destination=
       A decimal point is required in both halves: it is what separates a
       coordinate from a zoom level, a place id, or a pixel size. */
    m = value.match(/[@=](-?\d{1,3}\.\d+),(-?\d{1,3}\.\d+)/);
    if (m) return usable(m[1], m[2]);

    return null;
  }

  /* Web Mercator cannot draw the poles, and a swapped pair is the
     commonest paste error - 31,30 is in Egypt's desert, 31.48,30.00 is
     in the sea. Only the range is checkable here, so only the range is
     claimed. */
  function usable(a, b) {
    var lat = Number(a), lng = Number(b);
    if (!isFinite(lat) || !isFinite(lng)) return null;
    if (Math.abs(lat) > 85 || Math.abs(lng) > 180) return null;
    return { lat: lat, lng: lng };
  }

  var at = coordsFrom((window.HBH_SITE_CONTENT || {}).contact
    ? (window.HBH_SITE_CONTENT.contact || {}).mapUrl
    : (window.HBH_SITE || {}).mapUrl);

  /* No coordinates: take the panel away and leave the button.
     The address and the arrival notes are still on the page, so the
     visitor loses nothing but an empty frame - and telling them that OUR
     configuration value is unreadable would be noise about a problem
     only the centre can fix. A tile that fails to LOAD is different, and
     says so below: that is the page failing at something it started. */
  if (!at) {
    host.hidden = true;
    return;
  }

  var zoom = 16;
  var generation = 0;
  var lastView = '';

  function render() {
    if (!host.clientWidth) return;
    var view = [zoom, host.clientWidth, host.clientHeight].join(':');
    if (view === lastView) return;
    lastView = view;
    var current = ++generation;
    var size = 256, scale = Math.pow(2, zoom);
    var x = (at.lng + 180) / 360 * scale;
    var rad = at.lat * Math.PI / 180;
    var y = (1 - Math.log(Math.tan(rad) + 1 / Math.cos(rad)) / Math.PI) / 2 * scale;
    var width = host.clientWidth, height = host.clientHeight;
    var left = x * size - width / 2, top = y * size - height / 2;
    tiles.replaceChildren();
    status.hidden = false;
    status.textContent = 'جارٍ تحميل الخريطة…';
    var loaded = 0;
    var failed = false;
    for (var row = Math.floor(top / size); row <= Math.floor((top + height) / size); row++) {
      for (var col = Math.floor(left / size); col <= Math.floor((left + width) / size); col++) {
        var img = document.createElement('img');
        img.alt = '';
        img.width = size; img.height = size;
        img.draggable = false;
        img.style.left = (col * size - left) + 'px';
        img.style.top = (row * size - top) + 'px';
        img.onload = function () { if (current === generation && ++loaded && !failed) status.hidden = true; };
        img.onerror = function () {
          if (current === generation) {
            failed = true;
            status.hidden = false;
            status.textContent = 'تعذّر تحميل بعض تفاصيل الخريطة. يمكنك فتح الموقع على Google Maps بالزر أدناه.';
          }
        };
        img.src = 'https://tile.openstreetmap.org/' + zoom + '/' + col + '/' + row + '.png';
        tiles.appendChild(img);
      }
    }
    plus.disabled = zoom >= 18;
    minus.disabled = zoom <= 12;
  }

  host.querySelectorAll('[data-map-zoom]').forEach(function (button) {
    button.addEventListener('click', function () {
      zoom = Math.max(12, Math.min(18, zoom + Number(button.dataset.mapZoom)));
      render();
    });
  });

  // Load only when the contact section is approached.
  var active = false;
  var observer = new IntersectionObserver(function (entries) {
    if (entries.some(function (entry) { return entry.isIntersecting; })) {
      active = true; render(); observer.disconnect();
    }
  }, { rootMargin: '200px' });
  observer.observe(host);
  var resizeTimer;
  new ResizeObserver(function () {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(function () { if (active) render(); }, 150);
  }).observe(host);
}());
