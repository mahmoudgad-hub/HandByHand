import {
  ChangeDetectionStrategy, Component, DestroyRef, inject, signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { Router, RouterLink } from '@angular/router';

import { FormatService } from '@hbh/shared/format/format.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';
import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { EnrolmentApi, EnrolmentApplication } from '../../core/api/enrolment.api';

/**
 * The application form for a family that has never been to the centre.
 *
 * It is the only screen in this app reachable without signing in, and it has
 * to be: signing in needs a mobile number already on a child's file, and
 * these families have no file. So the form sits one link away from the login
 * screen and asks for what reception needs in order to ring them back.
 *
 * THREE THINGS IT IS CAREFUL ABOUT:
 *
 *   It does not create anything. What it sends lands in a quarantine table
 *   and stays there until a member of staff reads it and converts it. This
 *   screen cannot put a child into the clinical record and is not written as
 *   though it could.
 *
 *   It does not report why it was refused. The service answers 429 for a
 *   rate limit and 400 for everything else, without saying which - because
 *   "too many attempts for this mobile" would tell whoever typed it that the
 *   number is known to this centre. The messages here stay at that level and
 *   must not be "improved".
 *
 *   It asks for the child's difficulty in the family's own words, and labels
 *   it that way. It is not a diagnosis, it is not stored as one, and a form
 *   that implied otherwise would put a lay sentence into a clinical file.
 */
type FieldName =
  | 'parent_name_ar' | 'parent_mobile' | 'parent_email' | 'relationship_code'
  | 'address_ar' | 'preferred_contact_time'
  | 'child_name_ar' | 'child_birth_date' | 'child_gender'
  | 'main_concern_ar' | 'previous_therapy_ar';

@Component({
  selector: 'hbh-apply',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [Icon, TranslatePipe, RouterLink],
  templateUrl: './apply.html',
  styleUrl: './apply.css',
})
export class Apply {
  private readonly api = inject(EnrolmentApi);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);
  protected readonly format = inject(FormatService);
  /* The country code is a parameter of the centre, not a literal. */
  protected readonly config = inject(HBH_CONFIG);

  /* Closed sets, listed once. The labels come from the bundle keyed by the
     value itself, so a code the portal has not been taught shows its raw
     code rather than a wrong friendly word. */
  protected readonly relationships = ['MOTHER', 'FATHER', 'GUARDIAN'] as const;
  protected readonly genders = ['M', 'F'] as const;

  /*
   * Birth date as three lists, not a native date input.
   *
   * <input type="date"> renders in the BROWSER's locale, not the page's - a
   * parent on an English Chrome saw mm/dd/yyyy inside this Arabic form, and
   * 7 March entered as 07/03 was accepted as 3 July. Nothing errors: the
   * field is valid, the form submits, and the age that every clinical
   * decision hangs on is wrong by months.
   *
   * The parent fills this once, from home, with nobody checking it. A named
   * month cannot be misread.
   */
  protected readonly days = Array.from({ length: 31 }, (unused, i) => i + 1);
  protected readonly months = this.format.monthNames();
  protected readonly years = Array.from(
    { length: 26 }, (unused, i) => new Date().getFullYear() - i);

  protected readonly birthDay = signal('');
  protected readonly birthMonth = signal('');
  protected readonly birthYear = signal('');

  /**
   * Compose the three into the ISO date the service expects, and only when
   * all three are chosen: a half-built date is not a date, and writing one
   * would put "2019-00-00" on the wire.
   *
   * A day the month does not have - 31 April, 30 February - resolves to
   * empty rather than rolling forward to 1 May, which is what Date() does
   * on its own and what nobody would notice.
   */
  protected setBirthPart(part: 'd' | 'm' | 'y', raw: string): void {
    if (part === 'd') { this.birthDay.set(raw); }
    if (part === 'm') { this.birthMonth.set(raw); }
    if (part === 'y') { this.birthYear.set(raw); }

    const day = Number(this.birthDay());
    const month = Number(this.birthMonth());
    const year = Number(this.birthYear());
    if (!day || !month || !year) {
      this.setValue('child_birth_date', '');
      return;
    }
    const made = new Date(Date.UTC(year, month - 1, day));
    const real = made.getUTCFullYear() === year
      && made.getUTCMonth() === month - 1
      && made.getUTCDate() === day;
    this.setValue('child_birth_date', real ? made.toISOString().slice(0, 10) : '');
  }

  protected readonly values = signal<Record<string, string>>({
    parent_name_ar: '',
    parent_mobile: '',
    parent_email: '',
    // Defaulted, and shown as a real choice rather than left blank: a select
    // that renders its first option while holding nothing is a form that
    // looks filled and submits empty.
    relationship_code: 'MOTHER',
    address_ar: '',
    preferred_contact_time: '',
    child_name_ar: '',
    child_birth_date: '',
    child_gender: 'M',
    main_concern_ar: '',
    previous_therapy_ar: '',
  });

  protected readonly step=signal(0);
  protected readonly stepLabels=['البيانات الأساسية','الحالة والزيارة','الأهداف','المراجعة'];
  protected readonly sources=['WhatsApp','Facebook','Instagram','Google','ترشيح شخص','طبيب / أخصائي'];
  protected readonly reasons=['النطق والكلام','تأخر اللغة','الانتباه والتركيز','السلوك','التواصل الاجتماعي','أخرى'];
  protected readonly extra=signal<Record<string,string>>({health:'لا',previous:'لا، هذه أول مرة'});
  protected readonly selectedReasons=signal<string[]>([]);
  protected readonly goals=signal<string[]>(['','']);
  protected readonly consent=signal(false);
  protected readonly flowError=signal('');
  protected readonly draftNotice=signal('');
  private readonly draftKey='hbh-enrolment-draft-'+this.config.centerCode;
  constructor(){
    try{const raw=localStorage.getItem(this.draftKey);if(!raw)return;const draft=JSON.parse(raw);
      if(typeof draft.savedAt!=='number'||Date.now()-draft.savedAt>7*86400000){localStorage.removeItem(this.draftKey);return;}
      if(draft.values&&typeof draft.values==='object')this.values.update(v=>Object.fromEntries(Object.keys(v).map(k=>[k,typeof draft.values[k]==='string'?draft.values[k].slice(0,1800):v[k]])));
      if(draft.extra&&typeof draft.extra==='object')this.extra.set(Object.fromEntries(Object.entries(draft.extra).filter(([,v])=>typeof v==='string').map(([k,v])=>[k,String(v).slice(0,800)])));
      if(Array.isArray(draft.goals))this.goals.set(draft.goals.filter((g:unknown)=>typeof g==='string').slice(0,3));
      if(!this.goals().length)this.goals.set(['']);
      if(Array.isArray(draft.reasons))this.selectedReasons.set(draft.reasons.filter((r:string)=>this.reasons.includes(r)));
      this.draftNotice.set('تم استرجاع مسودتك المحفوظة على هذا الجهاز. لم يتم إرسالها بعد.');
    }catch{this.draftNotice.set('تعذر استرجاع المسودة. يمكنك تعبئة طلب جديد.');}
  }
  protected setExtra(key:string,value:string){this.extra.update(v=>({...v,[key]:value}));}
  protected toggleReason(reason:string){this.selectedReasons.update(v=>v.includes(reason)?v.filter(x=>x!==reason):[...v,reason]);}
  protected setGoal(index:number,value:string){this.goals.update(v=>v.map((g,i)=>i===index?value:g));}
  protected addGoal(){if(this.goals().length<3)this.goals.update(v=>[...v,'']);}
  protected removeGoal(index:number){if(this.goals().length>1)this.goals.update(v=>v.filter((_,i)=>i!==index));}
  protected saveDraft(){try{localStorage.setItem(this.draftKey,JSON.stringify({values:this.values(),extra:this.extra(),goals:this.goals(),reasons:this.selectedReasons(),savedAt:Date.now()}));this.draftNotice.set('تم حفظ المسودة على هذا الجهاز لمدة ٧ أيام. لم يتم إرسال الطلب للمركز.');}catch{this.draftNotice.set('تعذر حفظ المسودة على هذا الجهاز. أبقِ الصفحة مفتوحة لاستكمال الطلب.');}}
  protected clearDraft(){try{localStorage.removeItem(this.draftKey);this.draftNotice.set('');}catch{this.draftNotice.set('تعذر حذف المسودة من هذا الجهاز.');}}
  protected previousStep(){this.step.update(v=>Math.max(0,v-1));this.flowError.set('');window.scrollTo({top:0});}
  protected beneficiaryAge():string {
    const date=this.value('child_birth_date');if(!date||date>this.maxBirthDate)return '';
    const [y,m,d]=date.split('-').map(Number),[ty,tm,td]=this.maxBirthDate.split('-').map(Number);
    let months=(ty-y)*12+tm-m-(td<d?1:0);if(months<0)return 'أقل من شهر';
    return Math.floor(months/12)+' سنة و'+months%12+' شهر';
  }
  private validateBasics():boolean {
    const relation=this.value('relationship_code');
    if(relation==='FATHER'||relation==='MOTHER'){
      const key=relation==='FATHER'?'father_name':'mother_name';const name=this.extra()[key]?.trim();
      if(!name){this.step.set(0);this.flowError.set(relation==='FATHER'?'اكتب اسم الوالد المسؤول عن التواصل.':'اكتب اسم الوالدة المسؤولة عن التواصل.');setTimeout(()=>document.getElementById('x-'+key)?.focus());return false;}
      this.setValue('parent_name_ar',name);
    }
    if(this.extra()['has_companion']==='yes'){
      for(const key of ['companion_name','companion_relation','companion_phone'])if(!this.extra()[key]?.trim()){this.step.set(0);this.flowError.set('أكمل اسم المرافق وصلة القرابة ورقم هاتفه.');setTimeout(()=>document.getElementById('x-'+key)?.focus());return false;}
      if(!/^[+0-9 ()-]{7,20}$/.test(this.extra()['companion_phone'])){this.step.set(0);this.flowError.set('يرجى إدخال رقم هاتف صحيح للمرافق.');return false;}
    }

    for(const field of ['parent_name_ar','parent_mobile','child_name_ar','child_birth_date'] as const){if(!this.value(field).trim()){this.step.set(0);this.fail('apply.required.'+field,field);return false;}}
    if(!/^01[0-9]{9}$/.test(this.value('parent_mobile').trim())){this.step.set(0);this.fail('apply.badMobile','parent_mobile');return false;}
    if(this.value('child_birth_date')>this.maxBirthDate){this.step.set(0);this.flowError.set('تاريخ الميلاد لا يمكن أن يكون في المستقبل.');return false;}
    const email=this.value('parent_email').trim();if(email&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)){this.step.set(0);this.flowError.set('يرجى إدخال بريد إلكتروني صحيح.');return false;}
    return true;
  }
  protected nextStep(){if(this.busy())return;this.flowError.set('');if(!this.validateBasics())return;
    if(this.step()>=1&&!this.value('main_concern_ar').trim()){this.step.set(1);this.flowError.set('اكتب وصفًا مختصرًا لسبب الزيارة.');return;}
    if(this.step()<3){this.step.update(v=>v+1);window.scrollTo({top:0});return;}
    if(!this.consent()){this.flowError.set('برجاء الموافقة على استخدام البيانات قبل إرسال الطلب.');return;}this.submit();
  }

  protected readonly busy = signal(false);
  protected readonly errorKey = signal('');
  protected readonly badField = signal<string>('');

  /** The reference number, once there is one. The success screen. */
  protected readonly applicationNo = signal('');

  /**
   * Every reference this visit has produced, in order.
   *
   * A family with two children sends TWO applications - one row holds one
   * child, and there is no list of children on it. The second is not a
   * duplicate and does not create a second parent: convert_enrolment matches
   * the guardian on (centre, mobile) and attaches the new child to the parent
   * already known.
   *
   * So the form offers to do it again with the parent's half kept, and shows
   * every reference together - a family given two numbers in two separate
   * screens keeps one of them.
   */
  protected readonly references = signal<readonly string[]>([]);

  /**
   * A child cannot have been born tomorrow, and the database says so with a
   * check constraint. The picker says so first, on the centre's calendar -
   * taken from UTC it would offer tomorrow for three hours every evening.
   */
  protected readonly maxBirthDate = this.format.today();

  protected value(field: FieldName): string {
    return this.values()[field] ?? '';
  }

  protected setValue(field: FieldName, value: string): void {
    this.values.update((current) => ({ ...current, [field]: value }));
    if (this.badField() === field) {
      this.badField.set('');
      this.errorKey.set('');
    }
  }

  protected submit(event?: Event): void {
    event?.preventDefault();
    if (this.busy()) {
      return;
    }

    // Checked in the order the fields appear, and every rule for one field
    // before moving to the next. Grouping all the "required" checks first and
    // the shape checks after sent somebody to the bottom of the form to fill
    // a name and only THEN told them their phone number was wrong - two trips
    // for two problems that were both visible at once.
    //
    // One at a time, named, with the cursor put in the box. "Please complete
    // the form" in front of eleven fields makes a person read all eleven.
    const checks: readonly { field: FieldName; ok: (value: string) => boolean; key: string }[] = [
      { field: 'parent_name_ar', ok: (v) => !!v, key: 'apply.required.parent_name_ar' },
      { field: 'parent_mobile', ok: (v) => !!v, key: 'apply.required.parent_mobile' },
      // The mobile is how the centre calls back, so its shape is checked here
      // rather than left to a 400 that says nothing about which field it meant.
      { field: 'parent_mobile', ok: (v) => /^01[0-9]{9}$/.test(v), key: 'apply.badMobile' },
      { field: 'child_name_ar', ok: (v) => !!v, key: 'apply.required.child_name_ar' },
      { field: 'child_birth_date', ok: (v) => !!v, key: 'apply.required.child_birth_date' },
    ];
    for (const check of checks) {
      if (!check.ok(this.value(check.field).trim())) {
        this.fail(check.key, check.field);
        return;
      }
    }

    const values = this.values();
    const body: EnrolmentApplication = {
      parent_name_ar: values['parent_name_ar'].trim(),
      parent_mobile: values['parent_mobile'].trim(),
      relationship_code: values['relationship_code'],
      child_name_ar: values['child_name_ar'].trim(),
      child_birth_date: values['child_birth_date'],
      child_gender: values['child_gender'],
    };
    // Optional fields are omitted rather than sent empty: an empty string is
    // a value, and "" in an email column is not the same as no email.
    for (const field of [
      'parent_email', 'address_ar', 'preferred_contact_time',
      'main_concern_ar', 'previous_therapy_ar',
    ] as const) {
      const value = values[field].trim();
      if (value) {
        Object.assign(body, { [field]: value });
      }
    }

    const details=this.extra();
    Object.assign(body,{main_concern_ar:[values['main_concern_ar'].trim(),details['father_name']?'اسم الوالد: '+details['father_name']:'',details['father_job']?'مهنة الوالد: '+details['father_job']:'',details['mother_name']?'اسم الوالدة: '+details['mother_name']:'',details['mother_job']?'مهنة الوالدة: '+details['mother_job']:'',details['has_companion']==='yes'?'المرافق: '+details['companion_name']+' — '+details['companion_relation']+' — '+details['companion_phone']:'',this.selectedReasons().length?'مجالات المساعدة: '+this.selectedReasons().join('، '):'',details['health']?'حالة صحية أو دواء منتظم: '+details['health']:'',details['health_notes']?'ملاحظات صحية: '+details['health_notes']:'',details['source']?'كيف تعرفتم علينا: '+details['source']:''].filter(Boolean).join('\n\n'),
      previous_therapy_ar:[details['previous']?'خدمات سابقة: '+details['previous']:'',values['previous_therapy_ar'].trim(),this.goals().some(g=>g.trim())?'أهداف الأسرة خلال ٣–٦ أشهر:\n'+this.goals().filter(g=>g.trim()).join('\n'):'',details['notes']?'ملاحظات إضافية: '+details['notes']:''].filter(Boolean).join('\n\n')});
    this.busy.set(true);
    this.errorKey.set('');
    this.badField.set('');

    this.api.submit(body)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (answer) => {
          this.busy.set(false);
          this.applicationNo.set(answer.application_no);
          try{localStorage.removeItem(this.draftKey);}catch{}
          this.draftNotice.set('');
          this.references.update((all) => [...all, answer.application_no]);
          window.scrollTo({ top: 0 });
        },
        error: (error: unknown) => {
          this.busy.set(false);
          this.errorKey.set(this.messageFor(error));
        },
      });
  }

  protected backToLogin(): void {
    void this.router.navigate(['/login']);
  }

  /**
   * A second child for the same family.
   *
   * The parent's half is kept deliberately - retyping a name, a mobile and an
   * address for a sibling is how a form gets abandoned halfway - and the
   * mobile in particular MUST be the same one, because that is the field the
   * centre matches on when it attaches both children to one parent. The
   * child's half is cleared, because leaving the first child's name in the
   * box is how a family sends the same child twice.
   */
  protected addAnotherChild(): void {
    this.values.update((current) => ({
      ...current,
      child_name_ar: '',
      child_birth_date: '',
      child_gender: 'M',
      main_concern_ar: '',
      previous_therapy_ar: '',
    }));
    this.step.set(0);this.goals.set(['','']);this.extra.update(v=>({father_name:v['father_name']||'',father_job:v['father_job']||'',mother_name:v['mother_name']||'',mother_job:v['mother_job']||'',source:v['source']||'',health:'لا',previous:'لا، هذه أول مرة'}));this.selectedReasons.set([]);this.consent.set(false);this.flowError.set('');
    this.applicationNo.set('');
    this.errorKey.set('');
    this.badField.set('');
    window.scrollTo({ top: 0 });
    // Put the cursor where the work now is, after the form has drawn.
    setTimeout(() => document.getElementById('a-child_name_ar')?.focus());
  }

  /**
   * The message for one field, or nothing.
   *
   * THE MESSAGE HAS TO BE WHERE THE CURSOR LANDS. It used to be rendered in
   * one box above the submit button, and fail() puts the cursor in the bad
   * field - so on a form this long the two were hundreds of pixels apart, and
   * the focus() that was supposed to guide somebody was the very thing that
   * scrolled the explanation off the top of their screen.
   *
   * The owner hit it: a ten-digit mobile number, "send", and nothing visible
   * happened. The form had refused correctly and said why, in a place he
   * could not see. He went looking for the application in the console.
   *
   * Only one field is ever bad at a time - the loop in submit() returns on
   * the first failure - so this is a single message that moves, not ten
   * messages that could pile up.
   */
  protected fieldErr(field: FieldName): string {
    return this.badField() === field ? this.errorKey() : '';
  }

  /**
   * The message for the form as a whole: a refusal from the service, which
   * belongs to no field. Network trouble, a rate limit, a 400 the service
   * would not explain. Those stay above the button, which is where somebody
   * looks after pressing it.
   */
  protected formErr(): string {
    return this.badField() ? '' : this.errorKey();
  }

  private fail(key: string, field: FieldName): void {
    this.errorKey.set(key);
    this.badField.set(field);
    setTimeout(()=>document.getElementById(`a-${field}`)?.focus());
  }

  /**
   * What may be said about a refusal, which is not much.
   *
   * 429 is a rate limit and says so - but not WHICH limit, because the
   * service does not say and the difference is a fact about a family.
   * Everything else is "check what you typed", because a 400 here really can
   * be an unknown centre code, and telling somebody that would let them
   * enumerate the centres.
   */
  private messageFor(error: unknown): string {
    const status = (error as { status?: number })?.status;
    if (status === 0 || status === undefined) {
      return 'error.network';
    }
    if (status === 429) {
      return 'apply.tooMany';
    }
    if (status === 400) {
      return 'apply.refused';
    }
    return 'apply.failed';
  }
}


