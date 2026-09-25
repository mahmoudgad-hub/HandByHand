// Calling codes and national prefixes: libphonenumber-js 1.13.13 (MIT).
// Names: Unicode CLDR via Intl.DisplayNames. Flags: flag-icons 7.5.0 (MIT).
// Licenses are included under assets/flags.
export interface PhoneCountry {
  readonly id: string;
  readonly code: string;
  readonly prefix: string;
  readonly name: string;
}

/**
 * Every country the picker knows - kept, not deleted. Only the ones in
 * ENABLED_PHONE_COUNTRIES below are offered on the sign-in screen.
 */
export const ALL_PHONE_COUNTRIES: readonly PhoneCountry[] = [
  {
    "id": "eg",
    "code": "+20",
    "prefix": "0",
    "name": "مصر"
  },
  {
    "id": "is",
    "code": "+354",
    "prefix": "",
    "name": "آيسلندا"
  },
  {
    "id": "et",
    "code": "+251",
    "prefix": "0",
    "name": "إثيوبيا"
  },
  {
    "id": "az",
    "code": "+994",
    "prefix": "0",
    "name": "أذربيجان"
  },
  {
    "id": "am",
    "code": "+374",
    "prefix": "0",
    "name": "أرمينيا"
  },
  {
    "id": "aw",
    "code": "+297",
    "prefix": "",
    "name": "أروبا"
  },
  {
    "id": "er",
    "code": "+291",
    "prefix": "0",
    "name": "إريتريا"
  },
  {
    "id": "es",
    "code": "+34",
    "prefix": "",
    "name": "إسبانيا"
  },
  {
    "id": "au",
    "code": "+61",
    "prefix": "0",
    "name": "أستراليا"
  },
  {
    "id": "ee",
    "code": "+372",
    "prefix": "",
    "name": "إستونيا"
  },
  {
    "id": "il",
    "code": "+972",
    "prefix": "0",
    "name": "إسرائيل"
  },
  {
    "id": "sz",
    "code": "+268",
    "prefix": "",
    "name": "إسواتيني"
  },
  {
    "id": "af",
    "code": "+93",
    "prefix": "0",
    "name": "أفغانستان"
  },
  {
    "id": "ps",
    "code": "+970",
    "prefix": "0",
    "name": "الأراضي الفلسطينية"
  },
  {
    "id": "ar",
    "code": "+54",
    "prefix": "0",
    "name": "الأرجنتين"
  },
  {
    "id": "jo",
    "code": "+962",
    "prefix": "0",
    "name": "الأردن"
  },
  {
    "id": "io",
    "code": "+246",
    "prefix": "",
    "name": "الإقليم البريطاني في المحيط الهندي"
  },
  {
    "id": "ec",
    "code": "+593",
    "prefix": "0",
    "name": "الإكوادور"
  },
  {
    "id": "ae",
    "code": "+971",
    "prefix": "0",
    "name": "الإمارات العربية المتحدة"
  },
  {
    "id": "al",
    "code": "+355",
    "prefix": "0",
    "name": "ألبانيا"
  },
  {
    "id": "bh",
    "code": "+973",
    "prefix": "",
    "name": "البحرين"
  },
  {
    "id": "br",
    "code": "+55",
    "prefix": "0",
    "name": "البرازيل"
  },
  {
    "id": "pt",
    "code": "+351",
    "prefix": "",
    "name": "البرتغال"
  },
  {
    "id": "ba",
    "code": "+387",
    "prefix": "0",
    "name": "البوسنة والهرسك"
  },
  {
    "id": "cz",
    "code": "+420",
    "prefix": "",
    "name": "التشيك"
  },
  {
    "id": "me",
    "code": "+382",
    "prefix": "0",
    "name": "الجبل الأسود"
  },
  {
    "id": "dz",
    "code": "+213",
    "prefix": "0",
    "name": "الجزائر"
  },
  {
    "id": "dk",
    "code": "+45",
    "prefix": "",
    "name": "الدانمرك"
  },
  {
    "id": "cv",
    "code": "+238",
    "prefix": "",
    "name": "الرأس الأخضر"
  },
  {
    "id": "sv",
    "code": "+503",
    "prefix": "",
    "name": "السلفادور"
  },
  {
    "id": "sn",
    "code": "+221",
    "prefix": "",
    "name": "السنغال"
  },
  {
    "id": "sd",
    "code": "+249",
    "prefix": "0",
    "name": "السودان"
  },
  {
    "id": "se",
    "code": "+46",
    "prefix": "0",
    "name": "السويد"
  },
  {
    "id": "eh",
    "code": "+212",
    "prefix": "0",
    "name": "الصحراء الغربية"
  },
  {
    "id": "so",
    "code": "+252",
    "prefix": "0",
    "name": "الصومال"
  },
  {
    "id": "cn",
    "code": "+86",
    "prefix": "0",
    "name": "الصين"
  },
  {
    "id": "iq",
    "code": "+964",
    "prefix": "0",
    "name": "العراق"
  },
  {
    "id": "ga",
    "code": "+241",
    "prefix": "",
    "name": "الغابون"
  },
  {
    "id": "va",
    "code": "+39",
    "prefix": "",
    "name": "الفاتيكان"
  },
  {
    "id": "ph",
    "code": "+63",
    "prefix": "0",
    "name": "الفلبين"
  },
  {
    "id": "cm",
    "code": "+237",
    "prefix": "",
    "name": "الكاميرون"
  },
  {
    "id": "cg",
    "code": "+242",
    "prefix": "",
    "name": "الكونغو - برازافيل"
  },
  {
    "id": "cd",
    "code": "+243",
    "prefix": "0",
    "name": "الكونغو - كينشاسا"
  },
  {
    "id": "kw",
    "code": "+965",
    "prefix": "",
    "name": "الكويت"
  },
  {
    "id": "de",
    "code": "+49",
    "prefix": "0",
    "name": "ألمانيا"
  },
  {
    "id": "ma",
    "code": "+212",
    "prefix": "0",
    "name": "المغرب"
  },
  {
    "id": "mx",
    "code": "+52",
    "prefix": "",
    "name": "المكسيك"
  },
  {
    "id": "sa",
    "code": "+966",
    "prefix": "0",
    "name": "المملكة العربية السعودية"
  },
  {
    "id": "gb",
    "code": "+44",
    "prefix": "0",
    "name": "المملكة المتحدة"
  },
  {
    "id": "no",
    "code": "+47",
    "prefix": "",
    "name": "النرويج"
  },
  {
    "id": "at",
    "code": "+43",
    "prefix": "0",
    "name": "النمسا"
  },
  {
    "id": "ne",
    "code": "+227",
    "prefix": "",
    "name": "النيجر"
  },
  {
    "id": "in",
    "code": "+91",
    "prefix": "0",
    "name": "الهند"
  },
  {
    "id": "us",
    "code": "+1",
    "prefix": "1",
    "name": "الولايات المتحدة"
  },
  {
    "id": "jp",
    "code": "+81",
    "prefix": "0",
    "name": "اليابان"
  },
  {
    "id": "ye",
    "code": "+967",
    "prefix": "0",
    "name": "اليمن"
  },
  {
    "id": "gr",
    "code": "+30",
    "prefix": "",
    "name": "اليونان"
  },
  {
    "id": "ag",
    "code": "+1",
    "prefix": "1",
    "name": "أنتيغوا وبربودا"
  },
  {
    "id": "ad",
    "code": "+376",
    "prefix": "",
    "name": "أندورا"
  },
  {
    "id": "id",
    "code": "+62",
    "prefix": "0",
    "name": "إندونيسيا"
  },
  {
    "id": "ao",
    "code": "+244",
    "prefix": "",
    "name": "أنغولا"
  },
  {
    "id": "ai",
    "code": "+1",
    "prefix": "1",
    "name": "أنغويلا"
  },
  {
    "id": "uy",
    "code": "+598",
    "prefix": "0",
    "name": "أورغواي"
  },
  {
    "id": "uz",
    "code": "+998",
    "prefix": "",
    "name": "أوزبكستان"
  },
  {
    "id": "ug",
    "code": "+256",
    "prefix": "0",
    "name": "أوغندا"
  },
  {
    "id": "ua",
    "code": "+380",
    "prefix": "0",
    "name": "أوكرانيا"
  },
  {
    "id": "ir",
    "code": "+98",
    "prefix": "0",
    "name": "إيران"
  },
  {
    "id": "ie",
    "code": "+353",
    "prefix": "0",
    "name": "أيرلندا"
  },
  {
    "id": "it",
    "code": "+39",
    "prefix": "",
    "name": "إيطاليا"
  },
  {
    "id": "pg",
    "code": "+675",
    "prefix": "",
    "name": "بابوا غينيا الجديدة"
  },
  {
    "id": "py",
    "code": "+595",
    "prefix": "0",
    "name": "باراغواي"
  },
  {
    "id": "pk",
    "code": "+92",
    "prefix": "0",
    "name": "باكستان"
  },
  {
    "id": "pw",
    "code": "+680",
    "prefix": "",
    "name": "بالاو"
  },
  {
    "id": "bb",
    "code": "+1",
    "prefix": "1",
    "name": "بربادوس"
  },
  {
    "id": "bm",
    "code": "+1",
    "prefix": "1",
    "name": "برمودا"
  },
  {
    "id": "bn",
    "code": "+673",
    "prefix": "",
    "name": "بروناي"
  },
  {
    "id": "be",
    "code": "+32",
    "prefix": "0",
    "name": "بلجيكا"
  },
  {
    "id": "bg",
    "code": "+359",
    "prefix": "0",
    "name": "بلغاريا"
  },
  {
    "id": "bz",
    "code": "+501",
    "prefix": "",
    "name": "بليز"
  },
  {
    "id": "bd",
    "code": "+880",
    "prefix": "0",
    "name": "بنغلاديش"
  },
  {
    "id": "pa",
    "code": "+507",
    "prefix": "",
    "name": "بنما"
  },
  {
    "id": "bj",
    "code": "+229",
    "prefix": "",
    "name": "بنين"
  },
  {
    "id": "bt",
    "code": "+975",
    "prefix": "",
    "name": "بوتان"
  },
  {
    "id": "bw",
    "code": "+267",
    "prefix": "",
    "name": "بوتسوانا"
  },
  {
    "id": "pr",
    "code": "+1",
    "prefix": "1",
    "name": "بورتوريكو"
  },
  {
    "id": "bf",
    "code": "+226",
    "prefix": "",
    "name": "بوركينا فاسو"
  },
  {
    "id": "bi",
    "code": "+257",
    "prefix": "",
    "name": "بوروندي"
  },
  {
    "id": "pl",
    "code": "+48",
    "prefix": "",
    "name": "بولندا"
  },
  {
    "id": "bo",
    "code": "+591",
    "prefix": "0",
    "name": "بوليفيا"
  },
  {
    "id": "pf",
    "code": "+689",
    "prefix": "",
    "name": "بولينيزيا الفرنسية"
  },
  {
    "id": "pe",
    "code": "+51",
    "prefix": "0",
    "name": "بيرو"
  },
  {
    "id": "by",
    "code": "+375",
    "prefix": "8",
    "name": "بيلاروس"
  },
  {
    "id": "th",
    "code": "+66",
    "prefix": "0",
    "name": "تايلاند"
  },
  {
    "id": "tw",
    "code": "+886",
    "prefix": "0",
    "name": "تايوان"
  },
  {
    "id": "tm",
    "code": "+993",
    "prefix": "8",
    "name": "تركمانستان"
  },
  {
    "id": "tr",
    "code": "+90",
    "prefix": "0",
    "name": "تركيا"
  },
  {
    "id": "tt",
    "code": "+1",
    "prefix": "1",
    "name": "ترينيداد وتوباغو"
  },
  {
    "id": "td",
    "code": "+235",
    "prefix": "",
    "name": "تشاد"
  },
  {
    "id": "cl",
    "code": "+56",
    "prefix": "",
    "name": "تشيلي"
  },
  {
    "id": "tz",
    "code": "+255",
    "prefix": "0",
    "name": "تنزانيا"
  },
  {
    "id": "tg",
    "code": "+228",
    "prefix": "",
    "name": "توغو"
  },
  {
    "id": "tv",
    "code": "+688",
    "prefix": "",
    "name": "توفالو"
  },
  {
    "id": "tk",
    "code": "+690",
    "prefix": "",
    "name": "توكيلاو"
  },
  {
    "id": "tn",
    "code": "+216",
    "prefix": "",
    "name": "تونس"
  },
  {
    "id": "to",
    "code": "+676",
    "prefix": "",
    "name": "تونغا"
  },
  {
    "id": "tl",
    "code": "+670",
    "prefix": "",
    "name": "تيمور - ليشتي"
  },
  {
    "id": "jm",
    "code": "+1",
    "prefix": "1",
    "name": "جامايكا"
  },
  {
    "id": "gi",
    "code": "+350",
    "prefix": "",
    "name": "جبل طارق"
  },
  {
    "id": "ax",
    "code": "+358",
    "prefix": "0",
    "name": "جزر آلاند"
  },
  {
    "id": "bs",
    "code": "+1",
    "prefix": "1",
    "name": "جزر البهاما"
  },
  {
    "id": "km",
    "code": "+269",
    "prefix": "",
    "name": "جزر القمر"
  },
  {
    "id": "mq",
    "code": "+596",
    "prefix": "0",
    "name": "جزر المارتينيك"
  },
  {
    "id": "mv",
    "code": "+960",
    "prefix": "",
    "name": "جزر المالديف"
  },
  {
    "id": "tc",
    "code": "+1",
    "prefix": "1",
    "name": "جزر توركس وكايكوس"
  },
  {
    "id": "sb",
    "code": "+677",
    "prefix": "",
    "name": "جزر سليمان"
  },
  {
    "id": "fo",
    "code": "+298",
    "prefix": "",
    "name": "جزر فارو"
  },
  {
    "id": "fk",
    "code": "+500",
    "prefix": "",
    "name": "جزر فوكلاند"
  },
  {
    "id": "vi",
    "code": "+1",
    "prefix": "1",
    "name": "جزر فيرجن الأمريكية"
  },
  {
    "id": "vg",
    "code": "+1",
    "prefix": "1",
    "name": "جزر فيرجن البريطانية"
  },
  {
    "id": "ky",
    "code": "+1",
    "prefix": "1",
    "name": "جزر كايمان"
  },
  {
    "id": "ck",
    "code": "+682",
    "prefix": "",
    "name": "جزر كوك"
  },
  {
    "id": "cc",
    "code": "+61",
    "prefix": "0",
    "name": "جزر كوكوس (كيلينغ)"
  },
  {
    "id": "mh",
    "code": "+692",
    "prefix": "1",
    "name": "جزر مارشال"
  },
  {
    "id": "mp",
    "code": "+1",
    "prefix": "1",
    "name": "جزر ماريانا الشمالية"
  },
  {
    "id": "wf",
    "code": "+681",
    "prefix": "",
    "name": "جزر والس وفوتونا"
  },
  {
    "id": "cx",
    "code": "+61",
    "prefix": "0",
    "name": "جزيرة كريسماس"
  },
  {
    "id": "im",
    "code": "+44",
    "prefix": "0",
    "name": "جزيرة مان"
  },
  {
    "id": "nf",
    "code": "+672",
    "prefix": "",
    "name": "جزيرة نورفولك"
  },
  {
    "id": "cf",
    "code": "+236",
    "prefix": "",
    "name": "جمهورية أفريقيا الوسطى"
  },
  {
    "id": "do",
    "code": "+1",
    "prefix": "1",
    "name": "جمهورية الدومينيكان"
  },
  {
    "id": "za",
    "code": "+27",
    "prefix": "0",
    "name": "جنوب أفريقيا"
  },
  {
    "id": "ss",
    "code": "+211",
    "prefix": "0",
    "name": "جنوب السودان"
  },
  {
    "id": "ge",
    "code": "+995",
    "prefix": "0",
    "name": "جورجيا"
  },
  {
    "id": "dj",
    "code": "+253",
    "prefix": "",
    "name": "جيبوتي"
  },
  {
    "id": "je",
    "code": "+44",
    "prefix": "0",
    "name": "جيرسي"
  },
  {
    "id": "dm",
    "code": "+1",
    "prefix": "1",
    "name": "دومينيكا"
  },
  {
    "id": "rw",
    "code": "+250",
    "prefix": "0",
    "name": "رواندا"
  },
  {
    "id": "ru",
    "code": "+7",
    "prefix": "8",
    "name": "روسيا"
  },
  {
    "id": "ro",
    "code": "+40",
    "prefix": "0",
    "name": "رومانيا"
  },
  {
    "id": "re",
    "code": "+262",
    "prefix": "0",
    "name": "روينيون"
  },
  {
    "id": "zm",
    "code": "+260",
    "prefix": "0",
    "name": "زامبيا"
  },
  {
    "id": "zw",
    "code": "+263",
    "prefix": "0",
    "name": "زيمبابوي"
  },
  {
    "id": "ci",
    "code": "+225",
    "prefix": "",
    "name": "ساحل العاج"
  },
  {
    "id": "ws",
    "code": "+685",
    "prefix": "",
    "name": "ساموا"
  },
  {
    "id": "as",
    "code": "+1",
    "prefix": "1",
    "name": "ساموا الأمريكية"
  },
  {
    "id": "bl",
    "code": "+590",
    "prefix": "0",
    "name": "سان بارتليمي"
  },
  {
    "id": "pm",
    "code": "+508",
    "prefix": "0",
    "name": "سان بيير ومكويلون"
  },
  {
    "id": "mf",
    "code": "+590",
    "prefix": "0",
    "name": "سان مارتن"
  },
  {
    "id": "sm",
    "code": "+378",
    "prefix": "",
    "name": "سان مارينو"
  },
  {
    "id": "vc",
    "code": "+1",
    "prefix": "1",
    "name": "سانت فنسنت وجزر غرينادين"
  },
  {
    "id": "kn",
    "code": "+1",
    "prefix": "1",
    "name": "سانت كيتس ونيفيس"
  },
  {
    "id": "lc",
    "code": "+1",
    "prefix": "1",
    "name": "سانت لوسيا"
  },
  {
    "id": "sx",
    "code": "+1",
    "prefix": "1",
    "name": "سانت مارتن"
  },
  {
    "id": "sh",
    "code": "+290",
    "prefix": "",
    "name": "سانت هيلينا"
  },
  {
    "id": "st",
    "code": "+239",
    "prefix": "",
    "name": "ساو تومي وبرينسيبي"
  },
  {
    "id": "lk",
    "code": "+94",
    "prefix": "0",
    "name": "سريلانكا"
  },
  {
    "id": "sj",
    "code": "+47",
    "prefix": "",
    "name": "سفالبارد وجان ماين"
  },
  {
    "id": "sk",
    "code": "+421",
    "prefix": "0",
    "name": "سلوفاكيا"
  },
  {
    "id": "si",
    "code": "+386",
    "prefix": "0",
    "name": "سلوفينيا"
  },
  {
    "id": "sg",
    "code": "+65",
    "prefix": "",
    "name": "سنغافورة"
  },
  {
    "id": "sy",
    "code": "+963",
    "prefix": "0",
    "name": "سوريا"
  },
  {
    "id": "sr",
    "code": "+597",
    "prefix": "",
    "name": "سورينام"
  },
  {
    "id": "ch",
    "code": "+41",
    "prefix": "0",
    "name": "سويسرا"
  },
  {
    "id": "sl",
    "code": "+232",
    "prefix": "0",
    "name": "سيراليون"
  },
  {
    "id": "sc",
    "code": "+248",
    "prefix": "",
    "name": "سيشل"
  },
  {
    "id": "rs",
    "code": "+381",
    "prefix": "0",
    "name": "صربيا"
  },
  {
    "id": "tj",
    "code": "+992",
    "prefix": "",
    "name": "طاجيكستان"
  },
  {
    "id": "om",
    "code": "+968",
    "prefix": "",
    "name": "عُمان"
  },
  {
    "id": "gm",
    "code": "+220",
    "prefix": "",
    "name": "غامبيا"
  },
  {
    "id": "gh",
    "code": "+233",
    "prefix": "0",
    "name": "غانا"
  },
  {
    "id": "gd",
    "code": "+1",
    "prefix": "1",
    "name": "غرينادا"
  },
  {
    "id": "gl",
    "code": "+299",
    "prefix": "",
    "name": "غرينلاند"
  },
  {
    "id": "gt",
    "code": "+502",
    "prefix": "",
    "name": "غواتيمالا"
  },
  {
    "id": "gp",
    "code": "+590",
    "prefix": "0",
    "name": "غوادلوب"
  },
  {
    "id": "gu",
    "code": "+1",
    "prefix": "1",
    "name": "غوام"
  },
  {
    "id": "gf",
    "code": "+594",
    "prefix": "0",
    "name": "غويانا الفرنسية"
  },
  {
    "id": "gy",
    "code": "+592",
    "prefix": "",
    "name": "غيانا"
  },
  {
    "id": "gg",
    "code": "+44",
    "prefix": "0",
    "name": "غيرنزي"
  },
  {
    "id": "gn",
    "code": "+224",
    "prefix": "",
    "name": "غينيا"
  },
  {
    "id": "gq",
    "code": "+240",
    "prefix": "",
    "name": "غينيا الاستوائية"
  },
  {
    "id": "gw",
    "code": "+245",
    "prefix": "",
    "name": "غينيا بيساو"
  },
  {
    "id": "vu",
    "code": "+678",
    "prefix": "",
    "name": "فانواتو"
  },
  {
    "id": "fr",
    "code": "+33",
    "prefix": "0",
    "name": "فرنسا"
  },
  {
    "id": "ve",
    "code": "+58",
    "prefix": "0",
    "name": "فنزويلا"
  },
  {
    "id": "fi",
    "code": "+358",
    "prefix": "0",
    "name": "فنلندا"
  },
  {
    "id": "vn",
    "code": "+84",
    "prefix": "0",
    "name": "فيتنام"
  },
  {
    "id": "fj",
    "code": "+679",
    "prefix": "",
    "name": "فيجي"
  },
  {
    "id": "cy",
    "code": "+357",
    "prefix": "",
    "name": "قبرص"
  },
  {
    "id": "qa",
    "code": "+974",
    "prefix": "",
    "name": "قطر"
  },
  {
    "id": "kg",
    "code": "+996",
    "prefix": "0",
    "name": "قيرغيزستان"
  },
  {
    "id": "kz",
    "code": "+7",
    "prefix": "8",
    "name": "كازاخستان"
  },
  {
    "id": "nc",
    "code": "+687",
    "prefix": "",
    "name": "كاليدونيا الجديدة"
  },
  {
    "id": "hr",
    "code": "+385",
    "prefix": "0",
    "name": "كرواتيا"
  },
  {
    "id": "kh",
    "code": "+855",
    "prefix": "0",
    "name": "كمبوديا"
  },
  {
    "id": "ca",
    "code": "+1",
    "prefix": "1",
    "name": "كندا"
  },
  {
    "id": "cu",
    "code": "+53",
    "prefix": "0",
    "name": "كوبا"
  },
  {
    "id": "cw",
    "code": "+599",
    "prefix": "",
    "name": "كوراساو"
  },
  {
    "id": "kr",
    "code": "+82",
    "prefix": "0",
    "name": "كوريا الجنوبية"
  },
  {
    "id": "kp",
    "code": "+850",
    "prefix": "0",
    "name": "كوريا الشمالية"
  },
  {
    "id": "cr",
    "code": "+506",
    "prefix": "",
    "name": "كوستاريكا"
  },
  {
    "id": "xk",
    "code": "+383",
    "prefix": "0",
    "name": "كوسوفو"
  },
  {
    "id": "co",
    "code": "+57",
    "prefix": "0",
    "name": "كولومبيا"
  },
  {
    "id": "ki",
    "code": "+686",
    "prefix": "0",
    "name": "كيريباتي"
  },
  {
    "id": "ke",
    "code": "+254",
    "prefix": "0",
    "name": "كينيا"
  },
  {
    "id": "lv",
    "code": "+371",
    "prefix": "",
    "name": "لاتفيا"
  },
  {
    "id": "la",
    "code": "+856",
    "prefix": "0",
    "name": "لاوس"
  },
  {
    "id": "lb",
    "code": "+961",
    "prefix": "0",
    "name": "لبنان"
  },
  {
    "id": "lu",
    "code": "+352",
    "prefix": "",
    "name": "لوكسمبورغ"
  },
  {
    "id": "ly",
    "code": "+218",
    "prefix": "0",
    "name": "ليبيا"
  },
  {
    "id": "lr",
    "code": "+231",
    "prefix": "0",
    "name": "ليبيريا"
  },
  {
    "id": "lt",
    "code": "+370",
    "prefix": "0",
    "name": "ليتوانيا"
  },
  {
    "id": "li",
    "code": "+423",
    "prefix": "0",
    "name": "ليختنشتاين"
  },
  {
    "id": "ls",
    "code": "+266",
    "prefix": "",
    "name": "ليسوتو"
  },
  {
    "id": "mt",
    "code": "+356",
    "prefix": "",
    "name": "مالطا"
  },
  {
    "id": "ml",
    "code": "+223",
    "prefix": "",
    "name": "مالي"
  },
  {
    "id": "my",
    "code": "+60",
    "prefix": "0",
    "name": "ماليزيا"
  },
  {
    "id": "yt",
    "code": "+262",
    "prefix": "0",
    "name": "مايوت"
  },
  {
    "id": "mg",
    "code": "+261",
    "prefix": "0",
    "name": "مدغشقر"
  },
  {
    "id": "mk",
    "code": "+389",
    "prefix": "0",
    "name": "مقدونيا الشمالية"
  },
  {
    "id": "mw",
    "code": "+265",
    "prefix": "0",
    "name": "ملاوي"
  },
  {
    "id": "mo",
    "code": "+853",
    "prefix": "",
    "name": "منطقة ماكاو الإدارية الخاصة"
  },
  {
    "id": "mn",
    "code": "+976",
    "prefix": "0",
    "name": "منغوليا"
  },
  {
    "id": "mr",
    "code": "+222",
    "prefix": "",
    "name": "موريتانيا"
  },
  {
    "id": "mu",
    "code": "+230",
    "prefix": "",
    "name": "موريشيوس"
  },
  {
    "id": "mz",
    "code": "+258",
    "prefix": "",
    "name": "موزمبيق"
  },
  {
    "id": "md",
    "code": "+373",
    "prefix": "0",
    "name": "مولدوفا"
  },
  {
    "id": "mc",
    "code": "+377",
    "prefix": "0",
    "name": "موناكو"
  },
  {
    "id": "ms",
    "code": "+1",
    "prefix": "1",
    "name": "مونتسرات"
  },
  {
    "id": "mm",
    "code": "+95",
    "prefix": "0",
    "name": "ميانمار (بورما)"
  },
  {
    "id": "fm",
    "code": "+691",
    "prefix": "",
    "name": "ميكرونيزيا"
  },
  {
    "id": "na",
    "code": "+264",
    "prefix": "0",
    "name": "ناميبيا"
  },
  {
    "id": "nr",
    "code": "+674",
    "prefix": "",
    "name": "ناورو"
  },
  {
    "id": "np",
    "code": "+977",
    "prefix": "0",
    "name": "نيبال"
  },
  {
    "id": "ng",
    "code": "+234",
    "prefix": "0",
    "name": "نيجيريا"
  },
  {
    "id": "ni",
    "code": "+505",
    "prefix": "",
    "name": "نيكاراغوا"
  },
  {
    "id": "nz",
    "code": "+64",
    "prefix": "0",
    "name": "نيوزيلندا"
  },
  {
    "id": "nu",
    "code": "+683",
    "prefix": "",
    "name": "نيوي"
  },
  {
    "id": "ht",
    "code": "+509",
    "prefix": "",
    "name": "هايتي"
  },
  {
    "id": "hn",
    "code": "+504",
    "prefix": "",
    "name": "هندوراس"
  },
  {
    "id": "hu",
    "code": "+36",
    "prefix": "06",
    "name": "هنغاريا"
  },
  {
    "id": "nl",
    "code": "+31",
    "prefix": "0",
    "name": "هولندا"
  },
  {
    "id": "bq",
    "code": "+599",
    "prefix": "",
    "name": "هولندا الكاريبية"
  },
  {
    "id": "hk",
    "code": "+852",
    "prefix": "",
    "name": "هونغ كونغ الصينية (منطقة إدارية خاصة)"
  }
];

/**
 * The countries a family can sign in from today: the active rows of
 * hbh.country_dial_codes on 2026-09-16.
 *
 * Why not all of them: hbh.canonical_mobile refuses any other dial code
 * (HB173), so no application or staff-registered mobile from anywhere else
 * can exist. A parent who picked Italy was told "not registered - apply",
 * then met an application form that could not take the number.
 *
 * TO ENABLE A COUNTRY: add its row to hbh.country_dial_codes first (with its
 * mobile pattern), then its id here. Here alone is a promise the database
 * cannot keep. Owner's decision 2026-09-16: hide the rest for now, enable
 * later; the list is to come from the database in time.
 */
export const ENABLED_PHONE_COUNTRIES: ReadonlySet<string> =
  new Set(['eg', 'sa', 'ae', 'kw', 'qa', 'bh', 'om', 'jo']);

/** What the sign-in screen offers, in the order of the full list. */
export const PHONE_COUNTRIES: readonly PhoneCountry[] =
  ALL_PHONE_COUNTRIES.filter((country) => ENABLED_PHONE_COUNTRIES.has(country.id));
