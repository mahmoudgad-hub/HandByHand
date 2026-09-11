(function () {
  'use strict';
  var root = document.documentElement;
  root.classList.add('site-loading');
  var timer;
  function finish() {
    root.classList.remove('site-loading');
    clearTimeout(timer);
    var loader = document.getElementById('siteLoader');
    if (loader) loader.hidden = true;
  }
  // External fonts or a failed image must never keep the page covered.
  timer = setTimeout(finish, 5000);
  window.addEventListener('load', finish, { once: true });
  window.addEventListener('pageshow', function (event) { if (event.persisted) finish(); });
  if (document.readyState === 'complete') finish();
})();
