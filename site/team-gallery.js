(function () {
  'use strict';
  var dialog = document.createElement('dialog');
  dialog.className = 'team-media-dialog';
  dialog.setAttribute('aria-labelledby', 'teamMediaTitle');
  dialog.innerHTML = '<header><h2 id="teamMediaTitle"></h2><button type="button" class="media-close" aria-label="إغلاق / Close">×</button></header><div class="media-stage"><button type="button" class="media-prev" aria-label="السابق / Previous"><svg viewBox="0 0 24 24"><path d="m9 6 6 6-6 6"/></svg></button><div class="media-content"></div><button type="button" class="media-next" aria-label="التالي / Next"><svg viewBox="0 0 24 24"><path d="m15 6-6 6 6 6"/></svg></button></div><footer><span class="media-count" aria-live="polite"></span><a class="media-original" target="_blank" rel="noopener">فتح الملف / Open file</a></footer>';
  document.body.appendChild(dialog);
  var content = dialog.querySelector('.media-content');
  var profileText = document.createElement('div');
  profileText.className = 'team-profile-text';
  var body = document.createElement('div');
  body.className = 'team-profile-body';
  var stage = dialog.querySelector('.media-stage');
  stage.before(body);
  body.append(profileText, stage);
  var prev = dialog.querySelector('.media-prev');
  var next = dialog.querySelector('.media-next');
  var items = [], index = 0, savedOverflow = '';
  function safePath(src) {
    try { var u = new URL(src, location.href); return /^(https?:|file:)$/.test(u.protocol) ? u.href : null; } catch (_) { return null; }
  }
  function clear() { var video = content.querySelector('video'); if (video) video.pause(); content.replaceChildren(); }
  function render() {
    clear();
    var item = items[index], url = safePath(item.src);
    dialog.querySelector('h2').textContent = item.title || (document.documentElement.lang === 'en' ? 'Professional profile' : 'الملف المهني');
    dialog.querySelector('.media-count').textContent = (index + 1) + ' / ' + items.length;
    prev.disabled = next.disabled = items.length < 2;
    prev.hidden = next.hidden = items.length < 2;
    dialog.querySelector('.media-count').hidden = items.length < 2;
    var original = dialog.querySelector('.media-original');
    original.textContent = document.documentElement.lang === 'en' ? 'Open full-size file ↗' : 'فتح الملف بالحجم الكامل ↗';
    original.hidden = !url;
    if (!url) { content.textContent = 'تعذّر فتح الملف / Unable to open file'; return; }
    original.href = url;
    var node;
    if (item.type === 'video') { node = document.createElement('video'); node.controls = true; node.preload = 'metadata'; node.playsInline = true; }
    else if (item.type === 'pdf') { node = document.createElement('iframe'); node.title = item.title || 'Certificate'; }
    else { node = document.createElement('img'); node.alt = item.title || 'الملف المهني'; }
    node.addEventListener('error', function () { content.textContent = 'تعذّر تحميل الملف. يمكنك فتحه من الرابط أدناه.'; });
    node.src = url; content.appendChild(node);
  }
  function move(step) { index = (index + step + items.length) % items.length; render(); }
  document.addEventListener('click', function (e) {
    var link = e.target.closest('.member-profile'); if (!link) return;
    var card = link.closest('.member-card'); if (!card) return;
    profileText.replaceChildren();
    var displayedName = card.querySelector('h3').textContent.trim();
    var member = ((window.HBH_SITE_CONTENT || {}).team || []).find(function (entry) {
      return String(entry.id) === card.getAttribute('data-member-id');
    });
    if (member) {
      var en = document.documentElement.lang === 'en';
      var role = document.createElement('p');
      role.textContent = (en ? member.roleEn : member.roleAr) || member.roleAr || '';
      profileText.appendChild(role);
      var facts = document.createElement('ul');
      (member.facts || []).forEach(function (fact) {
        var li = document.createElement('li');
        li.textContent = (en ? fact.textEn : fact.textAr) || fact.textAr || '';
        facts.appendChild(li);
      });
      profileText.appendChild(facts);
    }
    profileText.hidden = !member;
    body.classList.toggle('media-only', !member);
    items = [];
    if (member) {
      var title = 'الملف المهني — ' + displayedName;
      if (member.profileHref) items.push({type: /\.pdf(?:[?#]|$)/i.test(member.profileHref) ? 'pdf' : 'image', src: member.profileHref, title: title});
      ['photos','videos','certificates'].forEach(function (kind) {
        (member[kind] || []).forEach(function (media) {
          if (!media.path || items.some(function (item) { return item.src === media.path; })) return;
          items.push({type:kind === 'videos' ? 'video' : /\.pdf(?:[?#]|$)/i.test(media.path) ? 'pdf' : 'image',src:media.path,title:media.captionAr || title});
        });
      });
    }
    if (!items.length) return;
    /* A class, not body.style.overflow. The site is served with
       Content-Security-Policy: style-src 'self', which blocks inline
       style attributes as well as inline <style> blocks - so the
       assignment was refused and the page went on scrolling behind the
       open gallery, with only a console line to say so. */
    e.preventDefault(); index = 0; render(); lockScroll(true); dialog.showModal();
  });

  function lockScroll(on) { document.body.classList.toggle('hbh-scroll-locked', on); }

  /* Released from every path that closes this dialog, and not from the
     `close` event alone: that event does not fire at all in some
     browsers this site is tested in, and a lock that is never released
     leaves the page permanently unscrollable after one visit to the
     gallery - a worse bug than the one being fixed. */
  function closeDialog() { lockScroll(false); clear(); if (dialog.open) dialog.close(); }
  prev.addEventListener('click', function () { move(-1); });
  next.addEventListener('click', function () { move(1); });
  dialog.querySelector('.media-close').addEventListener('click', function () { closeDialog(); });
  dialog.addEventListener('close', function () { lockScroll(false); clear(); });
  dialog.addEventListener('cancel', function () { lockScroll(false); clear(); });   // Escape
  dialog.addEventListener('click', function (e) { if (e.target === dialog) { var r = dialog.getBoundingClientRect(); if (e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom) closeDialog(); } });
  dialog.addEventListener('keydown', function (e) { if (e.target.tagName === 'VIDEO') return; if (e.key === 'ArrowRight') { e.preventDefault(); move(-1); } if (e.key === 'ArrowLeft') { e.preventDefault(); move(1); } });
})();
