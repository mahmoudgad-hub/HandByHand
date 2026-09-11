const menuBtn = document.querySelector(".menu-btn");
const nav = document.querySelector(".nav");

if (menuBtn && nav) {
  menuBtn.addEventListener("click", () => {
    const open = menuBtn.getAttribute("aria-expanded") === "true";
    menuBtn.setAttribute("aria-expanded", String(!open));
    nav.classList.toggle("is-open", !open);
  });

  nav.querySelectorAll("a").forEach(a => {
    a.addEventListener("click", () => {
      menuBtn.setAttribute("aria-expanded", "false");
      nav.classList.remove("is-open");
    });
  });
}

const sections = [...document.querySelectorAll("main section[id]")];
const links = [...document.querySelectorAll(".nav a")];

function setActiveNav() {
  let current = "home";
  const y = window.scrollY + 140;
  sections.forEach(section => {
    if (section.offsetTop <= y) current = section.id;
  });
  links.forEach(link => {
    link.classList.toggle("active", link.getAttribute("href") === `#${current}`);
  });
}
window.addEventListener("scroll", setActiveNav, {passive:true});
setActiveNav();

const reviewTrack = document.getElementById("reviewTrack");
document.querySelector(".slider-arrow.next")?.addEventListener("click", () => {
  reviewTrack?.scrollBy({left: 330, behavior:"smooth"});
});
document.querySelector(".slider-arrow.prev")?.addEventListener("click", () => {
  reviewTrack?.scrollBy({left: -330, behavior:"smooth"});
});

const modal = document.getElementById("videoModal");
document.querySelectorAll(".video-btn").forEach(btn => {
  btn.addEventListener("click", () => {
    modal.hidden = false;
    document.body.classList.add("modal-open");
  });
});
document.querySelectorAll("[data-close]").forEach(btn => {
  btn.addEventListener("click", () => {
    modal.hidden = true;
    document.body.classList.remove("modal-open");
  });
});
document.addEventListener("keydown", e => {
  if (e.key === "Escape" && modal && !modal.hidden) {
    modal.hidden = true;
    document.body.classList.remove("modal-open");
  }
});


