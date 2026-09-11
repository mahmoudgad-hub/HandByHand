/* =====================================================================
   Hand By Hand - بوابة ولي الأمر (النموذج التفاعلي)
   File: html/app/hbh-app.js

   Prototype navigation only. No data, no network, no business rule.
   Every rule this prototype appears to enforce is enforced on the
   server in the real application - this file only makes the screens
   reachable so the flow can be shown end to end.
   ===================================================================== */
(function () {
  'use strict';

  var body   = document.getElementById('paBody');
  var head   = document.getElementById('paHead');
  var tabs   = document.getElementById('paTabs');
  var back   = document.getElementById('paBack');
  var title  = document.getElementById('paTitle');
  var sub    = document.getElementById('paSub');
  var nav    = document.getElementById('stgNav');
  var toast  = document.getElementById('toast');
  var toastT = document.getElementById('toastText');

  var screens = [].slice.call(document.querySelectorAll('.scr'));
  var order   = screens.map(function (s) { return s.id.replace(/^s-/, ''); });
  var current = order[0];

  // -------------------------------------------------------------------
  // Screen picker - presentation chrome, built from the screens present
  // -------------------------------------------------------------------
  screens.forEach(function (s) {
    var key = s.id.replace(/^s-/, '');
    var b = document.createElement('button');
    b.type = 'button';
    b.className = 'stg__chip';
    b.textContent = s.dataset.label || key;
    b.dataset.go = key;
    nav.appendChild(b);
  });

  // -------------------------------------------------------------------
  // Navigation
  // -------------------------------------------------------------------
  function go(key) {
    var target = document.getElementById('s-' + key);
    if (!target) { return; }
    current = key;

    screens.forEach(function (s) { s.classList.toggle('is-on', s === target); });

    // Auth and welcome screens carry no app chrome.
    var bare = target.dataset.chrome === 'none';
    head.hidden = bare;
    tabs.hidden = bare;
    body.style.padding = bare ? '0' : '';

    if (!bare) {
      title.textContent = target.dataset.title || '';
      sub.textContent   = target.dataset.sub   || '';
      sub.hidden        = !target.dataset.sub;
      // The back button appears only where a parent screen is declared.
      back.hidden = !target.dataset.back;
      back.dataset.go = target.dataset.back || '';
    }

    var tab = target.dataset.tab;
    [].forEach.call(tabs.children, function (t) {
      t.classList.toggle('is-on', !!tab && t.dataset.go === tab);
    });
    [].forEach.call(nav.children, function (c) {
      c.classList.toggle('is-on', c.dataset.go === key);
    });

    body.scrollTop = 0;
  }

  // -------------------------------------------------------------------
  // One delegated listener drives every interaction in the prototype
  // -------------------------------------------------------------------
  document.addEventListener('click', function (e) {
    var t;

    // toggle a home-programme task
    t = e.target.closest('[data-task]');
    if (t) { t.classList.toggle('is-done'); return; }

    // toggle a consent switch
    t = e.target.closest('[data-sw]');
    if (t) {
      t.classList.toggle('is-on');
      t.setAttribute('aria-pressed', t.classList.contains('is-on') ? 'true' : 'false');
      return;
    }

    // segmented control
    t = e.target.closest('.seg__i');
    if (t) {
      [].forEach.call(t.parentNode.children, function (c) { c.classList.remove('is-on'); });
      t.classList.add('is-on');
      return;
    }

    // a message confirming an action, then navigation if both are set
    t = e.target.closest('[data-toast]');
    if (t) { say(t.dataset.toast); }

    t = e.target.closest('[data-go]');
    if (t && t.dataset.go) { go(t.dataset.go); }
  });

  var toastTimer;
  function say(text) {
    toastT.textContent = text;
    toast.classList.add('is-on');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { toast.classList.remove('is-on'); }, 2400);
  }

  // -------------------------------------------------------------------
  // One-time code: advance on entry, step back on delete
  // -------------------------------------------------------------------
  var otp = [].slice.call(document.querySelectorAll('#otpBoxes input'));
  otp.forEach(function (box, i) {
    box.addEventListener('input', function () {
      box.value = box.value.replace(/\D/g, '').slice(0, 1);
      box.classList.toggle('is-set', !!box.value);
      if (box.value && otp[i + 1]) { otp[i + 1].focus(); }
    });
    box.addEventListener('keydown', function (e) {
      if (e.key === 'Backspace' && !box.value && otp[i - 1]) { otp[i - 1].focus(); }
    });
  });

  // Countdown to resend - decorative, the real one is issued by the server
  var timer = document.getElementById('otpTimer');
  if (timer) {
    var left = 47;
    setInterval(function () {
      if (left > 0) { left--; }
      timer.textContent = '00:' + String(left).padStart(2, '0');
    }, 1000);
  }

  // Live session clock
  var clock = document.getElementById('liveClock');
  if (clock) {
    var secs = 761;
    setInterval(function () {
      secs++;
      var h = Math.floor(secs / 3600);
      var m = Math.floor((secs % 3600) / 60);
      var s = secs % 60;
      clock.textContent = [h, m, s].map(function (n) {
        return String(n).padStart(2, '0');
      }).join(':');
    }, 1000);
  }

  // -------------------------------------------------------------------
  // Arrow keys walk the screens - for demonstrating on a laptop
  // -------------------------------------------------------------------
  document.addEventListener('keydown', function (e) {
    if (e.target.tagName === 'INPUT') { return; }
    var i = order.indexOf(current);
    // RTL page: ArrowLeft moves forward.
    if (e.key === 'ArrowLeft'  && order[i + 1]) { go(order[i + 1]); }
    if (e.key === 'ArrowRight' && order[i - 1]) { go(order[i - 1]); }
  });

  go(current);
}());
