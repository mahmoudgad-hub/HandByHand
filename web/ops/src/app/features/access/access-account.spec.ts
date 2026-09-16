import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting, HttpTestingController } from '@angular/common/http/testing';
import { of } from 'rxjs';
import { Access } from './access';
import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { ToastService } from '@hbh/shared/toast/toast.service';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { FormatService } from '@hbh/shared/format/format.service';

describe('User account editor', () => {
  let http: HttpTestingController;
  let screen: any;
  let refresh: jasmine.Spy;
  beforeEach(() => {
    refresh=jasmine.createSpy('refresh').and.returnValue(of({}));
    TestBed.configureTestingModule({providers:[provideHttpClient(),provideHttpClientTesting(),
      {provide:HBH_CONFIG,useValue:{apiBaseUrl:''}},
      {provide:OpsAuthService,useValue:{can:()=>true,me:()=>({userId:7}),loadIdentity:refresh}},
      {provide:ToastService,useValue:{show:()=>{},error:()=>{}}},
      {provide:I18nService,useValue:{translate:(key:string)=>key}},
      {provide:FormatService,useValue:{}},
    ]}).overrideComponent(Access,{set:{template:'',imports:[]}});
    http=TestBed.inject(HttpTestingController);
    screen=TestBed.createComponent(Access).componentInstance;
    http.expectOne('/api/v1/roles').flush(null,{status:503,statusText:'Unavailable'});
    screen.users.set([{user_id:7,username:'fixed-name',full_name_ar:'Original',mobile:'+201000000000',roles:[]}]);
    screen.selectedUserId.set(7);screen.resetAccount();
  });
  afterEach(()=>http.verify());
  it('defaults to staff including therapists and combines category with search',()=>{
    screen.users.set([
      {user_id:1,user_type:'STAFF',full_name_ar:'Staff',username:'staff'},
      {user_id:2,user_type:'THERAPIST',full_name_ar:'Therapist',username:'therapist'},
      {user_id:3,user_type:'GUARDIAN',full_name_ar:'Parent',username:'parent'},
    ]);
    expect(screen.shownUsers().map((u:any)=>u.user_id)).toEqual([1,2]);
    screen.changeUserCategory('GUARDIAN');
    expect(screen.shownUsers().map((u:any)=>u.user_id)).toEqual([3]);
    screen.changeUserCategory('ALL');expect(screen.shownUsers().length).toBe(3);
    screen.searchTerm.set('parent');expect(screen.shownUsers().map((u:any)=>u.user_id)).toEqual([3]);
  });
  it('saves only editable values and refreshes the signed-in identity',()=>{
    screen.accountName.setValue('Updated');screen.saveAccount();screen.saveAccount();
    const request=http.expectOne('/api/v1/users/7');
    expect(request.request.method).toBe('PATCH');
    expect(request.request.body).toEqual({full_name_ar:'Updated'});
    request.flush(null,{status:204,statusText:'No Content'});
    expect(screen.selectedUser().full_name_ar).toBe('Updated');
    expect(screen.accountDirty()).toBeFalse();expect(refresh).toHaveBeenCalledTimes(1);
  });
  it('uses explicit clear_mobile when removing a number',()=>{
    screen.accountMobile.setValue('');screen.saveAccount();
    const request=http.expectOne('/api/v1/users/7');
    expect(request.request.body).toEqual({clear_mobile:true});request.flush(null);
    expect(screen.selectedUser().mobile).toBeNull();
  });
  it('cancel restores stored values and prevents empty names from reaching the server',()=>{
    screen.accountName.setValue('');screen.saveAccount();http.expectNone('/api/v1/users/7');
    expect(screen.accountError()).toBeTruthy();screen.resetAccount();
    expect(screen.accountName.value).toBe('Original');expect(screen.accountDirty()).toBeFalse();
  });
});
