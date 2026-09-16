/* A small tile map: no third-party iframe or API key. */
(function () {
  'use strict';
  var host = document.getElementById('contactMapCanvas');
  if (!host) return;
  var contact = (window.HBH_SITE_CONTENT || {}).contact || window.HBH_SITE || {};
  var pair = String(contact.mapUrl || '').trim().match(/^(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)$/);
  if (!pair) return;
  var lat = Number(pair[1]), lng = Number(pair[2]);
  if (Math.abs(lat) > 85 || Math.abs(lng) > 180) return;
  var zoom = 16;
  var tiles = host.querySelector('.contact-map-tiles');
  var status = host.querySelector('.contact-map-status');
  var plus = host.querySelector('[data-map-zoom="1"]');
  var minus = host.querySelector('[data-map-zoom="-1"]');
  var generation = 0;
  var lastView = '';
  function render() {
    if (!host.clientWidth) return;
    var view = [zoom, host.clientWidth, host.clientHeight].join(':');
    if (view === lastView) return;
    lastView = view;
    var current = ++generation;
    var size = 256, scale = Math.pow(2, zoom);
    var x = (lng + 180) / 360 * scale;
    var rad = lat * Math.PI / 180;
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