/* ===== Arabic / English language switcher ===== */
const translations = {
  ar: {
    "nav.home":"الرئيسية",
    "nav.about":"من نحن",
    "nav.services":"خدماتنا",
    "nav.team":"فريق العمل",
    "nav.videos":"فيديوهات من المركز",
    "nav.reviews":"آراء العملاء",
    "nav.faq":"الأسئلة الشائعة",
    "nav.contact":"تواصل معنا",
    "cta.book":"احجز تقييمًا الآن",
    "cta.contact":"تواصل معنا",
    "hero.together":"معًا",
    "hero.title":"نصنع فرقًا أكبر",
    "hero.subtitle":"مركز متخصص في تنمية مهارات الأطفال من خلال برامج علاجية متكاملة وخطط فردية.",
    "benefit.care":"رعاية وشراكة",
    "benefit.programs":"برامج متخصصة",
    "benefit.future":"مستقبل أفضل",
    "sections.services":"خدماتنا",
    "sections.servicesSub":"برامج متكاملة تلبي احتياجات طفلك",
    "cta.allServices":"عرض جميع الخدمات",
    "sections.videos":"فيديوهات من المركز",
    "sections.videosSub":"لقطات تعليمية بعد الحصول على موافقات النشر المناسبة",
    "cta.moreVideos":"عرض المزيد من الفيديوهات",
    "sections.reviews":"آراء أولياء الأمور",
    "sections.reviewsSub":"مكان مخصص لآراء حقيقية بعد موافقة أصحابها",
    "cta.moreReviews":"عرض المزيد من الآراء",
    "sections.team":"فريقنا من المدربين والأخصائيين",
    "sections.teamSub":"خبرات متنوعة بهدف تقديم أفضل دعم لأطفالنا",
    "cta.teamAll":"تعرف على فريقنا كاملًا",
    "sections.why":"لماذا Hand by Hand ؟",
    "services.speech":"تخاطب وتنمية لغة",
    "services.occupational":"علاج وظيفي",
    "services.aba":"تحليل سلوك تطبيقي (ABA)",
    "services.music":"علاج بالموسيقى",
    "services.sensory":"تكامل حسي",
    "services.academic":"أكاديمي وصعوبات تعلم",
    "videos.speech":"جلسة تخاطب وتنمية لغة",
    "videos.occupational":"جلسة علاج وظيفي",
    "videos.skills":"أنشطة تنمية مهارات",
    "videos.aba":"برنامج تحليل السلوك (ABA)",
    "why.individual":"خطط فردية لكل طفل",
    "why.safe":"بيئة آمنة وداعمة",
    "why.team":"فريق متخصص وخبير",
    "why.followup":"متابعة مستمرة وقياس النتائج",
    "ctaJourney.title":"ابدأ رحلة طفلك اليوم",
    "ctaJourney.sub":"احجز تقييمًا الآن وامنح طفلك فرصة لمستقبل أفضل",
    "sections.contact":"تواصل معنا",
    "sections.faq":"الأسئلة الشائعة",
    "faq.q1":"هل الجلسات فردية؟",
    "faq.a1":"نعم، الجلسة مخصصة لطفل واحد.",
    "faq.q2":"هل يتم تسجيل البث المباشر؟",
    "faq.a2":"لا. البث مباشر فقط ولا يتم تسجيله أو حفظه.",
    "faq.q3":"كيف أحجز تقييمًا؟",
    "faq.a3":"اضغط على زر «احجز تقييمًا الآن» ثم تواصل مع المركز أو اربطه بنموذج طلب الالتحاق."
  },
  en: {
    "nav.home":"Home",
    "nav.about":"About Us",
    "nav.services":"Services",
    "nav.team":"Our Team",
    "nav.videos":"Center Videos",
    "nav.reviews":"Testimonials",
    "nav.faq":"FAQ",
    "nav.contact":"Contact Us",
    "cta.book":"Book an Assessment",
    "cta.contact":"Contact Us",
    "hero.together":"Together",
    "hero.title":"we make a bigger difference",
    "hero.subtitle":"A specialized center supporting children's skills through integrated therapy programs and individualized plans.",
    "benefit.care":"Care & Partnership",
    "benefit.programs":"Specialized Programs",
    "benefit.future":"A Better Future",
    "sections.services":"Our Services",
    "sections.servicesSub":"Integrated programs designed around your child's needs",
    "cta.allServices":"View All Services",
    "sections.videos":"Videos from the Center",
    "sections.videosSub":"Educational moments shared only with the appropriate publishing permissions",
    "cta.moreVideos":"View More Videos",
    "sections.reviews":"Parent Testimonials",
    "sections.reviewsSub":"A space for genuine parent feedback shared with permission",
    "cta.moreReviews":"View More Testimonials",
    "sections.team":"Our Trainers & Specialists",
    "sections.teamSub":"Diverse expertise focused on supporting every child",
    "cta.teamAll":"Meet Our Full Team",
    "sections.why":"Why Hand by Hand?",
    "services.speech":"Speech & Language Development",
    "services.occupational":"Occupational Therapy",
    "services.aba":"Applied Behavior Analysis (ABA)",
    "services.music":"Music Therapy",
    "services.sensory":"Sensory Integration",
    "services.academic":"Academic Support & Learning Difficulties",
    "videos.speech":"Speech & Language Session",
    "videos.occupational":"Occupational Therapy Session",
    "videos.skills":"Skills Development Activities",
    "videos.aba":"ABA Program",
    "why.individual":"Individual plans for every child",
    "why.safe":"A safe and supportive environment",
    "why.team":"A specialized and experienced team",
    "why.followup":"Ongoing follow-up and outcome measurement",
    "ctaJourney.title":"Start Your Child's Journey Today",
    "ctaJourney.sub":"Book an assessment and take the first clear step toward better support",
    "sections.contact":"Contact Us",
    "sections.faq":"Frequently Asked Questions",
    "faq.q1":"Are sessions individual?",
    "faq.a1":"Yes. Each session is designed for one child.",
    "faq.q2":"Is the live session recorded?",
    "faq.a2":"No. Live viewing is real-time only and is not recorded or stored.",
    "faq.q3":"How do I book an assessment?",
    "faq.a3":"Use the “Book an Assessment” button, then connect it to your enrollment form or center contact flow."
  }
};

const langToggle = document.getElementById("langToggle");
const langToggleText = document.getElementById("langToggleText");

function applyLanguage(lang) {
  const dict = translations[lang] || translations.ar;
  const isArabic = lang === "ar";

  document.documentElement.lang = lang;
  document.documentElement.dir = isArabic ? "rtl" : "ltr";
  document.body.classList.toggle("lang-en", !isArabic);

  document.querySelectorAll("[data-i18n]").forEach((el) => {
    const key = el.dataset.i18n;
    if (!dict[key]) return;

    if (key === "hero.subtitle") {
      el.textContent = dict[key];
    } else if (key.startsWith("benefit.")) {
      el.textContent = dict[key];
    } else {
      el.textContent = dict[key];
    }
  });

  if (langToggleText) {
    langToggleText.textContent = isArabic ? "EN" : "AR";
  }

  localStorage.setItem("hbh-language", lang);
}

langToggle?.addEventListener("click", () => {
  const current = document.documentElement.lang === "ar" ? "ar" : "en";
  applyLanguage(current === "ar" ? "en" : "ar");
});

applyLanguage(localStorage.getItem("hbh-language") || "ar");
